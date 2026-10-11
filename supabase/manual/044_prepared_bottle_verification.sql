-- SOMA / FACOLUB prepared bottles module - 044 rollback-only verification
-- Depends on: 020-024, 030-033, and 040-043.
-- Requires one active FACOLUB Admin, Management, and Factory user.
-- Every fixture and movement is rolled back at the end.

begin;

create temporary table preparation_test_context (
  admin_id uuid, management_id uuid, factory_id uuid, location_id uuid
) on commit drop;
insert into preparation_test_context
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

create temporary table preparation_test_ids (
  empty_id uuid, front_label_id uuid, back_label_id uuid, output_id uuid,
  recipe_id uuid, reservation_id uuid, preparation_id uuid, blocked_preparation_id uuid
) on commit drop;
insert into preparation_test_ids default values;
grant select, update on pg_temp.preparation_test_context, pg_temp.preparation_test_ids to authenticated;
do $$
declare temporary_schema_name text;
begin
  select nspname into temporary_schema_name from pg_namespace where oid = pg_my_temp_schema();
  execute format('grant usage on schema %I to authenticated', temporary_schema_name);
end
$$;

do $$
begin
  if exists (select 1 from preparation_test_context
    where admin_id is null or management_id is null or factory_id is null or location_id is null) then
    raise exception 'Verification needs active FACOLUB Admin/Management/Factory users and FACOLUB-MAIN';
  end if;
end
$$;

-- Admin creates rollback-scoped stock references and a two-label recipe.
select set_config('request.jwt.claim.sub', (select admin_id::text from preparation_test_context), true);
set local role authenticated;
update preparation_test_ids set empty_id = (select (public.save_stock_item(
  null, 'S3-ROLLBACK-EMPTY-5L', '[S3 ROLLBACK] Empty Bottle 5L',
  'empty_bottle', 'piece', null, null, 'Rollback-only S3 verification', true
)).id);
update preparation_test_ids set front_label_id = (select (public.save_stock_item(
  null, 'S3-ROLLBACK-FRONT-5L', '[S3 ROLLBACK] 10W40 5L Front Label',
  'label', 'piece', null, null, 'Rollback-only S3 verification', true
)).id);
update preparation_test_ids set back_label_id = (select (public.save_stock_item(
  null, 'S3-ROLLBACK-BACK-5L', '[S3 ROLLBACK] 10W40 5L Back Label',
  'label', 'piece', null, null, 'Rollback-only S3 verification', true
)).id);
update preparation_test_ids set output_id = (select (public.save_stock_item(
  null, 'S3-ROLLBACK-PREP-10W40-5L', '[S3 ROLLBACK] Prepared Bottle 10W40 5L',
  'prepared_bottle', 'piece', null, null, 'Rollback-only S3 verification', true
)).id);
update preparation_test_ids set recipe_id = (
  select (public.create_prepared_bottle_recipe(
    (select output_id from preparation_test_ids), null, '10W40', '5L',
    jsonb_build_array(
      jsonb_build_object('stock_item_id', (select empty_id from preparation_test_ids),
                         'quantity_per_output', 1),
      jsonb_build_object('stock_item_id', (select front_label_id from preparation_test_ids),
                         'quantity_per_output', 1),
      jsonb_build_object('stock_item_id', (select back_label_id from preparation_test_ids),
                         'quantity_per_output', 1)
    )
  )) ->> 'id'
)::uuid;
reset role;

-- Physical: empty 500, front 300, back 100, output 0. Reserve 50 front labels.
select set_config('request.jwt.claim.sub', (select management_id::text from preparation_test_context), true);
set local role authenticated;
select public.record_stock_movement(item_id, (select location_id from preparation_test_context),
  'opening_balance', quantity, 'in', 'prepared_bottle_verification', gen_random_uuid(), 'S3 rollback balance')
from (values
  ((select empty_id from preparation_test_ids), 500::numeric),
  ((select front_label_id from preparation_test_ids), 300::numeric),
  ((select back_label_id from preparation_test_ids), 100::numeric)
) opening(item_id, quantity);
update preparation_test_ids set reservation_id = (select (public.create_stock_reservation(
  (select front_label_id from preparation_test_ids),
  (select location_id from preparation_test_context), 50,
  'prepared_bottle_verification', gen_random_uuid()
)).id);
reset role;

