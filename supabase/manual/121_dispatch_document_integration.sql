-- SOMA / FACOLUB S8 dispatch - 121 partial-delivery BL/BT integration
-- Run after 120_dispatch_storage_rls.sql. Historical documents are preserved.

alter table public.delivery_notes add column if not exists dispatch_id uuid;
alter table public.transport_notes add column if not exists dispatch_id uuid;
do $$ begin alter table public.delivery_notes add constraint delivery_notes_dispatch_id_fkey
  foreign key(dispatch_id) references public.dispatches(id) on delete restrict;
exception when duplicate_object then null; end $$;
do $$ begin alter table public.transport_notes add constraint transport_notes_dispatch_id_fkey
  foreign key(dispatch_id) references public.dispatches(id) on delete restrict;
exception when duplicate_object then null; end $$;

do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid='public.delivery_notes'::regclass and contype='u'
    and conkey=array[(select attnum from pg_attribute where attrelid='public.delivery_notes'::regclass and attname='order_id')]
  loop execute format('alter table public.delivery_notes drop constraint %I',c.conname); end loop;
  for c in select conname from pg_constraint where conrelid='public.transport_notes'::regclass and contype='u'
    and conkey=array[(select attnum from pg_attribute where attrelid='public.transport_notes'::regclass and attname='order_id')]
  loop execute format('alter table public.transport_notes drop constraint %I',c.conname); end loop;
end $$;
drop index if exists public.delivery_notes_order_id_key;
drop index if exists public.transport_notes_order_id_key;
create unique index if not exists delivery_notes_dispatch_unique on public.delivery_notes(dispatch_id) where dispatch_id is not null;
create unique index if not exists transport_notes_dispatch_unique on public.transport_notes(dispatch_id) where dispatch_id is not null;
create index if not exists delivery_notes_order_idx on public.delivery_notes(order_id,created_at);
create index if not exists transport_notes_order_idx on public.transport_notes(order_id,created_at);

create table if not exists public.shipping_document_number_sequences (
  document_date date primary key,
  last_value bigint not null check(last_value > 0)
);
alter table public.shipping_document_number_sequences enable row level security;
revoke all on public.shipping_document_number_sequences from public,anon,authenticated;

-- Seed the new counter above every preserved BL/BT suffix for each date.
insert into public.shipping_document_number_sequences(document_date,last_value)
select to_date(substring(number_value from 4 for 6),'YYMMDD'),
  max(substring(number_value from 11)::bigint)
from (
  select delivery_note_number number_value from public.delivery_notes
  where delivery_note_number ~ '^BL-[0-9]{6}-[0-9]{2,}$'
  union all
  select transport_note_number from public.transport_notes
  where transport_note_number ~ '^BT-[0-9]{6}-[0-9]{2,}$'
) historical
group by to_date(substring(number_value from 4 for 6),'YYMMDD')
on conflict(document_date) do update
set last_value=greatest(public.shipping_document_number_sequences.last_value,excluded.last_value);

create or replace function public.allocate_shipping_document_reference(target_date date)
returns text language plpgsql security definer set search_path='' as $$
declare next_value bigint;
begin
  if target_date is null then raise exception 'Shipping document date is required' using errcode='22023'; end if;
  insert into public.shipping_document_number_sequences(document_date,last_value) values(target_date,1)
  on conflict(document_date) do update set last_value=public.shipping_document_number_sequences.last_value+1
  returning last_value into next_value;
  return format('%s-%s',to_char(target_date,'YYMMDD'),lpad(next_value::text,2,'0'));
end $$;
revoke all on function public.allocate_shipping_document_reference(date) from public,anon,authenticated;

create table if not exists public.delivery_note_items (
  id uuid primary key default gen_random_uuid(), delivery_note_id uuid not null references public.delivery_notes(id) on delete restrict,
  dispatch_item_id uuid references public.dispatch_items(id) on delete restrict, sku_snapshot text not null,
  description_snapshot text not null, quantity numeric(18,3) not null check(quantity>0), position integer not null default 0,
  created_at timestamptz not null default now(), unique(delivery_note_id,dispatch_item_id)
);
create table if not exists public.transport_note_items (
  id uuid primary key default gen_random_uuid(), transport_note_id uuid not null references public.transport_notes(id) on delete restrict,
  dispatch_item_id uuid references public.dispatch_items(id) on delete restrict, sku_snapshot text not null,
  description_snapshot text not null, quantity numeric(18,3) not null check(quantity>0), position integer not null default 0,
  created_at timestamptz not null default now(), unique(transport_note_id,dispatch_item_id)
);
alter table public.delivery_note_items enable row level security;
alter table public.transport_note_items enable row level security;
revoke all on public.delivery_note_items,public.transport_note_items from public,anon,authenticated;
create policy delivery_note_items_management_read on public.delivery_note_items for select to authenticated using(
  public.has_environment_access('FACOLUB') and public.current_app_role() in ('admin','management'));
create policy transport_note_items_management_read on public.transport_note_items for select to authenticated using(
  public.has_environment_access('FACOLUB') and public.current_app_role() in ('admin','management'));
grant select on public.delivery_note_items,public.transport_note_items to authenticated;

