-- SOMA / FACOLUB production planning module - 050 foundation
-- Depends on: Stock S1 020-024 and Prepared Bottles S3 040-043.
-- Additive only: normalized product/format catalog and production plan drafts.

do $$
begin
  if to_regclass('public.stock_items') is null
    or to_regclass('public.stock_movements') is null
    or to_regclass('public.stock_reservations') is null
    or to_regclass('public.bottle_preparations') is null
    or to_regprocedure('public.assert_stock_actor(public.app_role[])') is null
    or to_regprocedure('public.stock_quantities(uuid,uuid)') is null then
    raise exception 'FACOLUB Stock S1 and Prepared Bottles S3 are required before Planning S4.';
  end if;
end
$$;

do $$ begin
  create type public.production_plan_status as enum ('draft', 'planned', 'validated', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.planning_quantity_mode as enum ('bottles', 'cartons');
exception when duplicate_object then null;
end $$;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_code_format check (
    code is null or (code = upper(trim(code)) and code ~ '^[A-Z0-9._-]{1,60}$')
  ),
  constraint products_name_length check (char_length(trim(name)) between 1 and 120)
);

create table if not exists public.packaging_formats (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  volume_liters numeric(12,3) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint packaging_formats_code_format check (
    code = upper(trim(code)) and code ~ '^[A-Z0-9._-]{1,30}$'
  ),
  constraint packaging_formats_name_length check (char_length(trim(name)) between 1 and 80),
  constraint packaging_formats_volume_positive check (volume_liters > 0)
);

create table if not exists public.product_formats (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  format_id uuid not null references public.packaging_formats(id) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_formats_one_combination unique (product_id, format_id)
);

-- S1 deliberately reserved stock_items.product_format_id without binding it.
-- Link all new values now while leaving any legacy non-null rows to be audited
-- separately instead of making this additive migration fail.
do $$
begin
  if not exists (select 1 from pg_constraint
    where conname = 'stock_items_product_format_fk'
      and conrelid = 'public.stock_items'::regclass) then
    alter table public.stock_items
      add constraint stock_items_product_format_fk
      foreign key (product_format_id) references public.product_formats(id)
      on delete restrict not valid;
  end if;
end
$$;

create table if not exists public.production_plans (
  id uuid primary key default gen_random_uuid(),
  plan_number text unique,
  production_date date not null,
  location_id uuid not null references public.stock_locations(id) on delete restrict,
  status public.production_plan_status not null default 'draft',
  priority integer,
  assigned_to uuid references public.profiles(id) on delete restrict,
  comment text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  validated_by uuid references public.profiles(id) on delete restrict,
  validated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint production_plans_number_format check (
    plan_number is null or plan_number ~ '^PLAN-[0-9]{6}-[0-9]{2,}$'
  ),
  constraint production_plans_priority_range check (priority is null or priority between 1 and 5),
  constraint production_plans_comment_length check (
    comment is null or char_length(trim(comment)) between 1 and 2000
  ),
  constraint production_plans_lifecycle_consistent check (
    (status = 'draft' and plan_number is null and validated_by is null and validated_at is null)
    or (status = 'planned' and plan_number is not null and validated_by is null and validated_at is null)
    or (status = 'validated' and plan_number is not null and validated_by is not null
        and validated_at is not null)
    or (status = 'cancelled')
  )
);

create table if not exists public.production_plan_items (
  id uuid primary key default gen_random_uuid(),
  production_plan_id uuid not null references public.production_plans(id) on delete cascade,
  product_format_id uuid not null references public.product_formats(id) on delete restrict,
  recipe_id uuid,
  quantity_mode public.planning_quantity_mode not null,
  entered_quantity numeric(20,3) not null,
  planned_bottles numeric(20,3) not null,
  planned_cartons numeric(20,3),
  bottles_per_carton integer,
  product_name_snapshot text not null,
  format_name_snapshot text not null,
  output_stock_item_id uuid references public.stock_items(id) on delete restrict,
  output_item_name_snapshot text,
  position integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint production_plan_items_quantities_positive check (
    entered_quantity > 0 and planned_bottles > 0
    and (planned_cartons is null or planned_cartons > 0)
  ),
  constraint production_plan_items_whole_bottles check (mod(planned_bottles, 1) = 0),
  constraint production_plan_items_whole_cartons check (
    planned_cartons is null or mod(planned_cartons, 1) = 0
  ),
  constraint production_plan_items_capacity_positive check (
    bottles_per_carton is null or bottles_per_carton > 0
  ),
  constraint production_plan_items_position_positive check (position > 0),
  constraint production_plan_items_one_product_format unique (production_plan_id, product_format_id),
  constraint production_plan_items_one_position unique (production_plan_id, position),
  constraint production_plan_items_mode_consistent check (
    (quantity_mode = 'bottles' and entered_quantity = planned_bottles)
    or (quantity_mode = 'cartons' and entered_quantity = planned_cartons
        and planned_cartons is not null and bottles_per_carton is not null
        and planned_bottles = planned_cartons * bottles_per_carton)
  )
);

create table if not exists public.production_plan_number_sequences (
  plan_date date primary key,
  last_value bigint not null,
  constraint production_plan_number_sequences_positive check (last_value > 0)
);

create index if not exists products_active_name_idx on public.products (name) where is_active;
create index if not exists packaging_formats_active_idx
  on public.packaging_formats (volume_liters, name) where is_active;