-- A/B/E: recipe resolution, quantity 100, multiple labels, and reservation-aware availability.
select set_config('request.jwt.claim.sub', (select factory_id::text from preparation_test_context), true);
set local role authenticated;
do $$
declare preview jsonb;
begin
  preview := public.calculate_preparation_requirements(
    (select recipe_id from preparation_test_ids), 100,
    (select location_id from preparation_test_context)
  );
  if jsonb_array_length(preview -> 'components') <> 3 then
    raise exception 'TEST FAILED A: recipe did not resolve all three components';
  end if;
  if not exists (select 1 from jsonb_array_elements(preview -> 'components') c
    where (c ->> 'stock_item_id')::uuid = (select front_label_id from preparation_test_ids)
      and (c ->> 'required_quantity')::numeric = 100
      and (c ->> 'physical_quantity')::numeric = 300
      and (c ->> 'reserved_quantity')::numeric = 50
      and (c ->> 'available_quantity')::numeric = 250
      and (c ->> 'sufficient')::boolean) then
    raise exception 'TEST FAILED B/E: front-label requirement or reservation quantities are wrong';
  end if;
  preview := public.calculate_preparation_requirements(
    (select recipe_id from preparation_test_ids), 260,
    (select location_id from preparation_test_context)
  );
  if not exists (select 1 from jsonb_array_elements(preview -> 'components') c
    where (c ->> 'stock_item_id')::uuid = (select front_label_id from preparation_test_ids)
      and (c ->> 'missing_quantity')::numeric = 10
      and not (c ->> 'sufficient')::boolean) then
    raise exception 'TEST FAILED E: reserved stock was not excluded from available stock';
  end if;
end
$$;

update preparation_test_ids set preparation_id = (select (public.create_bottle_preparation_draft(
  (select recipe_id from preparation_test_ids),
  (select location_id from preparation_test_context), 100, 'S3 rollback confirmation'
)).id);

-- Drafts never change stock.
do $$ begin
  if exists (select 1 from public.stock_movements movement
    where movement.reference_type = 'bottle_preparation'
      and movement.reference_id = (select preparation_id from preparation_test_ids)) then
    raise exception 'TEST FAILED: draft preparation changed stock';
  end if;
end $$;

-- J: Factory cannot configure or directly mutate recipes.
do $$
begin
  perform public.update_prepared_bottle_recipe(
    (select recipe_id from preparation_test_ids), (select output_id from preparation_test_ids),
    null, '10W40', '5L', '[]'::jsonb
  );
  raise exception 'TEST FAILED J: Factory updated a recipe';
exception when insufficient_privilege then null;
end
$$;
do $$
begin
  update public.prepared_bottle_recipes set product_name = 'ILLEGAL'
  where id = (select recipe_id from preparation_test_ids);
  raise exception 'TEST FAILED J: Factory directly updated a recipe';
exception when insufficient_privilege then null;
end
$$;

-- C/F/G/H: atomic confirmation posts three OUT rows and one IN row.
select public.confirm_bottle_preparation((select preparation_id from preparation_test_ids));
-- I: retry/double-click is idempotent.
select public.confirm_bottle_preparation((select preparation_id from preparation_test_ids));

