-- SOMA invoice module - 003 concurrency-safe numbering and issuing
-- Run in Supabase SQL Editor after 001 and 002.
-- Safe to run once: yes.
-- Idempotent: yes for schema/function creation.
-- Number format: FAC-YYYY-000001; sequence resets by invoice year.

create table if not exists public.invoice_number_sequences (
  invoice_year integer primary key check (invoice_year between 2000 and 9999),
  last_value bigint not null check (last_value > 0)
);

create or replace function public.issue_invoice(target_invoice_id uuid)
returns public.invoices
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_invoice public.invoices;
  target_invoice_year integer;
  next_value bigint;
begin
  if not public.has_environment_access('FACOLUB')
    or public.current_app_role() not in ('admin'::public.app_role, 'management'::public.app_role)
  then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  select invoice.* into target_invoice
  from public.invoices invoice
  where invoice.id = target_invoice_id
  for update;

  if not found then
    raise exception 'Invoice not found' using errcode = 'P0002';
  end if;
  if target_invoice.status <> 'draft'::public.invoice_status then
    raise exception 'Only draft invoices can be issued' using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.invoice_items item where item.invoice_id = target_invoice_id
  ) then
    raise exception 'An invoice must contain at least one line' using errcode = '23514';
  end if;

  target_invoice_year := extract(year from target_invoice.invoice_date)::integer;
  insert into public.invoice_number_sequences (invoice_year, last_value)
  values (target_invoice_year, 1)
  on conflict (invoice_year) do update
  set last_value = public.invoice_number_sequences.last_value + 1
  returning last_value into next_value;

  update public.invoices invoice
  set invoice_number = format('FAC-%s-%s', target_invoice_year, lpad(next_value::text, 6, '0')),
      status = 'issued'::public.invoice_status,
      total = public.invoice_authoritative_total(target_invoice_id),
      issued_at = now(),
      updated_at = now()
  where invoice.id = target_invoice_id
  returning invoice.* into target_invoice;

  return target_invoice;
end;
$$;

comment on function public.issue_invoice(uuid) is
  'Atomically allocates the annual FAC invoice number and freezes the authoritative total.';

-- Verification query:
select
  to_regclass('public.invoice_number_sequences') as sequence_table,
  to_regprocedure('public.issue_invoice(uuid)') as issue_function;
