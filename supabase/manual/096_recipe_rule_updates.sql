-- FACOLUB post-catalog patch - 096 prospective recipe packaging updates
-- Depends on 094. Existing recipe versions and production history are retained.
-- Only active recipes that already contain prepared-bottle and bulk mappings are
-- versioned. Missing operational mappings are reported, never guessed.

do $$
declare current_recipe public.production_recipes;
declare replacement_id uuid;
declare resolved record;
declare next_version integer;
declare next_position integer;
declare already_matches boolean;
begin
  for current_recipe in
    select recipe.*
    from public.production_recipes recipe
    join public.product_formats product_format on product_format.id = recipe.product_format_id
    where recipe.is_active
      and product_format.official_catalog_number between 1 and 41
    order by recipe.product_format_id
  loop
    select * into resolved
    from public.resolve_product_packaging_rule(current_recipe.product_format_id);
    if not found or resolved.rule_id is null then continue; end if;

    -- Bulk oil and prepared-bottle identity remain business mappings. Never infer them.
    if not exists (
      select 1 from public.production_recipe_components component
      where component.recipe_id = current_recipe.id
        and component.component_role = 'prepared_bottle'::public.production_component_role
    ) or not exists (
      select 1 from public.production_recipe_components component
      where component.recipe_id = current_recipe.id
        and component.component_role = 'bulk_lubricant'::public.production_component_role
    ) then
      continue;
    end if;

    select
      exists (
        select 1 from public.production_recipe_components component
        where component.recipe_id = current_recipe.id
          and component.component_role = 'seal'::public.production_component_role
          and component.component_stock_item_id = resolved.seal_stock_item_id
          and component.quantity_per_bottle = 1
      ) and (
        (resolved.carton_stock_item_id is null and not exists (
          select 1 from public.production_recipe_components component
          where component.recipe_id = current_recipe.id
            and component.component_role = 'carton'::public.production_component_role
        ))
        or
        (resolved.carton_stock_item_id is not null and exists (
          select 1 from public.production_recipe_components component
          where component.recipe_id = current_recipe.id
            and component.component_role = 'carton'::public.production_component_role
            and component.component_stock_item_id = resolved.carton_stock_item_id
            and component.quantity_per_bottle = round(1::numeric / resolved.bottles_per_carton, 6)
        ))
      ) into already_matches;

    if already_matches then continue; end if;

    select coalesce(max(recipe.version), 0) + 1 into next_version
    from public.production_recipes recipe
    where recipe.product_format_id = current_recipe.product_format_id;

    update public.production_recipes recipe set is_active = false
    where recipe.id = current_recipe.id;

    insert into public.production_recipes (
      product_format_id, output_stock_item_id, version, is_active,
      supersedes_recipe_id, created_by
    ) values (
      current_recipe.product_format_id, current_recipe.output_stock_item_id,
      next_version, true, current_recipe.id, current_recipe.created_by
    ) returning id into replacement_id;

    insert into public.production_recipe_components (
      recipe_id, component_stock_item_id, quantity_per_bottle, component_role, position
    )
    select replacement_id, component.component_stock_item_id,
      component.quantity_per_bottle, component.component_role, component.position
    from public.production_recipe_components component
    where component.recipe_id = current_recipe.id
      and component.component_role not in (
        'seal'::public.production_component_role,
        'carton'::public.production_component_role
      );

    select coalesce(max(component.position), 0) + 1 into next_position
    from public.production_recipe_components component
    where component.recipe_id = replacement_id;

    insert into public.production_recipe_components (
      recipe_id, component_stock_item_id, quantity_per_bottle, component_role, position
    ) values (
      replacement_id, resolved.seal_stock_item_id, 1,
      'seal'::public.production_component_role, next_position
    );

    if resolved.carton_stock_item_id is not null then
      insert into public.production_recipe_components (
        recipe_id, component_stock_item_id, quantity_per_bottle, component_role, position
      ) values (
        replacement_id, resolved.carton_stock_item_id,
        round(1::numeric / resolved.bottles_per_carton, 6),
        'carton'::public.production_component_role, next_position + 1
      );
    end if;
  end loop;
