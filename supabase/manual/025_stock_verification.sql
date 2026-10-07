-- SOMA / FACOLUB stock module - 025 rollback-only verification
-- Depends on: 020-024 and one active FACOLUB user for each role.
-- This script creates test rows inside a transaction and always rolls back.

begin;

create temporary table stock_test_context (
  admin_id uuid,
  management_id uuid,
  factory_id uuid,
  location_id uuid
) on commit drop;

insert into stock_test_context
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

create temporary table stock_test_ids (
  item_id uuid,
  inactive_item_id uuid,
  receipt_movement_id uuid,
  correction_movement_id uuid,
  reservation_id uuid,
  reservation_reference_id uuid default gen_random_uuid()
) on commit drop;
insert into stock_test_ids default values;

grant select, update on pg_temp.stock_test_context, pg_temp.stock_test_ids to authenticated;
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
    select 1 from stock_test_context
    where admin_id is null or management_id is null or factory_id is null or location_id is null
  ) then
    raise exception 'Verification needs active FACOLUB Admin/Management/Factory users and FACOLUB-MAIN';
  end if;
end
$$;

-- Admin configuration succeeds and minimum threshold data is retained.
select set_config('request.jwt.claim.sub', (select admin_id::text from stock_test_context), true);
set local role authenticated;
update stock_test_ids set item_id = (
  select (public.save_stock_item(
    null, 'S1-ROLLBACK-ACTIVE', '[S1 ROLLBACK] ACTIVE ITEM',
    'empty_bottle'::public.stock_item_category, 'piece'::public.stock_unit,
    null, 200, 'Rollback-only stock verification', true
  )).id
);
update stock_test_ids set inactive_item_id = (
  select (public.save_stock_item(
    null, 'S1-ROLLBACK-INACTIVE', '[S1 ROLLBACK] INACTIVE ITEM',
    'other'::public.stock_item_category, 'piece'::public.stock_unit,
    null, null, 'Rollback-only stock verification', false
  )).id
);
reset role;

-- Management can record valid operations through the trusted API.
select set_config('request.jwt.claim.sub', (select management_id::text from stock_test_context), true);
set local role authenticated;
update stock_test_ids set receipt_movement_id = (
  select movement_id from public.record_stock_movement(
    (select item_id from stock_test_ids),
    (select location_id from stock_test_context),
    'receipt'::public.stock_movement_type, 1000, 'in'::public.stock_direction,
    'verification', gen_random_uuid(), 'Rollback receipt'
  )
);
select * from public.record_stock_movement(
  (select item_id from stock_test_ids), (select location_id from stock_test_context),
  'production_consumption'::public.stock_movement_type, 200, 'out'::public.stock_direction,
  'verification', gen_random_uuid(), 'Rollback production consumption'
);
select * from public.record_stock_movement(
  (select item_id from stock_test_ids), (select location_id from stock_test_context),
  'damage'::public.stock_movement_type, 20, 'out'::public.stock_direction,
  'verification', gen_random_uuid(), 'Rollback damage'
);

-- Normal negative stock is rejected.
do $$
begin
  perform public.record_stock_movement(
    (select item_id from stock_test_ids), (select location_id from stock_test_context),
    'damage'::public.stock_movement_type, 781, 'out'::public.stock_direction,
    'verification', gen_random_uuid(), 'Must fail'
  );
  raise exception 'TEST FAILED: normal OUT allowed negative stock';
exception when check_violation then null;
end
$$;

-- Inactive stock items are rejected.
do $$
begin
  perform public.record_stock_movement(
    (select inactive_item_id from stock_test_ids), (select location_id from stock_test_context),
    'receipt'::public.stock_movement_type, 1, 'in'::public.stock_direction
  );
  raise exception 'TEST FAILED: inactive stock item accepted a movement';
exception when sqlstate 'P0002' then null;
end
$$;
reset role;

-- Only Admin can create a linked correction. The original remains unchanged.
select set_config('request.jwt.claim.sub', (select admin_id::text from stock_test_context), true);
set local role authenticated;
update stock_test_ids set correction_movement_id = (
  select movement_id from public.record_stock_correction(
    (select receipt_movement_id from stock_test_ids), 100, 'Rollback input error correction'
  )
);
reset role;

-- Management reserves 600 from physical 680, leaving available 80.
select set_config('request.jwt.claim.sub', (select management_id::text from stock_test_context), true);
set local role authenticated;
update stock_test_ids set reservation_id = (
  select (public.create_stock_reservation(
    (select item_id from stock_test_ids), (select location_id from stock_test_context),
    600, 'verification', (select reservation_reference_id from stock_test_ids)
  )).id
);

-- Overbooking and duplicate active references both fail at the database boundary.
do $$
begin
  perform public.create_stock_reservation(
    (select item_id from stock_test_ids), (select location_id from stock_test_context),
    81, 'verification-overbook', gen_random_uuid()
  );
  raise exception 'TEST FAILED: reservation overbooking was accepted';
