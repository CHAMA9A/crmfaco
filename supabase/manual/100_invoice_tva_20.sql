-- FACOLUB invoice patch - 100 confirmed SOMA TVA rate
-- Depends on 097_invoice_ttc_foundation.sql and 098_invoice_ttc_functions.sql.
-- Client-confirmed rule: unit prices are HT and the current TVA rate is 20%.
-- Existing issued/cancelled invoices remain unchanged. Every draft adopts 20%
-- and is recalculated by the authoritative invoice trigger when needed.

begin;

update public.invoice_tax_settings
set default_tax_rate = 20.0000
where singleton;

update public.invoices invoice
set tax_rate = 20.0000,
    updated_at = now()
where invoice.status = 'draft'::public.invoice_status
  and invoice.tax_rate is distinct from 20.0000;

commit;

-- Expected:
-- default_tax_rate = 20.0000
-- draft_without_20_percent = 0
-- issued_legacy_invoices_preserved may be greater than zero and is intentional.
select
  settings.default_tax_rate,
  count(*) filter (
    where invoice.status = 'draft'::public.invoice_status
      and invoice.tax_rate is distinct from 20.0000
  ) as draft_without_20_percent,
  count(*) filter (
    where invoice.status = 'issued'::public.invoice_status
      and invoice.tax_rate is null
  ) as issued_legacy_invoices_preserved
from public.invoice_tax_settings settings
left join public.invoices invoice on true
where settings.singleton
group by settings.default_tax_rate;

-- New/configured invoices must expose the three authoritative rows used by
-- both the web detail and PDF: TOTAL HT, TVA 20 %, TOTAL TTC.
select
  invoice.invoice_number,
  invoice.status,
  invoice.subtotal_ht as total_ht,
  invoice.tax_rate,
  invoice.tax_total as tva,
  invoice.total_ttc,
  invoice.total_ttc = invoice.subtotal_ht + invoice.tax_total as totals_consistent
from public.invoices invoice
where invoice.tax_rate = 20.0000
order by invoice.created_at desc
limit 20;
