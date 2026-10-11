-- SOMA / FACOLUB prepared bottles module - 041 numbering and recipe API
-- Depends on: 040_prepared_bottles_foundation.sql

create table if not exists public.preparation_number_sequences (
  preparation_date date primary key,
  last_value bigint not null,
  constraint preparation_number_sequences_positive check (last_value > 0)
);
alter table public.preparation_number_sequences enable row level security;
revoke all on public.preparation_number_sequences from anon, authenticated;

create or replace function public.allocate_preparation_number(target_date date)
returns text language plpgsql security definer set search_path = '' as $$
declare next_value bigint;
begin
  if target_date is null then
    raise exception 'Preparation date is required for numbering' using errcode = '22023';
  end if;
  insert into public.preparation_number_sequences (preparation_date, last_value)
  values (target_date, 1)
  on conflict (preparation_date) do update
    set last_value = public.preparation_number_sequences.last_value + 1
  returning last_value into next_value;
  return format('PREP-%s-%s', to_char(target_date, 'DDMMYY'), lpad(next_value::text, 2, '0'));
end;
$$;

create or replace function public.assert_prepared_bottle_actor(
  required_roles public.app_role[] default array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]
)
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  return public.assert_stock_actor(required_roles);
end;
$$;

create or replace function public.prepared_bottle_recipe_payload(target_recipe_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', recipe.id,
    'output_stock_item_id', recipe.output_stock_item_id,
    'output_stock_item_name', output_item.name,
    'product_format_id', recipe.product_format_id,
    'product_name', recipe.product_name,
    'format_name', recipe.format_name,
    'version', recipe.version,
    'is_active', recipe.is_active,
    'supersedes_recipe_id', recipe.supersedes_recipe_id,
    'created_by', recipe.created_by,
    'created_at', recipe.created_at,
    'updated_at', recipe.updated_at,
    'components', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', component.id,
        'stock_item_id', component.component_stock_item_id,
        'stock_item_name', item.name,
        'category', item.category,
        'unit', item.unit,
        'quantity_per_output', component.quantity_per_output,
        'position', component.position
      ) order by component.position, component.id)
      from public.prepared_bottle_recipe_components component
      join public.stock_items item on item.id = component.component_stock_item_id
      where component.recipe_id = recipe.id
    ), '[]'::jsonb)
  )
  from public.prepared_bottle_recipes recipe
  join public.stock_items output_item on output_item.id = recipe.output_stock_item_id
  where recipe.id = target_recipe_id
$$;

