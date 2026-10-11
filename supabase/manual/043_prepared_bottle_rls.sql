-- SOMA / FACOLUB prepared bottles module - 043 RLS and grants
-- Depends on: 040-042.

alter table public.prepared_bottle_recipes enable row level security;
alter table public.prepared_bottle_recipe_components enable row level security;
alter table public.bottle_preparations enable row level security;
alter table public.bottle_preparation_components enable row level security;
alter table public.preparation_number_sequences enable row level security;

drop policy if exists prepared_bottle_recipes_facolub_read on public.prepared_bottle_recipes;
create policy prepared_bottle_recipes_facolub_read on public.prepared_bottle_recipes
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
  and (is_active or public.current_app_role() = 'admin'::public.app_role)
);

drop policy if exists prepared_bottle_recipe_components_facolub_read
  on public.prepared_bottle_recipe_components;
create policy prepared_bottle_recipe_components_facolub_read
on public.prepared_bottle_recipe_components
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
  and exists (
    select 1 from public.prepared_bottle_recipes recipe
    where recipe.id = recipe_id
      and (recipe.is_active or public.current_app_role() = 'admin'::public.app_role)
  )
);

drop policy if exists bottle_preparations_facolub_read on public.bottle_preparations;
create policy bottle_preparations_facolub_read on public.bottle_preparations
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
);

drop policy if exists bottle_preparation_components_facolub_read
  on public.bottle_preparation_components;
create policy bottle_preparation_components_facolub_read
on public.bottle_preparation_components
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
  and exists (
    select 1 from public.bottle_preparations preparation
    where preparation.id = preparation_id
  )
);

-- There are deliberately no INSERT/UPDATE/DELETE policies. Recipe mutations
-- are Admin-only RPCs; operational mutations are validated RPCs; movements
-- remain protected by the existing stock ledger RLS.
revoke all on public.prepared_bottle_recipes from anon, authenticated;
revoke all on public.prepared_bottle_recipe_components from anon, authenticated;
revoke all on public.bottle_preparations from anon, authenticated;
revoke all on public.bottle_preparation_components from anon, authenticated;
revoke all on public.preparation_number_sequences from anon, authenticated;
grant select on public.prepared_bottle_recipes to authenticated;
grant select on public.prepared_bottle_recipe_components to authenticated;
grant select on public.bottle_preparations to authenticated;
grant select on public.bottle_preparation_components to authenticated;

revoke all on function public.allocate_preparation_number(date) from public, anon, authenticated;
revoke all on function public.assert_prepared_bottle_actor(public.app_role[]) from public, anon, authenticated;
revoke all on function public.prepared_bottle_recipe_payload(uuid) from public, anon, authenticated;
revoke all on function public.insert_prepared_bottle_recipe_components(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.snapshot_preparation_recipe(uuid,uuid) from public, anon, authenticated;
revoke all on function public.bottle_preparation_payload(uuid) from public, anon, authenticated;
revoke all on function public.post_bottle_preparation_movement(uuid,uuid) from public, anon, authenticated;

-- Verification query: only SELECT policies should exist.
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename in (
  'prepared_bottle_recipes', 'prepared_bottle_recipe_components',
  'bottle_preparations', 'bottle_preparation_components',
  'preparation_number_sequences'
)
order by tablename, policyname;
