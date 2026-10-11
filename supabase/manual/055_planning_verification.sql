-- SOMA / FACOLUB production planning module - 055 rollback-only verification
-- Depends on: 020-024, 030-033, 040-043, and 050-054.
-- Requires one active FACOLUB Admin, Management, and Factory user.
-- Every catalog row, stock fixture, plan, recipe, and movement is rolled back.

begin;

create temporary table planning_test_context (
  admin_id uuid, management_id uuid, factory_id uuid, location_id uuid,
  movements_before bigint, reservations_before bigint
) on commit drop;
insert into planning_test_context (admin_id, management_id, factory_id, location_id)
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

create temporary table planning_test_ids (
  product_id uuid, product_format_1l_id uuid, product_format_2l_id uuid,
  product_format_5l_id uuid, prepared_id uuid, oil_id uuid, seal_id uuid,
  carton_id uuid, output_id uuid, recipe_id uuid, reservation_id uuid,
  plan_id uuid, plan_item_id uuid
) on commit drop;
insert into planning_test_ids default values;

grant select, update on pg_temp.planning_test_context, pg_temp.planning_test_ids to authenticated;
do $$
declare temporary_schema_name text;
begin
  select nspname into temporary_schema_name from pg_namespace where oid = pg_my_temp_schema();
  execute format('grant usage on schema %I to authenticated', temporary_schema_name);
end
$$;

do $$
begin
  if exists (select 1 from planning_test_context
    where admin_id is null or management_id is null or factory_id is null or location_id is null) then
    raise exception 'Verification needs active FACOLUB Admin/Management/Factory users and FACOLUB-MAIN';
  end if;
end
$$;

-- Admin configures one product, its three approved formats, carton capacities,
-- four recipe inputs, and the finished-product output.
select set_config('request.jwt.claim.sub', (select admin_id::text from planning_test_context), true);
set local role authenticated;

update planning_test_ids set product_id = (select (public.save_planning_product(
  null, 'S4-ROLLBACK-10W40', '[S4 ROLLBACK] 10W40', true
)).id);

update planning_test_ids set product_format_1l_id = (select (public.save_product_format(
  null, (select product_id from planning_test_ids),
  (select id from public.packaging_formats where code = '1L'), true
)).id);
update planning_test_ids set product_format_2l_id = (select (public.save_product_format(
  null, (select product_id from planning_test_ids),
  (select id from public.packaging_formats where code = '2L'), true
)).id);
update planning_test_ids set product_format_5l_id = (select (public.save_product_format(
  null, (select product_id from planning_test_ids),
  (select id from public.packaging_formats where code = '5L'), true
)).id);

select public.configure_packaging_rule((select id from public.packaging_formats where code = '1L'), 24);
select public.configure_packaging_rule((select id from public.packaging_formats where code = '2L'), 12);
select public.configure_packaging_rule((select id from public.packaging_formats where code = '5L'), 4);

update planning_test_ids set prepared_id = (select (public.save_stock_item(
  null, 'S4-ROLLBACK-PREP-5L', '[S4 ROLLBACK] Prepared Bottle 5L',
  'prepared_bottle', 'piece', (select product_format_5l_id from planning_test_ids),
  50, 'Rollback-only S4 verification', true
)).id);
update planning_test_ids set oil_id = (select (public.save_stock_item(
  null, 'S4-ROLLBACK-OIL-10W40', '[S4 ROLLBACK] Bulk 10W40',
  'bulk_lubricant', 'liter', null, null, 'Rollback-only S4 verification', true
)).id);
update planning_test_ids set seal_id = (select (public.save_stock_item(
  null, 'S4-ROLLBACK-SEAL', '[S4 ROLLBACK] Seal',
  'seal', 'piece', null, null, 'Rollback-only S4 verification', true
)).id);
update planning_test_ids set carton_id = (select (public.save_stock_item(
  null, 'S4-ROLLBACK-CARTON-5L', '[S4 ROLLBACK] Carton 5L',
  'carton', 'piece', null, null, 'Rollback-only S4 verification', true
)).id);
update planning_test_ids set output_id = (select (public.save_stock_item(
  null, 'S4-ROLLBACK-FINISHED-10W40-5L', '[S4 ROLLBACK] Finished 10W40 5L',
  'finished_product', 'piece', (select product_format_5l_id from planning_test_ids),
  null, 'Rollback-only S4 verification', true
)).id);

