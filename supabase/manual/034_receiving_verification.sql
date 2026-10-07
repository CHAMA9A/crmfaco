-- SOMA / FACOLUB receiving module - 034 rollback-only verification
-- Depends on: 020-024 and 030-033, plus one active FACOLUB user per role.
-- Creates test rows inside one transaction and always rolls back.

begin;

create temporary table receiving_test_context (
  admin_id uuid,
  management_id uuid,
  factory_id uuid,
  location_id uuid
) on commit drop;

insert into receiving_test_context
select
  (select profile.id from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id
   join public.environments environment on environment.id = access.environment_id
   where profile.role = 'admin' and profile.is_active and access.is_active
     and environment.is_active and environment.code = 'FACOLUB' limit 1),
  (select profile.id from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id
   join public.environments environment on environment.id = access.environment_id
   where profile.role = 'management' and profile.is_active and access.is_active
     and environment.is_active and environment.code = 'FACOLUB' limit 1),
  (select profile.id from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id
   join public.environments environment on environment.id = access.environment_id
   where profile.role = 'factory' and profile.is_active and access.is_active
     and environment.is_active and environment.code = 'FACOLUB' limit 1),
  (select id from public.stock_locations where code = 'FACOLUB-MAIN' and is_active);

create temporary table receiving_test_ids (
  item_id uuid,
  inactive_item_id uuid,
  supplier_id uuid,
  reservation_id uuid,
  receipt_id uuid,
  management_receipt_id uuid,
  attachment_id uuid,
  receipt_number text
) on commit drop;
insert into receiving_test_ids default values;

grant select, update on pg_temp.receiving_test_context, pg_temp.receiving_test_ids to authenticated;
do $$
declare temporary_schema_name text;
begin
  select nspname into temporary_schema_name from pg_namespace where oid = pg_my_temp_schema();
  execute format('grant usage on schema %I to authenticated', temporary_schema_name);
end
$$;

do $$
begin
  if exists (
    select 1 from receiving_test_context
    where admin_id is null or management_id is null or factory_id is null or location_id is null
  ) then
    raise exception 'Verification needs active FACOLUB Admin/Management/Factory users and FACOLUB-MAIN';
  end if;
end
$$;

-- Admin creates only rollback-scoped master data.
select set_config('request.jwt.claim.sub', (select admin_id::text from receiving_test_context), true);
set local role authenticated;
update receiving_test_ids set item_id = (
  select (public.save_stock_item(
    null, 'S2-ROLLBACK-ACTIVE', '[S2 ROLLBACK] RECEIVING ITEM',
    'empty_bottle'::public.stock_item_category, 'piece'::public.stock_unit,
    null, 25, 'Rollback-only receiving verification', true
  )).id
);
update receiving_test_ids set inactive_item_id = (
  select (public.save_stock_item(
    null, 'S2-ROLLBACK-INACTIVE', '[S2 ROLLBACK] INACTIVE ITEM',
    'other'::public.stock_item_category, 'piece'::public.stock_unit,
    null, null, 'Rollback-only receiving verification', false
  )).id
);
update receiving_test_ids set supplier_id = (
  select (public.save_supplier(
    null, '[S2 ROLLBACK] ABC Packaging', null, null, null, true
  )).id
);
reset role;

-- Establish physical 100 and reserved 40. Receiving must not touch the reservation.
select set_config('request.jwt.claim.sub', (select management_id::text from receiving_test_context), true);
set local role authenticated;
select * from public.record_stock_movement(
  (select item_id from receiving_test_ids),
  (select location_id from receiving_test_context),
  'opening_balance'::public.stock_movement_type,
  100,
  'in'::public.stock_direction,
  'receiving_verification',
  gen_random_uuid(),
  'Rollback opening balance'
);
update receiving_test_ids set reservation_id = (
  select (public.create_stock_reservation(
    (select item_id from receiving_test_ids),
    (select location_id from receiving_test_context),
    40,
    'receiving_verification',
    gen_random_uuid()
  )).id
);
update receiving_test_ids set management_receipt_id = (
  select (public.create_receipt_draft(
    current_date,
    (select location_id from receiving_test_context),
    null, 'Management-only draft', null, null
  )).id
);
reset role;

