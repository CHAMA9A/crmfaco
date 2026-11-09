-- FACOLUB stock catalog completion - 117 read-only verification and tests
-- Run manually after 116_stock_catalog_completion_seed.sql. This file changes no data.

do $$
declare failures text[] := array[]::text[];
begin
  if (select count(*) from public.product_formats where official_catalog_number between 1 and 41) <> 41
    or (select count(distinct sku) from public.product_formats where official_catalog_number between 1 and 41) <> 41 then
    failures := array_append(failures, 'official finished catalog is not exactly 41 unique SKUs');
  end if;

  if exists (select 1 from public.product_formats pf where pf.official_catalog_number between 1 and 41
    and not exists (select 1 from public.product_format_bottle_mappings m where m.product_format_id = pf.id)) then
    failures := array_append(failures, 'a finished SKU has no prepared/empty bottle mapping');
  end if;
  if exists (select 1 from public.product_formats pf where pf.official_catalog_number between 1 and 41
    and not exists (select 1 from public.product_format_label_mappings m where m.product_format_id = pf.id)) then
    failures := array_append(failures, 'a finished SKU has no label reference mapping');
  end if;
  if exists (select 1 from public.product_formats pf where pf.official_catalog_number between 1 and 41
    and not exists (select 1 from public.product_format_bulk_lubricant_mappings m where m.product_format_id = pf.id)) then
    failures := array_append(failures, 'a finished SKU has no explicit bulk-oil identity mapping');
  end if;

  if exists (
    select 1 from public.product_format_bottle_mappings m
    join public.product_formats pf on pf.id = m.product_format_id
    join public.packaging_formats f on f.id = pf.format_id
    join public.stock_items bottle on bottle.id = m.empty_bottle_stock_item_id
    where pf.official_catalog_number between 1 and 41
      and (bottle.category <> 'empty_bottle' or bottle.unit <> 'piece'
        or lower(bottle.name) not like '% ' || lower(f.code))
  ) then failures := array_append(failures, 'an empty-bottle mapping does not match its format'); end if;

  if (select count(distinct m.empty_bottle_stock_item_id)
      from public.product_format_bottle_mappings m
      join public.product_formats pf on pf.id = m.product_format_id
      where pf.official_catalog_number between 1 and 41) <> 4 then
    failures := array_append(failures, 'official mappings do not share exactly four physical empty bottles');
  end if;

  if (select count(*) from public.facolub_bulk_lubricant_catalog) <> 19
    or (select count(distinct oil_name) from public.facolub_bulk_lubricant_catalog) <> 19 then
    failures := array_append(failures, 'FACOLUB bulk master is not exactly 19 unique oils');
  end if;
  if exists (select 1 from public.facolub_bulk_lubricant_catalog c
    join public.stock_items i on i.id = c.stock_item_id
    where i.category <> 'bulk_lubricant' or i.unit <> 'tonne') then
    failures := array_append(failures, 'a FACOLUB bulk oil does not use the tonne unit');
  end if;

  if exists (
    with expected(display_order, oil_name) as (values
      (1,'5W30'), (2,'5W40'), (3,'10W40'), (4,'15W40'), (5,'SAE 40'),
      (6,'SAE 50'), (7,'20W50'), (8,'SAE 90'), (9,'SAE 140'), (10,'ATF'),
      (11,'2T'), (12,'4T 10W40'), (13,'4T 20W50 Ultra'), (14,'4T 20W50'),
      (15,'4T 10W40 F7500'), (16,'4T 15W50 F5500'), (17,'4T 20W50 F3300'),
      (18,'Hydraulique 68'), (19,'Dynovex')
    )
    select 1 from expected full join public.facolub_bulk_lubricant_catalog actual
      using (display_order, oil_name)
    where expected.display_order is null or actual.display_order is null
  ) then failures := array_append(failures, 'bulk identities differ from the supplied authoritative list'); end if;

  if exists (select 1 from public.stock_movements movement
    where movement.reference_type in ('stock_catalog_completion_115', 'stock_catalog_completion_116')
       or movement.metadata ->> 'source' in ('stock_catalog_completion_115', 'stock_catalog_completion_116')) then
    failures := array_append(failures, 'catalog completion fabricated a stock movement');
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.stock_movements'::regclass
    and tgname = 'stock_movements_immutable' and not tgisinternal) then
    failures := array_append(failures, 'historical stock movement immutability trigger is missing');
  end if;

  -- Required acceptance examples.
  if exists (
    with cases(sku, format_code, bulk_name) as (values
      ('FAC-PRE-10W40-01L','1L','10W40'),
      ('FAC-ULT-SAE50-05L','5L','SAE 50'),
      ('FAC-4T-F7500-10W40-01L','1L','4T 10W40 F7500'),
      ('FAC-EXT-SAE140-25L','25L','SAE 140')
    )
    select 1 from cases expected
    left join public.product_formats pf on pf.sku = expected.sku
    left join public.packaging_formats f on f.id = pf.format_id
    left join public.product_format_bottle_mappings bm on bm.product_format_id = pf.id
    left join public.stock_items empty_bottle on empty_bottle.id = bm.empty_bottle_stock_item_id
    left join public.stock_items prepared on prepared.id = bm.prepared_bottle_stock_item_id
    left join public.product_format_bulk_lubricant_mappings bulk_map on bulk_map.product_format_id = pf.id
    left join public.facolub_bulk_lubricant_catalog bulk on bulk.stock_item_id = bulk_map.bulk_stock_item_id
    where f.code is distinct from expected.format_code
       or empty_bottle.name is distinct from 'Empty Bottle ' || expected.format_code
       or prepared.id is null or bulk.oil_name is distinct from expected.bulk_name
       or not exists (select 1 from public.product_format_label_mappings lm where lm.product_format_id = pf.id)
  ) then failures := array_append(failures, 'one or more required acceptance examples failed'); end if;

  if cardinality(failures) > 0 then
    raise exception 'FACOLUB stock catalog verification failed: %', array_to_string(failures, '; ');
  end if;
