-- FACOLUB post-catalog patch - 098 authoritative HT/TVA/TTC functions
-- Depends on 097. Default TVA remains null until the client confirms it.

create or replace function public.invoice_authoritative_totals(target_invoice_id uuid)
returns table (
  subtotal_ht numeric(18,2),
  tax_rate numeric(7,4),
  tax_total numeric(18,2),
  total_ttc numeric(18,2)
) language sql stable security invoker set search_path = '' as $$
  select
    coalesce(sum(item.line_total), 0)::numeric(18,2),
    invoice.tax_rate,
    case when invoice.tax_rate is null then 0
      else round(coalesce(sum(item.line_total), 0) * invoice.tax_rate / 100, 2)
    end::numeric(18,2),
    (coalesce(sum(item.line_total), 0) + case when invoice.tax_rate is null then 0
      else round(coalesce(sum(item.line_total), 0) * invoice.tax_rate / 100, 2)
    end)::numeric(18,2)
  from public.invoices invoice
  left join public.invoice_items item on item.invoice_id = invoice.id
  where invoice.id = target_invoice_id
  group by invoice.id, invoice.tax_rate
$$;

create or replace function public.invoice_authoritative_total(target_invoice_id uuid)
returns numeric(18,2) language sql stable security invoker set search_path = '' as $$
  select totals.total_ttc
  from public.invoice_authoritative_totals(target_invoice_id) totals
$$;

create or replace function public.enforce_invoice_financials()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare configured_rate numeric(7,4);
declare totals record;
begin
  if tg_op = 'UPDATE' and old.status <> 'draft'::public.invoice_status then
    return new;
  end if;

  if new.tax_rate is null then
    select settings.default_tax_rate into configured_rate
    from public.invoice_tax_settings settings where settings.singleton;
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

  select * into strict totals from public.invoice_authoritative_totals(new.id);
  new.subtotal_ht := totals.subtotal_ht;
  new.tax_total := totals.tax_total;
  new.total_ttc := totals.total_ttc;
  new.total := totals.total_ttc;
  return new;
end;
$$;

drop trigger if exists invoices_enforce_financials on public.invoices;
create trigger invoices_enforce_financials
before insert or update on public.invoices
for each row execute function public.enforce_invoice_financials();

create or replace function public.sync_invoice_total()
returns trigger language plpgsql security definer set search_path = '' as $$
declare affected_invoice_id uuid := coalesce(new.invoice_id, old.invoice_id);
begin
  -- The invoice BEFORE UPDATE trigger replaces all submitted financial values
  -- with database-derived HT/TVA/TTC values.
  update public.invoices set updated_at = now() where id = affected_invoice_id;
  if tg_op = 'UPDATE' and old.invoice_id <> new.invoice_id then
    update public.invoices set updated_at = now() where id = old.invoice_id;
  end if;
  return null;
end;
$$;

create or replace function public.configure_default_invoice_tax_rate(target_tax_rate numeric)
returns public.invoice_tax_settings language plpgsql security definer set search_path = '' as $$
declare result public.invoice_tax_settings;
begin
  if auth.uid() is null
    or not public.has_environment_access('FACOLUB')
    or public.current_app_role() <> 'admin'::public.app_role then
    raise exception 'Forbidden' using errcode = '42501';
  end if;
  if target_tax_rate is null or target_tax_rate < 0 or target_tax_rate > 100 then
    raise exception 'TVA rate must be between 0 and 100.' using errcode = '22023';
  end if;
  update public.invoice_tax_settings
  set default_tax_rate = round(target_tax_rate, 4), updated_by = auth.uid()
  where singleton returning * into result;
  return result;
end;
$$;

revoke all on function public.invoice_authoritative_totals(uuid) from public, anon;
revoke all on function public.invoice_authoritative_total(uuid) from public, anon;
revoke all on function public.enforce_invoice_financials() from public, anon, authenticated;
revoke all on function public.sync_invoice_total() from public, anon, authenticated;
revoke all on function public.configure_default_invoice_tax_rate(numeric) from public, anon;
grant execute on function public.invoice_authoritative_totals(uuid) to authenticated;
grant execute on function public.invoice_authoritative_total(uuid) to authenticated;
grant execute on function public.configure_default_invoice_tax_rate(numeric) to authenticated;

comment on function public.invoice_authoritative_totals(uuid) is
  'Invoice-level rounding: sum rounded line HT, calculate TVA once, round TVA to 2 decimals, TTC = HT + TVA.';
comment on function public.invoice_authoritative_total(uuid) is
  'Compatibility function returning authoritative TTC, never browser input.';

select
  settings.default_tax_rate,
  case when settings.default_tax_rate is null
    then 'Default TVA rate requires client confirmation.'
    else 'Configured' end as configuration_status,
  to_regprocedure('public.invoice_authoritative_totals(uuid)') as totals_function,
  to_regprocedure('public.configure_default_invoice_tax_rate(numeric)') as configuration_function
from public.invoice_tax_settings settings where settings.singleton;