-- Factory can use the controlled receiving flow but cannot write the ledger directly.
select set_config('request.jwt.claim.sub', (select factory_id::text from receiving_test_context), true);
set local role authenticated;
do $$
begin
  perform public.record_stock_movement(
    (select item_id from receiving_test_ids),
    (select location_id from receiving_test_context),
    'receipt'::public.stock_movement_type,
    1,
    'in'::public.stock_direction,
    'arbitrary',
    gen_random_uuid(),
    'Must fail'
  );
  raise exception 'TEST FAILED G: Factory recorded an arbitrary movement';
exception when insufficient_privilege then null;
end
$$;
do $$
begin
  insert into public.stock_movements (
    stock_item_id, location_id, movement_type, quantity, direction, created_by
  ) values (
    (select item_id from receiving_test_ids),
    (select location_id from receiving_test_context),
    'receipt', 1, 'in', (select factory_id from receiving_test_context)
  );
  raise exception 'TEST FAILED G: Factory inserted directly into the movement ledger';
exception when insufficient_privilege then null;
end
$$;

update receiving_test_ids set receipt_id = (
  select (public.create_receipt_draft(
    current_date,
    (select location_id from receiving_test_context),
    (select supplier_id from receiving_test_ids),
    null,
    'BL-S2-ROLLBACK',
    'Rollback-only goods receiving test'
  )).id
);

-- Quantity and active-item rules are enforced at the RPC boundary.
do $$
begin
  perform public.add_receipt_item(
    (select receipt_id from receiving_test_ids),
    (select item_id from receiving_test_ids),
    0
  );
  raise exception 'TEST FAILED: zero receipt quantity was accepted';
exception when invalid_parameter_value then null;
end
$$;
do $$
begin
  perform public.add_receipt_item(
    (select receipt_id from receiving_test_ids),
    (select inactive_item_id from receiving_test_ids),
    1
  );
  raise exception 'TEST FAILED: inactive stock item was accepted';
exception when no_data_found then null;
end
$$;

select public.add_receipt_item(
  (select receipt_id from receiving_test_ids),
  (select item_id from receiving_test_ids),
  200
);

-- A draft has no movement and leaves 100 physical / 40 reserved / 60 available.
do $$
declare balance record;
begin
  if exists (
    select 1 from public.stock_movements movement
    where movement.reference_type = 'receipt'
      and movement.reference_id = (select receipt_id from receiving_test_ids)
  ) then
    raise exception 'TEST FAILED A: draft receipt changed stock';
  end if;
  select * into balance from public.get_stock_balance(
    (select item_id from receiving_test_ids),
    (select location_id from receiving_test_context)
  );
  if balance.physical_quantity <> 100
    or balance.reserved_quantity <> 40
    or balance.available_quantity <> 60 then
    raise exception 'TEST FAILED A: draft balance is %, %, %',
      balance.physical_quantity, balance.reserved_quantity, balance.available_quantity;
  end if;
end
$$;
reset role;

-- Metadata-only fixture: binary Storage uploads cannot be emulated safely in SQL.
-- attach_receipt_photo itself requires the object to exist in the private bucket.
with inserted_attachment as (
  insert into public.receipt_attachments (
    receipt_id, storage_path, file_name, mime_type, file_size, uploaded_by
  )
  select
    ids.receipt_id,
    ids.receipt_id::text || '/rollback-verification.jpg',
    'rollback-verification.jpg',
    'image/jpeg',
    1024,
    context.factory_id
  from receiving_test_ids ids cross join receiving_test_context context
  returning id
)
update receiving_test_ids
set attachment_id = (select id from inserted_attachment limit 1);

