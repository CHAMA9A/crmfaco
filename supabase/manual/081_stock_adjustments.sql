-- SOMA / FACOLUB stock counts - 081 traceable adjustment extension
-- Depends on: 080 and the existing S1 public.stock_adjustments table.

do $$ begin
  create type public.stock_adjustment_type as enum (
    'count_difference', 'loss', 'damage', 'correction', 'other'
  );
exception when duplicate_object then null;
end $$;

alter table public.stock_adjustments
  add column if not exists stock_count_id uuid
    references public.stock_counts(id) on delete restrict,
  add column if not exists stock_count_item_id uuid
    references public.stock_count_items(id) on delete restrict,
  add column if not exists adjustment_type public.stock_adjustment_type
    not null default 'count_difference',
  add column if not exists original_movement_id uuid
    references public.stock_movements(id) on delete restrict,
  add column if not exists stock_movement_id uuid
    references public.stock_movements(id) on delete restrict,
  add column if not exists rejected_by uuid
    references public.profiles(id) on delete restrict,
  add column if not exists rejected_at timestamptz,
  add column if not exists rejection_reason text;

create unique index if not exists stock_adjustments_count_item_idx
  on public.stock_adjustments (stock_count_item_id)
  where stock_count_item_id is not null;
create unique index if not exists stock_adjustments_movement_idx
  on public.stock_adjustments (stock_movement_id)
  where stock_movement_id is not null;
create index if not exists stock_adjustments_status_type_idx
  on public.stock_adjustments (status, adjustment_type, created_at desc);
create index if not exists stock_adjustments_original_movement_idx
  on public.stock_adjustments (original_movement_id)
  where original_movement_id is not null;

create table if not exists public.stock_adjustment_attachments (
  id uuid primary key default gen_random_uuid(),
  stock_adjustment_id uuid not null
    references public.stock_adjustments(id) on delete restrict,
  storage_path text not null unique,
  file_name text not null,
  mime_type text not null,
  file_size bigint,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint stock_adjustment_attachments_path_length check (
    char_length(trim(storage_path)) between 1 and 500
  ),
  constraint stock_adjustment_attachments_name_length check (
    char_length(trim(file_name)) between 1 and 255
  ),
  constraint stock_adjustment_attachments_mime check (
    mime_type in ('image/jpeg','image/png','image/webp','application/pdf')
  ),
  constraint stock_adjustment_attachments_size check (
    file_size is null or file_size between 1 and 10485760
  )
);
create index if not exists stock_adjustment_attachments_adjustment_idx
  on public.stock_adjustment_attachments (stock_adjustment_id, created_at);

alter table public.stock_adjustment_attachments enable row level security;
revoke all on public.stock_adjustment_attachments from anon, authenticated;

create or replace function public.normalize_stock_adjustment()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.reason := trim(new.reason);
  new.rejection_reason := nullif(trim(new.rejection_reason), '');
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.protect_stock_adjustment()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Stock adjustments cannot be deleted' using errcode = '55000';
  end if;
  if old.status in ('posted','rejected') then
    raise exception 'Applied or rejected stock adjustments are immutable' using errcode = '55000';
  end if;
  if old.id is distinct from new.id
    or old.stock_item_id is distinct from new.stock_item_id
    or old.location_id is distinct from new.location_id
    or old.expected_quantity is distinct from new.expected_quantity
    or old.counted_quantity is distinct from new.counted_quantity
    or old.requested_by is distinct from new.requested_by
    or old.stock_count_id is distinct from new.stock_count_id
    or old.stock_count_item_id is distinct from new.stock_count_item_id
    or old.adjustment_type is distinct from new.adjustment_type
    or old.original_movement_id is distinct from new.original_movement_id
    or old.created_at is distinct from new.created_at then
    raise exception 'Stock adjustment request identity is immutable' using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists stock_adjustments_set_updated_at on public.stock_adjustments;
drop trigger if exists stock_adjustments_normalize on public.stock_adjustments;
create trigger stock_adjustments_normalize before insert or update on public.stock_adjustments
for each row execute function public.normalize_stock_adjustment();
drop trigger if exists stock_adjustments_protect on public.stock_adjustments;
create trigger stock_adjustments_protect before update or delete on public.stock_adjustments
for each row execute function public.protect_stock_adjustment();

revoke all on function public.normalize_stock_adjustment() from public, anon, authenticated;
revoke all on function public.protect_stock_adjustment() from public, anon, authenticated;

comment on column public.stock_adjustments.difference_quantity is
  'Authoritative signed stock effect: counted_quantity - expected_quantity.';
comment on column public.stock_adjustments.stock_movement_id is
  'Immutable ledger movement created atomically when the adjustment is posted.';
comment on type public.stock_adjustment_status is
  'S7 uses pending for review and posted for the fully approved/applied terminal state.';

select
  to_regtype('public.stock_adjustment_type') is not null as type_created,
  count(*) filter (where column_name in (
    'stock_count_id','stock_count_item_id','adjustment_type',
    'original_movement_id','stock_movement_id','rejected_by','rejected_at','rejection_reason'
  )) as columns_available
from information_schema.columns
where table_schema = 'public' and table_name = 'stock_adjustments';
