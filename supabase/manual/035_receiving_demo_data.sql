-- SOMA / FACOLUB - persistent demo data for Stock S1 + Receiving S2
-- Depends on: 020-024 and 030-033.
--
-- IMPORTANT:
-- - This script COMMITS visible demo data. It is not a rollback-only test.
-- - It is safe to run again: DEMO items, suppliers, stock seeds, reservations,
--   and receipts are reused instead of duplicated.
-- - Confirmed receipt photo rows are metadata-only placeholders. Use the draft
--   receipt in the app to test a real private Storage upload from a phone.

begin;

create temporary table receiving_demo_context (
  admin_id uuid,
  management_id uuid,
  factory_id uuid,
  location_id uuid
) on commit drop;

insert into receiving_demo_context
select
  (select profile.id
   from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id
   join public.environments environment on environment.id = access.environment_id
   where profile.role = 'admin' and profile.is_active and access.is_active
     and environment.is_active and environment.code = 'FACOLUB'
   order by profile.id limit 1),
  (select profile.id
   from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id
   join public.environments environment on environment.id = access.environment_id
   where profile.role = 'management' and profile.is_active and access.is_active
     and environment.is_active and environment.code = 'FACOLUB'
   order by profile.id limit 1),
  (select profile.id
   from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id
   join public.environments environment on environment.id = access.environment_id
   where profile.role = 'factory' and profile.is_active and access.is_active
     and environment.is_active and environment.code = 'FACOLUB'
   order by profile.id limit 1),
  (select location.id
   from public.stock_locations location
   where location.code = 'FACOLUB-MAIN' and location.is_active
   limit 1);

do $$
begin
  if exists (
    select 1
    from receiving_demo_context
    where admin_id is null
      or management_id is null
      or factory_id is null
      or location_id is null
  ) then
    raise exception
      'Demo data needs active FACOLUB Admin/Management/Factory users and FACOLUB-MAIN';
  end if;
end
$$;

create temporary table receiving_demo_items (
  code text primary key,
  id uuid
) on commit drop;

insert into receiving_demo_items (code) values
  ('DEMO-BTL-1L'),
  ('DEMO-LBL-1L'),
  ('DEMO-CAP-RED'),
  ('DEMO-CRT-12X1'),
  ('DEMO-BULK-15W40'),
  ('DEMO-PREP-1L'),
  ('DEMO-FIN-15W40-1L'),
  ('DEMO-ADD-VI'),
  ('DEMO-SPARE-PUMP');

create temporary table receiving_demo_suppliers (
  demo_key text primary key,
  id uuid
) on commit drop;

insert into receiving_demo_suppliers (demo_key) values
  ('packaging'),
  ('lubricants'),
  ('additives');

create temporary table receiving_demo_receipts (
  demo_key text primary key,
  reference text not null unique,
  actor_role text not null,
  intended_status public.receipt_status not null,
  id uuid,
  was_created boolean not null default false
) on commit drop;

insert into receiving_demo_receipts (
  demo_key, reference, actor_role, intended_status
) values
  ('management_confirmed', 'DEMO-BL-1001', 'management', 'confirmed'),
  ('factory_confirmed', 'DEMO-BL-1002', 'factory', 'confirmed'),
  ('factory_draft', 'DEMO-DRAFT-MOBILE', 'factory', 'draft'),
  ('management_cancelled', 'DEMO-CANCELLED-01', 'management', 'cancelled');

-- Authenticated test roles need access to the transaction-scoped ID tables.
grant select, insert, update on
  pg_temp.receiving_demo_context,
  pg_temp.receiving_demo_items,
  pg_temp.receiving_demo_suppliers,
  pg_temp.receiving_demo_receipts
to authenticated;

do $$
declare
  temporary_schema_name text;
begin
  select namespace.nspname
  into temporary_schema_name
  from pg_namespace namespace
  where namespace.oid = pg_my_temp_schema();

  execute format('grant usage on schema %I to authenticated', temporary_schema_name);
end
$$;

