-- FACOLUB stock catalog completion - 116 references and mappings
-- Run manually after 115_stock_catalog_completion_foundation.sql.
-- Idempotent catalog configuration only: no stock movement, reservation, balance,
-- receipt, preparation, production, order, invoice, or dispatch row is written.

begin;

do $$
begin
  if (select count(*) from public.product_formats
      where official_catalog_number between 1 and 41 and sku is not null) <> 41 then
    raise exception 'Expected the official 41-SKU catalog. Run/fix 090-093 first.';
  end if;
  if not ('tonne' = any(enum_range(null::public.stock_unit)::text[])) then
    raise exception 'The tonne unit is missing. Commit 115 before running 116.';
  end if;
end
$$;

create temporary table facolub_formats (
  format_code text primary key,
  canonical_code text not null,
  canonical_name text not null,
  stock_item_id uuid
) on commit drop;

insert into facolub_formats (format_code, canonical_code, canonical_name) values
  ('1L', 'EMPTY-BOTTLE-01L', 'Empty Bottle 1L'),
  ('2L', 'EMPTY-BOTTLE-02L', 'Empty Bottle 2L'),
  ('5L', 'EMPTY-BOTTLE-05L', 'Empty Bottle 5L'),
  ('25L', 'EMPTY-BOTTLE-25L', 'Empty Bottle 25L');

do $$
declare target record;
declare matches integer;
declare existing_id uuid;
begin
  for target in select * from facolub_formats order by format_code loop
    select count(*), (array_agg(item.id))[1] into matches, existing_id
    from public.stock_items item
    where item.category = 'empty_bottle'::public.stock_item_category
      and item.unit = 'piece'::public.stock_unit
      and (
        item.code = target.canonical_code
        or lower(trim(item.name)) = lower(target.canonical_name)
      );

    if matches > 1 then
      raise exception 'Multiple physical empty-bottle items match format %. Consolidate before rerunning 116.',
        target.format_code;
    elsif matches = 0 then
      insert into public.stock_items
        (code, name, category, unit, is_active, minimum_stock, notes)
      values
        (target.canonical_code, target.canonical_name, 'empty_bottle', 'piece', true, null,
         'Shared physical bottle inventory by format; FACOLUB catalog completion 116')
      returning id into existing_id;
    else
      update public.stock_items set is_active = true where id = existing_id;
    end if;

    update facolub_formats set stock_item_id = existing_id
    where format_code = target.format_code;
  end loop;
end
$$;

-- Reuse compatible canonical-code rows that predate product-format linkage.
do $$
declare conflict_skus text;
begin
  select string_agg(product_format.sku, ', ' order by product_format.sku)
  into conflict_skus
  from public.product_formats product_format
  join public.stock_items item on item.code = 'LBL-' || product_format.sku
  where product_format.official_catalog_number between 1 and 41
    and (item.category <> 'label'::public.stock_item_category
      or item.unit <> 'piece'::public.stock_unit
      or (item.product_format_id is not null and item.product_format_id <> product_format.id));
  if conflict_skus is not null then
    raise exception 'Conflicting canonical label codes for: %', conflict_skus;
  end if;

  select string_agg(product_format.sku, ', ' order by product_format.sku)
  into conflict_skus
  from public.product_formats product_format
  join public.stock_items item on item.code = 'PREP-' || product_format.sku
  where product_format.official_catalog_number between 1 and 41
    and (item.category <> 'prepared_bottle'::public.stock_item_category
      or item.unit <> 'piece'::public.stock_unit
      or (item.product_format_id is not null and item.product_format_id <> product_format.id));
  if conflict_skus is not null then
    raise exception 'Conflicting canonical prepared-bottle codes for: %', conflict_skus;
  end if;
end
$$;

update public.stock_items item
set product_format_id = product_format.id, is_active = true
from public.product_formats product_format
where product_format.official_catalog_number between 1 and 41
  and item.code in ('LBL-' || product_format.sku, 'PREP-' || product_format.sku)
  and item.product_format_id is null;

