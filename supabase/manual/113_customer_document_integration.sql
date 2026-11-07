-- SOMA FACOLUB customer CRM - 113 document snapshot and delivery integration
-- Run after 112_customer_rls.sql. Additive/idempotent; final document values stay immutable.

alter table public.orders add column if not exists customer_if_snapshot text;
alter table public.orders add column if not exists customer_rc_snapshot text;
alter table public.invoices add column if not exists customer_if_snapshot text;
alter table public.invoices add column if not exists customer_rc_snapshot text;

create or replace function public.apply_customer_defaults_to_order()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c public.customers;
begin
  if tg_op = 'UPDATE' and new.customer_id = old.customer_id then return new; end if;
  select * into c from public.customers where id = new.customer_id and is_active;
  if not found then raise exception 'Active customer not found' using errcode = 'P0002'; end if;
  new.purchase_order := coalesce(new.purchase_order, c.purchase_order_default);
  new.destination_city := coalesce(new.destination_city, c.delivery_city, c.city);
  new.destination_address := coalesce(new.destination_address, c.default_delivery_address,
    c.address_line1, c.address);
  return new;
end;
$$;

drop trigger if exists orders_apply_customer_defaults on public.orders;
create trigger orders_apply_customer_defaults before insert or update of customer_id on public.orders
for each row execute function public.apply_customer_defaults_to_order();

create or replace function public.snapshot_customer_on_order_confirmation()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c public.customers;
begin
  if old.status = 'draft' and new.status <> 'draft' then
    select * into c from public.customers where id = new.customer_id;
    new.customer_name_snapshot := c.company_name;
    new.customer_city_snapshot := c.city;
    new.customer_address_snapshot := coalesce(c.address_line1, c.address);
    new.customer_ice_snapshot := c.ice;
    new.customer_if_snapshot := c.if_number;
    new.customer_rc_snapshot := c.rc;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_snapshot_customer_crm on public.orders;
create trigger orders_snapshot_customer_crm before update of status on public.orders
for each row execute function public.snapshot_customer_on_order_confirmation();

create or replace function public.protect_order_legal_snapshots()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if old.status <> 'draft'::public.order_status and (
    new.customer_if_snapshot is distinct from old.customer_if_snapshot
    or new.customer_rc_snapshot is distinct from old.customer_rc_snapshot
  ) then
    raise exception 'Confirmed order customer snapshots are immutable' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_protect_legal_snapshots on public.orders;
create trigger orders_protect_legal_snapshots before update on public.orders
for each row execute function public.protect_order_legal_snapshots();

create or replace function public.snapshot_customer_on_invoice_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c public.customers;
begin
  select * into c from public.customers where id = new.customer_id;
  if not found then raise exception 'Customer not found' using errcode = 'P0002'; end if;
  new.customer_name_snapshot := c.company_name;
  new.customer_city_snapshot := c.city;
  new.customer_address_snapshot := coalesce(c.address_line1, c.address);
  new.customer_ice_snapshot := c.ice;
  new.customer_if_snapshot := c.if_number;
  new.customer_rc_snapshot := c.rc;
  return new;
end;
$$;

drop trigger if exists invoices_snapshot_customer_crm on public.invoices;
create trigger invoices_snapshot_customer_crm before insert on public.invoices
for each row execute function public.snapshot_customer_on_invoice_insert();

comment on trigger invoices_snapshot_customer_crm on public.invoices is
  'Copies current CRM identity once; later customer edits never rewrite invoice snapshots.';

select
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='invoices' and column_name='customer_if_snapshot') as invoice_if_snapshot,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='customer_rc_snapshot') as order_rc_snapshot;
