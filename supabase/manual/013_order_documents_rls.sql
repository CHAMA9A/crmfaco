-- SOMA order document bundle - 013 RLS, grants, and legacy invoice boundaries
-- Run after 012_delivery_transport_documents.sql.
-- ADMIN/MANAGEMENT can read commercial data; FACTORY receives no rows.
-- New order mutations are RPC-only. Existing legacy invoice workflows remain available.

do $$ begin
  if to_regprocedure('public.current_app_role()') is null
    or to_regprocedure('public.has_environment_access(text)') is null then
    raise exception 'FACOLUB auth helper functions are missing';
  end if;
end $$;

alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.delivery_notes enable row level security;
alter table public.transport_notes enable row level security;
alter table public.order_number_sequences enable row level security;

drop policy if exists orders_commercial_select on public.orders;
create policy orders_commercial_select on public.orders for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);

drop policy if exists order_items_commercial_select on public.order_items;
create policy order_items_commercial_select on public.order_items for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);

drop policy if exists delivery_notes_commercial_select on public.delivery_notes;
create policy delivery_notes_commercial_select on public.delivery_notes for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);

drop policy if exists transport_notes_commercial_select on public.transport_notes;
create policy transport_notes_commercial_select on public.transport_notes for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);

-- Preserve direct creation/editing only for pre-order (legacy) invoice drafts.
drop policy if exists invoices_management_insert_draft on public.invoices;
create policy invoices_management_insert_draft on public.invoices for insert to authenticated
with check (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and status = 'draft'::public.invoice_status
  and invoice_number is null
  and order_id is null
  and created_by = auth.uid()
);

drop policy if exists invoices_management_update_draft on public.invoices;
create policy invoices_management_update_draft on public.invoices for update to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and status = 'draft'::public.invoice_status
  and order_id is null
)
with check (
  status = 'draft'::public.invoice_status
  and invoice_number is null
  and order_id is null
);

drop policy if exists invoice_items_management_insert_draft on public.invoice_items;
create policy invoice_items_management_insert_draft on public.invoice_items for insert to authenticated
with check (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and order_item_id is null
  and exists (
    select 1 from public.invoices invoice
    where invoice.id = invoice_id
      and invoice.status = 'draft'::public.invoice_status
      and invoice.order_id is null
  )
);

drop policy if exists invoice_items_management_update_draft on public.invoice_items;
create policy invoice_items_management_update_draft on public.invoice_items for update to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and order_item_id is null
  and exists (
    select 1 from public.invoices invoice
    where invoice.id = invoice_id
      and invoice.status = 'draft'::public.invoice_status
      and invoice.order_id is null
  )
)
with check (
  order_item_id is null
  and exists (
    select 1 from public.invoices invoice
    where invoice.id = invoice_id
      and invoice.status = 'draft'::public.invoice_status
      and invoice.order_id is null
  )
);

drop policy if exists invoice_items_management_delete_draft on public.invoice_items;
create policy invoice_items_management_delete_draft on public.invoice_items for delete to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
  and order_item_id is null
  and exists (
    select 1 from public.invoices invoice
    where invoice.id = invoice_id
      and invoice.status = 'draft'::public.invoice_status
      and invoice.order_id is null
  )
);

revoke all on public.orders, public.order_items, public.delivery_notes,
  public.transport_notes, public.order_number_sequences from public, anon, authenticated;
grant select on public.orders, public.order_items, public.delivery_notes,
  public.transport_notes to authenticated;

-- Existing invoice grants deliberately omit order_id, order_item_id, and price-confirmation fields.
revoke insert, update, delete on public.invoices, public.invoice_items from authenticated;
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

-- Verification query: Factory must have policies but no permissive Factory predicate.
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('orders', 'order_items', 'delivery_notes', 'transport_notes')
order by tablename, policyname;
