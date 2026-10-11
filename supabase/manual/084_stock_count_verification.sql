-- SOMA / FACOLUB stock counts - 084 rollback-only verification
-- Depends on: 020-024 and 080-083.
-- Requires active FACOLUB Admin, Management, and Factory users.

begin;

create temporary table count_test_context (
  admin_id uuid, management_id uuid, factory_id uuid, location_id uuid,
  movements_before bigint
) on commit drop;
insert into count_test_context (admin_id, management_id, factory_id, location_id)
select
  (select profile.id from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id and access.is_active
   join public.environments environment on environment.id = access.environment_id and environment.is_active
   where profile.role = 'admin' and profile.is_active and environment.code = 'FACOLUB' limit 1),
  (select profile.id from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id and access.is_active
   join public.environments environment on environment.id = access.environment_id and environment.is_active
   where profile.role = 'management' and profile.is_active and environment.code = 'FACOLUB' limit 1),
  (select profile.id from public.profiles profile
   join public.user_environment_access access on access.user_id = profile.id and access.is_active
   join public.environments environment on environment.id = access.environment_id and environment.is_active
   where profile.role = 'factory' and profile.is_active and environment.code = 'FACOLUB' limit 1),
  (select id from public.stock_locations where code = 'FACOLUB-MAIN' and is_active);

create temporary table count_test_ids (
  item_id uuid, opening_movement_id uuid, reservation_id uuid,
  count_id uuid, count_item_id uuid, zero_count_id uuid, zero_item_id uuid,
  positive_count_id uuid, positive_item_id uuid,
  stale_count_id uuid, stale_item_id uuid,
  loss_adjustment_id uuid, damage_adjustment_id uuid,
  correction_adjustment_id uuid, shortage_adjustment_id uuid
) on commit drop;
insert into count_test_ids default values;
grant select, update on pg_temp.count_test_context, pg_temp.count_test_ids to authenticated;
do $$ declare temporary_schema_name text;
begin
  select nspname into temporary_schema_name from pg_namespace where oid = pg_my_temp_schema();
  execute format('grant usage on schema %I to authenticated', temporary_schema_name);
end $$;

do $$ begin
  if exists (select 1 from count_test_context where admin_id is null
    or management_id is null or factory_id is null or location_id is null) then
    raise exception 'Verification needs active FACOLUB Admin/Management/Factory users and FACOLUB-MAIN';
  end if;
end $$;

-- Rollback-scoped catalog item.
select set_config('request.jwt.claim.sub', (select admin_id::text from count_test_context), true);
set local role authenticated;
update count_test_ids set item_id = (select (public.save_stock_item(
  null, 'S7-ROLLBACK-EMPTY-5L', '[S7 ROLLBACK] Empty Bottle 5L',
  'empty_bottle', 'piece', null, null, 'Rollback-only S7 verification', true
)).id);
reset role;

-- Initial physical 1,000; reserved 700; available 300.
select set_config('request.jwt.claim.sub', (select management_id::text from count_test_context), true);
set local role authenticated;
update count_test_ids set opening_movement_id = (select movement_id
  from public.record_stock_movement(
    (select item_id from count_test_ids), (select location_id from count_test_context),
    'opening_balance', 1000, 'in', 'stock_count_verification', gen_random_uuid(),
    'S7 rollback opening balance'));
update count_test_ids set reservation_id = (select (public.create_stock_reservation(
  (select item_id from count_test_ids), (select location_id from count_test_context),
  700, 'stock_count_verification', gen_random_uuid())).id);
update count_test_context set movements_before = (select count(*) from public.stock_movements);
reset role;

-- A/B/C: Factory draft snapshots PHYSICAL 1,000, calculates -20 server-side,
-- creates no movement, and receives a safe official number only on submission.
select set_config('request.jwt.claim.sub', (select factory_id::text from count_test_context), true);
set local role authenticated;
update count_test_ids set count_id = (select (public.create_stock_count_draft(
  (select location_id from count_test_context), current_date, 'S7 980 physical count')).id);
update count_test_ids set count_item_id = (select (public.add_stock_count_item(
  (select count_id from count_test_ids), (select item_id from count_test_ids), 1)).id);
select public.update_counted_quantity((select count_item_id from count_test_ids), 980,
  'Twenty bottles missing');
