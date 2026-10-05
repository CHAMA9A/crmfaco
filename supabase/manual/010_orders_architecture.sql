-- SOMA order document bundle - 010 order foundation and legacy-safe invoice link
-- Run in Supabase SQL Editor after 001-004, 006, and 009.
-- Additive migration: legacy invoices remain valid with order_id = null and keep
-- their existing numbers. New order-linked invoices are one-to-one with orders.

do $$ begin
  create type public.order_status as enum (
    'draft', 'confirmed', 'documents_ready', 'completed', 'cancelled'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.document_status as enum ('draft', 'issued', 'cancelled');
exception when duplicate_object then null;
end $$;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique,
  order_reference text unique,
  customer_id uuid not null references public.customers(id),
  order_date date not null,
  purchase_order text,
  destination_city text,
  destination_address text,
  status public.order_status not null default 'draft',
  customer_name_snapshot text,
  customer_city_snapshot text,
  customer_address_snapshot text,
  customer_ice_snapshot text,
  created_by uuid not null references public.profiles(id),
  confirmed_by uuid references public.profiles(id),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_draft_numbering check (
    (status = 'draft' and order_number is null and order_reference is null
      and confirmed_by is null and confirmed_at is null)
    or
    (status <> 'draft' and order_number is not null and order_reference is not null
      and confirmed_by is not null and confirmed_at is not null)
  ),
  constraint orders_reference_format check (
    order_reference is null or order_reference ~ '^[0-9]{6}-[0-9]{2,}$'
  ),
  constraint orders_number_format check (
    order_number is null or order_number ~ '^CMD-[0-9]{6}-[0-9]{2,}$'
  )
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  -- Intentionally not an FK yet: no product-format catalog exists in this schema.
  product_format_id uuid,
  description text not null check (char_length(trim(description)) > 0),
  quantity numeric(18, 3) not null check (quantity > 0),
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id, id)
);

alter table public.invoices add column if not exists order_id uuid;
alter table public.invoices add column if not exists prices_confirmed_by uuid;
alter table public.invoices add column if not exists prices_confirmed_at timestamptz;
alter table public.invoice_items add column if not exists order_item_id uuid;

do $$ begin
  alter table public.invoices
    add constraint invoices_order_id_fkey foreign key (order_id)
    references public.orders(id);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.invoices
    add constraint invoices_prices_confirmed_by_fkey foreign key (prices_confirmed_by)
    references public.profiles(id);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.invoice_items
    add constraint invoice_items_order_item_id_fkey foreign key (order_item_id)
    references public.order_items(id);
exception when duplicate_object then null;
end $$;

create unique index if not exists invoices_order_id_unique
  on public.invoices (order_id) where order_id is not null;
create unique index if not exists invoice_items_invoice_order_item_unique
  on public.invoice_items (invoice_id, order_item_id) where order_item_id is not null;
create index if not exists orders_customer_date_idx
  on public.orders (customer_id, order_date desc);
create index if not exists orders_status_date_idx
  on public.orders (status, order_date desc);
create index if not exists orders_purchase_order_idx
  on public.orders (purchase_order) where purchase_order is not null;
create index if not exists order_items_order_position_idx
  on public.order_items (order_id, position, created_at);

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at before update on public.orders
for each row execute function public.set_updated_at();

drop trigger if exists order_items_set_updated_at on public.order_items;
create trigger order_items_set_updated_at before update on public.order_items
for each row execute function public.set_updated_at();

create or replace function public.protect_confirmed_order_fields()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if old.status <> 'draft'::public.order_status and (
    new.customer_id is distinct from old.customer_id
    or new.order_date is distinct from old.order_date
    or new.purchase_order is distinct from old.purchase_order
    or new.destination_city is distinct from old.destination_city
    or new.destination_address is distinct from old.destination_address
    or new.order_number is distinct from old.order_number
    or new.order_reference is distinct from old.order_reference
    or new.customer_name_snapshot is distinct from old.customer_name_snapshot
    or new.customer_city_snapshot is distinct from old.customer_city_snapshot
    or new.customer_address_snapshot is distinct from old.customer_address_snapshot
    or new.customer_ice_snapshot is distinct from old.customer_ice_snapshot
  ) then
    raise exception 'Confirmed order commercial data is immutable' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_protect_confirmed_fields on public.orders;
create trigger orders_protect_confirmed_fields
before update on public.orders for each row
execute function public.protect_confirmed_order_fields();

create or replace function public.require_draft_order_for_item_change()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare parent_order_id uuid := coalesce(new.order_id, old.order_id);
begin
  if not exists (
    select 1 from public.orders order_record
    where order_record.id = parent_order_id
      and order_record.status = 'draft'::public.order_status
  ) then
    raise exception 'Order items can only change while the order is draft'
      using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists order_items_require_draft on public.order_items;
create trigger order_items_require_draft
before insert or update or delete on public.order_items for each row
execute function public.require_draft_order_for_item_change();

comment on column public.invoices.order_id is
  'Nullable for legacy invoices; non-null order invoices are unique per order.';
comment on column public.invoice_items.order_item_id is
  'Source lineage only. Invoice description, quantity, price, and total remain snapshots.';
comment on table public.order_items is
  'Canonical ordered descriptions/quantities. Immutable after order confirmation.';

-- Verification query: all legacy invoices must report legacy_invoice_count = linked count 0.
select
  to_regclass('public.orders') as orders_table,
  to_regclass('public.order_items') as order_items_table,
  count(*) filter (where order_id is null) as legacy_invoice_count,
  count(*) filter (where order_id is not null) as linked_invoice_count
from public.invoices;