update planning_test_ids set recipe_id = (
  select (public.create_production_recipe(
    (select product_format_5l_id from planning_test_ids),
    (select output_id from planning_test_ids),
    jsonb_build_array(
      jsonb_build_object('stock_item_id', (select prepared_id from planning_test_ids),
                         'component_role', 'prepared_bottle', 'quantity_per_bottle', 1),
      jsonb_build_object('stock_item_id', (select oil_id from planning_test_ids),
                         'component_role', 'bulk_lubricant', 'quantity_per_bottle', 5),
      jsonb_build_object('stock_item_id', (select seal_id from planning_test_ids),
                         'component_role', 'seal', 'quantity_per_bottle', 1),
      jsonb_build_object('stock_item_id', (select carton_id from planning_test_ids),
                         'component_role', 'carton', 'quantity_per_bottle', 1)
    )
  )) ->> 'id'
)::uuid;
reset role;

-- A: authoritative conversions: 1L=24, 2L=12, 5L=4 bottles/carton.
do $$
declare normalized record;
begin
  select * into normalized from public.normalize_production_quantity(
    (select product_format_1l_id from planning_test_ids), 1, 'cartons');
  if normalized.planned_bottles <> 24 or normalized.planned_cartons <> 1 then
    raise exception 'TEST FAILED A: 1L carton conversion is wrong';
  end if;
  select * into normalized from public.normalize_production_quantity(
    (select product_format_2l_id from planning_test_ids), 1, 'cartons');
  if normalized.planned_bottles <> 12 or normalized.planned_cartons <> 1 then
    raise exception 'TEST FAILED A: 2L carton conversion is wrong';
  end if;
  select * into normalized from public.normalize_production_quantity(
    (select product_format_5l_id from planning_test_ids), 40, 'cartons');
  if normalized.planned_bottles <> 160 or normalized.planned_cartons <> 40 then
    raise exception 'TEST FAILED A: 40 cartons of 5L did not normalize to 160 bottles';
  end if;
end
$$;

-- Stock fixture: the seal has 1,000 physical but only 100 available because
-- 900 are already reserved. This proves availability is not physical stock.
select set_config('request.jwt.claim.sub', (select management_id::text from planning_test_context), true);
set local role authenticated;
select public.record_stock_movement(item_id, (select location_id from planning_test_context),
  'opening_balance', quantity, 'in', 'production_planning_verification', gen_random_uuid(),
  'S4 rollback balance')
from (values
  ((select prepared_id from planning_test_ids), 200::numeric),
  ((select oil_id from planning_test_ids), 1000::numeric),
  ((select seal_id from planning_test_ids), 1000::numeric),
  ((select carton_id from planning_test_ids), 60::numeric)
) opening(item_id, quantity);
update planning_test_ids set reservation_id = (select (public.create_stock_reservation(
  (select seal_id from planning_test_ids), (select location_id from planning_test_context),
  900, 'production_planning_verification', gen_random_uuid()
)).id);
update planning_test_context set
  movements_before = (select count(*) from public.stock_movements),
  reservations_before = (select count(*) from public.stock_reservations);

-- B/C/D/E: Management creates a multi-line-capable draft and one normalized
-- line. The preview uses the active recipe and reservation-aware availability.
update planning_test_ids set plan_id = (select (public.create_production_plan_draft(
  current_date, (select location_id from planning_test_context), 1,
  (select factory_id from planning_test_context), 'S4 rollback planning test'
)).id);
update planning_test_ids set plan_item_id = (select (public.save_production_plan_item(
  (select plan_id from planning_test_ids), null,
  (select product_format_5l_id from planning_test_ids), 40, 'cartons', 1
)).id);

