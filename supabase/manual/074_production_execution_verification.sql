-- SOMA / FACOLUB production execution - 074 rollback-only verification
-- Depends on: 020-024, 040-043, 050-054, 056, and 060-073.
-- Requires active FACOLUB Admin, Management, and Factory users.

begin;

create temporary table execution_test_context (
  admin_id uuid, management_id uuid, factory_id uuid, location_id uuid,
  movements_before bigint
) on commit drop;
insert into execution_test_context (admin_id, management_id, factory_id, location_id)
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

create temporary table execution_test_ids (
  product_id uuid, product_format_id uuid, prepared_id uuid, oil_id uuid,
  seal_id uuid, carton_id uuid, output_id uuid, recipe_id uuid,
  plan_id uuid, plan_item_id uuid, execution_id uuid, execution_item_id uuid,
  blocked_plan_id uuid, blocked_item_id uuid, blocked_execution_id uuid,
  blocked_execution_item_id uuid, issue_id uuid
) on commit drop;
insert into execution_test_ids default values;
grant select, update on pg_temp.execution_test_context, pg_temp.execution_test_ids
  to authenticated;
do $$ declare temporary_schema_name text;
begin
  select nspname into temporary_schema_name from pg_namespace where oid = pg_my_temp_schema();
  execute format('grant usage on schema %I to authenticated', temporary_schema_name);
end $$;

do $$ begin
  if exists (select 1 from execution_test_context where admin_id is null
    or management_id is null or factory_id is null or location_id is null) then
    raise exception 'Verification needs active FACOLUB Admin/Management/Factory users and FACOLUB-MAIN';
  end if;
end $$;

-- Rollback-scoped catalog and the exact 5L recipe from the business example.
select set_config('request.jwt.claim.sub', (select admin_id::text from execution_test_context), true);
set local role authenticated;
update execution_test_ids set product_id = (select (public.save_planning_product(
  null, 'S6-ROLLBACK-10W40', '[S6 ROLLBACK] 10W40', true)).id);
update execution_test_ids set product_format_id = (select (public.save_product_format(
  null, (select product_id from execution_test_ids),
  (select id from public.packaging_formats where code = '5L'), true)).id);
select public.configure_packaging_rule(
  (select id from public.packaging_formats where code = '5L'), 4);
update execution_test_ids set prepared_id = (select (public.save_stock_item(
  null, 'S6-ROLLBACK-PREP-5L', '[S6 ROLLBACK] Prepared Bottle 5L',
  'prepared_bottle', 'piece', (select product_format_id from execution_test_ids),
  null, 'Rollback-only S6 verification', true)).id);
update execution_test_ids set oil_id = (select (public.save_stock_item(
  null, 'S6-ROLLBACK-OIL', '[S6 ROLLBACK] Bulk 10W40',
  'bulk_lubricant', 'liter', null, null, 'Rollback-only S6 verification', true)).id);
update execution_test_ids set seal_id = (select (public.save_stock_item(
  null, 'S6-ROLLBACK-SEAL', '[S6 ROLLBACK] Seal',
  'seal', 'piece', null, null, 'Rollback-only S6 verification', true)).id);
update execution_test_ids set carton_id = (select (public.save_stock_item(
  null, 'S6-ROLLBACK-CARTON', '[S6 ROLLBACK] Carton 5L',
  'carton', 'piece', null, null, 'Rollback-only S6 verification', true)).id);
update execution_test_ids set output_id = (select (public.save_stock_item(
  null, 'S6-ROLLBACK-FINISHED', '[S6 ROLLBACK] Finished 10W40 5L',
  'finished_product', 'piece', (select product_format_id from execution_test_ids),
  null, 'Rollback-only S6 verification', true)).id);
update execution_test_ids set recipe_id = (
  select (public.create_production_recipe(
    (select product_format_id from execution_test_ids),
    (select output_id from execution_test_ids),
    jsonb_build_array(
      jsonb_build_object('stock_item_id',(select prepared_id from execution_test_ids),
        'component_role','prepared_bottle','quantity_per_bottle',1),
      jsonb_build_object('stock_item_id',(select oil_id from execution_test_ids),
        'component_role','bulk_lubricant','quantity_per_bottle',5),
      jsonb_build_object('stock_item_id',(select seal_id from execution_test_ids),
        'component_role','seal','quantity_per_bottle',1),
      jsonb_build_object('stock_item_id',(select carton_id from execution_test_ids),
        'component_role','carton','quantity_per_bottle',1)
    ))) ->> 'id')::uuid;
