-- SOMA / FACOLUB prepared bottles module - 042 trusted operational functions
-- Depends on: 040-041.
-- All confirmation work is one PostgreSQL transaction. Shared stock advisory
-- locks serialize preparations with movements and reservations.

create or replace function public.calculate_preparation_requirements(
  target_recipe_id uuid,
  target_quantity numeric,
  target_location_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
declare recipe public.prepared_bottle_recipes;
declare result jsonb;
begin
  perform public.assert_prepared_bottle_actor();
  if target_quantity is null or target_quantity <= 0 then
    raise exception 'Preparation quantity must be greater than zero' using errcode = '22023';
  end if;
  select candidate.* into recipe from public.prepared_bottle_recipes candidate
  where candidate.id = target_recipe_id and candidate.is_active;
  if not found then raise exception 'Active prepared bottle recipe not found' using errcode = 'P0002'; end if;
  if effective_location_id is null or not exists (
    select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active
  ) then raise exception 'Active stock location not found' using errcode = 'P0002'; end if;

  select jsonb_build_object(
    'recipe_id', recipe.id,
    'location_id', effective_location_id,
    'quantity', target_quantity,
    'product_name', recipe.product_name,
    'format_name', recipe.format_name,
    'output', jsonb_build_object(
      'stock_item_id', recipe.output_stock_item_id,
      'name', output_item.name,
      'quantity', round(target_quantity, 3)
    ),
    'components', coalesce((
      select jsonb_agg(jsonb_build_object(
        'stock_item_id', component.component_stock_item_id,
        'name', item.name,
        'category', item.category,
        'quantity_per_output', component.quantity_per_output,
        'required_quantity', round(component.quantity_per_output * target_quantity, 3),
        'physical_quantity', quantities.physical_quantity,
        'reserved_quantity', quantities.reserved_quantity,
        'available_quantity', quantities.available_quantity,
        'missing_quantity', greatest(round(component.quantity_per_output * target_quantity, 3)
                                     - quantities.available_quantity, 0),
        'sufficient', quantities.available_quantity >= round(component.quantity_per_output * target_quantity, 3)
      ) order by component.position, component.id)
      from public.prepared_bottle_recipe_components component
      join public.stock_items item on item.id = component.component_stock_item_id
      cross join lateral public.stock_quantities(
        component.component_stock_item_id, effective_location_id
      ) quantities
      where component.recipe_id = recipe.id
    ), '[]'::jsonb)
  ) into result
  from public.stock_items output_item where output_item.id = recipe.output_stock_item_id;
  return result;
end;
$$;

create or replace function public.snapshot_preparation_recipe(
  target_preparation_id uuid,
  target_recipe_id uuid
)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.bottle_preparation_components component
  where component.preparation_id = target_preparation_id;
  insert into public.bottle_preparation_components (
    preparation_id, component_stock_item_id, component_name_snapshot,
    component_category, quantity_per_output, position
  )
  select target_preparation_id, component.component_stock_item_id, item.name,
    item.category, component.quantity_per_output, component.position
  from public.prepared_bottle_recipe_components component
  join public.stock_items item on item.id = component.component_stock_item_id
  where component.recipe_id = target_recipe_id
  order by component.position;
  if not found then raise exception 'Recipe has no components' using errcode = '23514'; end if;
end;
$$;

create or replace function public.create_bottle_preparation_draft(
  target_recipe_id uuid,
  target_location_id uuid default null,
  target_planned_quantity numeric default null,
  target_comment text default null
)
returns public.bottle_preparations language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_prepared_bottle_actor();
declare effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
declare recipe public.prepared_bottle_recipes;
declare output_item public.stock_items;
declare result public.bottle_preparations;
begin
  if target_planned_quantity is not null and target_planned_quantity <= 0 then
    raise exception 'Planned quantity must be greater than zero' using errcode = '22023';
  end if;
  select candidate.* into recipe from public.prepared_bottle_recipes candidate
  where candidate.id = target_recipe_id and candidate.is_active;
  if not found then raise exception 'Active prepared bottle recipe not found' using errcode = 'P0002'; end if;
  select item.* into output_item from public.stock_items item
  where item.id = recipe.output_stock_item_id and item.is_active;
  if not found then raise exception 'Active prepared bottle output not found' using errcode = 'P0002'; end if;
  if effective_location_id is null or not exists (
    select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active
  ) then raise exception 'Active stock location not found' using errcode = 'P0002'; end if;
  insert into public.bottle_preparations (
    recipe_id, location_id, output_stock_item_id, product_format_id,
    product_name_snapshot, format_name_snapshot, output_item_name_snapshot,
    recipe_version_snapshot, planned_quantity, status, comment, created_by
  ) values (
    recipe.id, effective_location_id, recipe.output_stock_item_id, recipe.product_format_id,
    recipe.product_name, recipe.format_name, output_item.name, recipe.version,
    target_planned_quantity, 'draft'::public.preparation_status,
    nullif(trim(target_comment), ''), actor_id
  ) returning * into result;
  perform public.snapshot_preparation_recipe(result.id, recipe.id);
  return result;
end;
$$;

create or replace function public.update_bottle_preparation_draft(
  target_preparation_id uuid,
  target_recipe_id uuid,
  target_location_id uuid,
  target_planned_quantity numeric,
  target_actual_quantity numeric,
  target_comment text
)
returns public.bottle_preparations language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_prepared_bottle_actor();
declare actor_role public.app_role := public.current_app_role();
declare current_preparation public.bottle_preparations;
declare recipe public.prepared_bottle_recipes;
declare output_item public.stock_items;
declare result public.bottle_preparations;
begin
  select preparation.* into current_preparation from public.bottle_preparations preparation
  where preparation.id = target_preparation_id for update;
  if not found then raise exception 'Bottle preparation not found' using errcode = 'P0002'; end if;
  if current_preparation.status <> 'draft'::public.preparation_status then
    raise exception 'Only a draft preparation can be edited' using errcode = '23514';
  end if;
  if actor_role = 'factory'::public.app_role and current_preparation.created_by <> actor_id then
    raise exception 'Factory users may edit only their own preparation drafts' using errcode = '42501';
  end if;
  if target_planned_quantity is not null and target_planned_quantity <= 0
    or target_actual_quantity is not null and target_actual_quantity <= 0 then
    raise exception 'Preparation quantities must be greater than zero' using errcode = '22023';
  end if;
  select candidate.* into recipe from public.prepared_bottle_recipes candidate
  where candidate.id = target_recipe_id and candidate.is_active;
  if not found then raise exception 'Active prepared bottle recipe not found' using errcode = 'P0002'; end if;
  select item.* into output_item from public.stock_items item
  where item.id = recipe.output_stock_item_id and item.is_active;
  if not found then raise exception 'Active prepared bottle output not found' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.stock_locations location
    where location.id = target_location_id and location.is_active) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;
  update public.bottle_preparations preparation set
    recipe_id = recipe.id, location_id = target_location_id,
    output_stock_item_id = recipe.output_stock_item_id,
    product_format_id = recipe.product_format_id,
    product_name_snapshot = recipe.product_name,
    format_name_snapshot = recipe.format_name,
    output_item_name_snapshot = output_item.name,
    recipe_version_snapshot = recipe.version,
    planned_quantity = target_planned_quantity,
    actual_quantity = target_actual_quantity,
    comment = nullif(trim(target_comment), '')
  where preparation.id = current_preparation.id returning * into result;
  perform public.snapshot_preparation_recipe(result.id, recipe.id);
  return result;
