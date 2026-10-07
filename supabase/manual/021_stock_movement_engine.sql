-- SOMA / FACOLUB stock module - 021 immutable movement ledger
-- Depends on: 020_stock_foundation.sql

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  location_id uuid not null references public.stock_locations(id) on delete restrict,
  movement_type public.stock_movement_type not null,
  quantity numeric(20,3) not null,
  direction public.stock_direction not null,
  reference_type text,
  reference_id uuid,
  reason text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  corrected_movement_id uuid references public.stock_movements(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  constraint stock_movements_quantity_positive check (quantity > 0),
  constraint stock_movements_reference_type_length check (
    reference_type is null or char_length(trim(reference_type)) between 1 and 80
  ),
  constraint stock_movements_reason_length check (
    reason is null or char_length(trim(reason)) between 1 and 1000
  ),
  constraint stock_movements_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint stock_movements_correction_link check (
    (movement_type = 'correction' and corrected_movement_id is not null)
    or (movement_type <> 'correction' and corrected_movement_id is null)
  ),
  constraint stock_movements_not_self_correction check (corrected_movement_id is distinct from id)
);

create index if not exists stock_movements_balance_idx
  on public.stock_movements (stock_item_id, location_id, created_at, id);
create index if not exists stock_movements_history_idx
  on public.stock_movements (created_at desc, id desc);
create index if not exists stock_movements_type_idx
  on public.stock_movements (movement_type, created_at desc);
create index if not exists stock_movements_creator_idx
  on public.stock_movements (created_by, created_at desc);
create index if not exists stock_movements_reference_idx
  on public.stock_movements (reference_type, reference_id)
  where reference_id is not null;
create index if not exists stock_movements_correction_idx
  on public.stock_movements (corrected_movement_id)
  where corrected_movement_id is not null;

alter table public.stock_movements enable row level security;
revoke all on public.stock_movements from anon, authenticated;

create or replace function public.reject_stock_movement_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'Confirmed stock movements are immutable; record a correction movement instead'
    using errcode = '55000';
end;
$$;

drop trigger if exists stock_movements_immutable on public.stock_movements;
create trigger stock_movements_immutable
before update or delete on public.stock_movements
for each row execute function public.reject_stock_movement_mutation();

revoke all on function public.reject_stock_movement_mutation() from public, anon, authenticated;

comment on table public.stock_movements is
  'Append-only physical stock ledger. IN adds quantity; OUT subtracts quantity.';
comment on column public.stock_movements.quantity is
  'Always positive; direction is the single canonical sign source.';
comment on column public.stock_movements.corrected_movement_id is
  'Correction audit link. The original movement is never changed or removed.';

-- Verification query:
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'stock_movements'
order by ordinal_position;
