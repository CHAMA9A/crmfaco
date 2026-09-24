-- SOMA invoice module - 007 issue the OPTIONAL test invoice
-- TEMPLATE: replace <ADMIN_USER_UUID> with an active Admin UUID that has FACOLUB access.
-- You may instead use an active Management UUID with FACOLUB access.
-- Safe to run once: yes, after reviewing 005's result and applying 006.
-- Idempotent: no. An issued invoice cannot be issued a second time.
-- Depends on: 001 through 006.

begin;

select set_config('request.jwt.claim.sub', '<ADMIN_USER_UUID>', true);
set local role authenticated;

-- Keep the composite return value as one column. Expanding it with .*
-- can cause PostgreSQL to evaluate a volatile composite function more than once.
select public.issue_invoice(invoice.id) as issued_invoice
from public.invoices invoice
where invoice.purchase_order = 'TEST-INVOICE-VALIDATION-2026-09-23'
  and invoice.status = 'draft'::public.invoice_status;

reset role;
commit;

-- Verification query (expected pattern: FAC-2026-######, status issued, total 10500.00):
select
  invoice.id,
  invoice.invoice_number,
  invoice.status,
  invoice.total,
  invoice.issued_at,
  public.invoice_authoritative_total(invoice.id) as calculated_total
from public.invoices invoice
where invoice.purchase_order = 'TEST-INVOICE-VALIDATION-2026-09-23';