-- Confirming as Factory creates exactly one linked IN movement.
select set_config('request.jwt.claim.sub', (select factory_id::text from receiving_test_context), true);
set local role authenticated;
select public.confirm_receipt((select receipt_id from receiving_test_ids));
update receiving_test_ids
set receipt_number = (
  select receipt.receipt_number from public.receipts receipt
  where receipt.id = (select receipt_id from receiving_test_ids)
);

-- Retrying the exact confirmation is idempotent and returns the same receipt.
select public.confirm_receipt((select receipt_id from receiving_test_ids));

do $$
begin
  if (select count(*) from public.stock_movements movement
      where movement.reference_type = 'receipt'
        and movement.reference_id = (select receipt_id from receiving_test_ids)) <> 1 then
    raise exception 'TEST FAILED F: double confirmation duplicated stock';
  end if;
  if not exists (
    select 1 from public.receipts receipt
    where receipt.id = (select receipt_id from receiving_test_ids)
      and receipt.status = 'confirmed'::public.receipt_status
      and receipt.receipt_number = (select receipt_number from receiving_test_ids)
      and receipt.receipt_number ~ '^REC-[0-9]{6}-[0-9]{2,}$'
      and receipt.confirmed_by = (select factory_id from receiving_test_context)
  ) then
    raise exception 'TEST FAILED B: receipt confirmation metadata is incomplete';
  end if;
  if not exists (
    select 1 from public.list_receipts(
      null, null, null, (select item_id from receiving_test_ids), null,
      'confirmed'::public.receipt_status, (select receipt_number from receiving_test_ids), 10
    ) listed
    where listed.id = (select receipt_id from receiving_test_ids)
  ) then
    raise exception 'TEST FAILED: Factory cannot list its confirmed receipt';
  end if;
  if public.get_receipt((select receipt_id from receiving_test_ids)) is null then
    raise exception 'TEST FAILED: Factory cannot read its receipt detail';
  end if;
end
$$;

-- A Factory user cannot see a Management user's draft through RLS.
do $$
begin
  if exists (
    select 1 from public.receipts receipt
    where receipt.id = (select management_receipt_id from receiving_test_ids)
  ) then
    raise exception 'TEST FAILED J: Factory can read another user''s receipt';
  end if;
end
$$;

-- Confirmed receipts cannot be cancelled or deleted through authenticated access.
do $$
begin
  perform public.cancel_receipt((select receipt_id from receiving_test_ids));
  raise exception 'TEST FAILED H: confirmed receipt was cancelled';
exception when check_violation then null;
end
$$;
do $$
begin
  delete from public.receipts
  where id = (select receipt_id from receiving_test_ids);
  raise exception 'TEST FAILED H: Factory deleted a confirmed receipt';
exception when insufficient_privilege then null;
end
$$;
reset role;

-- Consolidated stock, reservation, traceability, and attachment assertions.
do $$
declare balance record;
begin
  select * into balance from public.stock_quantities(
    (select item_id from receiving_test_ids),
    (select location_id from receiving_test_context)
  );
  if balance.physical_quantity <> 300 then
    raise exception 'TEST FAILED B/C: physical should be 300, got %', balance.physical_quantity;
  end if;
  if balance.reserved_quantity <> 40 then
    raise exception 'TEST FAILED D: reserved should remain 40, got %', balance.reserved_quantity;
  end if;
  if balance.available_quantity <> 260 then
    raise exception 'TEST FAILED E: available should be 260, got %', balance.available_quantity;
  end if;
  if not exists (
    select 1
    from public.stock_movements movement
    join public.receipt_items line
      on line.id::text = movement.metadata ->> 'receipt_item_id'
    where movement.reference_type = 'receipt'
      and movement.reference_id = (select receipt_id from receiving_test_ids)
      and movement.stock_item_id = (select item_id from receiving_test_ids)
      and movement.movement_type = 'receipt'::public.stock_movement_type
      and movement.direction = 'in'::public.stock_direction
      and movement.quantity = 200
  ) then
    raise exception 'TEST FAILED: receipt movement does not reference receipt and line';
  end if;
  if not exists (
    select 1 from public.receipt_attachments attachment
    where attachment.id = (select attachment_id from receiving_test_ids)
      and attachment.receipt_id = (select receipt_id from receiving_test_ids)
  ) then
    raise exception 'TEST FAILED I: receipt photo metadata is no longer linked';
  end if;
