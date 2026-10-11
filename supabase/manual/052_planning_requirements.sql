-- SOMA / FACOLUB production planning module - 052 authoritative requirements
-- Depends on: 050-051.
-- S4 calculations are previews/snapshots only: no movement and no reservation.

create table if not exists public.production_plan_requirements (
  id uuid primary key default gen_random_uuid(),
  production_plan_item_id uuid not null references public.production_plan_items(id) on delete cascade,
  recipe_component_id uuid references public.production_recipe_components(id) on delete restrict,
  component_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  component_name_snapshot text not null,
  component_role public.production_component_role not null,
  unit public.stock_unit not null,
  quantity_per_bottle numeric(20,6) not null,
  quantity_required numeric(20,3) not null,
  physical_quantity_snapshot numeric(20,3) not null,
  reserved_quantity_snapshot numeric(20,3) not null,
  available_quantity_snapshot numeric(20,3) not null,
  missing_quantity_snapshot numeric(20,3) not null,
  projected_available_after_plan numeric(20,3) not null,
  minimum_stock_snapshot numeric(20,3),
  sufficient boolean not null,
  below_minimum_after_plan boolean not null,
  created_at timestamptz not null default now(),
  constraint production_plan_requirements_quantities_positive check (
    quantity_per_bottle > 0 and quantity_required > 0
  ),
  constraint production_plan_requirements_missing_nonnegative check (missing_quantity_snapshot >= 0),
  constraint production_plan_requirements_one_component
    unique (production_plan_item_id, component_stock_item_id)
);

create index if not exists production_plan_requirements_item_idx
  on public.production_plan_requirements (production_plan_item_id, component_role);
create index if not exists production_plan_requirements_component_idx
  on public.production_plan_requirements (component_stock_item_id, production_plan_item_id);

alter table public.production_plan_requirements enable row level security;
revoke all on public.production_plan_requirements from anon, authenticated;

create or replace function public.normalize_production_quantity(
  target_product_format_id uuid,
  target_quantity numeric,
  target_mode public.planning_quantity_mode
)
returns table (
  planned_bottles numeric,
  planned_cartons numeric,
  bottles_per_carton integer
)
language plpgsql stable security definer set search_path = '' as $$
declare capacity integer;
declare format_id_value uuid;
begin
  if target_quantity is null or target_quantity <= 0 or mod(target_quantity, 1) <> 0 then
    raise exception 'Planning quantity must be a positive whole number' using errcode = '22023';
  end if;
  if target_mode is null then
    raise exception 'Planning quantity mode is required' using errcode = '22023';
  end if;
  select product_format.format_id into format_id_value
  from public.product_formats product_format
  join public.products product on product.id = product_format.product_id and product.is_active
  join public.packaging_formats format on format.id = product_format.format_id and format.is_active
  where product_format.id = target_product_format_id and product_format.is_active;
  if format_id_value is null then raise exception 'Active product format not found' using errcode = 'P0002'; end if;
  select rule.bottles_per_carton into capacity
  from public.packaging_rules rule
  where rule.format_id = format_id_value and rule.is_active;
  if capacity is null then
    raise exception 'Active carton capacity is not configured for this format' using errcode = '23514';
  end if;
  if target_mode::text = 'cartons' then
    planned_bottles := target_quantity * capacity;
    planned_cartons := target_quantity;
    bottles_per_carton := capacity;
    return next;
    return;
  elsif target_mode::text = 'bottles' then
    if mod(target_quantity, capacity) <> 0 then
      raise exception 'Bottle quantity must be a multiple of the carton capacity (%)', capacity
        using errcode = '23514';
    end if;
    planned_bottles := target_quantity;
    planned_cartons := target_quantity / capacity;
    bottles_per_carton := capacity;
    return next;
    return;
  end if;
  raise exception 'Unsupported planning quantity mode: %', target_mode using errcode = '22023';
  return;
end;
$$;

