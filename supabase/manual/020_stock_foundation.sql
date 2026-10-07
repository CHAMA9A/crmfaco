-- SOMA / FACOLUB stock module - 020 foundation
-- Run manually in Supabase SQL Editor after 001-015.
-- Additive only: stock enums, items, locations, and adjustment workflow foundation.

do $$
begin
  if to_regclass('public.profiles') is null
    or to_regprocedure('public.current_app_role()') is null
    or to_regprocedure('public.has_environment_access(text)') is null then
    raise exception 'FACOLUB auth foundation is missing. Run the existing auth SQL first.';
  end if;
end
$$;

do $$ begin
  create type public.stock_item_category as enum (
    'empty_bottle', 'label', 'prepared_bottle', 'seal', 'carton',
    'bulk_lubricant', 'finished_product', 'other'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  -- Canonical physical units only. A carton stock item is counted in pieces.
  create type public.stock_unit as enum ('piece', 'liter', 'kilogram');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.stock_direction as enum ('in', 'out');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.stock_movement_type as enum (
    'opening_balance', 'receipt',
    'preparation_consumption', 'preparation_output',
    'production_consumption', 'production_output',
    'dispatch', 'adjustment_in', 'adjustment_out',
    'loss', 'damage', 'correction',
    'reservation_release_related', 'other'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.stock_reservation_status as enum (
    'active', 'released', 'consumed', 'cancelled'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.stock_adjustment_status as enum (
    'draft', 'pending', 'approved', 'rejected', 'posted'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.stock_locations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_locations_code_format check (
    code = upper(trim(code)) and code ~ '^[A-Z0-9_-]{2,40}$'
  ),
  constraint stock_locations_name_length check (char_length(trim(name)) between 1 and 120)
);

create table if not exists public.stock_items (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  category public.stock_item_category not null,
  unit public.stock_unit not null,
  -- No product-format catalog exists in the inspected schema. Keep this UUID
  -- intentionally unbound until that authoritative catalog is introduced.
  product_format_id uuid,
  is_active boolean not null default true,
  minimum_stock numeric(20,3),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_items_code_format check (
    code is null or (code = upper(trim(code)) and code ~ '^[A-Z0-9._-]{1,60}$')
  ),
  constraint stock_items_name_length check (char_length(trim(name)) between 1 and 200),
  constraint stock_items_minimum_nonnegative check (minimum_stock is null or minimum_stock >= 0)
);

create table if not exists public.stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  location_id uuid not null references public.stock_locations(id) on delete restrict,
  expected_quantity numeric(20,3) not null,
  counted_quantity numeric(20,3) not null,
  difference_quantity numeric(20,3)
    generated always as (counted_quantity - expected_quantity) stored,
  reason text not null,
  status public.stock_adjustment_status not null default 'draft',
  requested_by uuid not null references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_adjustments_quantities_nonnegative check (
    expected_quantity >= 0 and counted_quantity >= 0
  ),
  constraint stock_adjustments_reason_length check (char_length(trim(reason)) between 1 and 1000),
  constraint stock_adjustments_approval_consistent check (
    (approved_by is null and approved_at is null)
    or (approved_by is not null and approved_at is not null)
  )
);

create index if not exists stock_items_category_active_idx
  on public.stock_items (category, name) where is_active;
create index if not exists stock_items_product_format_idx
  on public.stock_items (product_format_id) where product_format_id is not null;
create index if not exists stock_adjustments_item_location_idx
  on public.stock_adjustments (stock_item_id, location_id, created_at desc);

-- Secure new tables immediately; 023 later adds the explicit read policies.
alter table public.stock_locations enable row level security;
alter table public.stock_items enable row level security;
alter table public.stock_adjustments enable row level security;
revoke all on public.stock_locations from anon, authenticated;
revoke all on public.stock_items from anon, authenticated;
revoke all on public.stock_adjustments from anon, authenticated;

create or replace function public.normalize_stock_location()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.code := nullif(upper(trim(new.code)), '');
  new.name := trim(new.name);
  new.description := nullif(trim(new.description), '');
  return new;
end;
$$;

create or replace function public.normalize_stock_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.code := nullif(upper(trim(new.code)), '');
  new.name := trim(new.name);
  new.notes := nullif(trim(new.notes), '');
  return new;
end;
$$;

drop trigger if exists stock_locations_normalize on public.stock_locations;
create trigger stock_locations_normalize
before insert or update of code, name, description on public.stock_locations
for each row execute function public.normalize_stock_location();

drop trigger if exists stock_items_normalize on public.stock_items;
create trigger stock_items_normalize
before insert or update of code, name, notes on public.stock_items
for each row execute function public.normalize_stock_item();

drop trigger if exists stock_locations_set_updated_at on public.stock_locations;
create trigger stock_locations_set_updated_at
before update on public.stock_locations
for each row execute function public.set_updated_at();

drop trigger if exists stock_items_set_updated_at on public.stock_items;
create trigger stock_items_set_updated_at
before update on public.stock_items
for each row execute function public.set_updated_at();

drop trigger if exists stock_adjustments_set_updated_at on public.stock_adjustments;
create trigger stock_adjustments_set_updated_at
before update on public.stock_adjustments
for each row execute function public.set_updated_at();

revoke all on function public.normalize_stock_location() from public, anon, authenticated;
revoke all on function public.normalize_stock_item() from public, anon, authenticated;

-- One operational location is required so every ledger entry has an explicit
-- balance scope. Future locations can be added without changing the ledger.
insert into public.stock_locations (code, name, description, is_active)
values ('FACOLUB-MAIN', 'FACOLUB Main Warehouse', 'Default FACOLUB stock location', true)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  is_active = true;

comment on table public.stock_items is
  'Stock configuration only. Quantities are derived from the movement ledger and reservations.';
comment on column public.stock_items.product_format_id is
  'Reserved link for a future authoritative product-format catalog; intentionally not an FK in S1.';
comment on type public.stock_unit is
  'Canonical physical units. Packaging conversions and mass-volume conversions are outside S1.';
comment on table public.stock_adjustments is
  'Inventory count/approval foundation. Approved differences must later post immutable movements.';

-- Verification query:
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('stock_items', 'stock_locations', 'stock_adjustments')
order by table_name;
