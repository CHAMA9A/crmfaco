-- FACOLUB 2026 official product catalog - 093 read-only verification
-- Run manually after 092_facolub_product_stock_link.sql.
-- Expected first result: every boolean true; official counts 41/41/9/41.

with expected(official_number, range_code, product_name, format_code, sku) as (
  values
    (1,'PLATINUM','5W30','5L','FAC-PLA-5W30-05L'),(2,'PLATINUM','5W40','5L','FAC-PLA-5W40-05L'),
    (3,'PREMIUM','10W40','1L','FAC-PRE-10W40-01L'),(4,'PREMIUM','10W40','5L','FAC-PRE-10W40-05L'),
    (5,'PREMIUM','15W40','1L','FAC-PRE-15W40-01L'),(6,'PREMIUM','15W40','5L','FAC-PRE-15W40-05L'),
    (7,'PREMIUM','15W40','25L','FAC-PRE-15W40-25L'),(8,'ULTRA','SAE 40','1L','FAC-ULT-SAE40-01L'),
    (9,'ULTRA','SAE 40','2L','FAC-ULT-SAE40-02L'),(10,'ULTRA','SAE 40','5L','FAC-ULT-SAE40-05L'),
    (11,'ULTRA','SAE 40','25L','FAC-ULT-SAE40-25L'),(12,'ULTRA','SAE 50','1L','FAC-ULT-SAE50-01L'),
    (13,'ULTRA','SAE 50','2L','FAC-ULT-SAE50-02L'),(14,'ULTRA','SAE 50','5L','FAC-ULT-SAE50-05L'),
    (15,'ULTRA','SAE 50','25L','FAC-ULT-SAE50-25L'),(16,'ULTRA','20W50','1L','FAC-ULT-20W50-01L'),
    (17,'ULTRA','20W50','2L','FAC-ULT-20W50-02L'),(18,'ULTRA','20W50','5L','FAC-ULT-20W50-05L'),
    (19,'ULTRA','20W50','25L','FAC-ULT-20W50-25L'),(20,'EXTREME','SAE 90','1L','FAC-EXT-SAE90-01L'),
    (21,'EXTREME','SAE 90','2L','FAC-EXT-SAE90-02L'),(22,'EXTREME','SAE 90','5L','FAC-EXT-SAE90-05L'),
    (23,'EXTREME','SAE 90','25L','FAC-EXT-SAE90-25L'),(24,'EXTREME','SAE 140','1L','FAC-EXT-SAE140-01L'),
    (25,'EXTREME','SAE 140','2L','FAC-EXT-SAE140-02L'),(26,'EXTREME','SAE 140','5L','FAC-EXT-SAE140-05L'),
    (27,'EXTREME','SAE 140','25L','FAC-EXT-SAE140-25L'),(28,'OPTIMUM','ATF','1L','FAC-OPT-ATF-01L'),
    (29,'EXPERT','2T','1L','FAC-EXP-2T-01L'),(30,'EXPERT','2T','2L','FAC-EXP-2T-02L'),
    (31,'EXPERT','2T','5L','FAC-EXP-2T-05L'),(32,'EXPERT','2T','25L','FAC-EXP-2T-25L'),
    (33,'4T','4T 10W40','1L','FAC-4T-STD-10W40-01L'),
    (34,'4T','4T 20W50 Ultra','1L','FAC-4T-ULT-20W50-01L'),
    (35,'4T','4T 20W50','1L','FAC-4T-STD-20W50-01L'),
    (36,'4T','4T 10W40 F7500','1L','FAC-4T-F7500-10W40-01L'),
    (37,'4T','4T 15W50 F5500','1L','FAC-4T-F5500-15W50-01L'),
    (38,'4T','4T 20W50 F3300','1L','FAC-4T-F3300-20W50-01L'),
    (39,'HYDRAULIQUE','68','5L','FAC-HYD-68-05L'),(40,'HYDRAULIQUE','68','25L','FAC-HYD-68-25L'),
    (41,'DYNOVEX','DYNOVEX','1L','FAC-DYN-01L')
), actual as (
  select product_format.official_catalog_number, range.code as range_code,
    product.name as product_name, format.code as format_code, product_format.sku,
    item.id as stock_item_id
  from public.product_formats product_format
  join public.products product on product.id = product_format.product_id
  join public.product_ranges range on range.id = product.product_range_id
  join public.packaging_formats format on format.id = product_format.format_id
  left join public.stock_items item
    on item.product_format_id = product_format.id
   and item.category = 'finished_product'::public.stock_item_category
  where product_format.official_catalog_number between 1 and 41
)
select
  (select count(*) from expected) as expected_count,
  (select count(*) from actual) as actual_count,
  (select count(distinct sku) from actual) as unique_sku_count,
  (select count(distinct range_code) from actual) as category_count,
  (select count(*) from actual where stock_item_id is not null) as stock_link_count,
  not exists (
    select official_number, range_code, product_name, format_code, sku from expected
    except
    select official_catalog_number, range_code, product_name, format_code, sku from actual
  ) and not exists (
    select official_catalog_number, range_code, product_name, format_code, sku from actual
    except
    select official_number, range_code, product_name, format_code, sku from expected
  ) as all_mappings_exact,
  (select count(*) from actual) = 41 as exactly_41,
  (select count(distinct sku) from actual) = 41 as every_sku_unique,
  (select count(distinct range_code) from actual) = 9 as all_9_categories,
  (select count(*) from actual where stock_item_id is not null) = 41 as every_stock_item_linked;

-- Detailed rows: balances are derived exclusively from the existing immutable
-- movement/reservation engine. Zero movements therefore means physical = 0.
select
  lpad(product_format.official_catalog_number::text, 3, '0') as official_number,
  product_format.sku,
  range.code as category,
  product.name as product,
  format.code as format,
  item.code as stock_code,
  item.minimum_stock,
  movement_totals.existing_movement_count,
  balance_totals.physical,
  balance_totals.reserved,
  balance_totals.available
from public.product_formats product_format
join public.products product on product.id = product_format.product_id
join public.product_ranges range on range.id = product.product_range_id
join public.packaging_formats format on format.id = product_format.format_id
join public.stock_items item
  on item.product_format_id = product_format.id
 and item.category = 'finished_product'::public.stock_item_category
left join lateral (
  select count(*) as existing_movement_count
  from public.stock_movements movement where movement.stock_item_id = item.id
) movement_totals on true
left join lateral (
  select coalesce(sum(balance.physical_quantity), 0) as physical,
    coalesce(sum(balance.reserved_quantity), 0) as reserved,
    coalesce(sum(balance.available_quantity), 0) as available
  from public.stock_balances balance where balance.stock_item_id = item.id
) balance_totals on true
where product_format.official_catalog_number between 1 and 41
order by product_format.official_catalog_number;

-- Must return zero rows. These are conflicts requiring manual review; nothing
-- here mutates issued invoices, confirmed orders, recipes, plans, or movements.
select 'duplicate_sku' as conflict_type, product_format.sku as reference, count(*) as occurrences
from public.product_formats product_format
where product_format.sku is not null
group by product_format.sku having count(*) > 1
union all
select 'duplicate_official_number', product_format.official_catalog_number::text, count(*)
from public.product_formats product_format
where product_format.official_catalog_number is not null
group by product_format.official_catalog_number having count(*) > 1
union all
select 'missing_finished_stock_link', product_format.sku, 0
from public.product_formats product_format
where product_format.official_catalog_number between 1 and 41
  and not exists (
    select 1 from public.stock_items item
    where item.product_format_id = product_format.id
      and item.category = 'finished_product'::public.stock_item_category
  );