create or replace function public.calculate_production_requirements(
  target_product_format_id uuid,
  target_quantity numeric,
  target_mode public.planning_quantity_mode,
  target_location_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
declare normalized record;
declare recipe public.production_recipes;
declare result jsonb;
begin
  perform public.assert_stock_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  if effective_location_id is null or not exists (select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;
  select * into normalized from public.normalize_production_quantity(
    target_product_format_id, target_quantity, target_mode
  );
  select candidate.* into recipe from public.production_recipes candidate
  where candidate.product_format_id = target_product_format_id and candidate.is_active;
  if not found then raise exception 'Active production recipe not found' using errcode = 'P0002'; end if;
  if (select count(*) from public.production_recipe_components component
      where component.recipe_id = recipe.id) < 4
    or not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = recipe.id and component.component_role = 'prepared_bottle')
    or not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = recipe.id and component.component_role = 'bulk_lubricant')
    or not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = recipe.id and component.component_role = 'seal')
    or not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = recipe.id and component.component_role = 'carton') then
    raise exception 'Production recipe must contain prepared bottle, bulk lubricant, seal, and carton components'
      using errcode = '23514';
  end if;

  select jsonb_build_object(
    'product_format_id', product_format.id,
    'product_name', product.name,
    'format_name', format.name,
    'recipe_id', recipe.id,
    'recipe_version', recipe.version,
    'location_id', effective_location_id,
    'quantity_mode', target_mode,
    'entered_quantity', target_quantity,
    'planned_bottles', normalized.planned_bottles,
    'planned_cartons', normalized.planned_cartons,
    'bottles_per_carton', normalized.bottles_per_carton,
    'output', jsonb_build_object(
      'stock_item_id', output_item.id,
      'name', output_item.name,
      'quantity', normalized.planned_bottles
    ),
    'components', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recipe_component_id', component.id,
        'stock_item_id', item.id,
        'name', item.name,
        'role', component.component_role,
        'unit', item.unit,
        'quantity_per_bottle', case component.component_role
          when 'carton'::public.production_component_role
            then round(1::numeric / normalized.bottles_per_carton, 6)
          else component.quantity_per_bottle end,
        'required_quantity', required.quantity,
        'physical_quantity', quantities.physical_quantity,
        'reserved_quantity', quantities.reserved_quantity,
        'available_quantity', quantities.available_quantity,
        'missing_quantity', greatest(required.quantity - quantities.available_quantity, 0),
        'projected_available_after_plan', quantities.available_quantity - required.quantity,
        'minimum_stock', item.minimum_stock,
        'sufficient', quantities.available_quantity >= required.quantity,
        'below_minimum_after_plan', item.minimum_stock is not null
          and quantities.available_quantity - required.quantity < item.minimum_stock
      ) order by component.position, component.id)
      from public.production_recipe_components component
      join public.stock_items item on item.id = component.component_stock_item_id
      cross join lateral (
        select round(case component.component_role
          when 'carton'::public.production_component_role then normalized.planned_cartons
          else component.quantity_per_bottle * normalized.planned_bottles end, 3) as quantity
      ) required
      cross join lateral public.stock_quantities(item.id, effective_location_id) quantities
      where component.recipe_id = recipe.id
    ), '[]'::jsonb)
  ) into result
  from public.product_formats product_format
  join public.products product on product.id = product_format.product_id
  join public.packaging_formats format on format.id = product_format.format_id
  join public.stock_items output_item on output_item.id = recipe.output_stock_item_id
  where product_format.id = target_product_format_id;
  return result;
end;
$$;