do $$
declare conflicts text;
begin
  select string_agg(distinct product_format.sku, ', ' order by product_format.sku)
  into conflicts
  from public.product_formats product_format
  join public.stock_items item on item.product_format_id = product_format.id
  where product_format.official_catalog_number between 1 and 41
    and item.category in ('label', 'prepared_bottle')
    and item.unit <> 'piece';
  if conflicts is not null then
    raise exception 'Existing label/prepared items use a non-piece unit for: %', conflicts;
  end if;
end
$$;

insert into public.stock_items
  (code, name, category, unit, product_format_id, is_active, minimum_stock, notes)
select
  'LBL-' || product_format.sku,
  'Label ' || case when range.code = 'HYDRAULIQUE' then 'Hydraulique ' || product.name
                  else product.name end || ' ' || format.code,
  'label', 'piece', product_format.id, true, null,
  'Product-and-format-specific label reference; quantity configuration may require confirmation'
from public.product_formats product_format
join public.products product on product.id = product_format.product_id
join public.product_ranges range on range.id = product.product_range_id
join public.packaging_formats format on format.id = product_format.format_id
where product_format.official_catalog_number between 1 and 41
  and not exists (
    select 1 from public.stock_items item
    where item.product_format_id = product_format.id and item.category = 'label'
  );

do $$
declare duplicate_skus text;
begin
  select string_agg(product_format.sku, ', ' order by product_format.sku)
  into duplicate_skus
  from public.product_formats product_format
  where product_format.official_catalog_number between 1 and 41
    and (select count(*) from public.stock_items item
         where item.product_format_id = product_format.id
           and item.category = 'prepared_bottle') > 1;
  if duplicate_skus is not null then
    raise exception 'Multiple prepared-bottle stock items exist for: %', duplicate_skus;
  end if;
end
$$;

insert into public.stock_items
  (code, name, category, unit, product_format_id, is_active, minimum_stock, notes)
select
  'PREP-' || product_format.sku,
  'Prepared Bottle ' ||
    case when range.code = 'HYDRAULIQUE' then 'Hydraulique ' || product.name
         else product.name end || ' ' || format.code,
  'prepared_bottle', 'piece', product_format.id, true, null,
  'Official product-and-format prepared-bottle reference'
from public.product_formats product_format
join public.products product on product.id = product_format.product_id
join public.product_ranges range on range.id = product.product_range_id
join public.packaging_formats format on format.id = product_format.format_id
where product_format.official_catalog_number between 1 and 41
  and not exists (
    select 1 from public.stock_items item
    where item.product_format_id = product_format.id and item.category = 'prepared_bottle'
  );

update public.stock_items item set is_active = true
from public.product_formats product_format
where product_format.official_catalog_number between 1 and 41
  and item.product_format_id = product_format.id
  and item.category in ('label', 'prepared_bottle')
  and item.unit = 'piece';

create unique index if not exists stock_items_prepared_product_format_unique
  on public.stock_items (product_format_id)
  where product_format_id is not null and category = 'prepared_bottle';

insert into public.product_format_bottle_mappings
  (product_format_id, empty_bottle_stock_item_id, prepared_bottle_stock_item_id)
select product_format.id, physical_bottle.stock_item_id, prepared.id
from public.product_formats product_format
join public.packaging_formats format on format.id = product_format.format_id
join facolub_formats physical_bottle on physical_bottle.format_code = format.code
join public.stock_items prepared
  on prepared.product_format_id = product_format.id
 and prepared.category = 'prepared_bottle'
where product_format.official_catalog_number between 1 and 41
on conflict (product_format_id) do update set
  empty_bottle_stock_item_id = excluded.empty_bottle_stock_item_id,
  prepared_bottle_stock_item_id = excluded.prepared_bottle_stock_item_id;

-- Preserve every label reference. Only quantities already present in an active
-- prepared-bottle recipe are treated as confirmed; missing counts remain null.
insert into public.product_format_label_mappings
  (product_format_id, label_stock_item_id, quantity_per_prepared_bottle, configuration_source)
