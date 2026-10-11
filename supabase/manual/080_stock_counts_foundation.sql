-- SOMA / FACOLUB stock counts - 080 foundation
-- Depends on: 020-024. Additive only; no stock balance or history is rewritten.

do $$ begin
  create type public.stock_count_status as enum (
    'draft', 'submitted', 'approved', 'rejected', 'cancelled'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.stock_counts (
  id uuid primary key default gen_random_uuid(),
  count_number text unique,
  location_id uuid not null references public.stock_locations(id) on delete restrict,
  count_date date not null default current_date,
  status public.stock_count_status not null default 'draft',
  comment text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  submitted_by uuid references public.profiles(id) on delete restrict,
  submitted_at timestamptz,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  rejected_by uuid references public.profiles(id) on delete restrict,
  rejected_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_counts_number_format check (
    count_number is null or count_number ~ '^CNT-[0-9]{6}-[0-9]{2,}$'
  ),
  constraint stock_counts_comment_length check (
    comment is null or char_length(trim(comment)) between 1 and 2000
  ),
  constraint stock_counts_rejection_length check (
    rejection_reason is null or char_length(trim(rejection_reason)) between 1 and 2000
  ),
  constraint stock_counts_lifecycle_consistent check (
    (status = 'draft' and count_number is null and submitted_by is null and submitted_at is null
      and approved_by is null and approved_at is null and rejected_by is null and rejected_at is null)
    or (status = 'submitted' and count_number is not null and submitted_by is not null
      and submitted_at is not null and approved_by is null and approved_at is null
      and rejected_by is null and rejected_at is null)
    or (status = 'approved' and count_number is not null and submitted_by is not null
      and submitted_at is not null and approved_by is not null and approved_at is not null
      and rejected_by is null and rejected_at is null)
    or (status = 'rejected' and count_number is not null and submitted_by is not null
      and submitted_at is not null and approved_by is null and approved_at is null
      and rejected_by is not null and rejected_at is not null and rejection_reason is not null)
    or (status = 'cancelled' and approved_by is null and approved_at is null)
  )
);

create table if not exists public.stock_count_items (
  id uuid primary key default gen_random_uuid(),
  stock_count_id uuid not null references public.stock_counts(id) on delete restrict,
  stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  location_id uuid not null references public.stock_locations(id) on delete restrict,
  expected_physical_quantity numeric(20,3) not null,
  counted_quantity numeric(20,3),
  difference_quantity numeric(20,3)
    generated always as (counted_quantity - expected_physical_quantity) stored,
  snapshot_at timestamptz not null,
  snapshot_movement_count bigint not null check (snapshot_movement_count >= 0),
  comment text,
  position integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_count_items_one_item unique (stock_count_id, stock_item_id, location_id),
  constraint stock_count_items_expected_nonnegative check (expected_physical_quantity >= 0),
  constraint stock_count_items_counted_nonnegative check (
    counted_quantity is null or counted_quantity >= 0
  ),
  constraint stock_count_items_position_positive check (position > 0),
  constraint stock_count_items_comment_length check (
    comment is null or char_length(trim(comment)) between 1 and 2000
  )
);

create table if not exists public.stock_count_number_sequences (
  count_date date primary key,
  last_value integer not null check (last_value > 0)
);

create table if not exists public.stock_count_attachments (
  id uuid primary key default gen_random_uuid(),
  stock_count_id uuid not null references public.stock_counts(id) on delete restrict,
  stock_count_item_id uuid references public.stock_count_items(id) on delete restrict,
  storage_path text not null unique,
  file_name text not null,
  mime_type text not null,
  file_size bigint,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint stock_count_attachments_path_length check (
    char_length(trim(storage_path)) between 1 and 500
  ),
  constraint stock_count_attachments_name_length check (
    char_length(trim(file_name)) between 1 and 255
  ),
  constraint stock_count_attachments_mime check (
    mime_type in ('image/jpeg','image/png','image/webp','application/pdf')
  ),
  constraint stock_count_attachments_size check (
    file_size is null or file_size between 1 and 10485760
  )
);

create index if not exists stock_counts_date_status_idx
  on public.stock_counts (count_date desc, status, created_at desc);
create index if not exists stock_counts_creator_idx
  on public.stock_counts (created_by, created_at desc);
create index if not exists stock_count_items_count_idx
  on public.stock_count_items (stock_count_id, position, id);
create index if not exists stock_count_items_resource_idx
  on public.stock_count_items (stock_item_id, location_id, snapshot_at);
create index if not exists stock_count_attachments_count_idx
  on public.stock_count_attachments (stock_count_id, created_at);

alter table public.stock_counts enable row level security;
alter table public.stock_count_items enable row level security;
alter table public.stock_count_number_sequences enable row level security;
alter table public.stock_count_attachments enable row level security;
revoke all on public.stock_counts from anon, authenticated;
revoke all on public.stock_count_items from anon, authenticated;
revoke all on public.stock_count_number_sequences from anon, authenticated;
revoke all on public.stock_count_attachments from anon, authenticated;

create or replace function public.normalize_stock_count()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.comment := nullif(trim(new.comment), '');
  new.rejection_reason := nullif(trim(new.rejection_reason), '');
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.normalize_stock_count_item()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.comment := nullif(trim(new.comment), '');
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.protect_stock_count_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Stock counts cannot be deleted' using errcode = '55000';
  end if;
  if old.status in ('approved','rejected','cancelled') then
    raise exception 'Final stock counts are immutable' using errcode = '55000';
  end if;
  if old.id is distinct from new.id or old.location_id is distinct from new.location_id
    or old.count_date is distinct from new.count_date or old.created_by is distinct from new.created_by
    or old.created_at is distinct from new.created_at then
    raise exception 'Stock count identity is immutable' using errcode = '55000';
  end if;
  return new;
end;
$$;

create or replace function public.protect_stock_count_item()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare parent_status public.stock_count_status;
begin
  if tg_op = 'DELETE' then
    raise exception 'Stock count items cannot be deleted' using errcode = '55000';
  end if;
  select count.status into parent_status from public.stock_counts count
  where count.id = new.stock_count_id;
  if parent_status <> 'draft' then
    raise exception 'Only draft stock count items can be changed' using errcode = '55000';
  end if;
  if old.stock_count_id is distinct from new.stock_count_id
    or old.stock_item_id is distinct from new.stock_item_id
    or old.location_id is distinct from new.location_id
    or old.expected_physical_quantity is distinct from new.expected_physical_quantity
    or old.snapshot_at is distinct from new.snapshot_at
    or old.snapshot_movement_count is distinct from new.snapshot_movement_count
    or old.created_at is distinct from new.created_at then
    raise exception 'Stock count snapshot identity is immutable' using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists stock_counts_normalize on public.stock_counts;
create trigger stock_counts_normalize before insert or update on public.stock_counts
for each row execute function public.normalize_stock_count();
drop trigger if exists stock_counts_protect on public.stock_counts;
create trigger stock_counts_protect before update or delete on public.stock_counts
for each row execute function public.protect_stock_count_lifecycle();
drop trigger if exists stock_count_items_normalize on public.stock_count_items;
create trigger stock_count_items_normalize before insert or update on public.stock_count_items
for each row execute function public.normalize_stock_count_item();
drop trigger if exists stock_count_items_protect on public.stock_count_items;
create trigger stock_count_items_protect before update or delete on public.stock_count_items
for each row execute function public.protect_stock_count_item();

revoke all on function public.normalize_stock_count() from public, anon, authenticated;
revoke all on function public.normalize_stock_count_item() from public, anon, authenticated;
revoke all on function public.protect_stock_count_lifecycle() from public, anon, authenticated;
revoke all on function public.protect_stock_count_item() from public, anon, authenticated;

select
  to_regclass('public.stock_counts') is not null as stock_counts_created,
  to_regclass('public.stock_count_items') is not null as stock_count_items_created,
  to_regtype('public.stock_count_status') is not null as status_created;
