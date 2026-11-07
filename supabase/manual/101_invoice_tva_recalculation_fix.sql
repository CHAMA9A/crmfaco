-- FACOLUB invoice patch - 101 TVA recalculation fix
-- Depends on 098_invoice_ttc_functions.sql and 100_invoice_tva_20.sql.
-- Fixes the transition from a null/old rate to 20%: the BEFORE UPDATE trigger
-- must calculate with NEW.tax_rate, not the rate still persisted in the table.

begin;

create or replace function public.enforce_invoice_financials()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare configured_rate numeric(7,4);
declare calculated_subtotal numeric(18,2);
declare calculated_tax numeric(18,2);
begin
  if tg_op = 'UPDATE' and old.status <> 'draft'::public.invoice_status then
    return new;
  end if;

  if new.tax_rate is null then
    select settings.default_tax_rate into configured_rate
    from public.invoice_tax_settings settings
    where settings.singleton;
    new.tax_rate := configured_rate;
  end if;

  if tg_op = 'INSERT' then
    new.subtotal_ht := 0;
    new.tax_total := 0;
    new.total_ttc := 0;
    new.total := 0;
    return new;
  end if;

  if new.tax_rate is null and new.status <> 'draft'::public.invoice_status then
    raise exception 'Default TVA rate requires client confirmation.' using errcode = '23514';
  end if;

  select coalesce(sum(item.line_total), 0)::numeric(18,2)
  into calculated_subtotal
  from public.invoice_items item
  where item.invoice_id = new.id;

  calculated_tax := case
    when new.tax_rate is null then 0
    else round(calculated_subtotal * new.tax_rate / 100, 2)
  end::numeric(18,2);

  new.subtotal_ht := calculated_subtotal;
  new.tax_total := calculated_tax;
  new.total_ttc := calculated_subtotal + calculated_tax;
  new.total := new.total_ttc;
  return new;
end;
$$;

-- Recalculate every editable invoice with the confirmed fixed rate.
update public.invoices invoice
set tax_rate = 20.0000,
    updated_at = now()
where invoice.status = 'draft'::public.invoice_status;

commit;

-- Expected for every draft with a positive HT:
-- tax_rate = 20, tax_total = round(subtotal_ht * 20 / 100, 2),
-- total_ttc = subtotal_ht + tax_total, and all three checks are true.
select
  invoice.invoice_number,
  invoice.status,
  invoice.subtotal_ht as total_ht,
  invoice.tax_rate,
  invoice.tax_total as tva,
  invoice.total_ttc,
  invoice.tax_total = round(invoice.subtotal_ht * 20 / 100, 2) as tva_is_20_percent,
  invoice.total_ttc = invoice.subtotal_ht + invoice.tax_total as total_ttc_is_correct
from public.invoices invoice
where invoice.status = 'draft'::public.invoice_status
order by invoice.created_at desc;

-- Audit only: final invoices are immutable and are never silently rewritten.
-- Any returned row requires an explicit accounting correction decision.
select
  invoice.invoice_number,
  invoice.status,
  invoice.subtotal_ht as total_ht,
  invoice.tax_rate,
  invoice.tax_total as tva,
  invoice.total_ttc
from public.invoices invoice
where invoice.status <> 'draft'::public.invoice_status
  and invoice.tax_rate = 20.0000
  and (
    invoice.tax_total is distinct from round(invoice.subtotal_ht * 20 / 100, 2)
    or invoice.total_ttc is distinct from invoice.subtotal_ht + invoice.tax_total
  )
order by invoice.created_at desc;

