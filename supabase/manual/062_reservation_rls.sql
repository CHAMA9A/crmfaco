-- SOMA / FACOLUB production module - 062 reservation RLS and grants
-- Depends on: 060-061 and the existing stock/planning RLS in 023 and 054.

alter table public.production_plans enable row level security;
alter table public.production_plan_requirements enable row level security;
alter table public.stock_reservations enable row level security;

-- Keep the shared stock reservation read policy: stock_balances is a
-- security-invoker view, so hiding active production rows would show Factory
-- users a false available balance. Mutations remain RPC-only.
drop policy if exists stock_reservations_facolub_read on public.stock_reservations;
create policy stock_reservations_facolub_read on public.stock_reservations
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
);

revoke all on public.production_plans from anon, authenticated;
revoke all on public.production_plan_requirements from anon, authenticated;
revoke all on public.stock_reservations from anon, authenticated;
grant select on public.production_plans to authenticated;
grant select on public.production_plan_requirements to authenticated;
grant select on public.stock_reservations to authenticated;

-- Internal primitives are never callable from the browser.
revoke all on function public.production_plan_reservation_payload(uuid)
  from public, anon, authenticated;
revoke all on function public.release_production_plan_reservations_internal(uuid,uuid)
  from public, anon, authenticated;

-- Public S5 APIs perform their own FACOLUB role and mission checks.
revoke all on function public.reserve_production_plan(uuid) from public, anon;
revoke all on function public.release_production_plan_reservations(uuid) from public, anon;
revoke all on function public.get_production_plan_reservations(uuid) from public, anon;
revoke all on function public.list_production_plan_reservation_history(uuid,integer)
  from public, anon;

grant execute on function public.reserve_production_plan(uuid) to authenticated;
grant execute on function public.release_production_plan_reservations(uuid) to authenticated;
grant execute on function public.get_production_plan_reservations(uuid) to authenticated;
grant execute on function public.list_production_plan_reservation_history(uuid,integer)
  to authenticated;

-- S5 replaced cancellation so its existing authenticated grant is asserted.
revoke all on function public.cancel_production_plan(uuid) from public, anon;
grant execute on function public.cancel_production_plan(uuid) to authenticated;

-- Verification query: authenticated has SELECT but no direct write privilege,
-- and only the trusted S5 entry points are executable.
select
  has_table_privilege('authenticated', 'public.stock_reservations', 'SELECT')
    as can_read_reservations,
  has_table_privilege('authenticated', 'public.stock_reservations', 'INSERT,UPDATE,DELETE')
    as can_directly_write_reservations,
  has_function_privilege('authenticated', 'public.reserve_production_plan(uuid)', 'EXECUTE')
    as can_call_reserve,
  has_function_privilege('authenticated',
    'public.release_production_plan_reservations(uuid)', 'EXECUTE') as can_call_release,
  has_function_privilege('authenticated',
    'public.release_production_plan_reservations_internal(uuid,uuid)', 'EXECUTE')
    as can_call_internal_release;
