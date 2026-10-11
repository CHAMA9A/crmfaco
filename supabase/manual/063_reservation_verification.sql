-- SOMA / FACOLUB production reservations - 063 rollback-only verification
-- Depends on: 020-024, 040-043, 050-054, 056, and 060-062.
-- Requires one active FACOLUB Admin, Management, and Factory user.
-- Every fixture, plan, movement, and reservation is rolled back.

begin;

create temporary table reservation_test_context (
  admin_id uuid, management_id uuid, factory_id uuid, location_id uuid,
  movements_before bigint, reservations_before bigint
) on commit drop;
insert into reservation_test_context (admin_id, management_id, factory_id, location_id)
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

create temporary table reservation_test_ids (
  product_id uuid, product_format_id uuid, prepared_id uuid, oil_id uuid,
  seal_id uuid, carton_id uuid, output_id uuid, recipe_id uuid,
  plan_id uuid, plan_item_id uuid, blocked_plan_id uuid,
  blocked_plan_item_id uuid, external_reservation_id uuid
) on commit drop;
insert into reservation_test_ids default values;

grant select, update on pg_temp.reservation_test_context, pg_temp.reservation_test_ids
  to authenticated;
do $$
declare temporary_schema_name text;
begin
  select nspname into temporary_schema_name from pg_namespace where oid = pg_my_temp_schema();
  execute format('grant usage on schema %I to authenticated', temporary_schema_name);
end
$$;

do $$
begin
  if exists (select 1 from reservation_test_context
    where admin_id is null or management_id is null
      or factory_id is null or location_id is null) then
    raise exception 'Verification needs active FACOLUB Admin/Management/Factory users and FACOLUB-MAIN';
  end if;
end
$$;

-- Admin creates a rollback-scoped 5L catalog and a four-component recipe.
select set_config('request.jwt.claim.sub',
  (select admin_id::text from reservation_test_context), true);
set local role authenticated;

update reservation_test_ids set product_id = (select (public.save_planning_product(
  null, 'S5-ROLLBACK-10W40', '[S5 ROLLBACK] 10W40', true
)).id);
update reservation_test_ids set product_format_id = (select (public.save_product_format(
  null, (select product_id from reservation_test_ids),
  (select id from public.packaging_formats where code = '5L'), true
)).id);
select public.configure_packaging_rule(
  (select id from public.packaging_formats where code = '5L'), 4);

update reservation_test_ids set prepared_id = (select (public.save_stock_item(
  null, 'S5-ROLLBACK-PREP-5L', '[S5 ROLLBACK] Prepared Bottle 5L',
  'prepared_bottle', 'piece', (select product_format_id from reservation_test_ids),
  400, 'Rollback-only S5 verification', true
)).id);
update reservation_test_ids set oil_id = (select (public.save_stock_item(
  null, 'S5-ROLLBACK-OIL-10W40', '[S5 ROLLBACK] Bulk 10W40',
  'bulk_lubricant', 'liter', null, null, 'Rollback-only S5 verification', true
)).id);
update reservation_test_ids set seal_id = (select (public.save_stock_item(
  null, 'S5-ROLLBACK-SEAL', '[S5 ROLLBACK] Seal',
  'seal', 'piece', null, null, 'Rollback-only S5 verification', true
)).id);
update reservation_test_ids set carton_id = (select (public.save_stock_item(
  null, 'S5-ROLLBACK-CARTON-5L', '[S5 ROLLBACK] Carton 5L',
  'carton', 'piece', null, null, 'Rollback-only S5 verification', true
)).id);
update reservation_test_ids set output_id = (select (public.save_stock_item(
  null, 'S5-ROLLBACK-FINISHED-10W40-5L', '[S5 ROLLBACK] Finished 10W40 5L',
  'finished_product', 'piece', (select product_format_id from reservation_test_ids),
  null, 'Rollback-only S5 verification', true
)).id);