do $$ begin
  if not exists (select 1 from public.stock_count_items line
    where line.id = (select count_item_id from count_test_ids)
      and line.expected_physical_quantity = 1000
      and line.counted_quantity = 980 and line.difference_quantity = -20) then
    raise exception 'TEST FAILED A/C: physical snapshot or difference is wrong';
  end if;
  if (select count(*) from public.stock_movements)
      <> (select movements_before from count_test_context) then
    raise exception 'TEST FAILED A: draft count changed physical stock';
  end if;
end $$;
select public.submit_stock_count((select count_id from count_test_ids));
do $$ begin
  if not exists (select 1 from public.stock_counts count
    where count.id = (select count_id from count_test_ids)
      and count.status = 'submitted'
      and count.count_number ~ ('^CNT-' || to_char(current_date,'DDMMYY') || '-[0-9]{2,}$')) then
    raise exception 'TEST FAILED B: count submission or numbering is wrong';
  end if;
end $$;

-- H: Factory can submit but cannot approve.
do $$ begin
  perform public.approve_stock_count((select count_id from count_test_ids));
  raise exception 'TEST FAILED H: Factory approved a stock count';
exception when insufficient_privilege then null;
end $$;
reset role;

-- D/E/F: Management approval atomically posts adjustment_out 20. Reservation
-- remains 700 and approval retry is idempotent.
select set_config('request.jwt.claim.sub', (select management_id::text from count_test_context), true);
set local role authenticated;
select public.approve_stock_count((select count_id from count_test_ids));
select public.approve_stock_count((select count_id from count_test_ids));
do $$ declare balance record;
begin
  if (select count(*) from public.stock_movements movement
    where movement.reference_type = 'stock_adjustment'
      and movement.reference_id = (select adjustment.id from public.stock_adjustments adjustment
        where adjustment.stock_count_item_id = (select count_item_id from count_test_ids))) <> 1 then
    raise exception 'TEST FAILED D: approval retry duplicated the movement';
  end if;
  if not exists (select 1 from public.stock_adjustments adjustment
    join public.stock_movements movement on movement.id = adjustment.stock_movement_id
    where adjustment.stock_count_item_id = (select count_item_id from count_test_ids)
      and adjustment.status = 'posted' and adjustment.difference_quantity = -20
      and movement.movement_type = 'adjustment_out' and movement.direction = 'out'
      and movement.quantity = 20) then
    raise exception 'TEST FAILED D: negative difference was not posted correctly';
  end if;
  select * into balance from public.get_stock_balance(
    (select item_id from count_test_ids), (select location_id from count_test_context));
  if balance.physical_quantity <> 980 or balance.reserved_quantity <> 700
    or balance.available_quantity <> 280 then
    raise exception 'TEST FAILED E/F: physical/reserved/available balance is wrong';
  end if;
end $$;
reset role;

-- G: zero difference is retained as evidence with no adjustment or movement.
select set_config('request.jwt.claim.sub', (select factory_id::text from count_test_context), true);
set local role authenticated;
update count_test_ids set zero_count_id = (select (public.create_stock_count_draft(
  (select location_id from count_test_context), current_date, 'Zero difference')).id);
update count_test_ids set zero_item_id = (select (public.add_stock_count_item(
  (select zero_count_id from count_test_ids), (select item_id from count_test_ids), 1)).id);
select public.update_counted_quantity((select zero_item_id from count_test_ids), 980, null);
select public.submit_stock_count((select zero_count_id from count_test_ids));
reset role;
select set_config('request.jwt.claim.sub', (select management_id::text from count_test_context), true);
set local role authenticated;
select public.approve_stock_count((select zero_count_id from count_test_ids));
do $$ begin
  if exists (select 1 from public.stock_adjustments adjustment
    where adjustment.stock_count_item_id = (select zero_item_id from count_test_ids)) then
    raise exception 'TEST FAILED G: zero difference created an adjustment';
  end if;
end $$;
reset role;

-- I: a movement after snapshot makes the count stale; approval leaves no
-- partial adjustment and the submitted state is retained.
select set_config('request.jwt.claim.sub', (select factory_id::text from count_test_context), true);
set local role authenticated;
update count_test_ids set stale_count_id = (select (public.create_stock_count_draft(
  (select location_id from count_test_context), current_date, 'Must become stale')).id);