end
$$;

-- Expected: 41 / 41 / 41 / 41 / 4 / 19 / 19 / 0.
select count(distinct pf.id) as official_skus,
  count(distinct bm.product_format_id) as prepared_and_empty_mappings,
  count(distinct lm.product_format_id) as label_reference_mappings,
  count(distinct bulk_map.product_format_id) as bulk_identity_mappings,
  count(distinct bm.empty_bottle_stock_item_id) as shared_physical_empty_bottles,
  (select count(*) from public.facolub_bulk_lubricant_catalog) as bulk_oils,
  (select count(*) from public.facolub_bulk_lubricant_catalog c join public.stock_items i on i.id = c.stock_item_id where i.unit = 'tonne') as bulk_oils_in_tonnes,
  (select count(*) from public.stock_movements m where m.reference_type in ('stock_catalog_completion_115', 'stock_catalog_completion_116')
     or m.metadata ->> 'source' in ('stock_catalog_completion_115', 'stock_catalog_completion_116')) as fabricated_movements
from public.product_formats pf
left join public.product_format_bottle_mappings bm on bm.product_format_id = pf.id
left join public.product_format_label_mappings lm on lm.product_format_id = pf.id
left join public.product_format_bulk_lubricant_mappings bulk_map on bulk_map.product_format_id = pf.id
where pf.official_catalog_number between 1 and 41;

-- Products requiring multiple label items or multiple copies of one label.
select pf.sku, product.name, format.code as format, count(*) as label_item_count,
  sum(lm.quantity_per_prepared_bottle) as confirmed_label_count
from public.product_format_label_mappings lm
join public.product_formats pf on pf.id = lm.product_format_id
join public.products product on product.id = pf.product_id
join public.packaging_formats format on format.id = pf.format_id
where pf.official_catalog_number between 1 and 41
group by pf.sku, product.name, format.code
having count(*) > 1 or sum(lm.quantity_per_prepared_bottle) > 1
order by pf.sku;

-- Ambiguous label configurations: mapped reference, but no guessed count.
select pf.sku, product.name, format.code as format, label.name as label
from public.product_format_label_mappings lm
join public.product_formats pf on pf.id = lm.product_format_id
join public.products product on product.id = pf.product_id
join public.packaging_formats format on format.id = pf.format_id
join public.stock_items label on label.id = lm.label_stock_item_id
where pf.official_catalog_number between 1 and 41 and lm.quantity_per_prepared_bottle is null
order by pf.official_catalog_number, label.name;

-- Missing finished-product to bulk mappings. Expected: no rows.
select pf.sku, product.name, format.code as format
from public.product_formats pf
join public.products product on product.id = pf.product_id
join public.packaging_formats format on format.id = pf.format_id
left join public.product_format_bulk_lubricant_mappings m on m.product_format_id = pf.id
where pf.official_catalog_number between 1 and 41 and m.product_format_id is null
order by pf.official_catalog_number;

-- Active production recipes still expecting liters. Every returned row needs a
-- confirmed lubricant-specific conversion before it can consume the T master.
select pf.sku, product.name, format.code as format, recipe.id as recipe_id,
  current_bulk.name as current_bulk_item, current_bulk.unit as current_recipe_unit,
  tonne_bulk.name as mapped_tonne_item, bulk_map.liters_per_tonne
from public.production_recipes recipe
join public.product_formats pf on pf.id = recipe.product_format_id
join public.products product on product.id = pf.product_id
join public.packaging_formats format on format.id = pf.format_id
join public.production_recipe_components component on component.recipe_id = recipe.id
  and component.component_role = 'bulk_lubricant'
join public.stock_items current_bulk on current_bulk.id = component.component_stock_item_id
left join public.product_format_bulk_lubricant_mappings bulk_map on bulk_map.product_format_id = pf.id
left join public.stock_items tonne_bulk on tonne_bulk.id = bulk_map.bulk_stock_item_id
where recipe.is_active and current_bulk.unit = 'liter' and bulk_map.liters_per_tonne is null
order by pf.sku;
