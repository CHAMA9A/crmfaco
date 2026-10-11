-- SOMA / FACOLUB prepared bottles module - 040 foundation
-- Depends on: 020-024 and 030-033.
-- Additive only: versioned recipes, preparation drafts, and historical snapshots.

do $$
begin
  if to_regclass('public.stock_items') is null
    or to_regclass('public.stock_movements') is null
    or to_regclass('public.stock_reservations') is null
    or to_regprocedure('public.assert_stock_actor(public.app_role[])') is null
    or to_regprocedure('public.lock_stock_balance(uuid,uuid)') is null
    or to_regprocedure('public.stock_quantities(uuid,uuid)') is null then
    raise exception 'FACOLUB Stock S1/S2 is missing. Run 020-033 before Prepared Bottles S3.';
  end if;
end
$$;

do $$ begin
  create type public.preparation_status as enum ('draft', 'confirmed', 'cancelled');
exception when duplicate_object then null;
end $$;

create table if not exists public.prepared_bottle_recipes (
  id uuid primary key default gen_random_uuid(),
  output_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  product_format_id uuid,
  product_name text not null,
  format_name text not null,
  version integer not null default 1,
  is_active boolean not null default true,
  supersedes_recipe_id uuid references public.prepared_bottle_recipes(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint prepared_bottle_recipes_product_length
    check (char_length(trim(product_name)) between 1 and 120),
  constraint prepared_bottle_recipes_format_length
    check (char_length(trim(format_name)) between 1 and 80),
  constraint prepared_bottle_recipes_version_positive check (version > 0),
  constraint prepared_bottle_recipes_not_self_superseding
    check (supersedes_recipe_id is distinct from id)
);

create table if not exists public.prepared_bottle_recipe_components (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.prepared_bottle_recipes(id) on delete restrict,
  component_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  quantity_per_output numeric(20,6) not null,
  position integer not null,
  created_at timestamptz not null default now(),
  constraint prepared_bottle_recipe_components_quantity_positive
    check (quantity_per_output > 0),
  constraint prepared_bottle_recipe_components_position_positive check (position > 0),
  constraint prepared_bottle_recipe_components_one_item
    unique (recipe_id, component_stock_item_id),
  constraint prepared_bottle_recipe_components_one_position unique (recipe_id, position)
);

create table if not exists public.bottle_preparations (
  id uuid primary key default gen_random_uuid(),
  preparation_number text unique,
  recipe_id uuid not null references public.prepared_bottle_recipes(id) on delete restrict,
  location_id uuid not null references public.stock_locations(id) on delete restrict,
  output_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  product_format_id uuid,
  product_name_snapshot text not null,
  format_name_snapshot text not null,
  output_item_name_snapshot text not null,
  recipe_version_snapshot integer not null,
  planned_quantity numeric(20,3),
  actual_quantity numeric(20,3),
  status public.preparation_status not null default 'draft',
  comment text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  confirmed_by uuid references public.profiles(id) on delete restrict,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bottle_preparations_number_format check (
    preparation_number is null or preparation_number ~ '^PREP-[0-9]{6}-[0-9]{2,}$'
  ),
  constraint bottle_preparations_planned_positive
    check (planned_quantity is null or planned_quantity > 0),
  constraint bottle_preparations_actual_positive
    check (actual_quantity is null or actual_quantity > 0),
  constraint bottle_preparations_comment_length
    check (comment is null or char_length(trim(comment)) between 1 and 2000),
  constraint bottle_preparations_recipe_version_positive check (recipe_version_snapshot > 0),
  constraint bottle_preparations_lifecycle_consistent check (
    (status = 'draft' and preparation_number is null and confirmed_by is null and confirmed_at is null)
    or (status = 'confirmed' and preparation_number is not null and confirmed_by is not null
        and confirmed_at is not null and actual_quantity is not null)
    or (status = 'cancelled' and preparation_number is null and confirmed_by is null and confirmed_at is null)
  )
);

-- Frozen component requirements make a confirmed preparation understandable even
-- after its recipe is superseded. Movements remain the final physical evidence.
create table if not exists public.bottle_preparation_components (
  id uuid primary key default gen_random_uuid(),
  preparation_id uuid not null references public.bottle_preparations(id) on delete cascade,
  component_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  component_name_snapshot text not null,
  component_category public.stock_item_category not null,
  quantity_per_output numeric(20,6) not null,
  required_quantity numeric(20,3),
  position integer not null,
  created_at timestamptz not null default now(),
  constraint bottle_preparation_components_quantity_positive check (quantity_per_output > 0),
  constraint bottle_preparation_components_required_positive
    check (required_quantity is null or required_quantity > 0),
  constraint bottle_preparation_components_position_positive check (position > 0),
  constraint bottle_preparation_components_valid_category
    check (component_category in ('empty_bottle', 'label')),
  constraint bottle_preparation_components_one_item
    unique (preparation_id, component_stock_item_id),
  constraint bottle_preparation_components_one_position unique (preparation_id, position)
);

create unique index if not exists prepared_bottle_recipes_one_active_product_format_idx
  on public.prepared_bottle_recipes (lower(product_name), lower(format_name)) where is_active;
create unique index if not exists prepared_bottle_recipes_one_active_output_idx
  on public.prepared_bottle_recipes (output_stock_item_id) where is_active;
create index if not exists prepared_bottle_recipes_output_idx
  on public.prepared_bottle_recipes (output_stock_item_id, version desc);
create index if not exists prepared_bottle_recipe_components_item_idx
  on public.prepared_bottle_recipe_components (component_stock_item_id, recipe_id);
create index if not exists bottle_preparations_recent_idx
  on public.bottle_preparations (created_at desc, id desc);
create index if not exists bottle_preparations_filters_idx
  on public.bottle_preparations (status, product_name_snapshot, format_name_snapshot, created_at desc);
create index if not exists bottle_preparations_creator_idx
  on public.bottle_preparations (created_by, created_at desc);
create index if not exists bottle_preparation_components_item_idx
  on public.bottle_preparation_components (component_stock_item_id, preparation_id);

-- Each frozen component and each preparation output can post at most once.
create unique index if not exists stock_movements_preparation_component_unique_idx
  on public.stock_movements ((metadata ->> 'preparation_component_id'))
  where movement_type = 'preparation_consumption'::public.stock_movement_type
    and reference_type = 'bottle_preparation'
    and metadata ? 'preparation_component_id';
create unique index if not exists stock_movements_preparation_output_unique_idx
  on public.stock_movements (reference_id)
  where movement_type = 'preparation_output'::public.stock_movement_type
    and reference_type = 'bottle_preparation';

alter table public.prepared_bottle_recipes enable row level security;
alter table public.prepared_bottle_recipe_components enable row level security;
alter table public.bottle_preparations enable row level security;
alter table public.bottle_preparation_components enable row level security;
revoke all on public.prepared_bottle_recipes from anon, authenticated;
revoke all on public.prepared_bottle_recipe_components from anon, authenticated;
revoke all on public.bottle_preparations from anon, authenticated;
revoke all on public.bottle_preparation_components from anon, authenticated;

create or replace function public.normalize_prepared_bottle_recipe()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.product_name := trim(new.product_name);
  new.format_name := trim(new.format_name);
  return new;
end;
$$;

create or replace function public.validate_prepared_bottle_recipe()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare output_item public.stock_items;
begin
  select item.* into output_item from public.stock_items item
  where item.id = new.output_stock_item_id and item.is_active;
  if not found or output_item.category <> 'prepared_bottle'::public.stock_item_category then
    raise exception 'Recipe output must be an active prepared_bottle stock item'
      using errcode = '23514';
  end if;
  if output_item.unit <> 'piece'::public.stock_unit then
    raise exception 'Prepared bottle output must use the piece unit' using errcode = '23514';
  end if;
  if new.product_format_id is not null
    and output_item.product_format_id is distinct from new.product_format_id then
    raise exception 'Recipe product format must match the output stock item'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.validate_prepared_bottle_recipe_component()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare component_item public.stock_items;
declare output_id uuid;
begin
  select item.* into component_item from public.stock_items item
  where item.id = new.component_stock_item_id and item.is_active;
  if not found or component_item.category not in (
    'empty_bottle'::public.stock_item_category, 'label'::public.stock_item_category
  ) then
    raise exception 'Recipe components must be active empty_bottle or label stock items'
      using errcode = '23514';
  end if;
  if component_item.unit <> 'piece'::public.stock_unit then
    raise exception 'Prepared bottle components must use the piece unit' using errcode = '23514';
  end if;
  select recipe.output_stock_item_id into output_id
  from public.prepared_bottle_recipes recipe where recipe.id = new.recipe_id;
  if output_id is null then
    raise exception 'Prepared bottle recipe not found' using errcode = 'P0002';
  end if;
  if output_id = new.component_stock_item_id then
    raise exception 'Recipe output cannot also be a component' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.require_draft_preparation_for_component_change()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare parent_id uuid := coalesce(new.preparation_id, old.preparation_id);
begin
  if tg_op = 'UPDATE' and new.preparation_id is distinct from old.preparation_id then
    raise exception 'Preparation components cannot be moved between preparations'
      using errcode = '55000';
  end if;
  if not exists (select 1 from public.bottle_preparations preparation
    where preparation.id = parent_id and preparation.status = 'draft'::public.preparation_status) then
    raise exception 'Preparation components are immutable after draft' using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.protect_bottle_preparation_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft'::public.preparation_status then
      raise exception 'Confirmed or cancelled preparations cannot be deleted' using errcode = '55000';
    end if;
    return old;
  end if;
  if old.status <> 'draft'::public.preparation_status then
    raise exception 'Confirmed or cancelled preparations are immutable' using errcode = '55000';
  end if;
  if new.status not in ('draft'::public.preparation_status, 'confirmed'::public.preparation_status,
                        'cancelled'::public.preparation_status) then
    raise exception 'Invalid preparation status transition' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists prepared_bottle_recipes_normalize on public.prepared_bottle_recipes;
create trigger prepared_bottle_recipes_normalize before insert or update of product_name, format_name
on public.prepared_bottle_recipes for each row execute function public.normalize_prepared_bottle_recipe();
drop trigger if exists prepared_bottle_recipes_validate on public.prepared_bottle_recipes;
create trigger prepared_bottle_recipes_validate before insert or update of output_stock_item_id, product_format_id
on public.prepared_bottle_recipes for each row execute function public.validate_prepared_bottle_recipe();
drop trigger if exists prepared_bottle_recipes_updated_at on public.prepared_bottle_recipes;
create trigger prepared_bottle_recipes_updated_at before update on public.prepared_bottle_recipes
for each row execute function public.set_updated_at();
drop trigger if exists prepared_bottle_recipe_components_validate on public.prepared_bottle_recipe_components;
create trigger prepared_bottle_recipe_components_validate before insert or update
on public.prepared_bottle_recipe_components for each row
execute function public.validate_prepared_bottle_recipe_component();
drop trigger if exists bottle_preparations_protect_lifecycle on public.bottle_preparations;
create trigger bottle_preparations_protect_lifecycle before update or delete on public.bottle_preparations
for each row execute function public.protect_bottle_preparation_lifecycle();
drop trigger if exists bottle_preparations_updated_at on public.bottle_preparations;
create trigger bottle_preparations_updated_at before update on public.bottle_preparations
for each row execute function public.set_updated_at();
drop trigger if exists bottle_preparation_components_require_draft on public.bottle_preparation_components;
create trigger bottle_preparation_components_require_draft before insert or update or delete
on public.bottle_preparation_components for each row
execute function public.require_draft_preparation_for_component_change();

revoke all on function public.normalize_prepared_bottle_recipe() from public, anon, authenticated;
revoke all on function public.validate_prepared_bottle_recipe() from public, anon, authenticated;
revoke all on function public.validate_prepared_bottle_recipe_component() from public, anon, authenticated;
revoke all on function public.require_draft_preparation_for_component_change() from public, anon, authenticated;
revoke all on function public.protect_bottle_preparation_lifecycle() from public, anon, authenticated;

comment on table public.prepared_bottle_recipes is
  'Versioned product+format recipe producing one prepared_bottle stock item.';
comment on table public.bottle_preparations is
  'Draft/confirmed packaging preparation. Only trusted confirmation posts movements.';
comment on table public.bottle_preparation_components is
  'Frozen recipe component snapshot; confirmed required_quantity matches actual movements.';

-- Verification query:
select table_name from information_schema.tables
where table_schema = 'public' and table_name in (
  'prepared_bottle_recipes', 'prepared_bottle_recipe_components',
  'bottle_preparations', 'bottle_preparation_components'
) order by table_name;
