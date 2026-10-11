-- SOMA / FACOLUB production planning module - 056 quantity-mode hotfix
-- Depends on: 050-052.
-- Apply before rerunning 055 when the original 052 was already installed.
-- Fixes PL/pgSQL RETURN QUERY fall-through from carton mode into bottle checks.

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
  if format_id_value is null then
    raise exception 'Active product format not found' using errcode = 'P0002';
  end if;
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

revoke all on function public.normalize_production_quantity(
  uuid, numeric, public.planning_quantity_mode
) from public, anon, authenticated;

-- Verification query: `uses_explicit_output_path` must be true.
select
  routine_name,
  security_type,
  position('planned_bottles := target_quantity * capacity' in routine_definition) > 0
    as uses_explicit_output_path
from information_schema.routines
where routine_schema = 'public'
  and routine_name = 'normalize_production_quantity';