do $$
declare balance record;
begin
  if (select count(*) from public.stock_movements movement
    where movement.reference_type = 'bottle_preparation'
      and movement.reference_id = (select preparation_id from preparation_test_ids)) <> 4 then
    raise exception 'TEST FAILED F/G/I: expected exactly four movements after double confirmation';
  end if;
  if (select count(*) from public.stock_movements movement
    where movement.reference_type = 'bottle_preparation'
      and movement.reference_id = (select preparation_id from preparation_test_ids)
      and movement.movement_type = 'preparation_consumption' and movement.direction = 'out') <> 3 then
    raise exception 'TEST FAILED F: component OUT movements are wrong';
  end if;
  if (select count(*) from public.stock_movements movement
    where movement.reference_type = 'bottle_preparation'
      and movement.reference_id = (select preparation_id from preparation_test_ids)
      and movement.movement_type = 'preparation_output' and movement.direction = 'in'
      and movement.quantity = 100) <> 1 then
    raise exception 'TEST FAILED G: output IN movement is wrong';
  end if;
  if exists (select 1 from public.stock_movements movement
    where movement.reference_id = (select preparation_id from preparation_test_ids)
      and movement.reference_type <> 'bottle_preparation') then
    raise exception 'TEST FAILED H: preparation movements do not share the canonical reference';
  end if;
  select * into balance from public.get_stock_balance(
    (select empty_id from preparation_test_ids), (select location_id from preparation_test_context));
  if balance.physical_quantity <> 400 or balance.available_quantity <> 400 then
    raise exception 'TEST FAILED C: empty-bottle balance is wrong';
  end if;
  select * into balance from public.get_stock_balance(
    (select front_label_id from preparation_test_ids), (select location_id from preparation_test_context));
  if balance.physical_quantity <> 200 or balance.reserved_quantity <> 50
    or balance.available_quantity <> 150 then
    raise exception 'TEST FAILED C/E: front-label balance is wrong';
  end if;
  select * into balance from public.get_stock_balance(
    (select output_id from preparation_test_ids), (select location_id from preparation_test_context));
  if balance.physical_quantity <> 100 then
    raise exception 'TEST FAILED G: prepared-bottle output balance is wrong';
  end if;
end
$$;

-- Confirmed records are protected twice: authenticated users have no direct
-- UPDATE privilege, and the lifecycle trigger also rejects owner-side changes.
do $$
begin
  update public.bottle_preparations set actual_quantity = 999
  where id = (select preparation_id from preparation_test_ids);
  raise exception 'TEST FAILED: authenticated user directly updated a confirmed preparation';
exception when insufficient_privilege then null;
end
$$;

reset role;
do $$
begin
  update public.bottle_preparations set actual_quantity = 999
  where id = (select preparation_id from preparation_test_ids);
  raise exception 'TEST FAILED: lifecycle trigger allowed a confirmed preparation update';
exception when object_not_in_prerequisite_state then null;
end
$$;
select set_config('request.jwt.claim.sub', (select factory_id::text from preparation_test_context), true);
set local role authenticated;

-- D: with back labels exhausted, confirmation fails and the whole attempt rolls back.
update preparation_test_ids set blocked_preparation_id = (select (public.create_bottle_preparation_draft(
  (select recipe_id from preparation_test_ids),
  (select location_id from preparation_test_context), 1, 'Must remain draft'
)).id);
do $$
begin
  perform public.confirm_bottle_preparation((select blocked_preparation_id from preparation_test_ids));
  raise exception 'TEST FAILED D: insufficient labels did not block confirmation';
exception when check_violation then
  if sqlerrm not like 'Insufficient stock for %' then raise; end if;
end
$$;
do $$
begin
  if exists (select 1 from public.stock_movements movement
    where movement.reference_type = 'bottle_preparation'
      and movement.reference_id = (select blocked_preparation_id from preparation_test_ids)) then
    raise exception 'TEST FAILED D: failed confirmation left partial movements';
  end if;
  if not exists (select 1 from public.bottle_preparations preparation
    where preparation.id = (select blocked_preparation_id from preparation_test_ids)
      and preparation.status = 'draft' and preparation.preparation_number is null) then
    raise exception 'TEST FAILED D: failed confirmation did not roll back its preparation state';
  end if;
end
$$;
reset role;

-- Structural concurrency assertion. For a live two-session proof, create two
-- drafts that together exceed one label balance and confirm them simultaneously;
-- the shared item/location advisory lock permits exactly one success.
do $$
declare definition text;
begin
  select pg_get_functiondef('public.confirm_bottle_preparation(uuid)'::regprocedure) into definition;
  if position('lock_stock_balance' in definition) = 0
    or position('order by candidate.component_stock_item_id' in lower(definition)) = 0 then
    raise exception 'TEST FAILED: confirmation lacks ordered shared stock locking';
  end if;
end
$$;

select 'PASS: Prepared Bottles S3 verification completed; transaction will be rolled back.' as result;
rollback;
