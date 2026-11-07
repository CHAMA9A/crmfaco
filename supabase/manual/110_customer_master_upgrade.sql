-- SOMA FACOLUB customer CRM - 110 authoritative customer master
-- Run after 101_invoice_tva_recalculation_fix.sql.
-- Additive/idempotent: preserves every existing customer and document reference.

do $$ begin
  create type public.customer_price_category as enum (
    'intercompany', 'wholesale', 'retail', 'custom'
  );
exception when duplicate_object then null;
end $$;

alter table public.customers add column if not exists customer_code text;
alter table public.customers add column if not exists whatsapp text;
alter table public.customers add column if not exists if_number text;
alter table public.customers add column if not exists rc text;
alter table public.customers add column if not exists address_line1 text;
alter table public.customers add column if not exists address_line2 text;
alter table public.customers add column if not exists postal_code text;
alter table public.customers add column if not exists country text;
alter table public.customers add column if not exists default_price_category public.customer_price_category;
alter table public.customers add column if not exists notes text;
alter table public.customers add column if not exists default_delivery_address text;
alter table public.customers add column if not exists delivery_city text;
alter table public.customers add column if not exists delivery_contact_name text;
alter table public.customers add column if not exists delivery_phone text;
alter table public.customers add column if not exists delivery_instructions text;
alter table public.customers add column if not exists external_customer_id text;
alter table public.customers add column if not exists created_by uuid;

update public.customers
set address_line1 = nullif(trim(address), '')
where address_line1 is null and nullif(trim(address), '') is not null;

do $$ begin
  alter table public.customers add constraint customers_created_by_fkey
    foreign key (created_by) references public.profiles(id);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.customers add constraint customers_customer_code_format
    check (customer_code is null or customer_code ~ '^CLI-[0-9]{6,}$');
exception when duplicate_object then null;
end $$;

create unique index if not exists customers_customer_code_unique
  on public.customers (customer_code) where customer_code is not null;
create unique index if not exists customers_external_customer_id_unique
  on public.customers (external_customer_id) where external_customer_id is not null;
create index if not exists customers_ice_lookup_idx
  on public.customers (lower(trim(ice))) where nullif(trim(ice), '') is not null;
create index if not exists customers_contact_lookup_idx
  on public.customers (lower(contact_person));
create index if not exists customers_city_category_active_idx
  on public.customers (city, default_price_category, is_active);

create sequence if not exists public.customer_code_seq as bigint start with 1;

do $$
declare highest_code bigint;
begin
  select coalesce(max(substring(customer_code from 5)::bigint), 0)
  into highest_code
  from public.customers
  where customer_code ~ '^CLI-[0-9]{6,}$';
  if highest_code > 0 then
    perform setval('public.customer_code_seq', highest_code, true);
  end if;
end $$;

create table if not exists public.customer_notes (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  note text not null check (char_length(trim(note)) between 1 and 4000),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.customer_product_prices (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  product_format_id uuid not null references public.product_formats(id),
  unit_price_ht numeric(18,2) not null check (unit_price_ht >= 0),
  currency text not null default 'MAD' check (currency ~ '^[A-Z]{3}$'),
  is_active boolean not null default true,
  valid_from date,
  valid_to date,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customer_product_prices_dates check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create unique index if not exists customer_product_prices_active_unique
  on public.customer_product_prices (customer_id, product_format_id)
  where is_active and valid_to is null;
create index if not exists customer_notes_customer_date_idx
  on public.customer_notes (customer_id, created_at desc);
create index if not exists customer_product_prices_customer_idx
  on public.customer_product_prices (customer_id, is_active, product_format_id);

drop trigger if exists customer_product_prices_set_updated_at on public.customer_product_prices;
create trigger customer_product_prices_set_updated_at before update on public.customer_product_prices
for each row execute function public.set_updated_at();

comment on column public.customers.address is
  'Legacy compatibility field. New CRM writes mirror address_line1 here.';
comment on column public.customer_product_prices.unit_price_ht is
  'Customer-specific unit price excluding VAT. Invoice logic owns TVA/TTC.';

select count(*) as preserved_customer_count,
  count(*) filter (where address_line1 is not null) as customers_with_address,
  to_regclass('public.customer_notes') as notes_table,
  to_regclass('public.customer_product_prices') as custom_prices_table
from public.customers;
