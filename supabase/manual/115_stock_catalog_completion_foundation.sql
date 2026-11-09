-- FACOLUB stock catalog completion - 115 mapping and tonne-safe foundation
-- Run manually after 114_customer_verification.sql.
-- Additive only. This file creates no stock quantities, movements, reservations,
-- preparation executions, production executions, orders, invoices, or dispatches.

do $$
begin
  if to_regclass('public.stock_items') is null
    or to_regclass('public.product_formats') is null
    or to_regclass('public.prepared_bottle_recipes') is null
    or to_regclass('public.production_recipes') is null then
    raise exception 'FACOLUB stock, catalog, prepared-bottle, and production foundations are required.';
  end if;
end
$$;

-- PostgreSQL enum extension is intentionally its own top-level statement. The
-- next file uses the value only after this statement has committed.
alter type public.stock_unit add value if not exists 'tonne';

create table if not exists public.facolub_bulk_lubricant_catalog (
  oil_code text primary key,
  oil_name text not null unique,
  display_order smallint not null unique,
  stock_item_id uuid not null unique references public.stock_items(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint facolub_bulk_lubricant_catalog_code check (
    oil_code = upper(trim(oil_code)) and oil_code ~ '^BULK-[0-9]{2}$'
  ),
  constraint facolub_bulk_lubricant_catalog_name check (
    char_length(trim(oil_name)) between 1 and 120
  ),
  constraint facolub_bulk_lubricant_catalog_order check (display_order between 1 and 19)
);

-- One official finished product/format resolves to one physical empty bottle
-- and one prepared-bottle stock reference. Empty bottles remain shared by format.
create table if not exists public.product_format_bottle_mappings (
  product_format_id uuid primary key references public.product_formats(id) on delete restrict,
  empty_bottle_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  prepared_bottle_stock_item_id uuid not null unique references public.stock_items(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Multiple label components are supported. A null quantity means the label
-- reference is known but its count/type configuration has not been confirmed.
create table if not exists public.product_format_label_mappings (
  product_format_id uuid not null references public.product_formats(id) on delete restrict,
  label_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  quantity_per_prepared_bottle numeric(20,6),
  configuration_source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (product_format_id, label_stock_item_id),
  constraint product_format_label_mappings_quantity check (
    quantity_per_prepared_bottle is null or quantity_per_prepared_bottle > 0
  ),
  constraint product_format_label_mappings_source check (
    configuration_source is null
    or char_length(trim(configuration_source)) between 1 and 200
  )
);

-- Mapping is explicit, but conversion is deliberately nullable. Production
-- currently consumes bulk lubricant in liters; no mass/volume conversion is
-- valid until density (or a confirmed liters-per-tonne factor) is configured.
create table if not exists public.product_format_bulk_lubricant_mappings (
  product_format_id uuid primary key references public.product_formats(id) on delete restrict,
  bulk_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  liters_per_tonne numeric(20,6),
  conversion_source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_format_bulk_conversion_positive check (
    liters_per_tonne is null or liters_per_tonne > 0
  ),
  constraint product_format_bulk_conversion_source check (
    (liters_per_tonne is null and conversion_source is null)
    or (liters_per_tonne is not null
      and char_length(trim(conversion_source)) between 1 and 500)
  )
);

create index if not exists product_format_bottle_mappings_empty_idx
  on public.product_format_bottle_mappings (empty_bottle_stock_item_id);
create index if not exists product_format_label_mappings_label_idx
  on public.product_format_label_mappings (label_stock_item_id);
create index if not exists product_format_bulk_mappings_stock_idx
  on public.product_format_bulk_lubricant_mappings (bulk_stock_item_id);

create or replace function public.validate_facolub_catalog_stock_mapping()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare mapped_item public.stock_items;
begin
  if tg_table_name = 'product_format_bottle_mappings' then
    select item.* into mapped_item from public.stock_items item
    where item.id = new.empty_bottle_stock_item_id and item.is_active;
    if not found or mapped_item.category <> 'empty_bottle'::public.stock_item_category
      or mapped_item.unit <> 'piece'::public.stock_unit then
      raise exception 'Empty-bottle mapping requires an active empty_bottle item in pieces'
        using errcode = '23514';
    end if;

    select item.* into mapped_item from public.stock_items item
    where item.id = new.prepared_bottle_stock_item_id and item.is_active;
    if not found or mapped_item.category <> 'prepared_bottle'::public.stock_item_category
      or mapped_item.unit <> 'piece'::public.stock_unit
      or mapped_item.product_format_id is distinct from new.product_format_id then
      raise exception 'Prepared-bottle mapping requires a matching active product-format item in pieces'
        using errcode = '23514';
    end if;
  elsif tg_table_name = 'product_format_label_mappings' then
    select item.* into mapped_item from public.stock_items item
    where item.id = new.label_stock_item_id and item.is_active;
    if not found or mapped_item.category <> 'label'::public.stock_item_category
      or mapped_item.unit <> 'piece'::public.stock_unit
      or mapped_item.product_format_id is distinct from new.product_format_id then
      raise exception 'Label mapping requires a matching active product-format label item in pieces'
        using errcode = '23514';
    end if;
  elsif tg_table_name = 'product_format_bulk_lubricant_mappings' then
    select item.* into mapped_item from public.stock_items item
    where item.id = new.bulk_stock_item_id and item.is_active;
    if not found or mapped_item.category <> 'bulk_lubricant'::public.stock_item_category
      or mapped_item.unit::text <> 'tonne' then
      raise exception 'Bulk mapping requires an active bulk_lubricant item in tonnes'
        using errcode = '23514';
    end if;
  elsif tg_table_name = 'facolub_bulk_lubricant_catalog' then
    select item.* into mapped_item from public.stock_items item
    where item.id = new.stock_item_id and item.is_active;
    if not found or mapped_item.category <> 'bulk_lubricant'::public.stock_item_category
      or mapped_item.unit::text <> 'tonne' then
      raise exception 'FACOLUB bulk catalog requires an active bulk_lubricant item in tonnes'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists facolub_bulk_catalog_validate on public.facolub_bulk_lubricant_catalog;
create trigger facolub_bulk_catalog_validate before insert or update
on public.facolub_bulk_lubricant_catalog for each row
execute function public.validate_facolub_catalog_stock_mapping();
drop trigger if exists product_format_bottle_mappings_validate on public.product_format_bottle_mappings;
create trigger product_format_bottle_mappings_validate before insert or update
on public.product_format_bottle_mappings for each row
execute function public.validate_facolub_catalog_stock_mapping();
drop trigger if exists product_format_label_mappings_validate on public.product_format_label_mappings;
create trigger product_format_label_mappings_validate before insert or update
on public.product_format_label_mappings for each row
execute function public.validate_facolub_catalog_stock_mapping();
drop trigger if exists product_format_bulk_mappings_validate on public.product_format_bulk_lubricant_mappings;
create trigger product_format_bulk_mappings_validate before insert or update
on public.product_format_bulk_lubricant_mappings for each row
execute function public.validate_facolub_catalog_stock_mapping();

drop trigger if exists facolub_bulk_catalog_updated_at on public.facolub_bulk_lubricant_catalog;
create trigger facolub_bulk_catalog_updated_at before update
on public.facolub_bulk_lubricant_catalog for each row execute function public.set_updated_at();
drop trigger if exists product_format_bottle_mappings_updated_at on public.product_format_bottle_mappings;
create trigger product_format_bottle_mappings_updated_at before update
on public.product_format_bottle_mappings for each row execute function public.set_updated_at();
drop trigger if exists product_format_label_mappings_updated_at on public.product_format_label_mappings;
create trigger product_format_label_mappings_updated_at before update
on public.product_format_label_mappings for each row execute function public.set_updated_at();
drop trigger if exists product_format_bulk_mappings_updated_at on public.product_format_bulk_lubricant_mappings;
create trigger product_format_bulk_mappings_updated_at before update
on public.product_format_bulk_lubricant_mappings for each row execute function public.set_updated_at();

alter table public.facolub_bulk_lubricant_catalog enable row level security;
alter table public.product_format_bottle_mappings enable row level security;
alter table public.product_format_label_mappings enable row level security;
alter table public.product_format_bulk_lubricant_mappings enable row level security;

drop policy if exists facolub_bulk_catalog_read on public.facolub_bulk_lubricant_catalog;
create policy facolub_bulk_catalog_read on public.facolub_bulk_lubricant_catalog
for select to authenticated using (public.has_environment_access('FACOLUB'));
drop policy if exists product_format_bottle_mappings_read on public.product_format_bottle_mappings;
create policy product_format_bottle_mappings_read on public.product_format_bottle_mappings
for select to authenticated using (public.has_environment_access('FACOLUB'));
drop policy if exists product_format_label_mappings_read on public.product_format_label_mappings;
create policy product_format_label_mappings_read on public.product_format_label_mappings
for select to authenticated using (public.has_environment_access('FACOLUB'));
drop policy if exists product_format_bulk_mappings_read on public.product_format_bulk_lubricant_mappings;
create policy product_format_bulk_mappings_read on public.product_format_bulk_lubricant_mappings
for select to authenticated using (public.has_environment_access('FACOLUB'));

revoke all on public.facolub_bulk_lubricant_catalog from public, anon, authenticated;
revoke all on public.product_format_bottle_mappings from public, anon, authenticated;
revoke all on public.product_format_label_mappings from public, anon, authenticated;
revoke all on public.product_format_bulk_lubricant_mappings from public, anon, authenticated;
grant select on public.facolub_bulk_lubricant_catalog to authenticated;
grant select on public.product_format_bottle_mappings to authenticated;
grant select on public.product_format_label_mappings to authenticated;
grant select on public.product_format_bulk_lubricant_mappings to authenticated;
revoke all on function public.validate_facolub_catalog_stock_mapping()
  from public, anon, authenticated;

comment on table public.product_format_label_mappings is
  'Supports multiple product-specific labels. Null quantity means configuration is unresolved and must not be guessed.';
comment on column public.product_format_bulk_lubricant_mappings.liters_per_tonne is
  'Optional lubricant-specific mass/volume conversion. Never default to 1000.';

select
  exists (select 1 from pg_enum where enumtypid = 'public.stock_unit'::regtype
          and enumlabel = 'tonne') as tonne_unit_installed,
  to_regclass('public.product_format_bottle_mappings') is not null as bottle_mapping_ready,
  to_regclass('public.product_format_label_mappings') is not null as label_mapping_ready,
  to_regclass('public.product_format_bulk_lubricant_mappings') is not null as bulk_mapping_ready;