end;
$$;

create or replace function public.cancel_bottle_preparation(target_preparation_id uuid)
returns public.bottle_preparations language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_prepared_bottle_actor();
declare actor_role public.app_role := public.current_app_role();
declare result public.bottle_preparations;
begin
  select preparation.* into result from public.bottle_preparations preparation
  where preparation.id = target_preparation_id for update;
  if not found then raise exception 'Bottle preparation not found' using errcode = 'P0002'; end if;
  if result.status = 'cancelled'::public.preparation_status then return result; end if;
  if result.status <> 'draft'::public.preparation_status then
    raise exception 'Confirmed preparations cannot be cancelled' using errcode = '23514';
  end if;
  if actor_role = 'factory'::public.app_role and result.created_by <> actor_id then
    raise exception 'Factory users may cancel only their own preparation drafts' using errcode = '42501';
  end if;
  update public.bottle_preparations preparation set status = 'cancelled'::public.preparation_status
  where preparation.id = result.id returning * into result;
  return result;
end;
$$;

create or replace function public.bottle_preparation_payload(target_preparation_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'preparation', to_jsonb(preparation),
    'location_name', location.name,
    'created_by_name', creator.display_name,
    'confirmed_by_name', confirmer.display_name,
    'components', coalesce((select jsonb_agg(jsonb_build_object(
      'id', component.id,
      'stock_item_id', component.component_stock_item_id,
      'name', component.component_name_snapshot,
      'category', component.component_category,
      'quantity_per_output', component.quantity_per_output,
      'required_quantity', component.required_quantity,
      'movement_id', movement.id,
      'movement_quantity', movement.quantity
    ) order by component.position, component.id)
    from public.bottle_preparation_components component
    left join public.stock_movements movement
      on movement.reference_type = 'bottle_preparation'
     and movement.reference_id = preparation.id
     and movement.metadata ->> 'preparation_component_id' = component.id::text
    where component.preparation_id = preparation.id), '[]'::jsonb),
    'output_movement', (select jsonb_build_object(
      'id', movement.id, 'stock_item_id', movement.stock_item_id,
      'quantity', movement.quantity, 'direction', movement.direction,
      'created_at', movement.created_at
    ) from public.stock_movements movement
    where movement.reference_type = 'bottle_preparation'
      and movement.reference_id = preparation.id
      and movement.movement_type = 'preparation_output'::public.stock_movement_type
    limit 1)
  )
  from public.bottle_preparations preparation
  join public.stock_locations location on location.id = preparation.location_id
  join public.profiles creator on creator.id = preparation.created_by
  left join public.profiles confirmer on confirmer.id = preparation.confirmed_by
  where preparation.id = target_preparation_id
