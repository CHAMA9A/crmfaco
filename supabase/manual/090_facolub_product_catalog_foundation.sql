-- FACOLUB 2026 official product catalog - 090 normalized foundation
-- Run manually in Supabase SQL Editor after 084_stock_count_verification.sql.
-- Additive and idempotent: no catalog rows or stock quantities are created here.

do $$
begin
  if to_regclass('public.products') is null
    or to_regclass('public.packaging_formats') is null
    or to_regclass('public.product_formats') is null
    or to_regclass('public.stock_items') is null
    or to_regclass('public.order_items') is null
    or to_regclass('public.invoice_items') is null then
    raise exception 'FACOLUB catalog dependencies are missing. Apply the existing invoice, order, stock, and planning SQL first.';
  end if;
end
$$;

create table if not exists public.product_ranges (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  display_order integer not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_ranges_code_format check (
    code = upper(trim(code)) and code ~ '^[A-Z0-9._-]{1,40}$'
  ),
  constraint product_ranges_name_length check (char_length(trim(name)) between 1 and 80),
  constraint product_ranges_display_order_positive check (display_order > 0)
);

alter table public.products add column if not exists product_range_id uuid;
alter table public.product_formats add column if not exists sku text;
alter table public.product_formats add column if not exists official_catalog_number smallint;
alter table public.invoice_items add column if not exists product_format_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'products_product_range_id_fkey'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_product_range_id_fkey
      foreign key (product_range_id) references public.product_ranges(id)
      on delete restrict not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'order_items_product_format_id_fkey'
      and conrelid = 'public.order_items'::regclass
  ) then
    -- NOT VALID preserves any historical free-text order rows with legacy UUIDs.
    -- PostgreSQL still enforces the relation for all new/changed links.
    alter table public.order_items
      add constraint order_items_product_format_id_fkey
      foreign key (product_format_id) references public.product_formats(id)
      on delete restrict not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'invoice_items_product_format_id_fkey'
      and conrelid = 'public.invoice_items'::regclass
  ) then
    alter table public.invoice_items
      add constraint invoice_items_product_format_id_fkey
      foreign key (product_format_id) references public.product_formats(id)
      on delete restrict not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'product_formats_sku_format'
      and conrelid = 'public.product_formats'::regclass
  ) then
    alter table public.product_formats
      add constraint product_formats_sku_format check (
        sku is null or (
          sku = upper(trim(sku))
          and sku ~ '^[A-Z0-9][A-Z0-9._-]{0,79}$'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'product_formats_official_catalog_number_range'
      and conrelid = 'public.product_formats'::regclass
  ) then
    alter table public.product_formats
      add constraint product_formats_official_catalog_number_range check (
        official_catalog_number is null or official_catalog_number between 1 and 999
      ) not valid;
  end if;
end
$$;

create unique index if not exists product_formats_sku_unique
  on public.product_formats (sku) where sku is not null;
create unique index if not exists product_formats_official_catalog_number_unique
  on public.product_formats (official_catalog_number)
  where official_catalog_number is not null;
create index if not exists products_range_active_name_idx
  on public.products (product_range_id, name) where is_active;
create index if not exists invoice_items_product_format_idx
  on public.invoice_items (product_format_id) where product_format_id is not null;

create or replace function public.normalize_product_range()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.code := upper(trim(new.code));
  new.name := trim(new.name);
  return new;
end;
$$;

drop trigger if exists product_ranges_normalize on public.product_ranges;
create trigger product_ranges_normalize
before insert or update of code, name on public.product_ranges
for each row execute function public.normalize_product_range();

drop trigger if exists product_ranges_set_updated_at on public.product_ranges;
create trigger product_ranges_set_updated_at
before update on public.product_ranges
for each row execute function public.set_updated_at();

alter table public.product_ranges enable row level security;
drop policy if exists product_ranges_facolub_read on public.product_ranges;
create policy product_ranges_facolub_read on public.product_ranges
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
  and (is_active or public.current_app_role() = 'admin'::public.app_role)
);

revoke all on public.product_ranges from public, anon, authenticated;
grant select on public.product_ranges to authenticated;
revoke all on function public.normalize_product_range() from public, anon, authenticated;

comment on table public.product_ranges is
  'Normalized FACOLUB commercial range/category (PLATINUM, PREMIUM, ULTRA, and others).';
comment on column public.product_formats.sku is
  'Authoritative finished-product SKU. Nullable for legacy/non-official product-format rows.';
comment on column public.product_formats.official_catalog_number is
  'Official catalog row number; nullable for legacy/non-official product-format rows.';
comment on column public.invoice_items.product_format_id is
  'Optional catalog lineage. Description, quantity, unit price, and line total remain immutable document snapshots.';

select
  to_regclass('public.product_ranges') as product_ranges_table,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'products'
      and column_name = 'product_range_id'
  ) as product_range_link_exists,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'product_formats'
      and column_name = 'sku'
  ) as sku_column_exists,
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'product_formats_sku_unique'
  ) as sku_unique_index_exists;
