-- SOMA / FACOLUB production planning module - 053 trusted APIs
-- Depends on: 050-052.

create or replace function public.assert_planning_actor(
  required_roles public.app_role[] default array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]
)
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  return public.assert_stock_actor(required_roles);
end;
$$;

create or replace function public.allocate_production_plan_number(target_date date)
returns text language plpgsql security definer set search_path = '' as $$
declare next_value bigint;
begin
  if target_date is null then raise exception 'Production date is required for numbering' using errcode = '22023'; end if;
  insert into public.production_plan_number_sequences (plan_date, last_value)
  values (target_date, 1)
  on conflict (plan_date) do update
    set last_value = public.production_plan_number_sequences.last_value + 1
  returning last_value into next_value;
  return format('PLAN-%s-%s', to_char(target_date, 'DDMMYY'), lpad(next_value::text, 2, '0'));
end;
$$;

create or replace function public.save_planning_product(
  target_id uuid, target_code text, target_name text, target_is_active boolean default true
)
returns public.products language plpgsql security definer set search_path = '' as $$
declare result public.products;
begin
  perform public.assert_planning_actor(array['admin'::public.app_role]);
  if target_name is null or char_length(trim(target_name)) < 1 then
    raise exception 'Product name is required' using errcode = '22023';
  end if;
  if target_id is null then
    insert into public.products (code, name, is_active)
    values (nullif(upper(trim(target_code)), ''), trim(target_name), coalesce(target_is_active, true))
    returning * into result;
  else
    update public.products product set code = nullif(upper(trim(target_code)), ''),
      name = trim(target_name), is_active = coalesce(target_is_active, product.is_active)
    where product.id = target_id returning * into result;
    if not found then raise exception 'Product not found' using errcode = 'P0002'; end if;
  end if;
  return result;
end;
$$;

create or replace function public.save_product_format(
  target_id uuid, target_product_id uuid, target_format_id uuid, target_is_active boolean default true
)
returns public.product_formats language plpgsql security definer set search_path = '' as $$
declare result public.product_formats;
begin
  perform public.assert_planning_actor(array['admin'::public.app_role]);
  if not exists (select 1 from public.products product where product.id = target_product_id and product.is_active)
    or not exists (select 1 from public.packaging_formats format where format.id = target_format_id and format.is_active) then
    raise exception 'Active product and packaging format are required' using errcode = 'P0002';
  end if;
  if target_id is null then
    insert into public.product_formats (product_id, format_id, is_active)
    values (target_product_id, target_format_id, coalesce(target_is_active, true)) returning * into result;
  else
    update public.product_formats product_format set product_id = target_product_id,
      format_id = target_format_id, is_active = coalesce(target_is_active, product_format.is_active)
    where product_format.id = target_id returning * into result;
    if not found then raise exception 'Product format not found' using errcode = 'P0002'; end if;
  end if;
  return result;
end;
$$;

create or replace function public.configure_packaging_rule(
  target_format_id uuid, target_bottles_per_carton integer
)
returns public.packaging_rules language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_planning_actor(array['admin'::public.app_role]);
declare result public.packaging_rules;
begin
  if target_bottles_per_carton is null or target_bottles_per_carton <= 0 then
    raise exception 'Bottles per carton must be greater than zero' using errcode = '22023';
  end if;
  if not exists (select 1 from public.packaging_formats format
    where format.id = target_format_id and format.is_active) then
    raise exception 'Active packaging format not found' using errcode = 'P0002';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('packaging-rule:' || target_format_id::text, 0));
  update public.packaging_rules rule set is_active = false
  where rule.format_id = target_format_id and rule.is_active;
  insert into public.packaging_rules (format_id, bottles_per_carton, is_active, created_by)
  values (target_format_id, target_bottles_per_carton, true, actor_id) returning * into result;
  return result;
end;
$$;

