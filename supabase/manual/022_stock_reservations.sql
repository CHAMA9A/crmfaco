-- SOMA / FACOLUB stock module - 022 reservations and derived balances
-- Depends on: 020_stock_foundation.sql, 021_stock_movement_engine.sql

create table if not exists public.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  location_id uuid not null references public.stock_locations(id) on delete restrict,
  quantity numeric(20,3) not null,
  status public.stock_reservation_status not null default 'active',
  reference_type text not null,
  reference_id uuid not null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  released_at timestamptz,
  consumed_at timestamptz,
  constraint stock_reservations_quantity_positive check (quantity > 0),
  constraint stock_reservations_reference_type_length check (
    char_length(trim(reference_type)) between 1 and 80
  ),
  constraint stock_reservations_lifecycle check (
    (status = 'active' and released_at is null and consumed_at is null)
    or (status in ('released', 'cancelled') and released_at is not null and consumed_at is null)
    or (status = 'consumed' and consumed_at is not null and released_at is null)
  )
);

create unique index if not exists stock_reservations_one_active_reference_idx
  on public.stock_reservations (stock_item_id, location_id, reference_type, reference_id)
  where status = 'active';
create index if not exists stock_reservations_active_balance_idx
  on public.stock_reservations (stock_item_id, location_id)
  where status = 'active';
create index if not exists stock_reservations_history_idx
  on public.stock_reservations (created_at desc, id desc);

alter table public.stock_reservations enable row level security;
revoke all on public.stock_reservations from anon, authenticated;

create or replace function public.protect_stock_reservation_identity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.stock_item_id is distinct from old.stock_item_id
    or new.location_id is distinct from old.location_id
    or new.quantity is distinct from old.quantity
    or new.reference_type is distinct from old.reference_type
    or new.reference_id is distinct from old.reference_id
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'Reservation identity and quantity are immutable; release and recreate it'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists stock_reservations_protect_identity on public.stock_reservations;
create trigger stock_reservations_protect_identity
before update on public.stock_reservations
for each row execute function public.protect_stock_reservation_identity();

revoke all on function public.protect_stock_reservation_identity() from public, anon, authenticated;

create or replace view public.stock_balances
with (security_invoker = true)
as
with physical as (
  select
    movement.stock_item_id,
    movement.location_id,
    sum(case movement.direction when 'in' then movement.quantity else -movement.quantity end)
      as physical_quantity
  from public.stock_movements movement
  group by movement.stock_item_id, movement.location_id
), reserved as (
  select
    reservation.stock_item_id,
    reservation.location_id,
    sum(reservation.quantity) as reserved_quantity
  from public.stock_reservations reservation
  where reservation.status = 'active'
  group by reservation.stock_item_id, reservation.location_id
)
select
  item.id as stock_item_id,
  location.id as location_id,
  coalesce(physical.physical_quantity, 0)::numeric(20,3) as physical_quantity,
  coalesce(reserved.reserved_quantity, 0)::numeric(20,3) as reserved_quantity,
  (coalesce(physical.physical_quantity, 0) - coalesce(reserved.reserved_quantity, 0))::numeric(20,3)
    as available_quantity
from public.stock_items item
cross join public.stock_locations location
left join physical
  on physical.stock_item_id = item.id and physical.location_id = location.id
left join reserved
  on reserved.stock_item_id = item.id and reserved.location_id = location.id;

comment on table public.stock_reservations is
  'Non-physical allocation ledger. Only active rows contribute to reserved stock.';
comment on view public.stock_balances is
  'Authoritative derived quantities: available = physical movement sum - active reservations.';

revoke all on public.stock_balances from anon, authenticated;

-- Verification query:
select stock_item_id, location_id, physical_quantity, reserved_quantity, available_quantity
from public.stock_balances
order by stock_item_id, location_id
limit 20;
