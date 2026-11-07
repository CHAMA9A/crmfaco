-- FACOLUB 2026 official product catalog - 091 idempotent catalog seed
-- Run manually after 090_facolub_product_catalog_foundation.sql.
-- This file creates/reuses exactly the 41 supplied catalog references.
-- It creates no stock items, stock movements, reservations, or opening balances.

begin;

create temporary table facolub_official_catalog (
  official_number smallint primary key,
  range_code text not null,
  product_name text not null,
  format_code text not null,
  volume_liters numeric(12,3) not null,
  sku text not null unique
) on commit drop;

insert into facolub_official_catalog
  (official_number, range_code, product_name, format_code, volume_liters, sku)
values
  (1, 'PLATINUM', '5W30', '5L', 5, 'FAC-PLA-5W30-05L'),
  (2, 'PLATINUM', '5W40', '5L', 5, 'FAC-PLA-5W40-05L'),
  (3, 'PREMIUM', '10W40', '1L', 1, 'FAC-PRE-10W40-01L'),
  (4, 'PREMIUM', '10W40', '5L', 5, 'FAC-PRE-10W40-05L'),
  (5, 'PREMIUM', '15W40', '1L', 1, 'FAC-PRE-15W40-01L'),
  (6, 'PREMIUM', '15W40', '5L', 5, 'FAC-PRE-15W40-05L'),
  (7, 'PREMIUM', '15W40', '25L', 25, 'FAC-PRE-15W40-25L'),
  (8, 'ULTRA', 'SAE 40', '1L', 1, 'FAC-ULT-SAE40-01L'),
  (9, 'ULTRA', 'SAE 40', '2L', 2, 'FAC-ULT-SAE40-02L'),
  (10, 'ULTRA', 'SAE 40', '5L', 5, 'FAC-ULT-SAE40-05L'),
  (11, 'ULTRA', 'SAE 40', '25L', 25, 'FAC-ULT-SAE40-25L'),
  (12, 'ULTRA', 'SAE 50', '1L', 1, 'FAC-ULT-SAE50-01L'),
  (13, 'ULTRA', 'SAE 50', '2L', 2, 'FAC-ULT-SAE50-02L'),
  (14, 'ULTRA', 'SAE 50', '5L', 5, 'FAC-ULT-SAE50-05L'),
  (15, 'ULTRA', 'SAE 50', '25L', 25, 'FAC-ULT-SAE50-25L'),
  (16, 'ULTRA', '20W50', '1L', 1, 'FAC-ULT-20W50-01L'),
  (17, 'ULTRA', '20W50', '2L', 2, 'FAC-ULT-20W50-02L'),
  (18, 'ULTRA', '20W50', '5L', 5, 'FAC-ULT-20W50-05L'),
  (19, 'ULTRA', '20W50', '25L', 25, 'FAC-ULT-20W50-25L'),
  (20, 'EXTREME', 'SAE 90', '1L', 1, 'FAC-EXT-SAE90-01L'),
  (21, 'EXTREME', 'SAE 90', '2L', 2, 'FAC-EXT-SAE90-02L'),
  (22, 'EXTREME', 'SAE 90', '5L', 5, 'FAC-EXT-SAE90-05L'),
  (23, 'EXTREME', 'SAE 90', '25L', 25, 'FAC-EXT-SAE90-25L'),
  (24, 'EXTREME', 'SAE 140', '1L', 1, 'FAC-EXT-SAE140-01L'),
  (25, 'EXTREME', 'SAE 140', '2L', 2, 'FAC-EXT-SAE140-02L'),
  (26, 'EXTREME', 'SAE 140', '5L', 5, 'FAC-EXT-SAE140-05L'),
  (27, 'EXTREME', 'SAE 140', '25L', 25, 'FAC-EXT-SAE140-25L'),
  (28, 'OPTIMUM', 'ATF', '1L', 1, 'FAC-OPT-ATF-01L'),
  (29, 'EXPERT', '2T', '1L', 1, 'FAC-EXP-2T-01L'),
  (30, 'EXPERT', '2T', '2L', 2, 'FAC-EXP-2T-02L'),
  (31, 'EXPERT', '2T', '5L', 5, 'FAC-EXP-2T-05L'),
  (32, 'EXPERT', '2T', '25L', 25, 'FAC-EXP-2T-25L'),
  (33, '4T', '4T 10W40', '1L', 1, 'FAC-4T-STD-10W40-01L'),
  (34, '4T', '4T 20W50 Ultra', '1L', 1, 'FAC-4T-ULT-20W50-01L'),
  (35, '4T', '4T 20W50', '1L', 1, 'FAC-4T-STD-20W50-01L'),
  (36, '4T', '4T 10W40 F7500', '1L', 1, 'FAC-4T-F7500-10W40-01L'),
  (37, '4T', '4T 15W50 F5500', '1L', 1, 'FAC-4T-F5500-15W50-01L'),
  (38, '4T', '4T 20W50 F3300', '1L', 1, 'FAC-4T-F3300-20W50-01L'),
  (39, 'HYDRAULIQUE', '68', '5L', 5, 'FAC-HYD-68-05L'),
  (40, 'HYDRAULIQUE', '68', '25L', 25, 'FAC-HYD-68-25L'),
  (41, 'DYNOVEX', 'DYNOVEX', '1L', 1, 'FAC-DYN-01L');

do $$
begin
  if (select count(*) from facolub_official_catalog) <> 41
    or (select count(distinct sku) from facolub_official_catalog) <> 41 then
    raise exception 'The embedded official FACOLUB catalog must contain exactly 41 unique SKUs.';
  end if;