create or replace function public.insert_prepared_bottle_recipe_components(
  target_recipe_id uuid,
  target_components jsonb
)
returns void language plpgsql security definer set search_path = '' as $$
declare component jsonb;
declare component_id uuid;
declare component_quantity numeric;
declare component_position integer := 0;
begin
  if target_components is null or jsonb_typeof(target_components) <> 'array'
    or jsonb_array_length(target_components) < 2 then
    raise exception 'Recipe requires an empty bottle and at least one label component'
      using errcode = '22023';
  end if;
  for component in select value from jsonb_array_elements(target_components)
  loop
    component_position := component_position + 1;
    begin
      component_id := (component ->> 'stock_item_id')::uuid;
      component_quantity := (component ->> 'quantity_per_output')::numeric;
    exception when others then
      raise exception 'Every recipe component requires a valid stock_item_id and quantity_per_output'
        using errcode = '22023';
    end;
    if component_id is null or component_quantity is null or component_quantity <= 0 then
      raise exception 'Every recipe component quantity must be greater than zero'
        using errcode = '22023';
    end if;
    insert into public.prepared_bottle_recipe_components (
      recipe_id, component_stock_item_id, quantity_per_output, position
    ) values (target_recipe_id, component_id, component_quantity, component_position);
  end loop;
  if not exists (
    select 1 from public.prepared_bottle_recipe_components component
    join public.stock_items item on item.id = component.component_stock_item_id
    where component.recipe_id = target_recipe_id
      and item.category = 'empty_bottle'::public.stock_item_category
  ) or not exists (
    select 1 from public.prepared_bottle_recipe_components component
    join public.stock_items item on item.id = component.component_stock_item_id
    where component.recipe_id = target_recipe_id
      and item.category = 'label'::public.stock_item_category
  ) then
    raise exception 'Recipe requires an empty bottle and at least one label component'
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.create_prepared_bottle_recipe(
  target_output_stock_item_id uuid,
  target_product_format_id uuid,
  target_product_name text,
  target_format_name text,
  target_components jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare result public.prepared_bottle_recipes;
begin
  actor_id := public.assert_prepared_bottle_actor(array['admin'::public.app_role]);
  if target_product_name is null or char_length(trim(target_product_name)) < 1
    or target_format_name is null or char_length(trim(target_format_name)) < 1 then
    raise exception 'Product and format are required' using errcode = '22023';
  end if;
  insert into public.prepared_bottle_recipes (
    output_stock_item_id, product_format_id, product_name, format_name, version, is_active, created_by
  ) values (
    target_output_stock_item_id, target_product_format_id, trim(target_product_name),
    trim(target_format_name), 1, true, actor_id
  ) returning * into result;
  perform public.insert_prepared_bottle_recipe_components(result.id, target_components);
  return public.prepared_bottle_recipe_payload(result.id);
exception when unique_violation then
  raise exception 'An active prepared bottle recipe already exists for this product, format, or output item'
    using errcode = '23505';
end;
$$;

create or replace function public.update_prepared_bottle_recipe(
  target_recipe_id uuid,
  target_output_stock_item_id uuid,
  target_product_format_id uuid,
  target_product_name text,
  target_format_name text,
  target_components jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare prior public.prepared_bottle_recipes;
declare replacement public.prepared_bottle_recipes;
begin
  actor_id := public.assert_prepared_bottle_actor(array['admin'::public.app_role]);
  select recipe.* into prior from public.prepared_bottle_recipes recipe
  where recipe.id = target_recipe_id for update;
  if not found then raise exception 'Prepared bottle recipe not found' using errcode = 'P0002'; end if;
  if not prior.is_active then
    raise exception 'Only an active recipe can be superseded' using errcode = '23514';
  end if;
  if target_product_name is null or char_length(trim(target_product_name)) < 1
    or target_format_name is null or char_length(trim(target_format_name)) < 1 then
    raise exception 'Product and format are required' using errcode = '22023';
  end if;

  -- Always create a new version. Existing drafts have frozen component snapshots;
  -- confirmed rows and their movements continue to reference the prior version.
  update public.prepared_bottle_recipes recipe set is_active = false where recipe.id = prior.id;
  insert into public.prepared_bottle_recipes (
    output_stock_item_id, product_format_id, product_name, format_name, version,
    is_active, supersedes_recipe_id, created_by
  ) values (
    target_output_stock_item_id, target_product_format_id, trim(target_product_name),
    trim(target_format_name), prior.version + 1, true, prior.id, actor_id
  ) returning * into replacement;
  perform public.insert_prepared_bottle_recipe_components(replacement.id, target_components);
  return public.prepared_bottle_recipe_payload(replacement.id);
exception when unique_violation then
  raise exception 'An active prepared bottle recipe already exists for this product, format, or output item'
    using errcode = '23505';
end;
$$;

create or replace function public.deactivate_prepared_bottle_recipe(target_recipe_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result public.prepared_bottle_recipes;
begin
  perform public.assert_prepared_bottle_actor(array['admin'::public.app_role]);
  select recipe.* into result from public.prepared_bottle_recipes recipe
  where recipe.id = target_recipe_id for update;
  if not found then raise exception 'Prepared bottle recipe not found' using errcode = 'P0002'; end if;
  if result.is_active then
    update public.prepared_bottle_recipes recipe set is_active = false
    where recipe.id = result.id returning * into result;
  end if;
  return public.prepared_bottle_recipe_payload(result.id);
end;
$$;

create or replace function public.get_prepared_bottle_recipe(target_recipe_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  perform public.assert_prepared_bottle_actor();
  result := public.prepared_bottle_recipe_payload(target_recipe_id);
  if result is null then raise exception 'Prepared bottle recipe not found' using errcode = 'P0002'; end if;
  return result;
end;
$$;

create or replace function public.list_prepared_bottle_recipes(target_include_inactive boolean default false)
returns table (
  id uuid, output_stock_item_id uuid, output_stock_item_name text,
  product_format_id uuid, product_name text, format_name text,
  version integer, is_active boolean, component_count bigint, updated_at timestamptz
) language plpgsql stable security definer set search_path = '' as $$
declare actor_role public.app_role;
begin
  perform public.assert_prepared_bottle_actor();
  actor_role := public.current_app_role();
  if coalesce(target_include_inactive, false) and actor_role <> 'admin'::public.app_role then
    raise exception 'Only Admin may list inactive recipe versions' using errcode = '42501';
  end if;
  return query select recipe.id, recipe.output_stock_item_id, output_item.name,
    recipe.product_format_id, recipe.product_name, recipe.format_name,
    recipe.version, recipe.is_active, count(component.id), recipe.updated_at
  from public.prepared_bottle_recipes recipe
  join public.stock_items output_item on output_item.id = recipe.output_stock_item_id
  left join public.prepared_bottle_recipe_components component on component.recipe_id = recipe.id
  where recipe.is_active or coalesce(target_include_inactive, false)
  group by recipe.id, output_item.name
  order by recipe.product_name, recipe.format_name, recipe.version desc;
end;
$$;

revoke all on function public.allocate_preparation_number(date) from public, anon, authenticated;
revoke all on function public.assert_prepared_bottle_actor(public.app_role[]) from public, anon, authenticated;
revoke all on function public.prepared_bottle_recipe_payload(uuid) from public, anon, authenticated;
revoke all on function public.insert_prepared_bottle_recipe_components(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.create_prepared_bottle_recipe(uuid,uuid,text,text,jsonb) from public, anon;
revoke all on function public.update_prepared_bottle_recipe(uuid,uuid,uuid,text,text,jsonb) from public, anon;
revoke all on function public.deactivate_prepared_bottle_recipe(uuid) from public, anon;
revoke all on function public.get_prepared_bottle_recipe(uuid) from public, anon;
revoke all on function public.list_prepared_bottle_recipes(boolean) from public, anon;
grant execute on function public.create_prepared_bottle_recipe(uuid,uuid,text,text,jsonb) to authenticated;
grant execute on function public.update_prepared_bottle_recipe(uuid,uuid,uuid,text,text,jsonb) to authenticated;
grant execute on function public.deactivate_prepared_bottle_recipe(uuid) to authenticated;
grant execute on function public.get_prepared_bottle_recipe(uuid) to authenticated;
grant execute on function public.list_prepared_bottle_recipes(boolean) to authenticated;

-- Verification query (read-only; does not consume a number):
select preparation_date, last_value from public.preparation_number_sequences
order by preparation_date desc limit 20;