reset role;

select set_config('request.jwt.claim.sub',
  (select management_id::text from execution_test_context), true);
set local role authenticated;
select public.record_stock_movement(item_id, (select location_id from execution_test_context),
  'opening_balance', quantity, 'in', 'production_execution_verification', gen_random_uuid(),
  'S6 rollback balance')
from (values
  ((select prepared_id from execution_test_ids), 500::numeric),
  ((select oil_id from execution_test_ids), 3000::numeric),
  ((select seal_id from execution_test_ids), 500::numeric),
  ((select carton_id from execution_test_ids), 200::numeric)
) opening(item_id, quantity);
update execution_test_context set movements_before = (select count(*) from public.stock_movements);

update execution_test_ids set plan_id = (select (public.create_production_plan_draft(
  current_date, (select location_id from execution_test_context), 1,
  (select factory_id from execution_test_context), 'S6 37-carton completion')).id);
update execution_test_ids set plan_item_id = (select (public.save_production_plan_item(
  (select plan_id from execution_test_ids), null,
  (select product_format_id from execution_test_ids), 40, 'cartons', 1)).id);
select public.validate_production_plan((select plan_id from execution_test_ids));
select public.reserve_production_plan((select plan_id from execution_test_ids));
reset role;

-- A/B/C: Factory creates one idempotent execution and starts it. Start creates
-- no movement and leaves every reservation active.
select set_config('request.jwt.claim.sub',
  (select factory_id::text from execution_test_context), true);
set local role authenticated;
update execution_test_ids set execution_id = (
  select (public.prepare_production_execution((select plan_id from execution_test_ids))
    -> 'execution' ->> 'id')::uuid);
select public.prepare_production_execution((select plan_id from execution_test_ids));
update execution_test_ids set execution_item_id = (select id
  from public.production_execution_items
  where production_execution_id = (select execution_id from execution_test_ids));
select public.start_production_execution((select execution_id from execution_test_ids));
select public.start_production_execution((select execution_id from execution_test_ids));

do $$ begin
  if (select count(*) from public.production_executions execution
      where execution.production_plan_id = (select plan_id from execution_test_ids)) <> 1 then
    raise exception 'TEST FAILED A: prepare was not idempotent';
  end if;
  if not exists (select 1 from public.production_executions execution
    where execution.id = (select execution_id from execution_test_ids)
      and execution.status = 'in_progress'
      and execution.started_by = (select factory_id from execution_test_context)) then
    raise exception 'TEST FAILED B: execution did not start correctly';
  end if;
  if (select count(*) from public.stock_movements)
      <> (select movements_before from execution_test_context) then
    raise exception 'TEST FAILED C: Start created stock movements';
  end if;
end $$;

-- Overproduction is rejected before any ledger write.
do $$ begin
  perform public.complete_production_execution(
    (select execution_id from execution_test_ids),
    jsonb_build_array(jsonb_build_object(
      'execution_item_id',(select execution_item_id from execution_test_ids),
      'quantity',41,'mode','cartons')), null);
  raise exception 'TEST FAILED: actual production above plan was accepted';
exception when check_violation then null;
end $$;
do $$ begin
  if (select count(*) from public.stock_movements)
      <> (select movements_before from execution_test_context) then
    raise exception 'TEST FAILED: rejected completion left partial movements';
  end if;
end $$;