-- Admin creates or refreshes the isolated DEMO catalog.
select set_config(
  'request.jwt.claim.sub',
  (select admin_id::text from receiving_demo_context),
  true
);
set local role authenticated;

update receiving_demo_items set id = (
  select (public.save_stock_item(
    (select item.id from public.stock_items item where item.code = 'DEMO-BTL-1L'),
    'DEMO-BTL-1L', '[DEMO] Bouteille PET vide 1 L',
    'empty_bottle'::public.stock_item_category, 'piece'::public.stock_unit,
    null, 300, 'Jeu de demonstration FACOLUB', true
  )).id
) where code = 'DEMO-BTL-1L';

update receiving_demo_items set id = (
  select (public.save_stock_item(
    (select item.id from public.stock_items item where item.code = 'DEMO-LBL-1L'),
    'DEMO-LBL-1L', '[DEMO] Etiquette moteur 1 L',
    'label'::public.stock_item_category, 'piece'::public.stock_unit,
    null, 500, 'Jeu de demonstration FACOLUB', true
  )).id
) where code = 'DEMO-LBL-1L';

update receiving_demo_items set id = (
  select (public.save_stock_item(
    (select item.id from public.stock_items item where item.code = 'DEMO-CAP-RED'),
    'DEMO-CAP-RED', '[DEMO] Bouchon rouge avec joint',
    'seal'::public.stock_item_category, 'piece'::public.stock_unit,
    null, 400, 'Jeu de demonstration FACOLUB', true
  )).id
) where code = 'DEMO-CAP-RED';

update receiving_demo_items set id = (
  select (public.save_stock_item(
    (select item.id from public.stock_items item where item.code = 'DEMO-CRT-12X1'),
    'DEMO-CRT-12X1', '[DEMO] Carton 12 x 1 L',
    'carton'::public.stock_item_category, 'piece'::public.stock_unit,
    null, 100, 'Jeu de demonstration FACOLUB', true
  )).id
) where code = 'DEMO-CRT-12X1';

update receiving_demo_items set id = (
  select (public.save_stock_item(
    (select item.id from public.stock_items item where item.code = 'DEMO-BULK-15W40'),
    'DEMO-BULK-15W40', '[DEMO] Lubrifiant vrac 15W40',
    'bulk_lubricant'::public.stock_item_category, 'liter'::public.stock_unit,
    null, 250, 'Jeu de demonstration FACOLUB', true
  )).id
) where code = 'DEMO-BULK-15W40';

update receiving_demo_items set id = (
  select (public.save_stock_item(
    (select item.id from public.stock_items item where item.code = 'DEMO-PREP-1L'),
    'DEMO-PREP-1L', '[DEMO] Bouteille preparee 1 L',
    'prepared_bottle'::public.stock_item_category, 'piece'::public.stock_unit,
    null, 150, 'Jeu de demonstration FACOLUB', true
  )).id
) where code = 'DEMO-PREP-1L';

update receiving_demo_items set id = (
  select (public.save_stock_item(
    (select item.id from public.stock_items item where item.code = 'DEMO-FIN-15W40-1L'),
    'DEMO-FIN-15W40-1L', '[DEMO] Huile moteur 15W40 1 L',
    'finished_product'::public.stock_item_category, 'piece'::public.stock_unit,
    null, 100, 'Jeu de demonstration FACOLUB', true
  )).id
) where code = 'DEMO-FIN-15W40-1L';

update receiving_demo_items set id = (
  select (public.save_stock_item(
    (select item.id from public.stock_items item where item.code = 'DEMO-ADD-VI'),
    'DEMO-ADD-VI', '[DEMO] Additif ameliorant de viscosite',
    'other'::public.stock_item_category, 'kilogram'::public.stock_unit,
    null, 20, 'Jeu de demonstration FACOLUB', true
  )).id
) where code = 'DEMO-ADD-VI';

update receiving_demo_items set id = (
  select (public.save_stock_item(
    (select item.id from public.stock_items item where item.code = 'DEMO-SPARE-PUMP'),
    'DEMO-SPARE-PUMP', '[DEMO] Pompe de transvasement',
    'other'::public.stock_item_category, 'piece'::public.stock_unit,
    null, 20, 'Article volontairement sans stock pour tester l alerte', true
  )).id
) where code = 'DEMO-SPARE-PUMP';

