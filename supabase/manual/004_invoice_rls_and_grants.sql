-- SOMA invoice module - 004 RLS, grants, and security boundaries
-- Run in Supabase SQL Editor after 001, 002, and 003.
-- Safe to run once: yes.
-- Idempotent: yes. Policies are dropped and recreated with the definitions below.
-- Depends on existing helpers from the FACOLUB auth foundation:
-- public.current_app_role() and public.has_environment_access(text).

do $$
begin
  if to_regprocedure('public.current_app_role()') is null
    or to_regprocedure('public.has_environment_access(text)') is null
  then
    raise exception 'FACOLUB auth helper functions are missing. Run the auth foundation first.';
  end if;
end $$;

alter table public.customers enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
alter table public.invoice_number_sequences enable row level security;

drop policy if exists customers_management_select on public.customers;
create policy customers_management_select on public.customers
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);

drop policy if exists customers_management_insert on public.customers;
create policy customers_management_insert on public.customers
for insert to authenticated
with check (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);

drop policy if exists customers_management_update on public.customers;
create policy customers_management_update on public.customers
for update to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
)
with check (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);

drop policy if exists invoices_management_select on public.invoices;
create policy invoices_management_select on public.invoices
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);

drop policy if exists invoices_management_insert_draft on public.invoices;
create policy invoices_management_insert_draft on public.invoices
for insert to authenticated
with check (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and status = 'draft'::public.invoice_status
  and invoice_number is null
  and created_by = auth.uid()
);

drop policy if exists invoices_management_update_draft on public.invoices;
create policy invoices_management_update_draft on public.invoices
for update to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and status = 'draft'::public.invoice_status
)
with check (
  status = 'draft'::public.invoice_status
  and invoice_number is null
);

drop policy if exists invoice_items_management_select on public.invoice_items;
create policy invoice_items_management_select on public.invoice_items
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);

drop policy if exists invoice_items_management_insert_draft on public.invoice_items;
create policy invoice_items_management_insert_draft on public.invoice_items
for insert to authenticated
with check (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and exists (
    select 1 from public.invoices invoice
    where invoice.id = invoice_id and invoice.status = 'draft'::public.invoice_status
  )
);

drop policy if exists invoice_items_management_update_draft on public.invoice_items;
create policy invoice_items_management_update_draft on public.invoice_items
for update to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and exists (
    select 1 from public.invoices invoice
    where invoice.id = invoice_id and invoice.status = 'draft'::public.invoice_status
  )
)
with check (
  exists (
    select 1 from public.invoices invoice
    where invoice.id = invoice_id and invoice.status = 'draft'::public.invoice_status
  )
);

drop policy if exists invoice_items_management_delete_draft on public.invoice_items;
create policy invoice_items_management_delete_draft on public.invoice_items
for delete to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and exists (
    select 1 from public.invoices invoice
    where invoice.id = invoice_id and invoice.status = 'draft'::public.invoice_status
  )
);

revoke all on public.customers, public.invoices, public.invoice_items from anon;
revoke all on public.invoice_number_sequences from anon, authenticated;

revoke all on public.customers, public.invoices, public.invoice_items from authenticated;
grant select on public.customers, public.invoices, public.invoice_items to authenticated;
grant insert (
  company_name, contact_person, phone, email, city, address, ice,
  purchase_order_default, is_active
) on public.customers to authenticated;
grant update (
  company_name, contact_person, phone, email, city, address, ice,
  purchase_order_default, is_active, updated_at
) on public.customers to authenticated;
grant insert (
  invoice_date, customer_id, purchase_order, customer_name_snapshot,
  customer_city_snapshot, customer_address_snapshot, customer_ice_snapshot,
  currency, created_by
) on public.invoices to authenticated;
grant update (
  invoice_date, customer_id, purchase_order, customer_name_snapshot,
  customer_city_snapshot, customer_address_snapshot, customer_ice_snapshot,
  currency, updated_at
) on public.invoices to authenticated;
grant insert (invoice_id, description, quantity, unit_price, position)
  on public.invoice_items to authenticated;
grant update (description, quantity, unit_price, position)
  on public.invoice_items to authenticated;
grant delete on public.invoice_items to authenticated;

revoke all on function public.invoice_authoritative_total(uuid) from public, anon;
grant execute on function public.invoice_authoritative_total(uuid) to authenticated;
revoke all on function public.issue_invoice(uuid) from public, anon;
grant execute on function public.issue_invoice(uuid) to authenticated;

-- Verification query:
select schemaname, tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename in ('customers', 'invoices', 'invoice_items')
order by tablename, policyname;