exception when check_violation then null;
end
$$;
do $$
begin
  perform public.create_stock_reservation(
    (select item_id from stock_test_ids), (select location_id from stock_test_context),
    1, 'verification', (select reservation_reference_id from stock_test_ids)
  );
  raise exception 'TEST FAILED: duplicate active reservation was accepted';
exception when unique_violation then null;
end
$$;
reset role;

-- Factory can read safe quantities but cannot mutate the ledger or thresholds.
select set_config('request.jwt.claim.sub', (select factory_id::text from stock_test_context), true);
set local role authenticated;
do $$
begin
  if not exists (
    select 1 from public.stock_balances
    where stock_item_id = (select item_id from stock_test_ids)
  ) then
    raise exception 'TEST FAILED: Factory cannot read safe stock balances';
  end if;
end
$$;
do $$
begin
  perform public.record_stock_movement(
    (select item_id from stock_test_ids), (select location_id from stock_test_context),
    'receipt'::public.stock_movement_type, 1, 'in'::public.stock_direction
  );
  raise exception 'TEST FAILED: Factory recorded an arbitrary movement';
exception when insufficient_privilege then null;
end
$$;
do $$
begin
  update public.stock_items set minimum_stock = 0
  where id = (select item_id from stock_test_ids);
  raise exception 'TEST FAILED: Factory changed a threshold';
exception when insufficient_privilege then null;
end
$$;
do $$
begin
  update public.stock_movements set quantity = quantity
  where id = (select receipt_movement_id from stock_test_ids);
  raise exception 'TEST FAILED: authenticated user updated a confirmed movement';
exception when insufficient_privilege then null;
end
$$;
do $$
begin
  delete from public.stock_movements
  where id = (select receipt_movement_id from stock_test_ids);
  raise exception 'TEST FAILED: authenticated user deleted a confirmed movement';
exception when insufficient_privilege then null;
end
$$;
reset role;

-- Even the table owner cannot silently rewrite history without explicitly
-- disabling the immutable-ledger trigger.
do $$
begin
  update public.stock_movements set quantity = quantity
  where id = (select receipt_movement_id from stock_test_ids);
  raise exception 'TEST FAILED: immutable trigger allowed movement UPDATE';
exception when object_not_in_prerequisite_state then null;
end
$$;
do $$
begin
  delete from public.stock_movements
  where id = (select receipt_movement_id from stock_test_ids);
  raise exception 'TEST FAILED: immutable trigger allowed movement DELETE';
exception when object_not_in_prerequisite_state then null;
end
$$;

-- Consolidated A-E quantity/correction assertions and concurrency guard inspection.
do $$
declare
  balance record;
  original_quantity numeric;
begin
  select * into balance
  from public.stock_quantities(
    (select item_id from stock_test_ids), (select location_id from stock_test_context)
  );
  if balance.physical_quantity <> 680 then
    raise exception 'TEST FAILED A/B: physical should be 680, got %', balance.physical_quantity;
  end if;
  if balance.reserved_quantity <> 600 then
    raise exception 'TEST FAILED C: reserved should be 600, got %', balance.reserved_quantity;
  end if;
  if balance.available_quantity <> 80 then
    raise exception 'TEST FAILED D: available should be 80, got %', balance.available_quantity;
  end if;
  select quantity into original_quantity from public.stock_movements
  where id = (select receipt_movement_id from stock_test_ids);
  if original_quantity <> 1000 or not exists (
    select 1 from public.stock_movements
    where id = (select correction_movement_id from stock_test_ids)
      and corrected_movement_id = (select receipt_movement_id from stock_test_ids)
      and direction = 'out'::public.stock_direction and quantity = 100
  ) then
    raise exception 'TEST FAILED E: correction did not preserve/link the original';
  end if;
  if pg_get_functiondef('public.record_stock_movement(uuid,uuid,public.stock_movement_type,numeric,public.stock_direction,text,uuid,text,jsonb,boolean)'::regprocedure)
       not like '%lock_stock_balance%'
    or pg_get_functiondef('public.create_stock_reservation(uuid,uuid,numeric,text,uuid)'::regprocedure)
       not like '%lock_stock_balance%' then
    raise exception 'TEST FAILED J: movement/reservation functions do not share the balance lock';
  end if;
end
$$;

select
  'PASS (transaction will roll back)' as result,
  balance.physical_quantity,
  balance.reserved_quantity,
  balance.available_quantity,
  item.minimum_stock,
  (select count(*) from public.stock_movements movement
   where movement.stock_item_id = item.id) as immutable_ledger_rows
from stock_test_ids ids
join public.stock_items item on item.id = ids.item_id
cross join lateral public.stock_quantities(
  ids.item_id, (select location_id from stock_test_context)
) balance;

rollback;

-- True simultaneous-session reservation test (manual, optional):
-- 1. Create an item with physical 100 and note its item/location UUIDs.
-- 2. In SQL Editor tabs A and B: BEGIN; set the same authenticated Management JWT.
-- 3. In A reserve 70 and leave the transaction open.
-- 4. In B reserve 70. B must wait on the advisory transaction lock.
-- 5. COMMIT A. B must then fail with "Reservation exceeds available stock".
-- The rollback suite above verifies both callers use the same lock and that duplicate/overbook checks fail.