create or replace function public.production_recipe_payload(target_recipe_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', recipe.id, 'product_format_id', recipe.product_format_id,
    'product_name', product.name, 'format_name', format.name,
    'output_stock_item_id', recipe.output_stock_item_id,
    'output_stock_item_name', output_item.name,
    'version', recipe.version, 'is_active', recipe.is_active,
    'supersedes_recipe_id', recipe.supersedes_recipe_id,
    'created_by', recipe.created_by, 'created_at', recipe.created_at,
    'updated_at', recipe.updated_at,
    'components', coalesce((select jsonb_agg(jsonb_build_object(
      'id', component.id, 'stock_item_id', component.component_stock_item_id,
      'stock_item_name', item.name, 'category', item.category, 'unit', item.unit,
      'quantity_per_bottle', component.quantity_per_bottle,
      'component_role', component.component_role, 'position', component.position
    ) order by component.position, component.id)
    from public.production_recipe_components component
    join public.stock_items item on item.id = component.component_stock_item_id
    where component.recipe_id = recipe.id), '[]'::jsonb)
  )
  from public.production_recipes recipe
  join public.product_formats product_format on product_format.id = recipe.product_format_id
  join public.products product on product.id = product_format.product_id
  join public.packaging_formats format on format.id = product_format.format_id
  join public.stock_items output_item on output_item.id = recipe.output_stock_item_id
  where recipe.id = target_recipe_id
$$;