update reservation_test_ids set recipe_id = (
  select (public.create_production_recipe(
    (select product_format_id from reservation_test_ids),
    (select output_id from reservation_test_ids),
    jsonb_build_array(
      jsonb_build_object('stock_item_id', (select prepared_id from reservation_test_ids),
        'component_role', 'prepared_bottle', 'quantity_per_bottle', 1),
      jsonb_build_object('stock_item_id', (select oil_id from reservation_test_ids),
        'component_role', 'bulk_lubricant', 'quantity_per_bottle', 5),
      jsonb_build_object('stock_item_id', (select seal_id from reservation_test_ids),
        'component_role', 'seal', 'quantity_per_bottle', 1),
      jsonb_build_object('stock_item_id', (select carton_id from reservation_test_ids),
        'component_role', 'carton', 'quantity_per_bottle', 1)
    )
  )) ->> 'id'
)::uuid;
reset role;

-- Physical fixture and validated plan: 40 cartons = 160 bottles.
select set_config('request.jwt.claim.sub',
  (select management_id::text from reservation_test_context), true);
set local role authenticated;
select public.record_stock_movement(item_id,
  (select location_id from reservation_test_context),
  'opening_balance', quantity, 'in', 'production_reservation_verification',
  gen_random_uuid(), 'S5 rollback balance')
from (values
  ((select prepared_id from reservation_test_ids), 500::numeric),
  ((select oil_id from reservation_test_ids), 3000::numeric),
  ((select seal_id from reservation_test_ids), 500::numeric),
  ((select carton_id from reservation_test_ids), 200::numeric)
) opening(item_id, quantity);

update reservation_test_context set
  movements_before = (select count(*) from public.stock_movements),
  reservations_before = (select count(*) from public.stock_reservations);

update reservation_test_ids set plan_id = (select (public.create_production_plan_draft(
  current_date, (select location_id from reservation_test_context), 1,
  (select factory_id from reservation_test_context), 'S5 rollback reservation test'
)).id);
update reservation_test_ids set plan_item_id = (select (public.save_production_plan_item(
  (select plan_id from reservation_test_ids), null,
  (select product_format_id from reservation_test_ids), 40, 'cartons', 1
)).id);
select public.validate_production_plan((select plan_id from reservation_test_ids));
reset role;

-- A/B: validation produced the immutable source snapshot. A later recipe
-- change must not alter the quantities S5 reserves.
select set_config('request.jwt.claim.sub',
  (select admin_id::text from reservation_test_context), true);
set local role authenticated;
select public.update_production_recipe(
  (select recipe_id from reservation_test_ids), (select output_id from reservation_test_ids),
  jsonb_build_array(
    jsonb_build_object('stock_item_id', (select prepared_id from reservation_test_ids),
      'component_role', 'prepared_bottle', 'quantity_per_bottle', 1),
    jsonb_build_object('stock_item_id', (select oil_id from reservation_test_ids),
      'component_role', 'bulk_lubricant', 'quantity_per_bottle', 4.8),
    jsonb_build_object('stock_item_id', (select seal_id from reservation_test_ids),
      'component_role', 'seal', 'quantity_per_bottle', 1),
    jsonb_build_object('stock_item_id', (select carton_id from reservation_test_ids),
      'component_role', 'carton', 'quantity_per_bottle', 1)
  )
);
reset role;

-- C/D/E/F: Management reserves the complete snapshot atomically; retrying is
-- idempotent, physical stock is unchanged, and the minimum-stock warning uses
-- the new available quantity.
select set_config('request.jwt.claim.sub',
  (select management_id::text from reservation_test_context), true);
set local role authenticated;
select public.reserve_production_plan((select plan_id from reservation_test_ids));
select public.reserve_production_plan((select plan_id from reservation_test_ids));