create or replace function public.snapshot_production_plan_requirements(target_plan_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare plan public.production_plans;
declare plan_item public.production_plan_items;
declare component public.production_recipe_components;
declare item public.stock_items;
declare quantities record;
declare required numeric;
declare effective_per_bottle numeric;
declare preview jsonb;
begin
  select candidate.* into plan from public.production_plans candidate
  where candidate.id = target_plan_id for update;
  if not found then raise exception 'Production plan not found' using errcode = 'P0002'; end if;
  delete from public.production_plan_requirements requirement
  using public.production_plan_items line
  where line.production_plan_id = plan.id
    and requirement.production_plan_item_id = line.id;
  for plan_item in select line.* from public.production_plan_items line
    where line.production_plan_id = plan.id order by line.position, line.id
  loop
    -- A draft is normalized again against the current active recipe and carton
    -- rule at its first official transition. Once planned, its stored basis is
    -- intentionally stable even if Admin later versions the configuration.
    if plan.status = 'draft'::public.production_plan_status then
      preview := public.calculate_production_requirements(
        plan_item.product_format_id, plan_item.entered_quantity,
        plan_item.quantity_mode, plan.location_id
      );
      update public.production_plan_items line set
        recipe_id = (preview ->> 'recipe_id')::uuid,
        planned_bottles = (preview ->> 'planned_bottles')::numeric,
        planned_cartons = (preview ->> 'planned_cartons')::numeric,
        bottles_per_carton = (preview ->> 'bottles_per_carton')::integer,
        product_name_snapshot = preview ->> 'product_name',
        format_name_snapshot = preview ->> 'format_name',
        output_stock_item_id = (preview -> 'output' ->> 'stock_item_id')::uuid,
        output_item_name_snapshot = preview -> 'output' ->> 'name'
      where line.id = plan_item.id returning line.* into plan_item;
    end if;
    if plan_item.recipe_id is null or plan_item.bottles_per_carton is null then
      raise exception 'Plan item is missing its stable recipe or packaging snapshot'
        using errcode = '23514';
    end if;
    for component in select candidate.* from public.production_recipe_components candidate
      where candidate.recipe_id = plan_item.recipe_id order by candidate.position, candidate.id
    loop
      select candidate.* into item from public.stock_items candidate
      where candidate.id = component.component_stock_item_id and candidate.is_active;
      if not found then raise exception 'Active production component not found' using errcode = 'P0002'; end if;
      effective_per_bottle := case component.component_role
        when 'carton'::public.production_component_role
          then round(1::numeric / plan_item.bottles_per_carton, 6)
        else component.quantity_per_bottle end;
      required := round(case component.component_role
        when 'carton'::public.production_component_role then plan_item.planned_cartons
        else component.quantity_per_bottle * plan_item.planned_bottles end, 3);
      select * into quantities from public.stock_quantities(item.id, plan.location_id);
      insert into public.production_plan_requirements (
        production_plan_item_id, recipe_component_id, component_stock_item_id,
        component_name_snapshot, component_role, unit, quantity_per_bottle,
        quantity_required, physical_quantity_snapshot, reserved_quantity_snapshot,
        available_quantity_snapshot, missing_quantity_snapshot,
        projected_available_after_plan, minimum_stock_snapshot,
        sufficient, below_minimum_after_plan
      ) values (
        plan_item.id, component.id, item.id, item.name, component.component_role,
        item.unit, effective_per_bottle, required,
        quantities.physical_quantity, quantities.reserved_quantity, quantities.available_quantity,
        greatest(required - quantities.available_quantity, 0),
        quantities.available_quantity - required, item.minimum_stock,
        quantities.available_quantity >= required,
        item.minimum_stock is not null
          and quantities.available_quantity - required < item.minimum_stock
      );
    end loop;
  end loop;
end;
$$;

revoke all on function public.normalize_production_quantity(uuid,numeric,public.planning_quantity_mode)
  from public, anon, authenticated;
revoke all on function public.snapshot_production_plan_requirements(uuid)
  from public, anon, authenticated;
revoke all on function public.calculate_production_requirements(uuid,numeric,public.planning_quantity_mode,uuid)
  from public, anon;
grant execute on function public.calculate_production_requirements(uuid,numeric,public.planning_quantity_mode,uuid)
  to authenticated;

comment on table public.production_plan_requirements is
  'Stable S4 validation snapshots and the exact future S5 reservation source; never active reservations.';

-- Verification query:
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'production_plan_requirements'
order by ordinal_position;
