-- SOMA / FACOLUB production module - 060 reservation foundation
-- Depends on: 020-024, 050-054, and 056.
-- Adds reservation lifecycle metadata without moving physical stock.

do $$
begin
  if to_regtype('public.production_reservation_status') is null then
    create type public.production_reservation_status as enum (
      'not_reserved', 'reserved', 'released'
    );
  end if;
end
$$;

alter table public.production_plans
  add column if not exists reservation_status public.production_reservation_status
    not null default 'not_reserved',
  add column if not exists reserved_by uuid references public.profiles(id) on delete restrict,
  add column if not exists reserved_at timestamptz,
  add column if not exists released_by uuid references public.profiles(id) on delete restrict,
  add column if not exists released_at timestamptz;

alter table public.stock_reservations
  add column if not exists production_plan_requirement_id uuid
    references public.production_plan_requirements(id) on delete restrict;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'production_plans_reservation_lifecycle_consistent'
      and conrelid = 'public.production_plans'::regclass
  ) then
    alter table public.production_plans
      add constraint production_plans_reservation_lifecycle_consistent check (
        (reservation_status = 'not_reserved'
          and reserved_by is null and reserved_at is null
          and released_by is null and released_at is null)
        or (reservation_status = 'reserved'
          and reserved_by is not null and reserved_at is not null
          and released_by is null and released_at is null)
        or (reservation_status = 'released'
          and reserved_by is not null and reserved_at is not null
          and released_by is not null and released_at is not null)
      );
  end if;
end
$$;

-- Generic references retain their historical one-active-row guarantee. A
-- production plan may have several requirements for the same stock item, so
-- S5 gives each requirement its own active reservation identity.
drop index if exists public.stock_reservations_one_active_reference_idx;
create unique index if not exists stock_reservations_one_active_reference_idx
  on public.stock_reservations (stock_item_id, location_id, reference_type, reference_id)
  where status = 'active' and production_plan_requirement_id is null;

create unique index if not exists stock_reservations_one_active_plan_requirement_idx
  on public.stock_reservations (production_plan_requirement_id)
  where status = 'active' and production_plan_requirement_id is not null;

create index if not exists stock_reservations_plan_history_idx
  on public.stock_reservations (reference_id, created_at desc, id desc)
  where reference_type = 'production_plan';

create index if not exists production_plans_reservation_status_idx
  on public.production_plans (reservation_status, production_date, created_at);

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
    or new.production_plan_requirement_id is distinct from old.production_plan_requirement_id
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'Reservation identity and quantity are immutable; release and recreate it'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

-- Validated plan business data remains immutable. Only the controlled S5
-- reservation lifecycle may change while the plan stays validated.
create or replace function public.protect_production_plan_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  old_core jsonb;
  new_core jsonb;
  reservation_transition_allowed boolean := false;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft'::public.production_plan_status then
      raise exception 'Only draft production plans can be deleted' using errcode = '55000';
    end if;
    return old;
  end if;

  if old.status = 'cancelled'::public.production_plan_status then
    raise exception 'Cancelled production plans are immutable' using errcode = '55000';
  end if;

  if old.status = 'validated'::public.production_plan_status
    and new.status <> 'cancelled'::public.production_plan_status then
    old_core := to_jsonb(old) - array[
      'reservation_status', 'reserved_by', 'reserved_at',
      'released_by', 'released_at', 'updated_at'
    ];
    new_core := to_jsonb(new) - array[
      'reservation_status', 'reserved_by', 'reserved_at',
      'released_by', 'released_at', 'updated_at'
    ];
    reservation_transition_allowed := old_core = new_core and (
      new.reservation_status = old.reservation_status
      or (old.reservation_status in ('not_reserved', 'released')
          and new.reservation_status = 'reserved')
      or (old.reservation_status = 'reserved'
          and new.reservation_status = 'released')
    );
    if not reservation_transition_allowed then
      raise exception 'Validated production plans are immutable outside reservation lifecycle'
        using errcode = '55000';
    end if;
  end if;

  if old.status = 'planned'::public.production_plan_status
    and new.status not in ('planned'::public.production_plan_status,
                           'validated'::public.production_plan_status,
                           'cancelled'::public.production_plan_status) then
    raise exception 'A planned production plan cannot return to draft' using errcode = '55000';
  end if;
  return new;
end;
$$;

comment on column public.stock_reservations.production_plan_requirement_id is
  'S5 snapshot requirement represented by this reservation; null for non-production reservations.';
comment on column public.production_plans.reservation_status is
  'Operational S5 state. Reservations allocate available stock but never move physical stock.';

revoke all on function public.protect_stock_reservation_identity() from public, anon, authenticated;
revoke all on function public.protect_production_plan_lifecycle() from public, anon, authenticated;

-- Verification query: five plan columns, one reservation link, and both
-- active uniqueness indexes must be present.
select
  (select count(*) from information_schema.columns
   where table_schema = 'public' and table_name = 'production_plans'
     and column_name in ('reservation_status','reserved_by','reserved_at','released_by','released_at'))
    as plan_columns,
  (select count(*) from information_schema.columns
   where table_schema = 'public' and table_name = 'stock_reservations'
     and column_name = 'production_plan_requirement_id') as reservation_columns,
  (select count(*) from pg_indexes
   where schemaname = 'public' and indexname in (
     'stock_reservations_one_active_reference_idx',
     'stock_reservations_one_active_plan_requirement_idx'
   )) as active_uniqueness_indexes;
