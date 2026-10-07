-- SOMA / FACOLUB stock module - 023 grants and row-level security
-- Depends on: 020-022

alter table public.stock_locations enable row level security;
alter table public.stock_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.stock_reservations enable row level security;
alter table public.stock_adjustments enable row level security;

drop policy if exists stock_locations_facolub_read on public.stock_locations;
create policy stock_locations_facolub_read on public.stock_locations
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
);

drop policy if exists stock_items_facolub_read on public.stock_items;
create policy stock_items_facolub_read on public.stock_items
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
);

drop policy if exists stock_movements_facolub_read on public.stock_movements;
create policy stock_movements_facolub_read on public.stock_movements
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
);

drop policy if exists stock_reservations_facolub_read on public.stock_reservations;
create policy stock_reservations_facolub_read on public.stock_reservations
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
);

drop policy if exists stock_adjustments_facolub_read on public.stock_adjustments;
create policy stock_adjustments_facolub_read on public.stock_adjustments
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
);

-- There are intentionally no INSERT/UPDATE/DELETE policies. All writes go
-- through validated SECURITY DEFINER RPCs in 024.
revoke all on public.stock_locations from anon, authenticated;
revoke all on public.stock_items from anon, authenticated;
revoke all on public.stock_movements from anon, authenticated;
revoke all on public.stock_reservations from anon, authenticated;
revoke all on public.stock_adjustments from anon, authenticated;
revoke all on public.stock_balances from anon, authenticated;

grant select on public.stock_locations to authenticated;
grant select on public.stock_items to authenticated;
grant select on public.stock_movements to authenticated;
grant select on public.stock_reservations to authenticated;
grant select on public.stock_adjustments to authenticated;
grant select on public.stock_balances to authenticated;

revoke all on function public.normalize_stock_location() from public, anon, authenticated;
revoke all on function public.normalize_stock_item() from public, anon, authenticated;
revoke all on function public.reject_stock_movement_mutation() from public, anon, authenticated;
revoke all on function public.protect_stock_reservation_identity() from public, anon, authenticated;

-- Verification query: only SELECT policies should exist.
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename like 'stock_%'
order by tablename, policyname;