update receiving_demo_suppliers set id = (
  select (public.save_supplier(
    (select supplier.id from public.suppliers supplier
     where supplier.name = '[DEMO] Emballages Atlas'
     order by supplier.id limit 1),
    '[DEMO] Emballages Atlas', '+212 5 22 00 10 10',
    'demo.emballages@example.com', 'Zone industrielle, Casablanca', true
  )).id
) where demo_key = 'packaging';

update receiving_demo_suppliers set id = (
  select (public.save_supplier(
    (select supplier.id from public.suppliers supplier
     where supplier.name = '[DEMO] Lubrifiants Maghreb'
     order by supplier.id limit 1),
    '[DEMO] Lubrifiants Maghreb', '+212 5 22 00 20 20',
    'demo.lubrifiants@example.com', 'Port industriel, Mohammedia', true
  )).id
) where demo_key = 'lubricants';

update receiving_demo_suppliers set id = (
  select (public.save_supplier(
    (select supplier.id from public.suppliers supplier
     where supplier.name = '[DEMO] Colorants et Additifs'
     order by supplier.id limit 1),
    '[DEMO] Colorants et Additifs', '+212 5 22 00 30 30',
    'demo.additifs@example.com', 'Parc industriel, Berrechid', true
  )).id
) where demo_key = 'additives';

reset role;

-- Management establishes persistent opening balances and one active reservation.
select set_config(
  'request.jwt.claim.sub',
  (select management_id::text from receiving_demo_context),
  true
);
set local role authenticated;

do $$
declare
  seed record;
  target_item_id uuid;
begin
  for seed in
    select * from (values
      ('DEMO-BTL-1L',       800::numeric, 'd0000000-0000-4000-8000-000000000001'::uuid),
      ('DEMO-LBL-1L',      1200::numeric, 'd0000000-0000-4000-8000-000000000002'::uuid),
      ('DEMO-CAP-RED',     1000::numeric, 'd0000000-0000-4000-8000-000000000003'::uuid),
      ('DEMO-CRT-12X1',     200::numeric, 'd0000000-0000-4000-8000-000000000004'::uuid),
      ('DEMO-BULK-15W40',   600::numeric, 'd0000000-0000-4000-8000-000000000005'::uuid),
      ('DEMO-PREP-1L',      250::numeric, 'd0000000-0000-4000-8000-000000000006'::uuid),
      ('DEMO-FIN-15W40-1L', 150::numeric, 'd0000000-0000-4000-8000-000000000007'::uuid),
      ('DEMO-ADD-VI',        80::numeric, 'd0000000-0000-4000-8000-000000000008'::uuid)
    ) as values_to_seed(code, quantity, reference_id)
  loop
    select item.id into target_item_id
    from receiving_demo_items item
    where item.code = seed.code;

    if not exists (
      select 1
      from public.stock_movements movement
      where movement.stock_item_id = target_item_id
        and movement.reference_type = 'facolub_demo_seed'
        and movement.reference_id = seed.reference_id
    ) then
      perform public.record_stock_movement(
        target_item_id,
        (select location_id from receiving_demo_context),
        'opening_balance'::public.stock_movement_type,
        seed.quantity,
        'in'::public.stock_direction,
        'facolub_demo_seed',
        seed.reference_id,
        'Solde initial fictif FACOLUB',
        jsonb_build_object('demo', true, 'source', '035_receiving_demo_data')
      );
    end if;
  end loop;
end
$$;

do $$
begin
  if not exists (
    select 1
    from public.stock_reservations reservation
    where reservation.reference_type = 'facolub_demo_reservation'
      and reservation.reference_id = 'd1000000-0000-4000-8000-000000000001'::uuid
  ) then
    perform public.create_stock_reservation(
      (select id from receiving_demo_items where code = 'DEMO-FIN-15W40-1L'),
      (select location_id from receiving_demo_context),
      120,
      'facolub_demo_reservation',
      'd1000000-0000-4000-8000-000000000001'::uuid
    );
  end if;
