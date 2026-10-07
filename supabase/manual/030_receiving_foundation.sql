-- SOMA / FACOLUB receiving module - 030 foundation
-- Depends on: 020-024.
-- Additive only: suppliers, receipt drafts, receipt lines, and photo metadata.

do $$
begin
  if to_regclass('public.stock_items') is null
    or to_regclass('public.stock_locations') is null
    or to_regclass('public.stock_movements') is null
    or to_regprocedure('public.assert_stock_actor(public.app_role[])') is null
    or to_regprocedure('public.record_stock_movement(uuid,uuid,public.stock_movement_type,numeric,public.stock_direction,text,uuid,text,jsonb,boolean)') is null then
    raise exception 'FACOLUB Stock S1 is missing. Run 020-024 before Receiving S2.';
  end if;
end
$$;

do $$ begin
  create type public.receipt_status as enum ('draft', 'confirmed', 'cancelled');
exception when duplicate_object then null;
end $$;

-- No supplier/vendor table exists in the inspected project schema. S2 adds only
-- the operational identity fields needed for receiving; this is not a CRM.
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint suppliers_name_length check (char_length(trim(name)) between 1 and 200),
  constraint suppliers_phone_length check (phone is null or char_length(trim(phone)) between 1 and 80),
  constraint suppliers_email_length check (email is null or char_length(trim(email)) between 3 and 320),
  constraint suppliers_address_length check (address is null or char_length(trim(address)) between 1 and 1000)
);

create table if not exists public.receipts (
  id uuid primary key default gen_random_uuid(),
  receipt_number text unique,
  supplier_id uuid references public.suppliers(id) on delete restrict,
  supplier_name_snapshot text,
  reference text,
  receipt_date date not null default current_date,
  location_id uuid references public.stock_locations(id) on delete restrict,
  status public.receipt_status not null default 'draft',
  comment text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  confirmed_by uuid references public.profiles(id) on delete restrict,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint receipts_number_format check (
    receipt_number is null or receipt_number ~ '^REC-[0-9]{6}-[0-9]{2,}$'
  ),
  constraint receipts_supplier_snapshot_length check (
    supplier_name_snapshot is null
    or char_length(trim(supplier_name_snapshot)) between 1 and 200
  ),
  constraint receipts_reference_length check (
    reference is null or char_length(trim(reference)) between 1 and 200
  ),
  constraint receipts_comment_length check (
    comment is null or char_length(trim(comment)) between 1 and 2000
  ),
  constraint receipts_lifecycle_consistent check (
    (status = 'draft' and receipt_number is null and confirmed_by is null and confirmed_at is null)
    or (status = 'confirmed' and receipt_number is not null and confirmed_by is not null and confirmed_at is not null)
    or (status = 'cancelled' and receipt_number is null and confirmed_by is null and confirmed_at is null)
  )
);

create table if not exists public.receipt_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.receipts(id) on delete cascade,
  stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  quantity numeric(20,3) not null,
  unit public.stock_unit not null,
  position integer not null,
  created_at timestamptz not null default now(),
  constraint receipt_items_quantity_positive check (quantity > 0),
  constraint receipt_items_position_positive check (position > 0),
  constraint receipt_items_one_stock_item unique (receipt_id, stock_item_id),
  constraint receipt_items_position_unique unique (receipt_id, position)
);

create table if not exists public.receipt_attachments (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.receipts(id) on delete cascade,
  storage_path text not null unique,
  file_name text,
  mime_type text not null,
  file_size bigint,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint receipt_attachments_path_length check (
    char_length(trim(storage_path)) between 38 and 1000
  ),
  constraint receipt_attachments_file_name_length check (
    file_name is null or char_length(trim(file_name)) between 1 and 255
  ),
  constraint receipt_attachments_image_type check (
    mime_type in ('image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif')
  ),
  constraint receipt_attachments_size_limit check (
    file_size is null or (file_size > 0 and file_size <= 8388608)
  )
);

create index if not exists suppliers_active_name_idx
  on public.suppliers (name) where is_active;
create index if not exists receipts_recent_idx
  on public.receipts (created_at desc, id desc);
create index if not exists receipts_status_date_idx
  on public.receipts (status, receipt_date desc);
create index if not exists receipts_supplier_idx
  on public.receipts (supplier_id, receipt_date desc) where supplier_id is not null;
create index if not exists receipts_creator_idx
  on public.receipts (created_by, created_at desc);
create index if not exists receipt_items_stock_item_idx
  on public.receipt_items (stock_item_id, receipt_id);
create index if not exists receipt_attachments_receipt_idx
  on public.receipt_attachments (receipt_id, created_at, id);

-- One S2 receipt line can produce at most one physical movement. Legacy S1
-- receipt movements without receipt_item_id metadata are intentionally ignored.
create unique index if not exists stock_movements_receipt_item_unique_idx
  on public.stock_movements ((metadata ->> 'receipt_item_id'))
  where movement_type = 'receipt'::public.stock_movement_type
    and reference_type = 'receipt'
    and metadata ? 'receipt_item_id';