update count_test_ids set stale_item_id = (select (public.add_stock_count_item(
  (select stale_count_id from count_test_ids), (select item_id from count_test_ids), 1)).id);
select public.update_counted_quantity((select stale_item_id from count_test_ids), 970, null);
select public.submit_stock_count((select stale_count_id from count_test_ids));
reset role;
select set_config('request.jwt.claim.sub', (select management_id::text from count_test_context), true);
set local role authenticated;
select public.record_stock_movement(
  (select item_id from count_test_ids), (select location_id from count_test_context),
  'adjustment_in', 1, 'in', 'stock_count_verification', gen_random_uuid(),
  'Intervening movement for stale-count proof');
do $$ begin
  perform public.approve_stock_count((select stale_count_id from count_test_ids));
  raise exception 'TEST FAILED I: stale count was approved';
exception when object_not_in_prerequisite_state then
  if sqlerrm not like 'Stock changed after count started%' then raise; end if;
end $$;
do $$ begin
  if exists (select 1 from public.stock_adjustments adjustment
    where adjustment.stock_count_item_id = (select stale_item_id from count_test_ids)) then
    raise exception 'TEST FAILED I: stale approval left an adjustment';
  end if;
  if not exists (select 1 from public.stock_counts count
    where count.id = (select stale_count_id from count_test_ids) and count.status = 'submitted') then
    raise exception 'TEST FAILED I: stale approval changed count state';
  end if;
end $$;
reset role;

-- Loss and damage reports remain pending until Management approval.
select set_config('request.jwt.claim.sub', (select factory_id::text from count_test_context), true);
set local role authenticated;
update count_test_ids set loss_adjustment_id = (select (public.report_stock_loss(
  (select item_id from count_test_ids), (select location_id from count_test_context),
  10, 'Lost during handling')).id);
update count_test_ids set damage_adjustment_id = (select (public.report_stock_damage(
  (select item_id from count_test_ids), (select location_id from count_test_context),
  5, 'Damaged bottles')).id);
do $$ begin
  perform public.approve_stock_adjustment((select loss_adjustment_id from count_test_ids));
  raise exception 'TEST FAILED: Factory approved a loss';
exception when insufficient_privilege then null;
end $$;
reset role;
select set_config('request.jwt.claim.sub', (select management_id::text from count_test_context), true);
set local role authenticated;
select public.approve_stock_adjustment((select loss_adjustment_id from count_test_ids));
select public.approve_stock_adjustment((select loss_adjustment_id from count_test_ids));
select public.approve_stock_adjustment((select damage_adjustment_id from count_test_ids));
do $$ begin
  if (select count(*) from public.stock_movements movement
    where movement.reference_id = (select loss_adjustment_id from count_test_ids)
      and movement.movement_type = 'loss' and movement.quantity = 10) <> 1 then
    raise exception 'TEST FAILED: approved loss movement is missing or duplicated';
  end if;
  if not exists (select 1 from public.stock_movements movement
    where movement.reference_id = (select damage_adjustment_id from count_test_ids)
      and movement.movement_type = 'damage' and movement.quantity = 5) then
    raise exception 'TEST FAILED: approved damage movement is missing';
  end if;
end $$;
reset role;

-- J: correction reverses but never edits the original movement.
select set_config('request.jwt.claim.sub', (select factory_id::text from count_test_context), true);
set local role authenticated;
update count_test_ids set correction_adjustment_id = (select (public.request_stock_correction(
  (select opening_movement_id from count_test_ids), 1, 'Opening quantity input error')).id);
reset role;
select set_config('request.jwt.claim.sub', (select management_id::text from count_test_context), true);
set local role authenticated;
select public.approve_stock_adjustment((select correction_adjustment_id from count_test_ids));
do $$ begin
  if not exists (select 1 from public.stock_movements movement
    where movement.reference_id = (select correction_adjustment_id from count_test_ids)
      and movement.movement_type = 'correction' and movement.direction = 'out'
      and movement.quantity = 1
      and movement.corrected_movement_id = (select opening_movement_id from count_test_ids)) then
    raise exception 'TEST FAILED J: correction linkage is wrong';
  end if;
  if not exists (select 1 from public.stock_movements movement
    where movement.id = (select opening_movement_id from count_test_ids)
      and movement.quantity = 1000 and movement.direction = 'in') then
    raise exception 'TEST FAILED J: original movement was rewritten';
  end if;