select product_format.id, label.id,
  confirmed.quantity_per_output,
  case when confirmed.recipe_id is not null
    then 'existing active prepared_bottle_recipe ' || confirmed.recipe_id::text
    else null end
from public.product_formats product_format
join public.stock_items label
  on label.product_format_id = product_format.id and label.category = 'label'
left join lateral (
  select component.recipe_id, component.quantity_per_output
  from public.product_format_bottle_mappings bottle_mapping
  join public.prepared_bottle_recipes recipe
    on recipe.output_stock_item_id = bottle_mapping.prepared_bottle_stock_item_id
   and recipe.is_active
  join public.prepared_bottle_recipe_components component on component.recipe_id = recipe.id
  where bottle_mapping.product_format_id = product_format.id
    and component.component_stock_item_id = label.id
  limit 1
) confirmed on true
where product_format.official_catalog_number between 1 and 41
on conflict (product_format_id, label_stock_item_id) do update set
  quantity_per_prepared_bottle = coalesce(
    excluded.quantity_per_prepared_bottle,
    public.product_format_label_mappings.quantity_per_prepared_bottle
  ),
  configuration_source = coalesce(
    excluded.configuration_source,
    public.product_format_label_mappings.configuration_source
  );

create temporary table facolub_bulk_oils (
  display_order smallint primary key,
  oil_code text not null unique,
  oil_name text not null unique,
  range_code text not null,
  product_name text not null
) on commit drop;

insert into facolub_bulk_oils values
  (1,  'BULK-01', '5W30', 'PLATINUM', '5W30'),
  (2,  'BULK-02', '5W40', 'PLATINUM', '5W40'),
  (3,  'BULK-03', '10W40', 'PREMIUM', '10W40'),
  (4,  'BULK-04', '15W40', 'PREMIUM', '15W40'),
  (5,  'BULK-05', 'SAE 40', 'ULTRA', 'SAE 40'),
  (6,  'BULK-06', 'SAE 50', 'ULTRA', 'SAE 50'),
  (7,  'BULK-07', '20W50', 'ULTRA', '20W50'),
  (8,  'BULK-08', 'SAE 90', 'EXTREME', 'SAE 90'),
  (9,  'BULK-09', 'SAE 140', 'EXTREME', 'SAE 140'),
  (10, 'BULK-10', 'ATF', 'OPTIMUM', 'ATF'),
  (11, 'BULK-11', '2T', 'EXPERT', '2T'),
  (12, 'BULK-12', '4T 10W40', '4T', '4T 10W40'),
  (13, 'BULK-13', '4T 20W50 Ultra', '4T', '4T 20W50 Ultra'),
  (14, 'BULK-14', '4T 20W50', '4T', '4T 20W50'),
  (15, 'BULK-15', '4T 10W40 F7500', '4T', '4T 10W40 F7500'),
  (16, 'BULK-16', '4T 15W50 F5500', '4T', '4T 15W50 F5500'),
  (17, 'BULK-17', '4T 20W50 F3300', '4T', '4T 20W50 F3300'),
  (18, 'BULK-18', 'Hydraulique 68', 'HYDRAULIQUE', '68'),
  (19, 'BULK-19', 'Dynovex', 'DYNOVEX', 'DYNOVEX');

do $$
declare conflicts text;
begin
  select string_agg(oil.oil_code, ', ' order by oil.oil_code) into conflicts
  from facolub_bulk_oils oil
  join public.stock_items item on item.code = oil.oil_code
  where item.category <> 'bulk_lubricant'::public.stock_item_category
     or item.unit <> 'tonne'::public.stock_unit;
  if conflicts is not null then
    raise exception 'Canonical bulk codes have incompatible category/unit: %', conflicts;
  end if;
end
$$;

insert into public.stock_items
  (code, name, category, unit, is_active, minimum_stock, notes)