alter table public.suppliers enable row level security;
alter table public.receipts enable row level security;
alter table public.receipt_items enable row level security;
alter table public.receipt_attachments enable row level security;

revoke all on public.suppliers from anon, authenticated;
revoke all on public.receipts from anon, authenticated;
revoke all on public.receipt_items from anon, authenticated;
revoke all on public.receipt_attachments from anon, authenticated;

create or replace function public.normalize_supplier()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.name := trim(new.name);
  new.phone := nullif(trim(new.phone), '');
  new.email := nullif(lower(trim(new.email)), '');
  new.address := nullif(trim(new.address), '');
  return new;
end;
$$;

create or replace function public.normalize_receipt()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.receipt_number := nullif(upper(trim(new.receipt_number)), '');
  new.supplier_name_snapshot := nullif(trim(new.supplier_name_snapshot), '');
  new.reference := nullif(trim(new.reference), '');
  new.comment := nullif(trim(new.comment), '');
  return new;
end;
$$;

create or replace function public.validate_receipt_item()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  canonical_unit public.stock_unit;
begin
  select item.unit into canonical_unit
  from public.stock_items item
  where item.id = new.stock_item_id and item.is_active;
  if canonical_unit is null then
    raise exception 'Active stock item not found' using errcode = 'P0002';
  end if;
  if new.unit is distinct from canonical_unit then
    raise exception 'Receipt item unit must match the stock item unit' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.require_draft_receipt_for_child_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  parent_receipt_id uuid := coalesce(new.receipt_id, old.receipt_id);
begin
  if tg_op = 'UPDATE' and new.receipt_id is distinct from old.receipt_id then
    raise exception 'Receipt child records cannot be moved between receipts'
      using errcode = '55000';
  end if;
  if not exists (
    select 1 from public.receipts receipt
    where receipt.id = parent_receipt_id
      and receipt.status = 'draft'::public.receipt_status
  ) then
    raise exception 'Receipt lines and attachments are immutable after draft'
      using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.protect_receipt_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft'::public.receipt_status then
      raise exception 'Confirmed or cancelled receipts cannot be deleted'
        using errcode = '55000';
    end if;
    return old;
  end if;

  if old.status <> 'draft'::public.receipt_status then
    raise exception 'Confirmed or cancelled receipts are immutable'
      using errcode = '55000';
  end if;
  if new.status not in (
    'draft'::public.receipt_status,
    'confirmed'::public.receipt_status,
    'cancelled'::public.receipt_status
  ) then
    raise exception 'Invalid receipt status transition' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists suppliers_normalize on public.suppliers;
create trigger suppliers_normalize
before insert or update of name, phone, email, address on public.suppliers
for each row execute function public.normalize_supplier();

drop trigger if exists suppliers_set_updated_at on public.suppliers;
create trigger suppliers_set_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

drop trigger if exists receipts_normalize on public.receipts;
create trigger receipts_normalize
before insert or update of receipt_number, supplier_name_snapshot, reference, comment
on public.receipts
for each row execute function public.normalize_receipt();

drop trigger if exists receipts_protect_lifecycle on public.receipts;
create trigger receipts_protect_lifecycle
before update or delete on public.receipts
for each row execute function public.protect_receipt_lifecycle();

drop trigger if exists receipts_set_updated_at on public.receipts;
create trigger receipts_set_updated_at
before update on public.receipts
for each row execute function public.set_updated_at();

drop trigger if exists receipt_items_require_draft on public.receipt_items;
create trigger receipt_items_require_draft
before insert or update or delete on public.receipt_items
for each row execute function public.require_draft_receipt_for_child_change();

drop trigger if exists receipt_items_validate on public.receipt_items;
create trigger receipt_items_validate
before insert or update of stock_item_id, unit on public.receipt_items
for each row execute function public.validate_receipt_item();

drop trigger if exists receipt_attachments_require_draft on public.receipt_attachments;
create trigger receipt_attachments_require_draft
before insert or update or delete on public.receipt_attachments
for each row execute function public.require_draft_receipt_for_child_change();

revoke all on function public.normalize_supplier() from public, anon, authenticated;
revoke all on function public.normalize_receipt() from public, anon, authenticated;
revoke all on function public.validate_receipt_item() from public, anon, authenticated;
revoke all on function public.require_draft_receipt_for_child_change() from public, anon, authenticated;
revoke all on function public.protect_receipt_lifecycle() from public, anon, authenticated;

comment on table public.receipts is
  'Inbound goods receipt. Drafts never affect stock; confirmation is RPC-only and atomic.';
comment on table public.receipt_items is
  'Receipt lines with canonical stock-unit snapshots; one line per stock item per receipt.';
comment on table public.receipt_attachments is
  'Private Storage object metadata. Image binaries remain in the facolub-receipts bucket.';
comment on column public.receipts.supplier_name_snapshot is
  'Immutable operational supplier label preserved even if the supplier master later changes.';

-- Verification query:
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('suppliers', 'receipts', 'receipt_items', 'receipt_attachments')
order by table_name;