do $$
declare balance record;
begin
  if not exists (select 1 from public.production_plans plan
    where plan.id = (select plan_id from reservation_test_ids)
      and plan.status = 'validated' and plan.reservation_status = 'reserved'
      and plan.reserved_by = (select management_id from reservation_test_context)
      and plan.reserved_at is not null) then
    raise exception 'TEST FAILED C: plan reservation lifecycle is wrong';
  end if;
  if (select count(*) from public.stock_reservations reservation
      where reservation.reference_type = 'production_plan'
        and reservation.reference_id = (select plan_id from reservation_test_ids)
        and reservation.status = 'active') <> 4 then
    raise exception 'TEST FAILED C/F: expected exactly four active reservations after retry';
  end if;
  if exists (select 1 from public.production_plan_requirements requirement
    where requirement.production_plan_item_id = (select plan_item_id from reservation_test_ids)
      and not exists (select 1 from public.stock_reservations reservation
        where reservation.production_plan_requirement_id = requirement.id
          and reservation.reference_id = (select plan_id from reservation_test_ids)
          and reservation.quantity = requirement.quantity_required
          and reservation.status = 'active')) then
    raise exception 'TEST FAILED B/C: a snapshot requirement was not reserved exactly';
  end if;
  if not exists (select 1 from public.stock_reservations reservation
    where reservation.reference_id = (select plan_id from reservation_test_ids)
      and reservation.stock_item_id = (select oil_id from reservation_test_ids)
      and reservation.quantity = 800 and reservation.status = 'active') then
    raise exception 'TEST FAILED B: reservation did not use the historical 800-liter snapshot';
  end if;
  select * into balance from public.get_stock_balance(
    (select prepared_id from reservation_test_ids),
    (select location_id from reservation_test_context));
  if balance.physical_quantity <> 500 or balance.reserved_quantity <> 160
    or balance.available_quantity <> 340 then
    raise exception 'TEST FAILED D: prepared-bottle physical/reserved/available balance is wrong';
  end if;
  if not exists (select 1 from public.stock_items item
    where item.id = (select prepared_id from reservation_test_ids)
      and item.minimum_stock = 400 and balance.available_quantity < item.minimum_stock) then
    raise exception 'TEST FAILED E: minimum-stock warning condition is wrong';
  end if;
  if (select count(*) from public.stock_movements)
      <> (select movements_before from reservation_test_context) then
    raise exception 'TEST FAILED D: reservation created a physical movement';
  end if;
end
$$;

-- Factory sees operational state only and cannot reserve or release.
reset role;
select set_config('request.jwt.claim.sub',
  (select factory_id::text from reservation_test_context), true);
set local role authenticated;
do $$
declare payload jsonb;
begin
  payload := public.get_production_plan_reservations((select plan_id from reservation_test_ids));
  if payload ->> 'reservation_status' <> 'reserved' or payload ? 'reservations' then
    raise exception 'TEST FAILED H: Factory operational reservation payload is wrong';
  end if;
end
$$;
do $$
begin
  perform public.reserve_production_plan((select plan_id from reservation_test_ids));
  raise exception 'TEST FAILED H: Factory reserved a plan';
exception when insufficient_privilege then null;
end
$$;
do $$
begin
  perform public.release_production_plan_reservations((select plan_id from reservation_test_ids));
  raise exception 'TEST FAILED H: Factory released a plan';
exception when insufficient_privilege then null;
end
$$;
reset role;

-- G: release is idempotent and restores available stock without movements.
select set_config('request.jwt.claim.sub',
  (select management_id::text from reservation_test_context), true);
set local role authenticated;
select public.release_production_plan_reservations((select plan_id from reservation_test_ids));
select public.release_production_plan_reservations((select plan_id from reservation_test_ids));
do $$
declare balance record;
begin
  select * into balance from public.get_stock_balance(
    (select oil_id from reservation_test_ids),
    (select location_id from reservation_test_context));
  if balance.physical_quantity <> 3000 or balance.reserved_quantity <> 0
    or balance.available_quantity <> 3000 then
    raise exception 'TEST FAILED G: release did not restore available stock';
  end if;
  if (select count(*) from public.stock_movements)
      <> (select movements_before from reservation_test_context) then
    raise exception 'TEST FAILED G: release created a physical movement';
  end if;
end
$$;
reset role;

-- H: Admin may reserve/release. Direct table mutation remains prohibited.
select set_config('request.jwt.claim.sub',
  (select admin_id::text from reservation_test_context), true);
set local role authenticated;
select public.reserve_production_plan((select plan_id from reservation_test_ids));
select public.release_production_plan_reservations((select plan_id from reservation_test_ids));
do $$
begin
  update public.stock_reservations set quantity = quantity + 1
  where reference_id = (select plan_id from reservation_test_ids);
  raise exception 'TEST FAILED H: authenticated user directly mutated reservations';
exception when insufficient_privilege then null;
end
$$;
reset role;