end
$$;

-- Planning now resolves capacity by product/range/format. A no-carton rule
-- (25L) supports bottle planning only and snapshots null carton values.
create or replace function public.normalize_production_quantity(
  target_product_format_id uuid,
  target_quantity numeric,
  target_mode public.planning_quantity_mode
)
returns table (planned_bottles numeric, planned_cartons numeric, bottles_per_carton integer)
language plpgsql stable security definer set search_path = '' as $$
declare capacity integer;
declare resolved record;
begin
  if target_quantity is null or target_quantity <= 0 or mod(target_quantity, 1) <> 0 then
    raise exception 'Planning quantity must be a positive whole number' using errcode = '22023';
  end if;
  select * into resolved from public.resolve_product_packaging_rule(target_product_format_id);
  if not found then raise exception 'Active product packaging rule not found' using errcode = 'P0002'; end if;
  capacity := resolved.bottles_per_carton;
  if capacity is null then
    if target_mode <> 'bottles'::public.planning_quantity_mode then
      raise exception 'This product format has no carton; plan it in bottles' using errcode = '23514';
    end if;
    return query select target_quantity, null::numeric, null::integer;
    return;
  end if;
  if target_mode = 'cartons'::public.planning_quantity_mode then
    return query select target_quantity * capacity, target_quantity, capacity;
    return;
  elsif target_mode = 'bottles'::public.planning_quantity_mode then
    if mod(target_quantity, capacity) <> 0 then
      raise exception 'Bottle quantity must be a multiple of the carton capacity (%)', capacity
        using errcode = '23514';
    end if;
    return query select target_quantity, target_quantity / capacity, capacity;
    return;
  end if;
  raise exception 'Unsupported planning quantity mode: %', target_mode using errcode = '22023';
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
declare packaging record;
declare result jsonb;
begin
  perform public.assert_stock_actor(array['admin'::public.app_role, 'management'::public.app_role]);
  if effective_location_id is null or not exists (select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;
  select * into normalized from public.normalize_production_quantity(
    target_product_format_id, target_quantity, target_mode
  );
  select * into packaging from public.resolve_product_packaging_rule(target_product_format_id);
  select candidate.* into recipe from public.production_recipes candidate
  where candidate.product_format_id = target_product_format_id and candidate.is_active;
  if not found then raise exception 'Active production recipe not found' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = recipe.id and component.component_role = 'prepared_bottle')
    or not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = recipe.id and component.component_role = 'bulk_lubricant')
    or not exists (select 1 from public.production_recipe_components component
      where component.recipe_id = recipe.id and component.component_role = 'seal')
    or (packaging.carton_stock_item_id is not null and not exists (
      select 1 from public.production_recipe_components component
      where component.recipe_id = recipe.id and component.component_role = 'carton'
    ))
    or (packaging.carton_stock_item_id is null and exists (
      select 1 from public.production_recipe_components component
      where component.recipe_id = recipe.id and component.component_role = 'carton'
    )) then
    raise exception 'Production recipe does not match its configured packaging rule'
      using errcode = '23514';
  end if;

  select jsonb_build_object(
    'product_format_id', product_format.id, 'product_name', product.name,
    'format_name', format.name, 'recipe_id', recipe.id, 'recipe_version', recipe.version,
    'location_id', effective_location_id, 'quantity_mode', target_mode,
    'entered_quantity', target_quantity, 'planned_bottles', normalized.planned_bottles,
    'planned_cartons', normalized.planned_cartons,
    'bottles_per_carton', normalized.bottles_per_carton,
    'output', jsonb_build_object('stock_item_id', output_item.id, 'name', output_item.name,
      'quantity', normalized.planned_bottles),
    'components', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recipe_component_id', component.id, 'stock_item_id', item.id, 'name', item.name,
        'role', component.component_role, 'unit', item.unit,
        'quantity_per_bottle', component.quantity_per_bottle,
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
    if plan_item.recipe_id is null then
      raise exception 'Plan item is missing its stable recipe snapshot' using errcode = '23514';
    end if;
    if plan_item.bottles_per_carton is null and exists (
      select 1 from public.production_recipe_components candidate
      where candidate.recipe_id = plan_item.recipe_id
        and candidate.component_role = 'carton'::public.production_component_role
    ) then
      raise exception 'Carton component requires a stable carton-capacity snapshot'
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

revoke all on function public.normalize_production_quantity(
  uuid,numeric,public.planning_quantity_mode
) from public, anon, authenticated;
revoke all on function public.calculate_production_requirements(
  uuid,numeric,public.planning_quantity_mode,uuid
) from public, anon;
grant execute on function public.calculate_production_requirements(
  uuid,numeric,public.planning_quantity_mode,uuid
) to authenticated;
revoke all on function public.snapshot_production_plan_requirements(uuid)
  from public, anon, authenticated;

create or replace view public.official_recipe_packaging_audit
with (security_invoker = true)
as
select
  product_format.official_catalog_number,
  product_format.sku,
  range.code as product_range,
  product.name as product_name,
  format.code as format_code,
  recipe.id as active_recipe_id,
  recipe.version as active_recipe_version,
  prepared.component_stock_item_id as prepared_bottle_stock_item_id,
  bulk.component_stock_item_id as bulk_lubricant_stock_item_id,
  seal.component_stock_item_id as configured_seal_stock_item_id,
  carton.component_stock_item_id as configured_carton_stock_item_id,
  resolved.seal_stock_item_id as required_seal_stock_item_id,
  resolved.carton_stock_item_id as required_carton_stock_item_id,
  resolved.bottles_per_carton,
  case
    when recipe.id is null then 'missing_recipe'
    when prepared.id is null then 'missing_prepared_bottle_mapping'
    when bulk.id is null then 'missing_bulk_lubricant_mapping'
    when seal.component_stock_item_id is distinct from resolved.seal_stock_item_id
      or seal.quantity_per_bottle is distinct from 1 then 'seal_rule_mismatch'
    when resolved.carton_stock_item_id is null and carton.id is not null then 'unexpected_carton'
    when resolved.carton_stock_item_id is not null and (
      carton.component_stock_item_id is distinct from resolved.carton_stock_item_id
      or carton.quantity_per_bottle is distinct from round(1::numeric / resolved.bottles_per_carton, 6)
    ) then 'carton_rule_mismatch'
    else 'ready'
  end as status
from public.product_formats product_format
join public.products product on product.id = product_format.product_id
join public.product_ranges range on range.id = product.product_range_id
join public.packaging_formats format on format.id = product_format.format_id
left join public.production_recipes recipe
  on recipe.product_format_id = product_format.id and recipe.is_active
left join public.production_recipe_components prepared
  on prepared.recipe_id = recipe.id
 and prepared.component_role = 'prepared_bottle'::public.production_component_role
left join public.production_recipe_components bulk
  on bulk.recipe_id = recipe.id
 and bulk.component_role = 'bulk_lubricant'::public.production_component_role
left join public.production_recipe_components seal
  on seal.recipe_id = recipe.id
 and seal.component_role = 'seal'::public.production_component_role
left join public.production_recipe_components carton
  on carton.recipe_id = recipe.id
 and carton.component_role = 'carton'::public.production_component_role
left join lateral public.resolve_product_packaging_rule(product_format.id) resolved on true
where product_format.official_catalog_number between 1 and 41;

revoke all on public.official_recipe_packaging_audit from public, anon, authenticated;
grant select on public.official_recipe_packaging_audit to authenticated;

select status, count(*) as sku_count
from public.official_recipe_packaging_audit
group by status order by status;

select official_catalog_number, sku, product_range, product_name, format_code, status
from public.official_recipe_packaging_audit
where status <> 'ready'
order by official_catalog_number;
