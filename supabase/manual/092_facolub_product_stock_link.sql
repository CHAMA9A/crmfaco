-- FACOLUB 2026 official product catalog - 092 finished-stock linkage
-- Run manually after 091_facolub_product_catalog_seed.sql.
-- Reuses compatible stock_items and creates only missing configuration rows.
-- IMPORTANT: this file never inserts stock_movements, reservations, or balances.

begin;

do $$
declare official_count integer;
declare conflict_text text;
begin
  select count(*) into official_count
  from public.product_formats product_format
  where product_format.official_catalog_number between 1 and 41
    and product_format.sku is not null;
  if official_count <> 41 then
    raise exception 'Expected 41 seeded official product formats; found %. Run/fix 091 first.', official_count;
  end if;

  select string_agg(product_format.sku, ', ' order by product_format.sku)
  into conflict_text
  from public.product_formats product_format
  where product_format.official_catalog_number between 1 and 41
    and (
      (select count(*) from public.stock_items item
       where item.product_format_id = product_format.id
         and item.category = 'finished_product'::public.stock_item_category) > 1
      or exists (
        select 1 from public.stock_items item
        where item.code = product_format.sku
          and item.product_format_id is not null
          and (
            item.product_format_id <> product_format.id
            or item.category <> 'finished_product'::public.stock_item_category
            or item.unit <> 'piece'::public.stock_unit
          )
      )
      or exists (
        select 1 from public.stock_items item
        where item.product_format_id = product_format.id
          and item.category = 'finished_product'::public.stock_item_category
          and (
            (item.code is not null and item.code <> product_format.sku)
            or item.unit <> 'piece'::public.stock_unit
          )
      )
    );

  if conflict_text is not null then
    raise exception 'Conflicting finished stock references detected for SKUs: %. No history was changed.', conflict_text;
  end if;
end
$$;

-- A stock row already carrying the authoritative SKU can be linked only when
-- its identity is otherwise compatible and it has no conflicting catalog link.
do $$
declare conflict_text text;
begin
  select string_agg(product_format.sku, ', ' order by product_format.sku)
  into conflict_text
  from public.product_formats product_format
  join public.stock_items item on item.code = product_format.sku
  where product_format.official_catalog_number between 1 and 41
    and item.product_format_id is null
    and (
      item.category <> 'finished_product'::public.stock_item_category
      or item.unit <> 'piece'::public.stock_unit
    );

  if conflict_text is not null then
    raise exception 'Existing SKU-coded stock rows have incompatible category/unit: %. Resolve before rerunning 092.',
      conflict_text;
  end if;
end
$$;

update public.stock_items item
set product_format_id = product_format.id,
    is_active = true
from public.product_formats product_format
where product_format.official_catalog_number between 1 and 41
  and item.code = product_format.sku
  and item.product_format_id is null
  and item.category = 'finished_product'::public.stock_item_category
  and item.unit = 'piece'::public.stock_unit;

update public.stock_items item
set code = product_format.sku,
    is_active = true
from public.product_formats product_format
where product_format.official_catalog_number between 1 and 41
  and item.product_format_id = product_format.id
  and item.category = 'finished_product'::public.stock_item_category
  and item.unit = 'piece'::public.stock_unit
  and item.code is null;

insert into public.stock_items (
  code, name, category, unit, product_format_id, is_active, minimum_stock, notes
)
select
  product_format.sku,
  product.name || ' ' || format.code,
  'finished_product'::public.stock_item_category,
  'piece'::public.stock_unit,
  product_format.id,
  true,
  null,
  'Official FACOLUB 2026 catalog reference'
from public.product_formats product_format
join public.products product on product.id = product_format.product_id
join public.packaging_formats format on format.id = product_format.format_id
where product_format.official_catalog_number between 1 and 41
  and not exists (
    select 1 from public.stock_items item
    where item.product_format_id = product_format.id
      and item.category = 'finished_product'::public.stock_item_category
  );

update public.stock_items item
set is_active = true
from public.product_formats product_format
where product_format.official_catalog_number between 1 and 41
  and item.product_format_id = product_format.id
  and item.code = product_format.sku
  and item.category = 'finished_product'::public.stock_item_category
  and item.unit = 'piece'::public.stock_unit;

create unique index if not exists stock_items_finished_product_format_unique
  on public.stock_items (product_format_id)
  where product_format_id is not null
    and category = 'finished_product'::public.stock_item_category;

commit;

select
  count(distinct item.id) as linked_official_finished_stock_items,
  count(distinct item.id) filter (where item.minimum_stock is null) as minimum_stock_not_invented,
  coalesce(sum(balance.physical_quantity), 0) as physical_quantity_from_existing_ledger,
  coalesce(sum(balance.reserved_quantity), 0) as reserved_quantity_from_existing_reservations
from public.product_formats product_format
join public.stock_items item
  on item.product_format_id = product_format.id
 and item.category = 'finished_product'::public.stock_item_category
left join public.stock_balances balance on balance.stock_item_id = item.id
where product_format.official_catalog_number between 1 and 41;