do $$
declare preview jsonb;
begin
  preview := public.calculate_production_requirements(
    (select product_format_5l_id from planning_test_ids), 40, 'cartons',
    (select location_id from planning_test_context));
  if (preview ->> 'planned_bottles')::numeric <> 160
    or (preview ->> 'planned_cartons')::numeric <> 40
    or jsonb_array_length(preview -> 'components') <> 4 then
    raise exception 'TEST FAILED B/C: normalized plan quantities or recipe resolution are wrong';
  end if;
  if not exists (select 1 from jsonb_array_elements(preview -> 'components') component
    where component ->> 'role' = 'bulk_lubricant'
      and (component ->> 'required_quantity')::numeric = 800) then
    raise exception 'TEST FAILED C: bulk lubricant requirement should be 800 liters';
  end if;
  if not exists (select 1 from jsonb_array_elements(preview -> 'components') component
    where component ->> 'role' = 'carton'
      and (component ->> 'required_quantity')::numeric = 40) then
    raise exception 'TEST FAILED C: carton requirement should be 40';
  end if;
  if not exists (select 1 from jsonb_array_elements(preview -> 'components') component
    where component ->> 'role' = 'seal'
      and (component ->> 'physical_quantity')::numeric = 1000
      and (component ->> 'reserved_quantity')::numeric = 900
      and (component ->> 'available_quantity')::numeric = 100
      and (component ->> 'missing_quantity')::numeric = 60
      and not (component ->> 'sufficient')::boolean) then
    raise exception 'TEST FAILED D: reservations were not excluded from available seals';
  end if;
end
$$;

-- Draft planning is informational only.
do $$
begin
  if (select count(*) from public.stock_movements)
      <> (select movements_before from planning_test_context)
    or (select count(*) from public.stock_reservations)
      <> (select reservations_before from planning_test_context) then
    raise exception 'TEST FAILED E: draft planning changed stock or reservations';
  end if;
end
$$;

-- F/G/H: validation assigns PLAN-DDMMYY-NN, snapshots requirements and is
-- idempotent. It still creates neither movement nor reservation.
select public.validate_production_plan((select plan_id from planning_test_ids));
select public.validate_production_plan((select plan_id from planning_test_ids));

do $$
declare output_balance record;
begin
  if not exists (select 1 from public.production_plans plan
    where plan.id = (select plan_id from planning_test_ids)
      and plan.status = 'validated'
      and plan.plan_number ~ ('^PLAN-' || to_char(current_date, 'DDMMYY') || '-[0-9]{2,}$')
      and plan.validated_by = (select management_id from planning_test_context)
      and plan.validated_at is not null) then
    raise exception 'TEST FAILED F: validated plan lifecycle or numbering is wrong';
  end if;
  if (select count(*) from public.production_plan_requirements requirement
      where requirement.production_plan_item_id = (select plan_item_id from planning_test_ids)) <> 4 then
    raise exception 'TEST FAILED G: validation did not snapshot exactly four requirements';
  end if;
  if not exists (select 1 from public.production_plan_requirements requirement
    where requirement.production_plan_item_id = (select plan_item_id from planning_test_ids)
      and requirement.component_role = 'prepared_bottle'
      and requirement.quantity_required = 160
      and requirement.projected_available_after_plan = 40
      and requirement.sufficient and requirement.below_minimum_after_plan) then
    raise exception 'TEST FAILED G: minimum-stock warning snapshot is wrong';
  end if;
  if not exists (select 1 from public.production_plan_requirements requirement
    where requirement.production_plan_item_id = (select plan_item_id from planning_test_ids)
      and requirement.component_role = 'seal'
      and requirement.physical_quantity_snapshot = 1000
      and requirement.reserved_quantity_snapshot = 900
      and requirement.available_quantity_snapshot = 100
      and requirement.missing_quantity_snapshot = 60
      and not requirement.sufficient) then
    raise exception 'TEST FAILED G: insufficient seal snapshot is wrong';
  end if;
  if (select count(*) from public.stock_movements)
      <> (select movements_before from planning_test_context)
    or (select count(*) from public.stock_reservations)
      <> (select reservations_before from planning_test_context) then
    raise exception 'TEST FAILED H: validation changed stock or reservations';
  end if;
  select * into output_balance from public.get_stock_balance(
    (select output_id from planning_test_ids), (select location_id from planning_test_context));
  if output_balance.physical_quantity <> 0 or output_balance.available_quantity <> 0 then
    raise exception 'TEST FAILED H: planning created finished-product stock';
  end if;