-- D: authoritative preview normalizes 37 cartons to 148 bottles and uses the
-- immutable requirement snapshot for consumption/release.
do $$
declare preview jsonb;
begin
  preview := public.calculate_production_execution_completion(
    (select execution_id from execution_test_ids),
    jsonb_build_array(jsonb_build_object(
      'execution_item_id',(select execution_item_id from execution_test_ids),
      'quantity',37,'mode','cartons')));
  if (preview #>> '{items,0,actual_bottles}')::numeric <> 148
    or (preview #>> '{items,0,actual_cartons}')::numeric <> 37 then
    raise exception 'TEST FAILED D: actual quantity normalization is wrong';
  end if;
  if not exists (select 1 from jsonb_array_elements(preview #> '{items,0,materials}') material
    where material ->> 'name' = '[S6 ROLLBACK] Bulk 10W40'
      and (material ->> 'consumed_quantity')::numeric = 740
      and (material ->> 'released_quantity')::numeric = 60) then
    raise exception 'TEST FAILED D/E/F: bulk consumption preview is wrong';
  end if;
end $$;

select public.complete_production_execution(
  (select execution_id from execution_test_ids),
  jsonb_build_array(jsonb_build_object(
    'execution_item_id',(select execution_item_id from execution_test_ids),
    'quantity',37,'mode','cartons')), '37 cartons completed');
-- I: retry/double-click is idempotent.
select public.complete_production_execution(
  (select execution_id from execution_test_ids),
  jsonb_build_array(jsonb_build_object(
    'execution_item_id',(select execution_item_id from execution_test_ids),
    'quantity',37,'mode','cartons')), 'ignored retry');

-- E/F/G/H/I: exact consumption, unused release, output, lifecycle, balances,
-- and one canonical movement set.
do $$
declare balance record;
begin
  if (select count(*) from public.stock_movements movement
      where movement.reference_type = 'production_execution'
        and movement.reference_id = (select execution_id from execution_test_ids)) <> 5 then
    raise exception 'TEST FAILED E/G/I: expected four OUT and one IN movement';
  end if;
  if not exists (select 1 from public.stock_movements movement
    where movement.reference_id = (select execution_id from execution_test_ids)
      and movement.stock_item_id = (select oil_id from execution_test_ids)
      and movement.movement_type = 'production_consumption'
      and movement.direction = 'out' and movement.quantity = 740) then
    raise exception 'TEST FAILED E: bulk consumption is wrong';
  end if;
  if not exists (select 1 from public.stock_movements movement
    where movement.reference_id = (select execution_id from execution_test_ids)
      and movement.stock_item_id = (select output_id from execution_test_ids)
      and movement.movement_type = 'production_output'
      and movement.direction = 'in' and movement.quantity = 148) then
    raise exception 'TEST FAILED G: finished output is wrong';
  end if;
  if (select count(*) from public.production_reservation_resolutions resolution
      join public.production_execution_items item
        on item.id = resolution.production_execution_item_id
      where item.production_execution_id = (select execution_id from execution_test_ids)) <> 4 then
    raise exception 'TEST FAILED F: reservation resolution count is wrong';
  end if;
  if not exists (select 1 from public.production_reservation_resolutions resolution
    where resolution.stock_item_id = (select oil_id from execution_test_ids)
      and resolution.original_quantity = 800
      and resolution.consumed_quantity = 740
      and resolution.released_quantity = 60) then
    raise exception 'TEST FAILED E/F: bulk reservation resolution is wrong';
  end if;
  if exists (select 1 from public.stock_reservations reservation
    where reservation.reference_id = (select plan_id from execution_test_ids)
      and reservation.status = 'active') then
    raise exception 'TEST FAILED F: completed plan retained active reservations';
  end if;
  if not exists (select 1 from public.production_executions execution
    join public.production_execution_items item on item.production_execution_id = execution.id
    where execution.id = (select execution_id from execution_test_ids)
      and execution.status = 'done' and execution.completed_by = (select factory_id from execution_test_context)
      and item.actual_bottles = 148 and item.actual_cartons = 37) then
    raise exception 'TEST FAILED H: completed execution lifecycle is wrong';
  end if;
  select * into balance from public.get_stock_balance(
    (select prepared_id from execution_test_ids),(select location_id from execution_test_context));
  if balance.physical_quantity <> 352 or balance.reserved_quantity <> 0
    or balance.available_quantity <> 352 then
    raise exception 'TEST FAILED E/F: prepared-bottle balance is wrong';
  end if;
  select * into balance from public.get_stock_balance(
    (select output_id from execution_test_ids),(select location_id from execution_test_context));
  if balance.physical_quantity <> 148 or balance.available_quantity <> 148 then
    raise exception 'TEST FAILED G: finished-product balance is wrong';
  end if;
end $$;

-- Direct mutation remains prohibited for Factory.
do $$ begin
  update public.stock_movements set quantity = 999
  where reference_id = (select execution_id from execution_test_ids);
  raise exception 'TEST FAILED: Factory directly edited movements';
exception when insufficient_privilege then null;
end $$;
reset role;

-- Owner-side trigger proves Done item immutability independently of grants.
do $$ begin
  update public.production_execution_items set actual_bottles = 1
  where id = (select execution_item_id from execution_test_ids);
  raise exception 'TEST FAILED: Done execution item was mutable';
exception when object_not_in_prerequisite_state then null;
end $$;

-- J: a second reserved execution becomes Blocked without movements or release.
select set_config('request.jwt.claim.sub',
  (select management_id::text from execution_test_context), true);
set local role authenticated;
update execution_test_ids set blocked_plan_id = (select (public.create_production_plan_draft(
  current_date, (select location_id from execution_test_context), 2,
  (select factory_id from execution_test_context), 'S6 blocked execution')).id);
update execution_test_ids set blocked_item_id = (select (public.save_production_plan_item(
  (select blocked_plan_id from execution_test_ids), null,
  (select product_format_id from execution_test_ids), 1, 'cartons', 1)).id);
select public.validate_production_plan((select blocked_plan_id from execution_test_ids));
select public.reserve_production_plan((select blocked_plan_id from execution_test_ids));
reset role;

select set_config('request.jwt.claim.sub',
  (select factory_id::text from execution_test_context), true);
set local role authenticated;
update execution_test_ids set blocked_execution_id = (
  select (public.prepare_production_execution((select blocked_plan_id from execution_test_ids))
    -> 'execution' ->> 'id')::uuid);
update execution_test_ids set blocked_execution_item_id = (select id
  from public.production_execution_items
  where production_execution_id = (select blocked_execution_id from execution_test_ids));
select public.start_production_execution((select blocked_execution_id from execution_test_ids));
update execution_test_ids set issue_id = (
  select (public.report_production_issue(
    (select blocked_execution_id from execution_test_ids),
    'machine_issue','Rollback-only machine stop') -> 'issues' -> 0 ->> 'id')::uuid);

do $$ begin
  if not exists (select 1 from public.production_executions execution
    where execution.id = (select blocked_execution_id from execution_test_ids)
      and execution.status = 'blocked') then
    raise exception 'TEST FAILED J: execution was not blocked';
  end if;
  if exists (select 1 from public.stock_movements movement
    where movement.reference_type = 'production_execution'
      and movement.reference_id = (select blocked_execution_id from execution_test_ids)) then
    raise exception 'TEST FAILED J: blocked execution consumed or produced stock';
  end if;
  if not exists (select 1 from public.stock_reservations reservation
    where reservation.reference_id = (select blocked_plan_id from execution_test_ids)
      and reservation.status = 'active') then
    raise exception 'TEST FAILED J: blocked execution released reservations';
  end if;
end $$;
reset role;

-- Management resolves the traceable issue and resumes without touching stock.
select set_config('request.jwt.claim.sub',
  (select management_id::text from execution_test_context), true);
set local role authenticated;
select public.resolve_production_issue(
  (select issue_id from execution_test_ids), 'in_progress', 'Machine available again');
do $$ begin
  if not exists (select 1 from public.production_issues issue
    join public.production_executions execution on execution.id = issue.production_execution_id
    where issue.id = (select issue_id from execution_test_ids)
      and issue.resolved_by = (select management_id from execution_test_context)
      and issue.resolved_at is not null and execution.status = 'in_progress') then
    raise exception 'TEST FAILED J: Management did not resolve/resume the blocked execution';
  end if;
  if exists (select 1 from public.stock_movements movement
    where movement.reference_type = 'production_execution'
      and movement.reference_id = (select blocked_execution_id from execution_test_ids)) then
    raise exception 'TEST FAILED J: resolving an issue changed stock';
  end if;
end $$;
reset role;

-- Structural concurrency/atomicity assertion. Execution row, plan row,
-- reservation rows, and ordered stock resources are all transaction locks.
do $$ declare definition text;
begin
  select pg_get_functiondef(
    'public.complete_production_execution(uuid,jsonb,text)'::regprocedure) into definition;
  if position('for update' in lower(definition)) = 0
    or position('lock_stock_balance' in definition) = 0
    or position('order by locked.stock_item_id' in lower(definition)) = 0
    or position('production_reservation_resolutions' in definition) = 0 then
    raise exception 'TEST FAILED: completion lacks required transactional locks/resolution ledger';
  end if;
end $$;

select 'PASS: Production Execution S6 verification completed; transaction will be rolled back.'
  as result;
rollback;
