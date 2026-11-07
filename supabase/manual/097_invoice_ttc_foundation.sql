-- FACOLUB post-catalog patch - 097 invoice HT/TVA/TTC foundation
-- Additive compatibility migration. Existing issued totals are preserved.
-- Existing generic invoices.total becomes the compatibility alias for total_ttc.

begin;

create table if not exists public.invoice_tax_settings (
  singleton boolean primary key default true check (singleton),
  default_tax_rate numeric(7,4),
  updated_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invoice_tax_settings_rate check (
    default_tax_rate is null or default_tax_rate between 0 and 100
  )
);

insert into public.invoice_tax_settings (singleton, default_tax_rate)
values (true, null)
on conflict (singleton) do nothing;

alter table public.invoices add column if not exists subtotal_ht numeric(18,2);
alter table public.invoices add column if not exists tax_rate numeric(7,4);
alter table public.invoices add column if not exists tax_total numeric(18,2);
alter table public.invoices add column if not exists total_ttc numeric(18,2);

-- Preserve every historical final amount. A null tax_rate explicitly means
-- legacy/unspecified fiscal semantics; it is not silently presented as 0% TVA.
alter table public.invoices disable trigger invoices_protect_final;
alter table public.invoices disable trigger invoices_set_updated_at;
update public.invoices invoice
set subtotal_ht = coalesce(invoice.subtotal_ht, invoice.total),
    tax_total = coalesce(invoice.tax_total, 0),
    total_ttc = coalesce(invoice.total_ttc, invoice.total)
where invoice.subtotal_ht is null
   or invoice.tax_total is null
   or invoice.total_ttc is null;
alter table public.invoices enable trigger invoices_set_updated_at;
alter table public.invoices enable trigger invoices_protect_final;

alter table public.invoices alter column subtotal_ht set default 0;
alter table public.invoices alter column tax_total set default 0;
alter table public.invoices alter column total_ttc set default 0;
alter table public.invoices alter column subtotal_ht set not null;
alter table public.invoices alter column tax_total set not null;
alter table public.invoices alter column total_ttc set not null;

do $$
begin
  if not exists (select 1 from pg_constraint
    where conname = 'invoices_tax_rate_valid' and conrelid = 'public.invoices'::regclass) then
    alter table public.invoices add constraint invoices_tax_rate_valid check (
      tax_rate is null or tax_rate between 0 and 100
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint
    where conname = 'invoices_explicit_totals_nonnegative' and conrelid = 'public.invoices'::regclass) then
    alter table public.invoices add constraint invoices_explicit_totals_nonnegative check (
      subtotal_ht >= 0 and tax_total >= 0 and total_ttc >= 0
    ) not valid;
  end if;
end
$$;

drop trigger if exists invoice_tax_settings_set_updated_at on public.invoice_tax_settings;
create trigger invoice_tax_settings_set_updated_at
before update on public.invoice_tax_settings
for each row execute function public.set_updated_at();

alter table public.invoice_tax_settings enable row level security;
drop policy if exists invoice_tax_settings_manager_read on public.invoice_tax_settings;
create policy invoice_tax_settings_manager_read on public.invoice_tax_settings
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role)
);
revoke all on public.invoice_tax_settings from public, anon, authenticated;
grant select on public.invoice_tax_settings to authenticated;

comment on column public.invoice_items.unit_price is 'Authoritative unit price HT snapshot.';
comment on column public.invoice_items.line_total is 'Authoritative line HT: round(quantity * unit_price HT, 2).';
comment on column public.invoices.subtotal_ht is 'Authoritative sum of line HT totals.';
comment on column public.invoices.tax_rate is 'TVA percentage snapshot. Null only for legacy invoices with unspecified tax semantics.';
comment on column public.invoices.tax_total is 'Invoice-level TVA rounded to two decimals.';
comment on column public.invoices.total_ttc is 'Authoritative final TTC = subtotal_ht + tax_total.';
comment on column public.invoices.total is 'Compatibility alias maintained equal to total_ttc for new/updated drafts.';

commit;

select
  (select default_tax_rate from public.invoice_tax_settings where singleton) as configured_default_tax_rate,
  count(*) filter (where status = 'issued' and tax_rate is null) as preserved_legacy_issued_invoices,
  count(*) filter (where total_ttc <> total) as legacy_compatibility_mismatches
from public.invoices;