end $$;
reset role;

-- Reservation shortage is flagged but reservations remain untouched.
select set_config('request.jwt.claim.sub', (select factory_id::text from count_test_context), true);
set local role authenticated;
update count_test_ids set shortage_adjustment_id = (select (public.report_stock_loss(
  (select item_id from count_test_ids), (select location_id from count_test_context),
  300, 'Rollback-only shortage warning')).id);
reset role;
select set_config('request.jwt.claim.sub', (select management_id::text from count_test_context), true);
set local role authenticated;
do $$ declare payload jsonb; balance record;
begin
  payload := public.approve_stock_adjustment((select shortage_adjustment_id from count_test_ids));
  if not (payload ->> 'reservation_shortage')::boolean then
    raise exception 'TEST FAILED: over-reserved warning was not returned';
  end if;
  select * into balance from public.get_stock_balance(
    (select item_id from count_test_ids), (select location_id from count_test_context));
  if balance.reserved_quantity <> 700 or balance.physical_quantity >= balance.reserved_quantity
    or balance.available_quantity >= 0 then
    raise exception 'TEST FAILED: reservation shortage quantities are wrong';
  end if;
end $$;

-- Positive count difference produces adjustment_in.
reset role;
select set_config('request.jwt.claim.sub', (select factory_id::text from count_test_context), true);
set local role authenticated;
update count_test_ids set positive_count_id = (select (public.create_stock_count_draft(
  (select location_id from count_test_context), current_date, 'Positive difference')).id);
update count_test_ids set positive_item_id = (select (public.add_stock_count_item(
  (select positive_count_id from count_test_ids), (select item_id from count_test_ids), 1)).id);
select public.update_counted_quantity(
  (select positive_item_id from count_test_ids),
  (select expected_physical_quantity + 5 from public.stock_count_items
    where id = (select positive_item_id from count_test_ids)),
  null
);
select public.submit_stock_count((select positive_count_id from count_test_ids));
reset role;
select set_config('request.jwt.claim.sub', (select management_id::text from count_test_context), true);
set local role authenticated;
select public.approve_stock_count((select positive_count_id from count_test_ids));
do $$ begin
  if not exists (select 1 from public.stock_adjustments adjustment
    join public.stock_movements movement on movement.id = adjustment.stock_movement_id
    where adjustment.stock_count_item_id = (select positive_item_id from count_test_ids)
      and adjustment.difference_quantity = 5
      and movement.movement_type = 'adjustment_in' and movement.direction = 'in'
      and movement.quantity = 5) then
    raise exception 'TEST FAILED: positive difference was not posted as adjustment_in';
  end if;
end $$;
reset role;

-- Direct movement and applied-adjustment mutation remain prohibited.
select set_config('request.jwt.claim.sub', (select factory_id::text from count_test_context), true);
set local role authenticated;
do $$ begin
  update public.stock_movements set quantity = 999
  where id = (select opening_movement_id from count_test_ids);
  raise exception 'TEST FAILED: Factory directly edited movement history';
exception when insufficient_privilege then null;
end $$;
reset role;
do $$ begin
  update public.stock_adjustments set reason = 'ILLEGAL'
  where id = (select loss_adjustment_id from count_test_ids);
  raise exception 'TEST FAILED: posted adjustment was mutable';
exception when object_not_in_prerequisite_state then null;
end $$;

-- Structural concurrency proof: count approval takes ordered shared balance
-- locks before stale checks/writes and standalone approval uses the same lock.
do $$ declare definition text;
begin
  definition := pg_get_functiondef('public.approve_stock_count(uuid)'::regprocedure);
  if position('lock_stock_balance' in definition) = 0
    or position('order by candidate.stock_item_id' in lower(definition)) = 0
    or position('snapshot_movement_count <>' in lower(definition)) = 0 then
    raise exception 'TEST FAILED: count approval lacks ordered locks or stale detection';
  end if;
  definition := pg_get_functiondef(
    'public.apply_stock_adjustment_internal(uuid,uuid)'::regprocedure);
  if position('lock_stock_balance' in definition) = 0
    or position('reservation_shortage' in definition) = 0 then
    raise exception 'TEST FAILED: adjustment approval lacks stock locking or shortage warning';
  end if;
end $$;

select 'PASS: Stock Counts S7 verification completed; transaction will be rolled back.' as result;
rollback;