end
$$;

-- Reuse receipts from an earlier successful run.
update receiving_demo_receipts demo
set id = (
  select receipt.id
  from public.receipts receipt
  where receipt.reference = demo.reference
  order by receipt.created_at, receipt.id
  limit 1
);

-- One confirmed Management receipt.
with created as (
  select (public.create_receipt_draft(
    current_date - 5,
    (select location_id from receiving_demo_context),
    (select id from receiving_demo_suppliers where demo_key = 'packaging'),
    null,
    'DEMO-BL-1001',
    '[DEMO] Livraison emballages deja confirmee'
  )).id
  from receiving_demo_receipts demo
  where demo.demo_key = 'management_confirmed' and demo.id is null
)
update receiving_demo_receipts demo
set id = created.id, was_created = true
from created
where demo.demo_key = 'management_confirmed';

select public.add_receipt_item(receipt.id, item.id, 300, 1)
from receiving_demo_receipts receipt
join receiving_demo_items item on item.code = 'DEMO-BTL-1L'
where receipt.demo_key = 'management_confirmed' and receipt.was_created;

select public.add_receipt_item(receipt.id, item.id, 300, 2)
from receiving_demo_receipts receipt
join receiving_demo_items item on item.code = 'DEMO-LBL-1L'
where receipt.demo_key = 'management_confirmed' and receipt.was_created;

select public.add_receipt_item(receipt.id, item.id, 300, 3)
from receiving_demo_receipts receipt
join receiving_demo_items item on item.code = 'DEMO-CAP-RED'
where receipt.demo_key = 'management_confirmed' and receipt.was_created;

-- One cancelled receipt for history/status filtering.
with created as (
  select (public.create_receipt_draft(
    current_date - 1,
    (select location_id from receiving_demo_context),
    (select id from receiving_demo_suppliers where demo_key = 'packaging'),
    null,
    'DEMO-CANCELLED-01',
    '[DEMO] Livraison annulee avant confirmation'
  )).id
  from receiving_demo_receipts demo
  where demo.demo_key = 'management_cancelled' and demo.id is null
)
update receiving_demo_receipts demo
set id = created.id, was_created = true
from created
where demo.demo_key = 'management_cancelled';

select public.add_receipt_item(receipt.id, item.id, 100, 1)
from receiving_demo_receipts receipt
join receiving_demo_items item on item.code = 'DEMO-PREP-1L'
where receipt.demo_key = 'management_cancelled' and receipt.was_created;

select public.cancel_receipt(receipt.id)
from receiving_demo_receipts receipt
where receipt.demo_key = 'management_cancelled' and receipt.was_created;

reset role;

-- SQL cannot upload a real binary Storage object. This metadata-only evidence
-- lets the confirmed receipt exercise stock/history; its image preview will be
-- unavailable. The app-created draft below is the real photo-upload fixture.
insert into public.receipt_attachments (
  receipt_id, storage_path, file_name, mime_type, file_size, uploaded_by
)
select
  receipt.id,
  receipt.id::text || '/demo-placeholder.jpg',
  'demo-placeholder.jpg',
  'image/jpeg',
  1024,
  context.management_id
from receiving_demo_receipts receipt
cross join receiving_demo_context context
where receipt.demo_key = 'management_confirmed'
  and receipt.was_created;

select set_config(
  'request.jwt.claim.sub',
  (select management_id::text from receiving_demo_context),
  true
);
set local role authenticated;

select public.confirm_receipt(receipt.id)
from receiving_demo_receipts receipt
where receipt.demo_key = 'management_confirmed'
  and receipt.was_created;

reset role;

-- Factory gets one historical confirmed receipt and one editable mobile draft.
select set_config(
  'request.jwt.claim.sub',
  (select factory_id::text from receiving_demo_context),
  true
);
set local role authenticated;