$$;

create or replace function public.post_bottle_preparation_movement(
  target_preparation_id uuid,
  target_component_id uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
declare preparation public.bottle_preparations;
declare component public.bottle_preparation_components;
declare movement_id uuid;
declare target_item_id uuid;
declare target_quantity numeric;
declare target_type public.stock_movement_type;
declare target_direction public.stock_direction;
declare movement_metadata jsonb;
begin
  select candidate.* into preparation from public.bottle_preparations candidate
  where candidate.id = target_preparation_id and candidate.status = 'confirmed'::public.preparation_status
    and candidate.confirmed_by = actor_id;
  if not found then raise exception 'Confirmed preparation context not found' using errcode = '42501'; end if;
  if target_component_id is null then
    target_item_id := preparation.output_stock_item_id;
    target_quantity := preparation.actual_quantity;
    target_type := 'preparation_output'::public.stock_movement_type;
    target_direction := 'in'::public.stock_direction;
    movement_metadata := jsonb_build_object('preparation_number', preparation.preparation_number,
      'recipe_id', preparation.recipe_id, 'recipe_version', preparation.recipe_version_snapshot);
  else
    select candidate.* into component from public.bottle_preparation_components candidate
    where candidate.id = target_component_id and candidate.preparation_id = preparation.id;
    if not found then raise exception 'Preparation component not found' using errcode = 'P0002'; end if;
    target_item_id := component.component_stock_item_id;
    target_quantity := component.required_quantity;
    target_type := 'preparation_consumption'::public.stock_movement_type;
    target_direction := 'out'::public.stock_direction;
    movement_metadata := jsonb_build_object('preparation_component_id', component.id,
      'preparation_number', preparation.preparation_number,
      'quantity_per_output', component.quantity_per_output,
      'component_name', component.component_name_snapshot);
  end if;
  insert into public.stock_movements (
    stock_item_id, location_id, movement_type, quantity, direction,
    reference_type, reference_id, reason, created_by, metadata
  ) values (
    target_item_id, preparation.location_id, target_type, target_quantity, target_direction,
    'bottle_preparation', preparation.id,
    'Bottle preparation ' || preparation.preparation_number, actor_id, movement_metadata
  ) returning id into movement_id;
  return movement_id;
end;
$$;

create or replace function public.confirm_bottle_preparation(target_preparation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_prepared_bottle_actor();
declare actor_role public.app_role := public.current_app_role();
declare preparation public.bottle_preparations;
declare component public.bottle_preparation_components;
declare quantities record;
declare effective_quantity numeric;
declare official_number text;
begin
  select candidate.* into preparation from public.bottle_preparations candidate
  where candidate.id = target_preparation_id for update;
  if not found then raise exception 'Bottle preparation not found' using errcode = 'P0002'; end if;
  if preparation.status = 'confirmed'::public.preparation_status then
    return public.bottle_preparation_payload(preparation.id);
  end if;
  if preparation.status <> 'draft'::public.preparation_status then
    raise exception 'Cancelled preparations cannot be confirmed' using errcode = '23514';
  end if;
  if actor_role = 'factory'::public.app_role and preparation.created_by <> actor_id then
    raise exception 'Factory users may confirm only their own preparation drafts' using errcode = '42501';
  end if;
  effective_quantity := coalesce(preparation.actual_quantity, preparation.planned_quantity);
  if effective_quantity is null or effective_quantity <= 0 then
    raise exception 'Actual preparation quantity must be greater than zero' using errcode = '22023';
  end if;
  if not exists (select 1 from public.stock_locations location
    where location.id = preparation.location_id and location.is_active) then
    raise exception 'Active preparation location not found' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.stock_items item
    where item.id = preparation.output_stock_item_id and item.is_active
      and item.category = 'prepared_bottle'::public.stock_item_category) then
    raise exception 'Active prepared bottle output not found' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.bottle_preparation_components candidate
    where candidate.preparation_id = preparation.id
      and candidate.component_category = 'empty_bottle'::public.stock_item_category)
    or not exists (select 1 from public.bottle_preparation_components candidate
    where candidate.preparation_id = preparation.id
      and candidate.component_category = 'label'::public.stock_item_category) then
    raise exception 'Preparation requires an empty bottle and at least one label component'
      using errcode = '23514';
  end if;

  update public.bottle_preparation_components candidate
  set required_quantity = round(candidate.quantity_per_output * effective_quantity, 3)
  where candidate.preparation_id = preparation.id;

  -- Consistent UUID lock ordering prevents deadlocks. Reservation mutations and
  -- every stock OUT operation use the same lock keys.
  for component in select candidate.* from public.bottle_preparation_components candidate
    where candidate.preparation_id = preparation.id
    order by candidate.component_stock_item_id, candidate.id
  loop
    perform public.lock_stock_balance(component.component_stock_item_id, preparation.location_id);
  end loop;
  perform public.lock_stock_balance(preparation.output_stock_item_id, preparation.location_id);

  for component in select candidate.* from public.bottle_preparation_components candidate
    where candidate.preparation_id = preparation.id order by candidate.position, candidate.id
  loop
    select * into quantities from public.stock_quantities(
      component.component_stock_item_id, preparation.location_id
    );
    if component.required_quantity > quantities.available_quantity then
      raise exception 'Insufficient stock for %. Required: %. Available: %.',
        component.component_name_snapshot, component.required_quantity, quantities.available_quantity
        using errcode = '23514';
    end if;
  end loop;

  official_number := public.allocate_preparation_number(current_date);
  update public.bottle_preparations candidate set
    preparation_number = official_number,
    actual_quantity = effective_quantity,
    status = 'confirmed'::public.preparation_status,
    confirmed_by = actor_id,
    confirmed_at = now()
  where candidate.id = preparation.id returning * into preparation;

  for component in select candidate.* from public.bottle_preparation_components candidate
    where candidate.preparation_id = preparation.id order by candidate.position, candidate.id
  loop
    perform public.post_bottle_preparation_movement(preparation.id, component.id);
  end loop;
  perform public.post_bottle_preparation_movement(preparation.id, null);
  return public.bottle_preparation_payload(preparation.id);