end
$$;
reset role;

-- I: later configuration changes do not rewrite a validated plan's recipe,
-- normalized quantities, or requirement snapshots.
select set_config('request.jwt.claim.sub', (select admin_id::text from planning_test_context), true);
set local role authenticated;
select public.configure_packaging_rule((select id from public.packaging_formats where code = '5L'), 5);
select public.update_production_recipe(
  (select recipe_id from planning_test_ids), (select output_id from planning_test_ids),
  jsonb_build_array(
    jsonb_build_object('stock_item_id', (select prepared_id from planning_test_ids),
                       'component_role', 'prepared_bottle', 'quantity_per_bottle', 1),
    jsonb_build_object('stock_item_id', (select oil_id from planning_test_ids),
                       'component_role', 'bulk_lubricant', 'quantity_per_bottle', 4.8),
    jsonb_build_object('stock_item_id', (select seal_id from planning_test_ids),
                       'component_role', 'seal', 'quantity_per_bottle', 1),
    jsonb_build_object('stock_item_id', (select carton_id from planning_test_ids),
                       'component_role', 'carton', 'quantity_per_bottle', 1)
  )
);
do $$
begin
  if not exists (select 1 from public.production_plan_items item
    where item.id = (select plan_item_id from planning_test_ids)
      and item.recipe_id = (select recipe_id from planning_test_ids)
      and item.planned_bottles = 160 and item.planned_cartons = 40
      and item.bottles_per_carton = 4) then
    raise exception 'TEST FAILED I: historical plan quantities or recipe changed';
  end if;
  if not exists (select 1 from public.production_plan_requirements requirement
    where requirement.production_plan_item_id = (select plan_item_id from planning_test_ids)
      and requirement.component_role = 'bulk_lubricant'
      and requirement.quantity_required = 800) then
    raise exception 'TEST FAILED I: historical requirement snapshot changed';
  end if;
end
$$;
reset role;

-- J: Factory sees its validated mission but cannot configure recipes, create
-- plans, or mutate planning tables directly.
select set_config('request.jwt.claim.sub', (select factory_id::text from planning_test_context), true);
set local role authenticated;
do $$
begin
  if not exists (select 1 from public.list_factory_production_missions(current_date) mission
    where mission.plan_id = (select plan_id from planning_test_ids)
      and mission.planned_bottles = 160 and mission.planned_cartons = 40) then
    raise exception 'TEST FAILED J: Factory cannot see its production mission';
  end if;
  if exists (select 1 from public.production_recipes) then
    raise exception 'TEST FAILED J: Factory can see technical recipe configuration';
  end if;
end
$$;
do $$
begin
  perform public.create_production_plan_draft(current_date,
    (select location_id from planning_test_context), null, null, 'ILLEGAL');
  raise exception 'TEST FAILED J: Factory created a production plan';
exception when insufficient_privilege then null;
end
$$;
do $$
begin
  update public.production_plans set comment = 'ILLEGAL'
  where id = (select plan_id from planning_test_ids);
  raise exception 'TEST FAILED J: Factory directly updated a production plan';
exception when insufficient_privilege then null;
end
$$;
do $$
begin
  perform public.update_production_recipe(
    (select recipe_id from planning_test_ids), (select output_id from planning_test_ids), '[]'::jsonb);
  raise exception 'TEST FAILED J: Factory updated a production recipe';
exception when insufficient_privilege then null;
end
$$;
reset role;

select 'PASS: Production Planning S4 verification completed; transaction will be rolled back.' as result;
rollback;