-- A Factory user can only reuse its own existing receipts through RLS. The IDs
-- were already resolved above by the SQL Editor owner before switching roles.
with created as (
  select (public.create_receipt_draft(
    current_date - 2,
    (select location_id from receiving_demo_context),
    (select id from receiving_demo_suppliers where demo_key = 'lubricants'),
    null,
    'DEMO-BL-1002',
    '[DEMO] Livraison vrac deja confirmee'
  )).id
  from receiving_demo_receipts demo
  where demo.demo_key = 'factory_confirmed' and demo.id is null
)
update receiving_demo_receipts demo
set id = created.id, was_created = true
from created
where demo.demo_key = 'factory_confirmed';

select public.add_receipt_item(receipt.id, item.id, 250, 1)
from receiving_demo_receipts receipt
join receiving_demo_items item on item.code = 'DEMO-BULK-15W40'
where receipt.demo_key = 'factory_confirmed' and receipt.was_created;

select public.add_receipt_item(receipt.id, item.id, 40, 2)
from receiving_demo_receipts receipt
join receiving_demo_items item on item.code = 'DEMO-ADD-VI'
where receipt.demo_key = 'factory_confirmed' and receipt.was_created;

with created as (
  select (public.create_receipt_draft(
    current_date,
    (select location_id from receiving_demo_context),
    (select id from receiving_demo_suppliers where demo_key = 'packaging'),
    null,
    'DEMO-DRAFT-MOBILE',
    '[DEMO] Ouvrir dans l application, ajouter une vraie photo puis confirmer'
  )).id
  from receiving_demo_receipts demo
  where demo.demo_key = 'factory_draft' and demo.id is null
)
update receiving_demo_receipts demo
set id = created.id, was_created = true
from created
where demo.demo_key = 'factory_draft';

select public.add_receipt_item(receipt.id, item.id, 60, 1)
from receiving_demo_receipts receipt
join receiving_demo_items item on item.code = 'DEMO-CRT-12X1'
where receipt.demo_key = 'factory_draft' and receipt.was_created;

select public.add_receipt_item(receipt.id, item.id, 10, 2)
from receiving_demo_receipts receipt
join receiving_demo_items item on item.code = 'DEMO-SPARE-PUMP'
where receipt.demo_key = 'factory_draft' and receipt.was_created;

reset role;

insert into public.receipt_attachments (
  receipt_id, storage_path, file_name, mime_type, file_size, uploaded_by
)
select
  receipt.id,
  receipt.id::text || '/demo-placeholder.jpg',
  'demo-placeholder.jpg',
  'image/jpeg',
  1024,
  context.factory_id
from receiving_demo_receipts receipt
cross join receiving_demo_context context
where receipt.demo_key = 'factory_confirmed'
  and receipt.was_created;

select set_config(
  'request.jwt.claim.sub',
  (select factory_id::text from receiving_demo_context),
  true
);
set local role authenticated;

select public.confirm_receipt(receipt.id)
from receiving_demo_receipts receipt
where receipt.demo_key = 'factory_confirmed'
  and receipt.was_created;

reset role;

-- Compact result shown by the SQL Editor after a successful run.
select
  'DEMO DATA READY' as result,
  (select count(*) from receiving_demo_items) as demo_item_count,
  (select count(*) from receiving_demo_suppliers) as demo_supplier_count,
  (select count(*) from public.receipts receipt
   where receipt.reference like 'DEMO-%') as demo_receipt_count,
  (select count(*) from public.receipts receipt
   where receipt.reference like 'DEMO-%'
     and receipt.status = 'confirmed'::public.receipt_status) as confirmed_count,
  (select count(*) from public.receipts receipt
   where receipt.reference like 'DEMO-%'
     and receipt.status = 'draft'::public.receipt_status) as draft_count,
  (select count(*) from public.receipts receipt
   where receipt.reference like 'DEMO-%'
     and receipt.status = 'cancelled'::public.receipt_status) as cancelled_count,
  (select factory_id from receiving_demo_context) as factory_user_for_mobile_draft,
  (select profile.display_name
   from public.profiles profile
   where profile.id = (select factory_id from receiving_demo_context))
    as factory_user_name,
  (select id from receiving_demo_receipts where demo_key = 'factory_draft')
    as mobile_draft_receipt_id;

commit;