end;
$$;

create or replace function public.get_bottle_preparation(target_preparation_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  perform public.assert_prepared_bottle_actor();
  result := public.bottle_preparation_payload(target_preparation_id);
  if result is null then raise exception 'Bottle preparation not found' using errcode = 'P0002'; end if;
  return result;
end;
$$;

create or replace function public.list_bottle_preparations(
  target_date_from date default null,
  target_date_to date default null,
  target_product_name text default null,
  target_format_name text default null,
  target_created_by uuid default null,
  target_status public.preparation_status default null,
  target_limit integer default 100
)
returns table (
  id uuid, preparation_number text, status public.preparation_status,
  product_name text, format_name text, quantity numeric,
  output_stock_item_id uuid, output_stock_item_name text,
  created_by uuid, created_by_name text, confirmed_by uuid,
  confirmed_by_name text, confirmed_at timestamptz, created_at timestamptz
) language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.assert_prepared_bottle_actor();
  return query select preparation.id, preparation.preparation_number, preparation.status,
    preparation.product_name_snapshot, preparation.format_name_snapshot,
    coalesce(preparation.actual_quantity, preparation.planned_quantity),
    preparation.output_stock_item_id, preparation.output_item_name_snapshot,
    preparation.created_by, creator.display_name, preparation.confirmed_by,
    confirmer.display_name, preparation.confirmed_at, preparation.created_at
  from public.bottle_preparations preparation
  join public.profiles creator on creator.id = preparation.created_by
  left join public.profiles confirmer on confirmer.id = preparation.confirmed_by
  where (target_date_from is null or preparation.created_at >= target_date_from::timestamptz)
    and (target_date_to is null or preparation.created_at < (target_date_to + 1)::timestamptz)
    and (target_product_name is null or preparation.product_name_snapshot = target_product_name)
    and (target_format_name is null or preparation.format_name_snapshot = target_format_name)
    and (target_created_by is null or preparation.created_by = target_created_by)
    and (target_status is null or preparation.status = target_status)
  order by preparation.created_at desc, preparation.id desc
  limit least(greatest(coalesce(target_limit, 100), 1), 500);
end;
$$;

revoke all on function public.snapshot_preparation_recipe(uuid,uuid) from public, anon, authenticated;
revoke all on function public.bottle_preparation_payload(uuid) from public, anon, authenticated;
revoke all on function public.post_bottle_preparation_movement(uuid,uuid) from public, anon, authenticated;
revoke all on function public.calculate_preparation_requirements(uuid,numeric,uuid) from public, anon;
revoke all on function public.create_bottle_preparation_draft(uuid,uuid,numeric,text) from public, anon;
revoke all on function public.update_bottle_preparation_draft(uuid,uuid,uuid,numeric,numeric,text) from public, anon;
revoke all on function public.cancel_bottle_preparation(uuid) from public, anon;
revoke all on function public.confirm_bottle_preparation(uuid) from public, anon;
revoke all on function public.get_bottle_preparation(uuid) from public, anon;
revoke all on function public.list_bottle_preparations(date,date,text,text,uuid,public.preparation_status,integer) from public, anon;
grant execute on function public.calculate_preparation_requirements(uuid,numeric,uuid) to authenticated;
grant execute on function public.create_bottle_preparation_draft(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.update_bottle_preparation_draft(uuid,uuid,uuid,numeric,numeric,text) to authenticated;
grant execute on function public.cancel_bottle_preparation(uuid) to authenticated;
grant execute on function public.confirm_bottle_preparation(uuid) to authenticated;
grant execute on function public.get_bottle_preparation(uuid) to authenticated;
grant execute on function public.list_bottle_preparations(date,date,text,text,uuid,public.preparation_status,integer) to authenticated;

-- Verification query:
select routine_name, security_type from information_schema.routines
where routine_schema = 'public' and routine_name in (
  'calculate_preparation_requirements', 'create_bottle_preparation_draft',
  'update_bottle_preparation_draft', 'cancel_bottle_preparation',
  'confirm_bottle_preparation', 'get_bottle_preparation', 'list_bottle_preparations'
) order by routine_name;
