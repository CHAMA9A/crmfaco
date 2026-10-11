-- SOMA / FACOLUB production execution - 070 foundation
-- Depends on: 020-024, 050-054, 056, and 060-062.
-- Additive only: no plan, reservation, movement, or history row is rewritten.

do $$ begin
  create type public.production_execution_status as enum (
    'to_do', 'in_progress', 'done', 'blocked', 'cancelled'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.production_issue_category as enum (
    'missing_stock', 'damaged_material', 'machine_issue', 'wrong_quantity', 'other'
  );
exception when duplicate_object then null;
end $$;

-- S6 resolves a reserved plan through consumption. This value is added in its
-- own staged file so later files may safely use it after 070 commits.
alter type public.production_reservation_status add value if not exists 'consumed';

alter table public.production_plans
  add column if not exists consumed_by uuid references public.profiles(id) on delete restrict,
  add column if not exists consumed_at timestamptz;

create table if not exists public.production_executions (
  id uuid primary key default gen_random_uuid(),
  execution_number text not null unique,
  production_plan_id uuid not null unique
    references public.production_plans(id) on delete restrict,
  status public.production_execution_status not null default 'to_do',
  comment text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  started_by uuid references public.profiles(id) on delete restrict,
  started_at timestamptz,
  completed_by uuid references public.profiles(id) on delete restrict,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint production_executions_number_format check (
    execution_number ~ '^PROD-[0-9]{6}-[0-9]{2,}$'
  ),
  constraint production_executions_comment_length check (
    comment is null or char_length(trim(comment)) between 1 and 2000
  ),
  constraint production_executions_lifecycle_consistent check (
    (status = 'to_do' and started_by is null and started_at is null
      and completed_by is null and completed_at is null)
    or (status in ('in_progress', 'blocked')
      and started_by is not null and started_at is not null
      and completed_by is null and completed_at is null)
    or (status = 'done' and started_by is not null and started_at is not null
      and completed_by is not null and completed_at is not null)
    or (status = 'cancelled' and completed_by is null and completed_at is null)
  )
);

create table if not exists public.production_execution_items (
  id uuid primary key default gen_random_uuid(),
  production_execution_id uuid not null
    references public.production_executions(id) on delete restrict,
  production_plan_item_id uuid not null unique
    references public.production_plan_items(id) on delete restrict,
  planned_bottles numeric(20,3) not null,
  planned_cartons numeric(20,3),
  bottles_per_carton integer,
  actual_bottles numeric(20,3),
  actual_cartons numeric(20,3),
  output_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  output_movement_id uuid unique references public.stock_movements(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint production_execution_items_one_per_execution
    unique (production_execution_id, production_plan_item_id),
  constraint production_execution_items_planned_positive check (
    planned_bottles > 0 and (planned_cartons is null or planned_cartons > 0)
  ),
  constraint production_execution_items_actual_valid check (
    (actual_bottles is null and actual_cartons is null and output_movement_id is null)
    or (actual_bottles > 0 and actual_bottles <= planned_bottles
      and actual_cartons is not null and actual_cartons > 0)
  )
);

create table if not exists public.production_issues (
  id uuid primary key default gen_random_uuid(),
  production_execution_id uuid not null
    references public.production_executions(id) on delete restrict,
  category public.production_issue_category not null,
  description text not null,
  reported_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete restrict,
  resolution_note text,
  constraint production_issues_description_length check (
    char_length(trim(description)) between 1 and 2000
  ),
  constraint production_issues_resolution_consistent check (
    (resolved_at is null and resolved_by is null and resolution_note is null)
    or (resolved_at is not null and resolved_by is not null)
  )
);

-- The immutable S5 reservation remains the original allocation. One S6 row
-- records its complete resolution without destroying that history.
create table if not exists public.production_reservation_resolutions (
  id uuid primary key default gen_random_uuid(),
  production_execution_item_id uuid not null
    references public.production_execution_items(id) on delete restrict,
  production_plan_requirement_id uuid not null unique
    references public.production_plan_requirements(id) on delete restrict,
  stock_reservation_id uuid not null unique
    references public.stock_reservations(id) on delete restrict,
  stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  original_quantity numeric(20,3) not null,
  consumed_quantity numeric(20,3) not null,
  released_quantity numeric(20,3) not null,
  consumption_movement_id uuid not null unique
    references public.stock_movements(id) on delete restrict,
  resolved_by uuid not null references public.profiles(id) on delete restrict,
  resolved_at timestamptz not null default now(),
  constraint production_reservation_resolutions_quantities check (
    original_quantity > 0 and consumed_quantity > 0 and released_quantity >= 0
    and original_quantity = consumed_quantity + released_quantity
  )
);

create unique index if not exists production_issues_one_unresolved_idx
  on public.production_issues (production_execution_id) where resolved_at is null;
create index if not exists production_executions_status_date_idx
  on public.production_executions (status, created_at desc);
create index if not exists production_execution_items_execution_idx
  on public.production_execution_items (production_execution_id, created_at);
create index if not exists production_reservation_resolutions_execution_idx
  on public.production_reservation_resolutions (production_execution_item_id, resolved_at);

alter table public.production_executions enable row level security;
alter table public.production_execution_items enable row level security;
alter table public.production_issues enable row level security;
alter table public.production_reservation_resolutions enable row level security;
revoke all on public.production_executions from anon, authenticated;
revoke all on public.production_execution_items from anon, authenticated;
revoke all on public.production_issues from anon, authenticated;
revoke all on public.production_reservation_resolutions from anon, authenticated;

create or replace function public.normalize_production_execution()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.comment := nullif(trim(new.comment), '');
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists production_executions_normalize on public.production_executions;
create trigger production_executions_normalize
before insert or update on public.production_executions
for each row execute function public.normalize_production_execution();

create or replace function public.protect_production_execution_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Production executions cannot be deleted' using errcode = '55000';
  end if;
  if old.status in ('done', 'cancelled') then
    raise exception 'Completed or cancelled production executions are immutable'
      using errcode = '55000';
  end if;
  if old.production_plan_id is distinct from new.production_plan_id
    or old.execution_number is distinct from new.execution_number
    or old.created_by is distinct from new.created_by
    or old.created_at is distinct from new.created_at then
    raise exception 'Production execution identity is immutable' using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists production_executions_protect on public.production_executions;
create trigger production_executions_protect
before update or delete on public.production_executions
for each row execute function public.protect_production_execution_lifecycle();

create or replace function public.protect_production_execution_item()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare execution_status public.production_execution_status;
begin
  if tg_op = 'DELETE' then
    raise exception 'Production execution items cannot be deleted' using errcode = '55000';
  end if;
  select execution.status into execution_status
  from public.production_executions execution
  where execution.id = new.production_execution_id;
  if execution_status in ('done','cancelled') then
    raise exception 'Completed production execution items are immutable' using errcode = '55000';
  end if;
  if old.production_execution_id is distinct from new.production_execution_id
    or old.production_plan_item_id is distinct from new.production_plan_item_id
    or old.planned_bottles is distinct from new.planned_bottles
    or old.planned_cartons is distinct from new.planned_cartons
    or old.bottles_per_carton is distinct from new.bottles_per_carton
    or old.output_stock_item_id is distinct from new.output_stock_item_id
    or old.created_at is distinct from new.created_at then
    raise exception 'Production execution item snapshot is immutable' using errcode = '55000';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists production_execution_items_protect
  on public.production_execution_items;
create trigger production_execution_items_protect
before update or delete on public.production_execution_items
for each row execute function public.protect_production_execution_item();

create or replace function public.reject_production_resolution_mutation()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  raise exception 'Production reservation resolutions are immutable' using errcode = '55000';
end;
$$;

drop trigger if exists production_reservation_resolutions_immutable
  on public.production_reservation_resolutions;
create trigger production_reservation_resolutions_immutable
before update or delete on public.production_reservation_resolutions
for each row execute function public.reject_production_resolution_mutation();

revoke all on function public.normalize_production_execution() from public, anon, authenticated;
revoke all on function public.protect_production_execution_lifecycle()
  from public, anon, authenticated;
revoke all on function public.protect_production_execution_item()
  from public, anon, authenticated;
revoke all on function public.reject_production_resolution_mutation()
  from public, anon, authenticated;

-- Verification query: 4 tables, 2 new enums, 2 plan consumption columns.
select
  (select count(*) from information_schema.tables where table_schema = 'public'
    and table_name in ('production_executions','production_execution_items',
      'production_issues','production_reservation_resolutions')) as tables_created,
  (select count(*) from pg_type where typnamespace = 'public'::regnamespace
    and typname in ('production_execution_status','production_issue_category')) as enums_created,
  (select count(*) from information_schema.columns where table_schema = 'public'
    and table_name = 'production_plans'
    and column_name in ('consumed_by','consumed_at')) as plan_columns;
