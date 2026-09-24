-- SOMA invoice module - 005 OPTIONAL test data
-- Run only when you intentionally want the validation customer and draft invoice.
-- Safe to run once: yes. Creates clearly labelled TEST data only.
-- Idempotent: yes for this exact TEST customer, PO, and the two line descriptions.
-- Depends on: 001, 002, 003, and 004.
-- Does not issue the invoice; use 006 after reviewing the calculated total.

insert into public.customers (
  company_name, contact_person, phone, email, city, address, ice,
  purchase_order_default, is_active
)
select
  '[TEST] SOMA INVOICE VALIDATION',
  'TEST CONTACT - DO NOT USE',
  null,
  null,
  'CASABLANCA',
  'TEST ADDRESS - NOT A REAL CUSTOMER',
  'TEST-ICE-NOT-FISCAL',
  'TEST-INVOICE-VALIDATION-2026-09-23',
  false
where not exists (
  select 1 from public.customers
  where company_name = '[TEST] SOMA INVOICE VALIDATION'
);

insert into public.invoices (
  invoice_date, customer_id, purchase_order,
  customer_name_snapshot, customer_city_snapshot,
  customer_address_snapshot, customer_ice_snapshot,
  status, currency, created_by
)
select
  date '2026-09-23',
  customer.id,
  'TEST-INVOICE-VALIDATION-2026-09-23',
  customer.company_name,
  customer.city,
  customer.address,
  customer.ice,
  'draft'::public.invoice_status,
  'MAD',
  null
from public.customers customer
where customer.company_name = '[TEST] SOMA INVOICE VALIDATION'
  and not exists (
    select 1 from public.invoices
    where purchase_order = 'TEST-INVOICE-VALIDATION-2026-09-23'
  );

insert into public.invoice_items (invoice_id, description, quantity, unit_price, position)
select invoice.id, '[TEST] SOMA 10W40 - VALIDATION LINE', 10, 650.00, 1
from public.invoices invoice
where invoice.purchase_order = 'TEST-INVOICE-VALIDATION-2026-09-23'
  and not exists (
    select 1 from public.invoice_items item
    where item.invoice_id = invoice.id
      and item.description = '[TEST] SOMA 10W40 - VALIDATION LINE'
  );

insert into public.invoice_items (invoice_id, description, quantity, unit_price, position)
select invoice.id, '[TEST] SOMA 20W50 - VALIDATION LINE', 5, 800.00, 2
from public.invoices invoice
where invoice.purchase_order = 'TEST-INVOICE-VALIDATION-2026-09-23'
  and not exists (
    select 1 from public.invoice_items item
    where item.invoice_id = invoice.id
      and item.description = '[TEST] SOMA 20W50 - VALIDATION LINE'
  );

-- Verification query (expected stored_total and calculated_total: 10500.00):
select
  invoice.id as test_invoice_id,
  invoice.invoice_number,
  invoice.status,
  invoice.total as stored_total,
  public.invoice_authoritative_total(invoice.id) as calculated_total,
  count(item.id) as line_count
from public.invoices invoice
join public.invoice_items item on item.invoice_id = invoice.id
where invoice.purchase_order = 'TEST-INVOICE-VALIDATION-2026-09-23'
group by invoice.id, invoice.invoice_number, invoice.status, invoice.total;