end
$$;

-- Even the table owner cannot silently rewrite confirmed evidence/history.
do $$
begin
  delete from public.receipts
  where id = (select receipt_id from receiving_test_ids);
  raise exception 'TEST FAILED H: immutable trigger allowed confirmed receipt DELETE';
exception when object_not_in_prerequisite_state then null;
end
$$;
do $$
begin
  update public.receipt_items set quantity = quantity
  where receipt_id = (select receipt_id from receiving_test_ids);
  raise exception 'TEST FAILED H: confirmed receipt line was changed';
exception when object_not_in_prerequisite_state then null;
end
$$;
do $$
begin
  delete from public.receipt_attachments
  where id = (select attachment_id from receiving_test_ids);
  raise exception 'TEST FAILED I: confirmed receipt photo evidence was deleted';
exception when object_not_in_prerequisite_state then null;
end
$$;

-- Management can review all receipts.
select set_config('request.jwt.claim.sub', (select management_id::text from receiving_test_context), true);
set local role authenticated;
do $$
begin
  if not exists (
    select 1 from public.receipts receipt
    where receipt.id = (select receipt_id from receiving_test_ids)
  ) then
    raise exception 'TEST FAILED: Management cannot review Factory receiving';
  end if;
end
$$;
reset role;

-- An authenticated UUID without an active FACOLUB profile sees no receipt rows.
select set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
set local role authenticated;
do $$
begin
  if exists (select 1 from public.receipts) then
    raise exception 'TEST FAILED J: unauthorized authenticated user bypassed receipt RLS';
  end if;
end
$$;
reset role;

-- Storage is private and all four authenticated object policies exist.
do $$
begin
  if not exists (
    select 1 from storage.buckets bucket
    where bucket.id = 'facolub-receipts' and not bucket.public
      and bucket.file_size_limit = 8388608
  ) then
    raise exception 'TEST FAILED: facolub-receipts bucket is missing or public';
  end if;
  if (select count(*) from pg_policies policy
      where policy.schemaname = 'storage'
        and policy.tablename = 'objects'
        and policy.policyname in (
          'facolub_receipt_photos_select', 'facolub_receipt_photos_insert',
          'facolub_receipt_photos_update', 'facolub_receipt_photos_delete'
        )) <> 4 then
    raise exception 'TEST FAILED: private receipt photo policies are incomplete';
  end if;
end
$$;

select
  'PASS (transaction will roll back)' as result,
  ids.receipt_number,
  balance.physical_quantity,
  balance.reserved_quantity,
  balance.available_quantity,
  (select count(*) from public.stock_movements movement
   where movement.reference_type = 'receipt' and movement.reference_id = ids.receipt_id)
    as receipt_movement_count,
  (select count(*) from public.receipt_attachments attachment
   where attachment.receipt_id = ids.receipt_id) as linked_photo_count
from receiving_test_ids ids
cross join lateral public.stock_quantities(
  ids.item_id, (select location_id from receiving_test_context)
) balance;

rollback;

-- Optional true concurrency test in two SQL Editor tabs:
-- 1. Create one complete draft receipt and note its UUID.
-- 2. In tabs A and B, BEGIN and set the same authenticated Factory JWT claim.
-- 3. Call confirm_receipt(receipt_uuid) in both tabs before committing A.
-- 4. B waits on the receipt row lock; after A commits, B returns the same result.
-- 5. Exactly one receipt movement per line exists and stock changed only once.
