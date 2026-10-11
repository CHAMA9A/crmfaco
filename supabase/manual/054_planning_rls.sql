-- SOMA / FACOLUB production planning module - 054 RLS and grants
-- Depends on: 050-053.

alter table public.products enable row level security;
alter table public.packaging_formats enable row level security;
alter table public.product_formats enable row level security;
alter table public.packaging_rules enable row level security;
alter table public.production_recipes enable row level security;
alter table public.production_recipe_components enable row level security;
alter table public.production_plans enable row level security;
alter table public.production_plan_items enable row level security;
alter table public.production_plan_requirements enable row level security;
alter table public.production_plan_number_sequences enable row level security;

drop policy if exists products_facolub_read on public.products;
create policy products_facolub_read on public.products
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
  and (is_active or public.current_app_role() = 'admin'::public.app_role)
);

drop policy if exists packaging_formats_facolub_read on public.packaging_formats;
create policy packaging_formats_facolub_read on public.packaging_formats
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
  and (is_active or public.current_app_role() = 'admin'::public.app_role)
);

drop policy if exists product_formats_facolub_read on public.product_formats;
create policy product_formats_facolub_read on public.product_formats
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
  and (is_active or public.current_app_role() = 'admin'::public.app_role)
);

drop policy if exists packaging_rules_facolub_read on public.packaging_rules;
create policy packaging_rules_facolub_read on public.packaging_rules
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
  and (is_active or public.current_app_role() = 'admin'::public.app_role)
);

-- Recipe internals are useful to Admin/Management configuration screens but
-- deliberately hidden from Factory users. Factory receives only mission data.
drop policy if exists production_recipes_facolub_read on public.production_recipes;
create policy production_recipes_facolub_read on public.production_recipes
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and (is_active or public.current_app_role() = 'admin'::public.app_role)
);

drop policy if exists production_recipe_components_facolub_read
  on public.production_recipe_components;
create policy production_recipe_components_facolub_read
on public.production_recipe_components
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and exists (
    select 1 from public.production_recipes recipe
    where recipe.id = recipe_id
      and (recipe.is_active or public.current_app_role() = 'admin'::public.app_role)
  )
);

drop policy if exists production_plans_facolub_read on public.production_plans;
create policy production_plans_facolub_read on public.production_plans
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and (
    public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
    or (
      public.current_app_role() = 'factory'::public.app_role
      and status in ('planned'::public.production_plan_status,
                     'validated'::public.production_plan_status)
      and (assigned_to is null or assigned_to = auth.uid())
    )
  )
);

drop policy if exists production_plan_items_facolub_read on public.production_plan_items;
create policy production_plan_items_facolub_read on public.production_plan_items
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and exists (select 1 from public.production_plans plan where plan.id = production_plan_id)
);

drop policy if exists production_plan_requirements_facolub_read
  on public.production_plan_requirements;
create policy production_plan_requirements_facolub_read
on public.production_plan_requirements
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and exists (
    select 1 from public.production_plan_items item
    join public.production_plans plan on plan.id = item.production_plan_id
    where item.id = production_plan_item_id
  )
);

-- There are no INSERT/UPDATE/DELETE policies. Configuration and lifecycle
-- mutations are performed only by the role-checked SECURITY DEFINER APIs.
revoke all on public.products from anon, authenticated;
revoke all on public.packaging_formats from anon, authenticated;
revoke all on public.product_formats from anon, authenticated;
revoke all on public.packaging_rules from anon, authenticated;
revoke all on public.production_recipes from anon, authenticated;
revoke all on public.production_recipe_components from anon, authenticated;
revoke all on public.production_plans from anon, authenticated;
revoke all on public.production_plan_items from anon, authenticated;
revoke all on public.production_plan_requirements from anon, authenticated;
revoke all on public.production_plan_number_sequences from anon, authenticated;

grant select on public.products to authenticated;
grant select on public.packaging_formats to authenticated;
grant select on public.product_formats to authenticated;
grant select on public.packaging_rules to authenticated;
grant select on public.production_recipes to authenticated;
grant select on public.production_recipe_components to authenticated;
grant select on public.production_plans to authenticated;
grant select on public.production_plan_items to authenticated;
grant select on public.production_plan_requirements to authenticated;

revoke all on function public.normalize_planning_catalog() from public, anon, authenticated;
revoke all on function public.normalize_production_plan() from public, anon, authenticated;
revoke all on function public.protect_production_plan_lifecycle() from public, anon, authenticated;
revoke all on function public.require_draft_plan_for_item_change() from public, anon, authenticated;
revoke all on function public.validate_production_recipe() from public, anon, authenticated;
revoke all on function public.validate_production_recipe_component() from public, anon, authenticated;
revoke all on function public.normalize_production_quantity(uuid,numeric,public.planning_quantity_mode)
  from public, anon, authenticated;
revoke all on function public.snapshot_production_plan_requirements(uuid)
  from public, anon, authenticated;
revoke all on function public.assert_planning_actor(public.app_role[]) from public, anon, authenticated;
revoke all on function public.allocate_production_plan_number(date) from public, anon, authenticated;
revoke all on function public.production_recipe_payload(uuid) from public, anon, authenticated;
revoke all on function public.insert_production_recipe_components(uuid,jsonb)
  from public, anon, authenticated;

-- Verification query: only SELECT policies should exist; the sequence table
-- intentionally has none.
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename in (
  'products', 'packaging_formats', 'product_formats', 'packaging_rules',
  'production_recipes', 'production_recipe_components', 'production_plans',
  'production_plan_items', 'production_plan_requirements',
  'production_plan_number_sequences'
)
order by tablename, policyname;