select oil.oil_code, 'Bulk ' || oil.oil_name, 'bulk_lubricant', 'tonne', true, null,
  'FACOLUB authoritative bulk lubricant master; no default tonne/liter conversion'
from facolub_bulk_oils oil
where not exists (select 1 from public.stock_items item where item.code = oil.oil_code);

update public.stock_items item set name = 'Bulk ' || oil.oil_name, is_active = true
from facolub_bulk_oils oil
where item.code = oil.oil_code
  and item.category = 'bulk_lubricant' and item.unit = 'tonne';

insert into public.facolub_bulk_lubricant_catalog
  (oil_code, oil_name, display_order, stock_item_id)
select oil.oil_code, oil.oil_name, oil.display_order, item.id
from facolub_bulk_oils oil
join public.stock_items item on item.code = oil.oil_code
on conflict (oil_code) do update set
  oil_name = excluded.oil_name,
  display_order = excluded.display_order,
  stock_item_id = excluded.stock_item_id;

insert into public.product_format_bulk_lubricant_mappings
  (product_format_id, bulk_stock_item_id, liters_per_tonne, conversion_source)
select product_format.id, bulk_catalog.stock_item_id, null, null
from public.product_formats product_format
join public.products product on product.id = product_format.product_id
join public.product_ranges range on range.id = product.product_range_id
join facolub_bulk_oils oil
  on oil.range_code = range.code and oil.product_name = product.name
join public.facolub_bulk_lubricant_catalog bulk_catalog on bulk_catalog.oil_code = oil.oil_code
where product_format.official_catalog_number between 1 and 41
on conflict (product_format_id) do update set
  bulk_stock_item_id = excluded.bulk_stock_item_id;

commit;

-- UI metadata is derived without storing duplicate product/format names.
create or replace view public.stock_catalog_display
with (security_invoker = true)
as
select
  item.id as stock_item_id,
  case when range.code = 'HYDRAULIQUE' and product.id is not null
    then 'Hydraulique ' || product.name else product.name end as product_name,
  coalesce(format.code,
    case when item.category = 'empty_bottle'::public.stock_item_category then (
      select min(used_packaging.code)
      from public.product_format_bottle_mappings used_mapping
      join public.product_formats used_format on used_format.id = used_mapping.product_format_id
      join public.packaging_formats used_packaging on used_packaging.id = used_format.format_id
      where used_mapping.empty_bottle_stock_item_id = item.id
    ) end
  ) as format_code,
  product_format.sku,
  bulk.oil_name,
  case when item.category = 'empty_bottle'::public.stock_item_category then (
    select array_agg(distinct
      case when used_range.code = 'HYDRAULIQUE' then 'Hydraulique ' || used_product.name
           else used_product.name end
      order by case when used_range.code = 'HYDRAULIQUE' then 'Hydraulique ' || used_product.name
                    else used_product.name end)
    from public.product_format_bottle_mappings used_mapping
    join public.product_formats used_format on used_format.id = used_mapping.product_format_id
    join public.products used_product on used_product.id = used_format.product_id
    join public.product_ranges used_range on used_range.id = used_product.product_range_id
    where used_mapping.empty_bottle_stock_item_id = item.id
  ) else null::text[] end as used_by_products
from public.stock_items item
left join public.product_formats product_format on product_format.id = item.product_format_id
left join public.products product on product.id = product_format.product_id
left join public.product_ranges range on range.id = product.product_range_id
left join public.packaging_formats format on format.id = product_format.format_id
left join public.facolub_bulk_lubricant_catalog bulk on bulk.stock_item_id = item.id;

revoke all on public.stock_catalog_display from public, anon, authenticated;
grant select on public.stock_catalog_display to authenticated;

select
  (select count(*) from public.product_format_bottle_mappings) as bottle_mappings,
  (select count(distinct product_format_id) from public.product_format_label_mappings) as labeled_formats,
  (select count(*) from public.facolub_bulk_lubricant_catalog) as bulk_oils,
  (select count(*) from public.product_format_bulk_lubricant_mappings) as finished_to_bulk_mappings;