create or replace function public.insert_production_recipe_components(
  target_recipe_id uuid, target_components jsonb
)
returns void language plpgsql security definer set search_path = '' as $$
declare component jsonb;
declare component_id uuid;
declare component_quantity numeric;
declare component_role_value public.production_component_role;
declare component_position integer := 0;
declare capacity integer;
begin
  if target_components is null or jsonb_typeof(target_components) <> 'array'
    or jsonb_array_length(target_components) < 4 then
    raise exception 'Production recipe requires prepared bottle, bulk lubricant, seal, and carton components'
      using errcode = '22023';
  end if;
  select rule.bottles_per_carton into capacity
  from public.production_recipes recipe
  join public.product_formats product_format on product_format.id = recipe.product_format_id
  join public.packaging_rules rule on rule.format_id = product_format.format_id and rule.is_active
  where recipe.id = target_recipe_id;
  if capacity is null then raise exception 'Active carton capacity is required' using errcode = '23514'; end if;
  for component in select value from jsonb_array_elements(target_components)
  loop
    component_position := component_position + 1;
    begin
      component_id := (component ->> 'stock_item_id')::uuid;
      component_role_value := (component ->> 'component_role')::public.production_component_role;
      component_quantity := case component_role_value
        when 'carton'::public.production_component_role then round(1::numeric / capacity, 6)
        else (component ->> 'quantity_per_bottle')::numeric end;
    exception when others then
      raise exception 'Every production component requires valid item, role, and quantity'
        using errcode = '22023';
    end;
    if component_id is null or component_quantity is null or component_quantity <= 0 then
      raise exception 'Every component quantity must be greater than zero' using errcode = '22023';
    end if;
    insert into public.production_recipe_components (
      recipe_id, component_stock_item_id, quantity_per_bottle, component_role, position
    ) values (target_recipe_id, component_id, component_quantity, component_role_value, component_position);
  end loop;
  if not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = target_recipe_id and component.component_role = 'prepared_bottle')
    or not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = target_recipe_id and component.component_role = 'bulk_lubricant')
    or not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = target_recipe_id and component.component_role = 'seal')
    or not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = target_recipe_id and component.component_role = 'carton') then
    raise exception 'Production recipe requires prepared bottle, bulk lubricant, seal, and carton components'
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.create_production_recipe(
  target_product_format_id uuid, target_output_stock_item_id uuid, target_components jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_planning_actor(array['admin'::public.app_role]);
declare result public.production_recipes;
begin
  insert into public.production_recipes (
    product_format_id, output_stock_item_id, version, is_active, created_by
  ) values (target_product_format_id, target_output_stock_item_id, 1, true, actor_id)
  returning * into result;
  perform public.insert_production_recipe_components(result.id, target_components);
  return public.production_recipe_payload(result.id);
exception when unique_violation then
  raise exception 'An active production recipe already exists for this product format or output item'
    using errcode = '23505';
end;
$$;

create or replace function public.update_production_recipe(
  target_recipe_id uuid, target_output_stock_item_id uuid, target_components jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_planning_actor(array['admin'::public.app_role]);
declare prior public.production_recipes;
declare replacement public.production_recipes;
begin
  select recipe.* into prior from public.production_recipes recipe
  where recipe.id = target_recipe_id for update;
  if not found then raise exception 'Production recipe not found' using errcode = 'P0002'; end if;
  if not prior.is_active then raise exception 'Only an active recipe can be superseded' using errcode = '23514'; end if;
  update public.production_recipes recipe set is_active = false where recipe.id = prior.id;
  insert into public.production_recipes (
    product_format_id, output_stock_item_id, version, is_active, supersedes_recipe_id, created_by
  ) values (
    prior.product_format_id, target_output_stock_item_id, prior.version + 1, true, prior.id, actor_id
  ) returning * into replacement;
  perform public.insert_production_recipe_components(replacement.id, target_components);
  return public.production_recipe_payload(replacement.id);
exception when unique_violation then
  raise exception 'An active production recipe already exists for this output item'
    using errcode = '23505';
end;
$$;

create or replace function public.deactivate_production_recipe(target_recipe_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result public.production_recipes;
begin
  perform public.assert_planning_actor(array['admin'::public.app_role]);
  select recipe.* into result from public.production_recipes recipe
  where recipe.id = target_recipe_id for update;
  if not found then raise exception 'Production recipe not found' using errcode = 'P0002'; end if;
  if result.is_active then
    update public.production_recipes recipe set is_active = false where recipe.id = result.id
    returning * into result;
  end if;
  return public.production_recipe_payload(result.id);
end;
$$;

create or replace function public.create_production_plan_draft(
  target_production_date date,
  target_location_id uuid default null,
  target_priority integer default null,
  target_assigned_to uuid default null,
  target_comment text default null
)
returns public.production_plans language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_planning_actor(array[
  'admin'::public.app_role, 'management'::public.app_role
]);
declare effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
declare result public.production_plans;
begin
  if target_production_date is null then raise exception 'Production date is required' using errcode = '22023'; end if;
  if target_priority is not null and target_priority not between 1 and 5 then
    raise exception 'Priority must be between 1 and 5' using errcode = '22023';
  end if;
  if not exists (select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;
  if target_assigned_to is not null and not exists (select 1 from public.profiles profile
    join public.user_environment_access access on access.user_id = profile.id and access.is_active
    join public.environments environment on environment.id = access.environment_id and environment.is_active
    where profile.id = target_assigned_to and profile.is_active and profile.role = 'factory'
      and environment.code = 'FACOLUB') then
    raise exception 'Assigned Factory user is not active in FACOLUB' using errcode = 'P0002';
  end if;
  insert into public.production_plans (
    production_date, location_id, status, priority, assigned_to, comment, created_by
  ) values (
    target_production_date, effective_location_id, 'draft', target_priority,
    target_assigned_to, nullif(trim(target_comment), ''), actor_id
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.update_production_plan_draft(
  target_plan_id uuid, target_production_date date, target_location_id uuid,
  target_priority integer, target_assigned_to uuid, target_comment text
)
returns public.production_plans language plpgsql security definer set search_path = '' as $$
declare result public.production_plans;
begin
  perform public.assert_planning_actor(array['admin'::public.app_role, 'management'::public.app_role]);
  select plan.* into result from public.production_plans plan where plan.id = target_plan_id for update;
  if not found then raise exception 'Production plan not found' using errcode = 'P0002'; end if;
  if result.status <> 'draft' then raise exception 'Only draft production plans can be edited' using errcode = '23514'; end if;
  if target_production_date is null or target_priority is not null and target_priority not between 1 and 5 then
    raise exception 'Valid production date and priority are required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.stock_locations location
    where location.id = target_location_id and location.is_active) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;
  if target_assigned_to is not null and not exists (
    select 1 from public.profiles profile
    join public.user_environment_access access on access.user_id = profile.id and access.is_active
    join public.environments environment on environment.id = access.environment_id and environment.is_active
    where profile.id = target_assigned_to and profile.is_active and profile.role = 'factory'
      and environment.code = 'FACOLUB'
  ) then
    raise exception 'Assigned Factory user is not active in FACOLUB' using errcode = 'P0002';
  end if;
  update public.production_plans plan set production_date = target_production_date,
    location_id = target_location_id, priority = target_priority,
    assigned_to = target_assigned_to, comment = nullif(trim(target_comment), '')
  where plan.id = result.id returning * into result;
  return result;
end;
$$;

create or replace function public.save_production_plan_item(
  target_plan_id uuid, target_item_id uuid, target_product_format_id uuid,
  target_quantity numeric, target_mode public.planning_quantity_mode,
  target_position integer default null
)
returns public.production_plan_items language plpgsql security definer set search_path = '' as $$
declare plan public.production_plans;
declare preview jsonb;
declare result public.production_plan_items;
declare effective_position integer;
begin
  perform public.assert_planning_actor(array['admin'::public.app_role, 'management'::public.app_role]);
  select candidate.* into plan from public.production_plans candidate
  where candidate.id = target_plan_id for update;
  if not found then raise exception 'Production plan not found' using errcode = 'P0002'; end if;
  if plan.status <> 'draft' then raise exception 'Only draft production plans can be edited' using errcode = '23514'; end if;
  preview := public.calculate_production_requirements(
    target_product_format_id, target_quantity, target_mode, plan.location_id
  );
  effective_position := coalesce(target_position,
    (select coalesce(max(item.position), 0) + 1 from public.production_plan_items item
     where item.production_plan_id = plan.id));
  if effective_position <= 0 then raise exception 'Item position must be positive' using errcode = '22023'; end if;
  if target_item_id is null then
    insert into public.production_plan_items (
      production_plan_id, product_format_id, recipe_id, quantity_mode, entered_quantity,
      planned_bottles, planned_cartons, bottles_per_carton,
      product_name_snapshot, format_name_snapshot,
      output_stock_item_id, output_item_name_snapshot, position
    ) values (
      plan.id, target_product_format_id, (preview ->> 'recipe_id')::uuid, target_mode, target_quantity,
      (preview ->> 'planned_bottles')::numeric, (preview ->> 'planned_cartons')::numeric,
      (preview ->> 'bottles_per_carton')::integer,
      preview ->> 'product_name', preview ->> 'format_name',
      (preview -> 'output' ->> 'stock_item_id')::uuid, preview -> 'output' ->> 'name', effective_position
    ) returning * into result;
  else
    update public.production_plan_items item set product_format_id = target_product_format_id,
      recipe_id = (preview ->> 'recipe_id')::uuid, quantity_mode = target_mode,
      entered_quantity = target_quantity, planned_bottles = (preview ->> 'planned_bottles')::numeric,
      planned_cartons = (preview ->> 'planned_cartons')::numeric,
      bottles_per_carton = (preview ->> 'bottles_per_carton')::integer,
      product_name_snapshot = preview ->> 'product_name',
      format_name_snapshot = preview ->> 'format_name',
      output_stock_item_id = (preview -> 'output' ->> 'stock_item_id')::uuid,
      output_item_name_snapshot = preview -> 'output' ->> 'name', position = effective_position
    where item.id = target_item_id and item.production_plan_id = plan.id returning * into result;
    if not found then raise exception 'Production plan item not found' using errcode = 'P0002'; end if;
  end if;
  return result;
end;
$$;

create or replace function public.remove_production_plan_item(target_item_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare result public.production_plan_items;
begin
  perform public.assert_planning_actor(array['admin'::public.app_role, 'management'::public.app_role]);
  select item.* into result from public.production_plan_items item where item.id = target_item_id;
  if not found then raise exception 'Production plan item not found' using errcode = 'P0002'; end if;
  delete from public.production_plan_items item where item.id = result.id;
end;
$$;

create or replace function public.plan_production_plan(target_plan_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_planning_actor(array['admin'::public.app_role, 'management'::public.app_role]);
declare plan public.production_plans;
begin
  select candidate.* into plan from public.production_plans candidate where candidate.id = target_plan_id for update;
  if not found then raise exception 'Production plan not found' using errcode = 'P0002'; end if;
  if plan.status = 'planned' then
    return jsonb_build_object('plan_id', plan.id, 'plan_number', plan.plan_number, 'status', plan.status);
  end if;
  if plan.status <> 'draft' then raise exception 'Only a draft plan can be marked planned' using errcode = '23514'; end if;
  if not exists (select 1 from public.production_plan_items item where item.production_plan_id = plan.id) then
    raise exception 'Production plan requires at least one item' using errcode = '23514';
  end if;
  perform public.snapshot_production_plan_requirements(plan.id);
  update public.production_plans candidate set plan_number = public.allocate_production_plan_number(plan.production_date),
    status = 'planned' where candidate.id = plan.id returning candidate.* into plan;
  return jsonb_build_object('plan_id', plan.id, 'plan_number', plan.plan_number, 'status', plan.status);
end;
$$;

create or replace function public.validate_production_plan(target_plan_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := public.assert_planning_actor(array['admin'::public.app_role, 'management'::public.app_role]);
declare plan public.production_plans;
begin
  select candidate.* into plan from public.production_plans candidate where candidate.id = target_plan_id for update;
  if not found then raise exception 'Production plan not found' using errcode = 'P0002'; end if;
  if plan.status = 'validated' then
    return jsonb_build_object('plan_id', plan.id, 'plan_number', plan.plan_number, 'status', plan.status);
  end if;
  if plan.status not in ('draft', 'planned') then
    raise exception 'Only a draft or planned production plan can be validated' using errcode = '23514';
  end if;
  if not exists (select 1 from public.production_plan_items item where item.production_plan_id = plan.id) then
    raise exception 'Production plan requires at least one item' using errcode = '23514';
  end if;
  perform public.snapshot_production_plan_requirements(plan.id);
  update public.production_plans candidate set
    plan_number = coalesce(candidate.plan_number, public.allocate_production_plan_number(candidate.production_date)),
    status = 'validated', validated_by = actor_id, validated_at = now()
  where candidate.id = plan.id returning candidate.* into plan;
  return jsonb_build_object('plan_id', plan.id, 'plan_number', plan.plan_number, 'status', plan.status);
end;
$$;

create or replace function public.cancel_production_plan(target_plan_id uuid)
returns public.production_plans language plpgsql security definer set search_path = '' as $$
declare result public.production_plans;
begin
  perform public.assert_planning_actor(array['admin'::public.app_role, 'management'::public.app_role]);
  select plan.* into result from public.production_plans plan where plan.id = target_plan_id for update;
  if not found then raise exception 'Production plan not found' using errcode = 'P0002'; end if;
  if result.status = 'cancelled' then return result; end if;
  update public.production_plans plan set status = 'cancelled' where plan.id = result.id returning * into result;
  return result;
end;
$$;

create or replace function public.get_production_plan(target_plan_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := public.assert_planning_actor(array[
  'admin'::public.app_role, 'management'::public.app_role
]);
declare plan public.production_plans;
declare result jsonb;
begin
  select candidate.* into plan from public.production_plans candidate where candidate.id = target_plan_id;
  if not found then raise exception 'Production plan not found' using errcode = 'P0002'; end if;
  select jsonb_build_object(
    'plan', to_jsonb(candidate), 'location_name', location.name,
    'created_by_name', creator.display_name,
    'assigned_to_name', assignee.display_name,
    'validated_by_name', validator.display_name,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'item', to_jsonb(item),
      'requirements', coalesce((select jsonb_agg(to_jsonb(requirement)
        order by requirement.component_role, requirement.id)
        from public.production_plan_requirements requirement
        where requirement.production_plan_item_id = item.id), '[]'::jsonb)
    ) order by item.position, item.id)
    from public.production_plan_items item where item.production_plan_id = candidate.id), '[]'::jsonb)
  ) into result
  from public.production_plans candidate
  join public.stock_locations location on location.id = candidate.location_id
  join public.profiles creator on creator.id = candidate.created_by
  left join public.profiles assignee on assignee.id = candidate.assigned_to
  left join public.profiles validator on validator.id = candidate.validated_by
  where candidate.id = plan.id;
  return result;
end;
$$;

create or replace function public.list_production_plans(
  target_date_from date default null, target_date_to date default null,
  target_product_id uuid default null, target_status public.production_plan_status default null,
  target_sufficiency text default null, target_limit integer default 200
)
returns table (
  id uuid, plan_number text, production_date date, status public.production_plan_status,
  priority integer, assigned_to uuid, assigned_to_name text,
  created_by uuid, created_by_name text, item_count bigint,
  product_summary text, quantity_summary text, sufficiency text, created_at timestamptz
) language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := public.assert_planning_actor(array[
  'admin'::public.app_role, 'management'::public.app_role
]);
begin
  return query select plan.id, plan.plan_number, plan.production_date, plan.status,
    plan.priority, plan.assigned_to, assignee.display_name,
    plan.created_by, creator.display_name, coalesce(item_summary.item_count, 0),
    coalesce(item_summary.product_summary, ''), coalesce(item_summary.quantity_summary, ''),
    case
      when coalesce(requirement_summary.requirement_count, 0) = 0 then 'not_calculated'
      when requirement_summary.insufficient_count > 0 then 'insufficient'
      when requirement_summary.warning_count > 0 then 'warning'
      else 'sufficient'
    end, plan.created_at
  from public.production_plans plan
  join public.profiles creator on creator.id = plan.created_by
  left join public.profiles assignee on assignee.id = plan.assigned_to
  left join lateral (
    select count(item.id) as item_count,
      string_agg(distinct item.product_name_snapshot || ' ' || item.format_name_snapshot, ', ') as product_summary,
      string_agg(item.planned_bottles::text || ' bottles', ', ' order by item.position) as quantity_summary
    from public.production_plan_items item
    where item.production_plan_id = plan.id
  ) item_summary on true
  left join lateral (
    select
      count(requirement.id) as requirement_count,
      count(requirement.id) filter (where not requirement.sufficient) as insufficient_count,
      count(requirement.id) filter (where requirement.sufficient and requirement.below_minimum_after_plan) as warning_count
    from public.production_plan_items item
    join public.production_plan_requirements requirement
      on requirement.production_plan_item_id = item.id
    where item.production_plan_id = plan.id
  ) requirement_summary on true
  where (target_date_from is null or plan.production_date >= target_date_from)
    and (target_date_to is null or plan.production_date <= target_date_to)
    and (target_status is null or plan.status = target_status)
    and (target_product_id is null or exists (
      select 1 from public.production_plan_items item
      join public.product_formats product_format on product_format.id = item.product_format_id
      where item.production_plan_id = plan.id and product_format.product_id = target_product_id
    ))
    and (target_sufficiency is null or target_sufficiency = case
      when coalesce(requirement_summary.requirement_count, 0) = 0 then 'not_calculated'
      when requirement_summary.insufficient_count > 0 then 'insufficient'
      when requirement_summary.warning_count > 0 then 'warning'
      else 'sufficient' end)
  order by plan.production_date, coalesce(plan.priority, 5), plan.created_at
  limit least(greatest(coalesce(target_limit, 200), 1), 500);
end;
$$;

create or replace function public.list_factory_production_missions(target_date date default current_date)
returns table (
  plan_id uuid, plan_number text, production_date date, priority integer,
  product_name text, format_name text, planned_bottles numeric,
  planned_cartons numeric, status public.production_plan_status
) language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := public.assert_planning_actor(array['factory'::public.app_role]);
begin
  return query select plan.id, plan.plan_number, plan.production_date, plan.priority,
    item.product_name_snapshot, item.format_name_snapshot,
    item.planned_bottles, item.planned_cartons, plan.status
  from public.production_plans plan
  join public.production_plan_items item on item.production_plan_id = plan.id
  where plan.production_date = coalesce(target_date, current_date)
    and plan.status in ('planned', 'validated')
    and (plan.assigned_to is null or plan.assigned_to = actor_id)
  order by coalesce(plan.priority, 5), plan.created_at, item.position;
end;
$$;

-- Internal primitives.
revoke all on function public.assert_planning_actor(public.app_role[]) from public, anon, authenticated;
revoke all on function public.allocate_production_plan_number(date) from public, anon, authenticated;
revoke all on function public.production_recipe_payload(uuid) from public, anon, authenticated;
revoke all on function public.insert_production_recipe_components(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.snapshot_production_plan_requirements(uuid) from public, anon, authenticated;

-- Authenticated APIs; every function performs its own role and FACOLUB checks.
revoke all on function public.save_planning_product(uuid,text,text,boolean) from public, anon;
revoke all on function public.save_product_format(uuid,uuid,uuid,boolean) from public, anon;
revoke all on function public.configure_packaging_rule(uuid,integer) from public, anon;
revoke all on function public.create_production_recipe(uuid,uuid,jsonb) from public, anon;
revoke all on function public.update_production_recipe(uuid,uuid,jsonb) from public, anon;
revoke all on function public.deactivate_production_recipe(uuid) from public, anon;
revoke all on function public.create_production_plan_draft(date,uuid,integer,uuid,text) from public, anon;
revoke all on function public.update_production_plan_draft(uuid,date,uuid,integer,uuid,text) from public, anon;
revoke all on function public.save_production_plan_item(uuid,uuid,uuid,numeric,public.planning_quantity_mode,integer) from public, anon;
revoke all on function public.remove_production_plan_item(uuid) from public, anon;
revoke all on function public.plan_production_plan(uuid) from public, anon;
revoke all on function public.validate_production_plan(uuid) from public, anon;
revoke all on function public.cancel_production_plan(uuid) from public, anon;
revoke all on function public.get_production_plan(uuid) from public, anon;
revoke all on function public.list_production_plans(date,date,uuid,public.production_plan_status,text,integer) from public, anon;
revoke all on function public.list_factory_production_missions(date) from public, anon;

grant execute on function public.save_planning_product(uuid,text,text,boolean) to authenticated;
grant execute on function public.save_product_format(uuid,uuid,uuid,boolean) to authenticated;
grant execute on function public.configure_packaging_rule(uuid,integer) to authenticated;
grant execute on function public.create_production_recipe(uuid,uuid,jsonb) to authenticated;
grant execute on function public.update_production_recipe(uuid,uuid,jsonb) to authenticated;
grant execute on function public.deactivate_production_recipe(uuid) to authenticated;
grant execute on function public.create_production_plan_draft(date,uuid,integer,uuid,text) to authenticated;
grant execute on function public.update_production_plan_draft(uuid,date,uuid,integer,uuid,text) to authenticated;
grant execute on function public.save_production_plan_item(uuid,uuid,uuid,numeric,public.planning_quantity_mode,integer) to authenticated;
grant execute on function public.remove_production_plan_item(uuid) to authenticated;
grant execute on function public.plan_production_plan(uuid) to authenticated;
grant execute on function public.validate_production_plan(uuid) to authenticated;
grant execute on function public.cancel_production_plan(uuid) to authenticated;
grant execute on function public.get_production_plan(uuid) to authenticated;
grant execute on function public.list_production_plans(date,date,uuid,public.production_plan_status,text,integer) to authenticated;
grant execute on function public.list_factory_production_missions(date) to authenticated;

-- Verification query:
select routine_name, security_type from information_schema.routines
where routine_schema = 'public' and routine_name in (
  'calculate_production_requirements', 'create_production_plan_draft',
  'save_production_plan_item', 'plan_production_plan', 'validate_production_plan',
  'cancel_production_plan', 'get_production_plan', 'list_production_plans',
  'list_factory_production_missions', 'configure_packaging_rule'
) order by routine_name;
