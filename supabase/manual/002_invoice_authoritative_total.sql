-- SOMA invoice module - 002 authoritative total
-- Run in Supabase SQL Editor after 001_invoice_foundation.sql.
-- Safe to run once: yes.
-- Idempotent: yes. Existing totals are recalculated from invoice_items.
-- Authority: SUM(public.invoice_items.line_total); browser totals are never accepted.

create or replace function public.invoice_authoritative_total(target_invoice_id uuid)
returns numeric(18, 2)
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(item.line_total), 0)::numeric(18, 2)
  from public.invoice_items item
  where item.invoice_id = target_invoice_id
$$;

create or replace function public.sync_invoice_total()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_invoice_id uuid := coalesce(new.invoice_id, old.invoice_id);
begin
  update public.invoices invoice
  set total = public.invoice_authoritative_total(affected_invoice_id),
      updated_at = now()
  where invoice.id = affected_invoice_id;

  if tg_op = 'UPDATE' and old.invoice_id <> new.invoice_id then
    update public.invoices invoice
    set total = public.invoice_authoritative_total(old.invoice_id),
        updated_at = now()
    where invoice.id = old.invoice_id;
  end if;
  return null;
end;
$$;

drop trigger if exists invoice_items_sync_total on public.invoice_items;
create trigger invoice_items_sync_total
after insert or update or delete on public.invoice_items
for each row execute function public.sync_invoice_total();

-- Bring any pre-existing invoices into agreement with their stored line totals.
update public.invoices invoice
set total = public.invoice_authoritative_total(invoice.id)
where total is distinct from public.invoice_authoritative_total(invoice.id);

comment on function public.invoice_authoritative_total(uuid) is
  'Authoritative commercial invoice total: SUM(invoice_items.line_total).';

-- Verification query:
select
  to_regprocedure('public.invoice_authoritative_total(uuid)') as total_function,
  to_regprocedure('public.sync_invoice_total()') as trigger_function,
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.invoice_items'::regclass
      and tgname = 'invoice_items_sync_total'
      and not tgisinternal
  ) as total_trigger_exists;
