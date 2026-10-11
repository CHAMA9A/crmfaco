-- SOMA / FACOLUB production planning module - 051 configurable packaging and recipes
-- Depends on: 050_planning_foundation.sql.

do $$ begin
  create type public.production_component_role as enum (
    'prepared_bottle', 'bulk_lubricant', 'seal', 'carton', 'other'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.packaging_rules (
  id uuid primary key default gen_random_uuid(),
  format_id uuid not null references public.packaging_formats(id) on delete restrict,
  bottles_per_carton integer not null,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint packaging_rules_capacity_positive check (bottles_per_carton > 0)
);

create unique index if not exists packaging_rules_one_active_format_idx
  on public.packaging_rules (format_id) where is_active;
create index if not exists packaging_rules_format_history_idx
  on public.packaging_rules (format_id, created_at desc);

create table if not exists public.production_recipes (
  id uuid primary key default gen_random_uuid(),
  product_format_id uuid not null references public.product_formats(id) on delete restrict,
  output_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  version integer not null default 1,
  is_active boolean not null default true,
  supersedes_recipe_id uuid references public.production_recipes(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint production_recipes_version_positive check (version > 0),
  constraint production_recipes_not_self_superseding check (supersedes_recipe_id is distinct from id),
  constraint production_recipes_one_version unique (product_format_id, version)
);

create table if not exists public.production_recipe_components (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.production_recipes(id) on delete restrict,
  component_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  quantity_per_bottle numeric(20,6) not null,
  component_role public.production_component_role not null,
  position integer not null,
  created_at timestamptz not null default now(),
  constraint production_recipe_components_quantity_positive check (quantity_per_bottle > 0),
  constraint production_recipe_components_position_positive check (position > 0),
  constraint production_recipe_components_one_item unique (recipe_id, component_stock_item_id),
  constraint production_recipe_components_one_role unique (recipe_id, component_role),
  constraint production_recipe_components_one_position unique (recipe_id, position)
);

create unique index if not exists production_recipes_one_active_product_format_idx
  on public.production_recipes (product_format_id) where is_active;
create unique index if not exists production_recipes_one_active_output_idx
  on public.production_recipes (output_stock_item_id) where is_active;
create index if not exists production_recipe_components_item_idx
  on public.production_recipe_components (component_stock_item_id, recipe_id);

do $$
begin
  if not exists (select 1 from pg_constraint
    where conname = 'production_plan_items_recipe_fk'
      and conrelid = 'public.production_plan_items'::regclass) then
    alter table public.production_plan_items
      add constraint production_plan_items_recipe_fk
      foreign key (recipe_id) references public.production_recipes(id) on delete restrict;
  end if;
end
$$;

alter table public.packaging_rules enable row level security;
alter table public.production_recipes enable row level security;
alter table public.production_recipe_components enable row level security;
revoke all on public.packaging_rules from anon, authenticated;
revoke all on public.production_recipes from anon, authenticated;
revoke all on public.production_recipe_components from anon, authenticated;

create or replace function public.validate_production_recipe()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare output_item public.stock_items;
begin
  if not exists (select 1 from public.product_formats product_format
    join public.products product on product.id = product_format.product_id
    join public.packaging_formats format on format.id = product_format.format_id
    where product_format.id = new.product_format_id and product_format.is_active
      and product.is_active and format.is_active) then
    raise exception 'Active product format not found' using errcode = 'P0002';
  end if;
  select item.* into output_item from public.stock_items item
  where item.id = new.output_stock_item_id and item.is_active;
  if not found or output_item.category <> 'finished_product'::public.stock_item_category
    or output_item.unit <> 'piece'::public.stock_unit then
    raise exception 'Production recipe output must be an active finished_product item in pieces'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.validate_production_recipe_component()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare component_item public.stock_items;
declare expected_category public.stock_item_category;
declare output_id uuid;
begin
  select item.* into component_item from public.stock_items item
  where item.id = new.component_stock_item_id and item.is_active;
  if not found then raise exception 'Active production component stock item not found' using errcode = 'P0002'; end if;
  expected_category := case new.component_role
    when 'prepared_bottle'::public.production_component_role then 'prepared_bottle'::public.stock_item_category
    when 'bulk_lubricant'::public.production_component_role then 'bulk_lubricant'::public.stock_item_category
    when 'seal'::public.production_component_role then 'seal'::public.stock_item_category
    when 'carton'::public.production_component_role then 'carton'::public.stock_item_category
    else 'other'::public.stock_item_category
  end;
  if component_item.category <> expected_category then
    raise exception 'Component role % requires stock category %, but item % has category %',
      new.component_role, expected_category, component_item.name, component_item.category
      using errcode = '23514';
  end if;
  if new.component_role <> 'bulk_lubricant'::public.production_component_role
    and component_item.unit <> 'piece'::public.stock_unit then
    raise exception 'Packaging production components must use the piece unit' using errcode = '23514';
  end if;
  if new.component_role = 'bulk_lubricant'::public.production_component_role
    and component_item.unit <> 'liter'::public.stock_unit then
    raise exception 'Bulk lubricant production components must use the liter unit'
      using errcode = '23514';
  end if;
  select recipe.output_stock_item_id into output_id
  from public.production_recipes recipe where recipe.id = new.recipe_id;
  if output_id is null then raise exception 'Production recipe not found' using errcode = 'P0002'; end if;
  if output_id = new.component_stock_item_id then
    raise exception 'Finished product output cannot also be a recipe component'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists packaging_rules_updated_at on public.packaging_rules;
create trigger packaging_rules_updated_at before update on public.packaging_rules
for each row execute function public.set_updated_at();
drop trigger if exists production_recipes_validate on public.production_recipes;
create trigger production_recipes_validate before insert or update of product_format_id, output_stock_item_id
on public.production_recipes for each row execute function public.validate_production_recipe();
drop trigger if exists production_recipes_updated_at on public.production_recipes;
create trigger production_recipes_updated_at before update on public.production_recipes
for each row execute function public.set_updated_at();
drop trigger if exists production_recipe_components_validate on public.production_recipe_components;
create trigger production_recipe_components_validate before insert or update
on public.production_recipe_components for each row
execute function public.validate_production_recipe_component();

revoke all on function public.validate_production_recipe() from public, anon, authenticated;
revoke all on function public.validate_production_recipe_component() from public, anon, authenticated;

-- Seed only the approved configurable capacities. The first active Admin is
-- recorded as creator because configuration rows are auditable.
insert into public.packaging_rules (format_id, bottles_per_carton, is_active, created_by)
select format.id,
  case format.code when '1L' then 24 when '2L' then 12 when '5L' then 4 end,
  true,
  (select profile.id from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id and access.is_active
   join public.environments environment on environment.id = access.environment_id and environment.is_active
   where profile.role = 'admin'::public.app_role and profile.is_active
     and environment.code = 'FACOLUB' order by profile.created_at limit 1)
from public.packaging_formats format
where format.code in ('1L', '2L', '5L')
  and not exists (select 1 from public.packaging_rules rule
    where rule.format_id = format.id and rule.is_active)
  and exists (select 1 from public.profiles profile
    join public.user_environment_access access on access.user_id = profile.id and access.is_active
    join public.environments environment on environment.id = access.environment_id and environment.is_active
    where profile.role = 'admin'::public.app_role and profile.is_active
      and environment.code = 'FACOLUB');

comment on table public.packaging_rules is
  'Versionable carton capacity configuration. One active rule per packaging format.';
comment on table public.production_recipes is
  'Versioned finished-product recipe; labels and empty bottles are excluded in favor of prepared bottles.';

-- Verification query:
select format.code, format.name, rule.bottles_per_carton, rule.is_active
from public.packaging_formats format
left join public.packaging_rules rule on rule.format_id = format.id and rule.is_active
where format.code in ('1L', '2L', '5L')
order by format.volume_liters;