-- I: cancelling a reserved plan releases its complete set in the same
-- transaction. A second cancellation is harmless.
select set_config('request.jwt.claim.sub',
  (select management_id::text from reservation_test_context), true);
set local role authenticated;
select public.reserve_production_plan((select plan_id from reservation_test_ids));
select public.cancel_production_plan((select plan_id from reservation_test_ids));
select public.cancel_production_plan((select plan_id from reservation_test_ids));
do $$
begin
  if not exists (select 1 from public.production_plans plan
    where plan.id = (select plan_id from reservation_test_ids)
      and plan.status = 'cancelled' and plan.reservation_status = 'released'
      and plan.released_by = (select management_id from reservation_test_context)) then
    raise exception 'TEST FAILED I: cancellation lifecycle is wrong';
  end if;
  if exists (select 1 from public.stock_reservations reservation
    where reservation.reference_type = 'production_plan'
      and reservation.reference_id = (select plan_id from reservation_test_ids)
      and reservation.status = 'active') then
    raise exception 'TEST FAILED I: cancellation left active reservations';
  end if;
end
$$;

-- J: an unrelated reservation leaves only 50 seals available. Reserving the
-- second validated plan must fail without inserting even one partial row.
update reservation_test_ids set external_reservation_id = (select (public.create_stock_reservation(
  (select seal_id from reservation_test_ids),
  (select location_id from reservation_test_context), 450,
  'production_reservation_verification', gen_random_uuid()
)).id);
update reservation_test_ids set blocked_plan_id = (select (public.create_production_plan_draft(
  current_date, (select location_id from reservation_test_context), 2,
  (select factory_id from reservation_test_context), 'S5 must remain unreserved'
)).id);
update reservation_test_ids set blocked_plan_item_id = (select (public.save_production_plan_item(
  (select blocked_plan_id from reservation_test_ids), null,
  (select product_format_id from reservation_test_ids), 40, 'cartons', 1
)).id);
select public.validate_production_plan((select blocked_plan_id from reservation_test_ids));

do $$
begin
  perform public.reserve_production_plan((select blocked_plan_id from reservation_test_ids));
  raise exception 'TEST FAILED J: insufficient available stock did not block reservation';
exception when check_violation then
  if sqlerrm not like 'Insufficient available stock for %' then raise; end if;
end
$$;
do $$
begin
  if exists (select 1 from public.stock_reservations reservation
    where reservation.reference_type = 'production_plan'
      and reservation.reference_id = (select blocked_plan_id from reservation_test_ids)) then
    raise exception 'TEST FAILED J: failed reservation left partial rows';
  end if;
  if not exists (select 1 from public.production_plans plan
    where plan.id = (select blocked_plan_id from reservation_test_ids)
      and plan.status = 'validated' and plan.reservation_status = 'not_reserved') then
    raise exception 'TEST FAILED J: failed reservation changed plan state';
  end if;
  if (select count(*) from public.stock_movements)
      <> (select movements_before from reservation_test_context) then
    raise exception 'TEST FAILED J: S5 changed physical stock';
  end if;
  if (select count(*) from public.list_production_plan_reservation_history(
      (select plan_id from reservation_test_ids), 100)) <> 12 then
    raise exception 'TEST FAILED G/I: released reservation history is incomplete';
  end if;
end
$$;
reset role;

-- Structural concurrency proof. A live two-session test may reserve two plans
-- sharing scarce stock simultaneously; ordered shared balance locks allow only
-- one transaction to pass the aggregate availability check.
do $$
declare definition text;
begin
  select pg_get_functiondef('public.reserve_production_plan(uuid)'::regprocedure)
    into definition;
  if position('lock_stock_balance' in definition) = 0
    or position('order by requirement.component_stock_item_id' in lower(definition)) = 0
    or position('sum(requirement.quantity_required)' in lower(definition)) = 0 then
    raise exception 'TEST FAILED: reservation lacks ordered aggregate stock locking';
  end if;
  if position('record_stock_movement' in lower(definition)) > 0
    or position('insert into public.stock_movements' in lower(definition)) > 0 then
    raise exception 'TEST FAILED: reservation function contains physical stock mutation';
  end if;
end
$$;

select 'PASS: Production Reservations S5 verification completed; transaction will be rolled back.'
  as result;
rollback;
