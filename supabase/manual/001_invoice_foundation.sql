-- SOMA invoice module - 001 foundation
-- Run in Supabase SQL Editor.
-- Safe to run once: yes.
-- Idempotent: yes for the schema defined here (CREATE IF NOT EXISTS / CREATE OR REPLACE).
-- Depends on: the existing FACOLUB auth foundation (public.profiles).

create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.invoice_status as enum ('draft', 'issued', 'cancelled');
exception
  when duplicate_object then null;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  company_name text not null check (char_length(trim(company_name)) > 0),
  contact_person text,
  phone text,
  email text,
  city text,
  address text,
  ice text,
  purchase_order_default text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text unique,
  invoice_date date not null,
  customer_id uuid not null references public.customers(id),
  purchase_order text,
  customer_name_snapshot text not null,
  customer_city_snapshot text,
  customer_address_snapshot text,
  customer_ice_snapshot text,
  status public.invoice_status not null default 'draft',
  currency text not null default 'MAD',
  total numeric(18, 2) not null default 0 check (total >= 0),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  issued_at timestamptz,
  cancelled_at timestamptz
);

create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  description text not null check (char_length(trim(description)) > 0),
  quantity numeric(18, 3) not null check (quantity > 0),
  unit_price numeric(18, 2) not null check (unit_price >= 0),
  line_total numeric(18, 2) generated always as (round(quantity * unit_price, 2)) stored,
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists customers_company_name_idx
  on public.customers (company_name);
create index if not exists invoices_customer_date_idx
  on public.invoices (customer_id, invoice_date desc);
create index if not exists invoices_status_date_idx
  on public.invoices (status, invoice_date desc);
create index if not exists invoice_items_invoice_position_idx
  on public.invoice_items (invoice_id, position, created_at);

drop trigger if exists customers_set_updated_at on public.customers;
create trigger customers_set_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

drop trigger if exists invoices_set_updated_at on public.invoices;
create trigger invoices_set_updated_at
before update on public.invoices
for each row execute function public.set_updated_at();

-- Verification query:
select
  to_regclass('public.customers') as customers_table,
  to_regclass('public.invoices') as invoices_table,
  to_regclass('public.invoice_items') as invoice_items_table,
  exists (
    select 1 from pg_type where typnamespace = 'public'::regnamespace and typname = 'invoice_status'
  ) as invoice_status_exists;