create or replace function public.prepare_dispatch_documents(target_dispatch_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.dispatches; bl public.delivery_notes; bt public.transport_notes; ref text;
begin
  perform public.assert_order_document_manager();
  select * into d from public.dispatches where id=target_dispatch_id and status='confirmed' for update;
  if not found or d.order_id is null then raise exception 'Confirmed customer dispatch not found' using errcode='P0002'; end if;
  select * into bl from public.delivery_notes where dispatch_id=d.id;
  select * into bt from public.transport_notes where dispatch_id=d.id;
  if bl.id is not null and bt.id is not null then
    return jsonb_build_object('delivery_note_id',bl.id,'transport_note_id',bt.id);
  end if;
  ref:=public.allocate_shipping_document_reference(d.dispatch_date);
  insert into public.delivery_notes(order_id,dispatch_id,delivery_note_number,delivery_date,prepared_for,object,
    handover_date,transport_reception_name,status)
  values(d.order_id,d.id,'BL-'||ref,d.dispatch_date,d.destination_name,'acheminement de marchandises',
    d.dispatch_date,d.delivery_contact_snapshot,'draft')
  on conflict(dispatch_id) where dispatch_id is not null do nothing;
  select * into bl from public.delivery_notes where dispatch_id=d.id;
  insert into public.transport_notes(order_id,dispatch_id,transport_note_number,transport_date,transport_person,sender,
    pickup_date,loading_location,destination,vehicle_registration,status)
  values(d.order_id,d.id,'BT-'||ref,d.dispatch_date,d.driver_name,'SOMA LUBRIFIANTS',d.dispatch_date,'CASABLANCA',
    concat_ws(', ',d.delivery_address_snapshot,d.delivery_city_snapshot),d.vehicle_registration,'draft')
  on conflict(dispatch_id) where dispatch_id is not null do nothing;
  select * into bt from public.transport_notes where dispatch_id=d.id;
  insert into public.delivery_note_items(delivery_note_id,dispatch_item_id,sku_snapshot,description_snapshot,quantity,position)
    select bl.id,i.id,i.sku_snapshot,i.description_snapshot,i.quantity_loaded,
      (row_number() over(order by i.created_at,i.id)-1)::integer from public.dispatch_items i where i.dispatch_id=d.id
    on conflict do nothing;
  insert into public.transport_note_items(transport_note_id,dispatch_item_id,sku_snapshot,description_snapshot,quantity,position)
    select bt.id,i.id,i.sku_snapshot,i.description_snapshot,i.quantity_loaded,
      (row_number() over(order by i.created_at,i.id)-1)::integer from public.dispatch_items i where i.dispatch_id=d.id
    on conflict do nothing;
  return jsonb_build_object('delivery_note_id',bl.id,'transport_note_id',bt.id);
end $$;

-- Order confirmation continues to prepare the invoice only. BL/BT now require a confirmed dispatch.
create or replace function public.prepare_document_bundle(target_order_id uuid)
returns public.orders language plpgsql security definer set search_path='' as $$
declare target_order public.orders; target_invoice_id uuid;
begin
  perform public.assert_order_document_manager();
  select * into target_order from public.orders where id=target_order_id for update;
  if not found then raise exception 'Order not found' using errcode='P0002'; end if;
  if target_order.status in ('draft','cancelled') then raise exception 'Order must be confirmed first' using errcode='23514'; end if;
  insert into public.invoices(order_id,invoice_number,invoice_date,customer_id,purchase_order,
    customer_name_snapshot,customer_city_snapshot,customer_address_snapshot,customer_ice_snapshot,status,currency,created_by)
  values(target_order.id,'FAC-'||target_order.order_reference,target_order.order_date,target_order.customer_id,
    target_order.purchase_order,target_order.customer_name_snapshot,target_order.customer_city_snapshot,
    target_order.customer_address_snapshot,target_order.customer_ice_snapshot,'draft','MAD',auth.uid()) on conflict do nothing;
  select id into target_invoice_id from public.invoices where order_id=target_order.id;
  insert into public.invoice_items(invoice_id,order_item_id,description,quantity,unit_price,position)
    select target_invoice_id,oi.id,oi.description,oi.quantity,0,oi.position from public.order_items oi
    where oi.order_id=target_order.id and not exists(select 1 from public.invoice_items ii
      where ii.invoice_id=target_invoice_id and ii.order_item_id=oi.id);
  if target_order.status='confirmed' then update public.orders set status='documents_ready' where id=target_order.id returning * into target_order; end if;
  return target_order;
end $$;

create or replace function public.refresh_order_document_status(target_order_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if exists(select 1 from public.invoices i where i.order_id=target_order_id and i.status='issued')
    and not exists(select 1 from public.get_order_dispatch_remaining(target_order_id))
    and not exists(select 1 from public.dispatches d where d.order_id=target_order_id and d.status='confirmed'
      and (not exists(select 1 from public.delivery_notes bl where bl.dispatch_id=d.id and bl.status='issued')
        or not exists(select 1 from public.transport_notes bt where bt.dispatch_id=d.id and bt.status='issued'))) then
    update public.orders set status='completed' where id=target_order_id and status<>'cancelled';
  end if;
end $$;

revoke all on function public.prepare_dispatch_documents(uuid) from public,anon;
grant execute on function public.prepare_dispatch_documents(uuid) to authenticated;
comment on column public.delivery_notes.dispatch_id is 'Null for preserved pre-S8 documents; populated for S8 dispatch documents.';
comment on table public.delivery_note_items is 'Immutable actual-quantity snapshots from one confirmed physical dispatch.';

select count(*) filter(where dispatch_id is null) as preserved_legacy_bl,
  count(*) filter(where dispatch_id is not null) as dispatch_bl from public.delivery_notes;