end
$$;

insert into public.product_ranges (code, name, display_order, is_active)
values
  ('PLATINUM', 'PLATINUM', 1, true),
  ('PREMIUM', 'PREMIUM', 2, true),
  ('ULTRA', 'ULTRA', 3, true),
  ('EXTREME', 'EXTREME', 4, true),
  ('OPTIMUM', 'OPTIMUM', 5, true),
  ('EXPERT', 'EXPERT', 6, true),
  ('4T', '4T', 7, true),
  ('HYDRAULIQUE', 'HYDRAULIQUE', 8, true),
  ('DYNOVEX', 'DYNOVEX', 9, true)
on conflict (code) do update set
  name = excluded.name,
  display_order = excluded.display_order,
  is_active = true;

do $$
declare conflict_codes text;
begin
  select string_agg(distinct format.code, ', ' order by format.code)
  into conflict_codes
  from facolub_official_catalog official
  join public.packaging_formats format on format.code = official.format_code
  where format.volume_liters is distinct from official.volume_liters;

  if conflict_codes is not null then
    raise exception 'Existing packaging format volume conflicts with the official catalog: %', conflict_codes;
  end if;
end
$$;

insert into public.packaging_formats (code, name, volume_liters, is_active)
select distinct official.format_code, official.format_code, official.volume_liters, true
from facolub_official_catalog official
where not exists (
  select 1 from public.packaging_formats format where format.code = official.format_code
);

do $$
declare candidate record;
declare matching_count integer;
declare matching_product public.products;
declare target_range_id uuid;
begin
  for candidate in
    select distinct official.range_code, official.product_name
    from facolub_official_catalog official
    order by official.range_code, official.product_name
  loop
    select range.id into strict target_range_id
    from public.product_ranges range where range.code = candidate.range_code;

    select count(*) into matching_count
    from public.products product
    where lower(trim(product.name)) = lower(candidate.product_name);

    if matching_count > 1 then
      raise exception 'Multiple existing products match official product % (%). Resolve before rerunning 091.',
        candidate.product_name, candidate.range_code;
    elsif matching_count = 1 then
      select product.* into matching_product
      from public.products product
      where lower(trim(product.name)) = lower(candidate.product_name);

      if matching_product.product_range_id is not null
        and matching_product.product_range_id <> target_range_id then
        raise exception 'Existing product % is assigned to another range. Resolve before rerunning 091.',
          candidate.product_name;
      end if;

      update public.products product
      set product_range_id = target_range_id,
          is_active = true
      where product.id = matching_product.id;
    else
      insert into public.products (code, name, product_range_id, is_active)
      values (null, candidate.product_name, target_range_id, true);
    end if;
  end loop;
end
$$;

do $$
declare official record;
declare target_product_id uuid;
declare target_format_id uuid;
declare combination public.product_formats;
declare sku_owner public.product_formats;
declare number_owner public.product_formats;
begin
  for official in select * from facolub_official_catalog order by official_number
  loop
    select product.id into strict target_product_id
    from public.products product
    join public.product_ranges range on range.id = product.product_range_id
    where range.code = official.range_code
      and lower(trim(product.name)) = lower(official.product_name);

    select format.id into strict target_format_id
    from public.packaging_formats format where format.code = official.format_code;

    select product_format.* into combination
    from public.product_formats product_format
    where product_format.product_id = target_product_id
      and product_format.format_id = target_format_id;

    select product_format.* into sku_owner
    from public.product_formats product_format where product_format.sku = official.sku;

    select product_format.* into number_owner
    from public.product_formats product_format
    where product_format.official_catalog_number = official.official_number;

    if sku_owner.id is not null and (
      sku_owner.product_id <> target_product_id or sku_owner.format_id <> target_format_id
    ) then
      raise exception 'SKU % already belongs to another product/format. No data was overwritten.', official.sku;
    end if;

    if number_owner.id is not null and (
      number_owner.product_id <> target_product_id or number_owner.format_id <> target_format_id
    ) then
      raise exception 'Official number % already belongs to another product/format. No data was overwritten.',
        official.official_number;
    end if;

    if combination.id is null then
      insert into public.product_formats (
        product_id, format_id, sku, official_catalog_number, is_active
      ) values (
        target_product_id, target_format_id, official.sku, official.official_number, true
      );
    elsif combination.sku is not null and combination.sku <> official.sku then
      raise exception 'Product/format % / % already has conflicting SKU %. No data was overwritten.',
        official.product_name, official.format_code, combination.sku;
    elsif combination.official_catalog_number is not null
      and combination.official_catalog_number <> official.official_number then
      raise exception 'Product/format % / % already has conflicting official number %. No data was overwritten.',
        official.product_name, official.format_code, combination.official_catalog_number;
    else
      update public.product_formats product_format
      set sku = official.sku,
          official_catalog_number = official.official_number,
          is_active = true
      where product_format.id = combination.id;
    end if;
  end loop;
end
$$;

commit;

select
  count(*) filter (where product_format.sku like 'FAC-%') as facolub_sku_count,
  count(distinct product_format.sku) filter (where product_format.sku like 'FAC-%') as unique_facolub_sku_count,
  count(distinct range.code) filter (
    where product_format.official_catalog_number between 1 and 41
  ) as official_range_count
from public.product_formats product_format
join public.products product on product.id = product_format.product_id
left join public.product_ranges range on range.id = product.product_range_id
where product_format.official_catalog_number between 1 and 41
   or product_format.sku like 'FAC-%';
