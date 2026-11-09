-- SOMA / FACOLUB S8 dispatch - 118 foundation and numbering
-- Run manually after 117_stock_catalog_completion_verification.sql.
-- Additive only: creates no dispatch, movement, document, or demo rows.

do $$ begin
  create type public.dispatch_status as enum ('draft', 'confirmed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.dispatch_destination_type as enum ('customer', 'internal');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.dispatch_attachment_category as enum ('goods', 'vehicle', 'registration', 'other');
exception when duplicate_object then null;
end $$;

create table if not exists public.dispatch_number_sequences (
  dispatch_date date primary key,
  last_value bigint not null check (last_value > 0)
);

create table if not exists public.dispatches (
  id uuid primary key default gen_random_uuid(),
  dispatch_number text unique,
  order_id uuid references public.orders(id) on delete restrict,
  customer_id uuid references public.customers(id) on delete restrict,
  location_id uuid not null references public.stock_locations(id) on delete restrict,
  dispatch_date date not null default current_date,
  destination_type public.dispatch_destination_type not null,
  destination_name text not null,
  delivery_address_snapshot text,
  delivery_city_snapshot text,
  delivery_contact_snapshot text,
  status public.dispatch_status not null default 'draft',
  vehicle_description text,
  vehicle_registration text,
  driver_name text,
  driver_phone text,
  transport_company text,
  notes text,
  confirmed_at timestamptz,
  confirmed_by uuid references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint dispatches_number_format check (
    dispatch_number is null or dispatch_number ~ '^EXP-[0-9]{6}-[0-9]{2,}$'
  ),
  constraint dispatches_destination_name check (char_length(trim(destination_name)) between 1 and 200),
  constraint dispatches_order_destination check (
    (destination_type = 'customer' and order_id is not null and customer_id is not null)
    or (destination_type = 'internal' and customer_id is null)
  ),
  constraint dispatches_confirmation_state check (
    (status = 'confirmed' and dispatch_number is not null and confirmed_at is not null and confirmed_by is not null)
    or (status <> 'confirmed' and confirmed_at is null and confirmed_by is null)
  )
);

create table if not exists public.dispatch_items (
  id uuid primary key default gen_random_uuid(),
  dispatch_id uuid not null references public.dispatches(id) on delete cascade,
  order_item_id uuid references public.order_items(id) on delete restrict,
  product_format_id uuid not null references public.product_formats(id) on delete restrict,
  stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  sku_snapshot text not null,
  description_snapshot text not null,
  ordered_quantity_snapshot numeric(18,3),
  quantity_loaded numeric(18,3) not null,
  created_at timestamptz not null default now(),
  constraint dispatch_items_quantity_positive check (quantity_loaded > 0),
  constraint dispatch_items_ordered_positive check (
    ordered_quantity_snapshot is null or ordered_quantity_snapshot > 0
  ),
  constraint dispatch_items_unique_product unique (dispatch_id, product_format_id),
  constraint dispatch_items_unique_order_line unique (dispatch_id, order_item_id)
);

create table if not exists public.dispatch_attachments (
  id uuid primary key default gen_random_uuid(),
  dispatch_id uuid not null references public.dispatches(id) on delete cascade,
  category public.dispatch_attachment_category not null,
  storage_path text not null unique,
  file_name text,
  mime_type text not null,
  file_size bigint not null,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  uploaded_at timestamptz not null default now(),
  constraint dispatch_attachments_mime check (mime_type in ('image/jpeg','image/png','image/webp','image/heic','image/heif')),
  constraint dispatch_attachments_size check (file_size between 1 and 8388608),
  constraint dispatch_attachments_path check (char_length(trim(storage_path)) between 38 and 1000)
);

create table if not exists public.dispatch_corrections (
  id uuid primary key default gen_random_uuid(),
  dispatch_id uuid not null references public.dispatches(id) on delete restrict,
  dispatch_item_id uuid not null references public.dispatch_items(id) on delete restrict,
  original_movement_id uuid not null references public.stock_movements(id) on delete restrict,
  correction_movement_id uuid not null unique references public.stock_movements(id) on delete restrict,
  quantity numeric(18,3) not null check (quantity > 0),
  reason text not null check (char_length(trim(reason)) between 3 and 1000),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists dispatches_order_status_idx on public.dispatches (order_id, status, confirmed_at);
create index if not exists dispatches_customer_date_idx on public.dispatches (customer_id, dispatch_date desc);
create index if not exists dispatches_history_idx on public.dispatches (dispatch_date desc, created_at desc);
create index if not exists dispatch_items_dispatch_idx on public.dispatch_items (dispatch_id, created_at);
create index if not exists dispatch_items_order_line_idx on public.dispatch_items (order_item_id) where order_item_id is not null;
create index if not exists dispatch_attachments_dispatch_idx on public.dispatch_attachments (dispatch_id, category, uploaded_at);
create unique index if not exists stock_movements_dispatch_item_unique_idx
  on public.stock_movements ((metadata ->> 'dispatch_item_id'))
  where movement_type = 'dispatch' and metadata ? 'dispatch_item_id';

alter table public.dispatches enable row level security;
alter table public.dispatch_items enable row level security;
alter table public.dispatch_attachments enable row level security;
alter table public.dispatch_corrections enable row level security;
alter table public.dispatch_number_sequences enable row level security;
revoke all on public.dispatches, public.dispatch_items, public.dispatch_attachments,
  public.dispatch_corrections, public.dispatch_number_sequences from public, anon, authenticated;

create or replace function public.allocate_dispatch_number(target_date date)
returns text language plpgsql security definer set search_path = '' as $$
declare next_value bigint;
begin
  if target_date is null then raise exception 'Dispatch date is required' using errcode = '22023'; end if;
  insert into public.dispatch_number_sequences(dispatch_date, last_value) values (target_date, 1)
  on conflict (dispatch_date) do update set last_value = public.dispatch_number_sequences.last_value + 1
  returning last_value into next_value;
  return format('EXP-%s-%s', to_char(target_date, 'YYMMDD'), lpad(next_value::text, 2, '0'));
end $$;

create or replace function public.normalize_dispatch()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.destination_name := trim(new.destination_name);
  new.delivery_address_snapshot := nullif(trim(new.delivery_address_snapshot), '');
  new.delivery_city_snapshot := nullif(trim(new.delivery_city_snapshot), '');
  new.delivery_contact_snapshot := nullif(trim(new.delivery_contact_snapshot), '');
  new.vehicle_description := nullif(trim(new.vehicle_description), '');
  new.vehicle_registration := nullif(trim(new.vehicle_registration), '');
  new.driver_name := nullif(trim(new.driver_name), '');
  new.driver_phone := nullif(trim(new.driver_phone), '');
  new.transport_company := nullif(trim(new.transport_company), '');
  new.notes := nullif(trim(new.notes), '');
  return new;
end $$;

create or replace function public.protect_dispatch_event()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'DELETE' and old.status = 'confirmed' then
    raise exception 'Confirmed dispatches cannot be deleted; record a correction' using errcode = '55000';
  end if;
  if tg_op = 'UPDATE' and old.status = 'confirmed' and new is distinct from old then
    raise exception 'Confirmed dispatches are immutable; record a correction' using errcode = '55000';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create or replace function public.require_draft_dispatch_child()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare parent_id uuid := coalesce(new.dispatch_id, old.dispatch_id);
begin
  if not exists (select 1 from public.dispatches d where d.id = parent_id and d.status = 'draft') then
    raise exception 'Dispatch lines and photos can change only while draft' using errcode = '55000';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists dispatches_normalize on public.dispatches;
create trigger dispatches_normalize before insert or update on public.dispatches
for each row execute function public.normalize_dispatch();
drop trigger if exists dispatches_set_updated_at on public.dispatches;
create trigger dispatches_set_updated_at before update on public.dispatches
for each row execute function public.set_updated_at();
drop trigger if exists dispatches_protect_confirmed on public.dispatches;
create trigger dispatches_protect_confirmed before update or delete on public.dispatches
for each row execute function public.protect_dispatch_event();
drop trigger if exists dispatch_items_require_draft on public.dispatch_items;
create trigger dispatch_items_require_draft before insert or update or delete on public.dispatch_items
for each row execute function public.require_draft_dispatch_child();
drop trigger if exists dispatch_attachments_require_draft on public.dispatch_attachments;
create trigger dispatch_attachments_require_draft before insert or update or delete on public.dispatch_attachments
for each row execute function public.require_draft_dispatch_child();

revoke all on function public.allocate_dispatch_number(date) from public, anon, authenticated;
revoke all on function public.normalize_dispatch() from public, anon, authenticated;
revoke all on function public.protect_dispatch_event() from public, anon, authenticated;
revoke all on function public.require_draft_dispatch_child() from public, anon, authenticated;

comment on table public.dispatches is 'Physical loading event. Only confirmation creates finished-product stock OUT.';
comment on table public.dispatch_corrections is 'Foundation for explicit compensating movements; original events remain immutable.';

select to_regclass('public.dispatches') as dispatches,
  to_regclass('public.dispatch_items') as dispatch_items,
  to_regprocedure('public.allocate_dispatch_number(date)') as number_allocator;