create index if not exists product_formats_active_idx
  on public.product_formats (product_id, format_id) where is_active;
create index if not exists production_plans_date_status_idx
  on public.production_plans (production_date, status, priority, created_at);
create index if not exists production_plans_assigned_idx
  on public.production_plans (assigned_to, production_date) where assigned_to is not null;
create index if not exists production_plans_creator_idx
  on public.production_plans (created_by, created_at desc);
create index if not exists production_plan_items_product_format_idx
  on public.production_plan_items (product_format_id, production_plan_id);

alter table public.products enable row level security;
alter table public.packaging_formats enable row level security;
alter table public.product_formats enable row level security;
alter table public.production_plans enable row level security;
alter table public.production_plan_items enable row level security;
alter table public.production_plan_number_sequences enable row level security;
revoke all on public.products from anon, authenticated;
revoke all on public.packaging_formats from anon, authenticated;
revoke all on public.product_formats from anon, authenticated;
revoke all on public.production_plans from anon, authenticated;
revoke all on public.production_plan_items from anon, authenticated;
revoke all on public.production_plan_number_sequences from anon, authenticated;

create or replace function public.normalize_planning_catalog()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_table_name = 'products' then
    new.code := nullif(upper(trim(new.code)), '');
    new.name := trim(new.name);
  elsif tg_table_name = 'packaging_formats' then
    new.code := upper(trim(new.code));
    new.name := trim(new.name);
  end if;
  return new;
end;
$$;

create or replace function public.normalize_production_plan()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.plan_number := nullif(upper(trim(new.plan_number)), '');
  new.comment := nullif(trim(new.comment), '');
  return new;
end;
$$;

create or replace function public.protect_production_plan_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
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
    raise exception 'Validated production plans are immutable' using errcode = '55000';
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

create or replace function public.require_draft_plan_for_item_change()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare parent_id uuid := coalesce(new.production_plan_id, old.production_plan_id);
begin
  if tg_op = 'UPDATE' and new.production_plan_id is distinct from old.production_plan_id then
    raise exception 'Production plan items cannot be moved between plans' using errcode = '55000';
  end if;
  if not exists (select 1 from public.production_plans plan
    where plan.id = parent_id and plan.status = 'draft'::public.production_plan_status) then
    raise exception 'Production plan items are editable only while the plan is draft'
      using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists products_normalize on public.products;
create trigger products_normalize before insert or update of code, name on public.products
for each row execute function public.normalize_planning_catalog();
drop trigger if exists products_updated_at on public.products;
create trigger products_updated_at before update on public.products
for each row execute function public.set_updated_at();
drop trigger if exists packaging_formats_normalize on public.packaging_formats;
create trigger packaging_formats_normalize before insert or update of code, name
on public.packaging_formats for each row execute function public.normalize_planning_catalog();
drop trigger if exists packaging_formats_updated_at on public.packaging_formats;
create trigger packaging_formats_updated_at before update on public.packaging_formats
for each row execute function public.set_updated_at();
drop trigger if exists product_formats_updated_at on public.product_formats;
create trigger product_formats_updated_at before update on public.product_formats
for each row execute function public.set_updated_at();
drop trigger if exists production_plans_normalize on public.production_plans;
create trigger production_plans_normalize before insert or update of plan_number, comment
on public.production_plans for each row execute function public.normalize_production_plan();
drop trigger if exists production_plans_protect_lifecycle on public.production_plans;
create trigger production_plans_protect_lifecycle before update or delete on public.production_plans
for each row execute function public.protect_production_plan_lifecycle();
drop trigger if exists production_plans_updated_at on public.production_plans;
create trigger production_plans_updated_at before update on public.production_plans
for each row execute function public.set_updated_at();
drop trigger if exists production_plan_items_require_draft on public.production_plan_items;
create trigger production_plan_items_require_draft before insert or update or delete
on public.production_plan_items for each row execute function public.require_draft_plan_for_item_change();
drop trigger if exists production_plan_items_updated_at on public.production_plan_items;
create trigger production_plan_items_updated_at before update on public.production_plan_items
for each row execute function public.set_updated_at();

revoke all on function public.normalize_planning_catalog() from public, anon, authenticated;
revoke all on function public.normalize_production_plan() from public, anon, authenticated;
revoke all on function public.protect_production_plan_lifecycle() from public, anon, authenticated;
revoke all on function public.require_draft_plan_for_item_change() from public, anon, authenticated;

-- Configurable format references from the approved SOMA capacities. No product
-- or stock item is fabricated by this migration.
insert into public.packaging_formats (code, name, volume_liters, is_active) values
  ('1L', '1L', 1, true), ('2L', '2L', 2, true), ('5L', '5L', 5, true)
on conflict (code) do nothing;

comment on table public.production_plans is
  'S4 planning only. Draft/planned/validated rows never create reservations or stock movements.';
comment on table public.production_plan_items is
  'Multi-line plan architecture with server-normalized canonical bottle quantities.';
comment on table public.product_formats is
  'Normalized product and packaging-format combinations introduced because no authoritative catalog existed.';

-- Verification query:
select table_name from information_schema.tables
where table_schema = 'public' and table_name in (
  'products', 'packaging_formats', 'product_formats',
  'production_plans', 'production_plan_items', 'production_plan_number_sequences'
) order by table_name;
