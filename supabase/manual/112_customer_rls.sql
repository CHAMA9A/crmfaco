-- SOMA FACOLUB customer CRM - 112 strict CRM RLS and grants
-- Run after 111_customer_functions.sql. Idempotent.

alter table public.customers enable row level security;
alter table public.customer_notes enable row level security;
alter table public.customer_product_prices enable row level security;

drop policy if exists customers_management_select on public.customers;
create policy customers_management_select on public.customers for select to authenticated using (
  public.has_environment_access('FACOLUB') and public.current_app_role() in ('admin','management')
);
drop policy if exists customers_management_insert on public.customers;
drop policy if exists customers_management_update on public.customers;

drop policy if exists customer_notes_management_select on public.customer_notes;
create policy customer_notes_management_select on public.customer_notes for select to authenticated using (
  public.has_environment_access('FACOLUB') and public.current_app_role() in ('admin','management')
);
drop policy if exists customer_product_prices_management_select on public.customer_product_prices;
create policy customer_product_prices_management_select on public.customer_product_prices for select to authenticated using (
  public.has_environment_access('FACOLUB') and public.current_app_role() in ('admin','management')
);

revoke all on public.customers, public.customer_notes, public.customer_product_prices,
  public.customer_code_seq from public, anon, authenticated;
grant select on public.customers, public.customer_notes, public.customer_product_prices to authenticated;

select tablename, policyname, cmd, roles, qual from pg_policies
where schemaname='public' and tablename in ('customers','customer_notes','customer_product_prices')
order by tablename, policyname;
