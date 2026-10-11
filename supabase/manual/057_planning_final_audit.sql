-- SOMA / FACOLUB production planning module - 057 final installation audit
-- Depends on: 050-054 and 056. Read-only: creates no fixtures and changes no data.
-- Run 055 separately for the rollback-only behavioral verification.

begin;
set transaction read only;

do $$
declare
  expected_table text;
  expected_function text;
  definition text;
begin
  -- Core types and their exact business labels.
  if to_regtype('public.production_plan_status') is null
    or to_regtype('public.planning_quantity_mode') is null
    or to_regtype('public.production_component_role') is null then
    raise exception 'AUDIT FAILED: one or more S4 enum types are missing';
  end if;
  if (select array_agg(enumlabel::text order by enumsortorder)
      from pg_enum where enumtypid = 'public.production_plan_status'::regtype)
      <> array['draft','planned','validated','cancelled'] then
    raise exception 'AUDIT FAILED: production_plan_status labels are incorrect';
  end if;
  if (select array_agg(enumlabel::text order by enumsortorder)
      from pg_enum where enumtypid = 'public.planning_quantity_mode'::regtype)
      <> array['bottles','cartons'] then
    raise exception 'AUDIT FAILED: planning_quantity_mode labels are incorrect';
  end if;

  -- All S4 tables must exist and have RLS enabled.
  foreach expected_table in array array[
    'products', 'packaging_formats', 'product_formats', 'packaging_rules',
    'production_recipes', 'production_recipe_components', 'production_plans',
    'production_plan_items', 'production_plan_requirements',
    'production_plan_number_sequences'
  ] loop
    if to_regclass('public.' || expected_table) is null then
      raise exception 'AUDIT FAILED: table public.% is missing', expected_table;
    end if;
    if not exists (select 1 from pg_class relation
      join pg_namespace namespace on namespace.oid = relation.relnamespace
      where namespace.nspname = 'public' and relation.relname = expected_table
        and relation.relrowsecurity) then
      raise exception 'AUDIT FAILED: RLS is not enabled on public.%', expected_table;
    end if;
    if has_table_privilege('authenticated', 'public.' || expected_table, 'INSERT')
      or has_table_privilege('authenticated', 'public.' || expected_table, 'UPDATE')
      or has_table_privilege('authenticated', 'public.' || expected_table, 'DELETE') then
      raise exception 'AUDIT FAILED: authenticated has direct write privileges on public.%', expected_table;
    end if;
  end loop;

  -- Approved configurable carton capacities.
  if (select count(*) from public.packaging_formats format
      join public.packaging_rules rule on rule.format_id = format.id and rule.is_active
      where (format.code = '1L' and rule.bottles_per_carton = 24)
         or (format.code = '2L' and rule.bottles_per_carton = 12)
         or (format.code = '5L' and rule.bottles_per_carton = 4)) <> 3 then
    raise exception 'AUDIT FAILED: active carton capacities must be 1L=24, 2L=12, 5L=4';
  end if;
  if exists (select 1 from public.packaging_formats format
    join public.packaging_rules rule on rule.format_id = format.id and rule.is_active
    where format.code in ('1L','2L','5L')
    group by format.id having count(*) <> 1) then
    raise exception 'AUDIT FAILED: an approved format does not have exactly one active rule';
  end if;

  -- Required trusted interfaces.
  foreach expected_function in array array[
    'public.normalize_production_quantity(uuid,numeric,public.planning_quantity_mode)',
    'public.calculate_production_requirements(uuid,numeric,public.planning_quantity_mode,uuid)',
    'public.create_production_recipe(uuid,uuid,jsonb)',
    'public.update_production_recipe(uuid,uuid,jsonb)',
    'public.configure_packaging_rule(uuid,integer)',
    'public.create_production_plan_draft(date,uuid,integer,uuid,text)',
    'public.update_production_plan_draft(uuid,date,uuid,integer,uuid,text)',
    'public.save_production_plan_item(uuid,uuid,uuid,numeric,public.planning_quantity_mode,integer)',
    'public.plan_production_plan(uuid)',
    'public.validate_production_plan(uuid)',
    'public.cancel_production_plan(uuid)',
    'public.get_production_plan(uuid)',
    'public.list_production_plans(date,date,uuid,public.production_plan_status,text,integer)',
    'public.list_factory_production_missions(date)'
  ] loop
    if to_regprocedure(expected_function) is null then
      raise exception 'AUDIT FAILED: function % is missing', expected_function;
    end if;
    if not (select procedure.prosecdef from pg_proc procedure
      where procedure.oid = to_regprocedure(expected_function)) then
      raise exception 'AUDIT FAILED: function % is not SECURITY DEFINER', expected_function;
    end if;
  end loop;

  -- The applied hotfix must use the explicit, non-fall-through output path.
  definition := pg_get_functiondef(
    'public.normalize_production_quantity(uuid,numeric,public.planning_quantity_mode)'::regprocedure
  );
  if position('planned_bottles := target_quantity * capacity' in definition) = 0
    or position('return next' in lower(definition)) = 0
    or position('return query' in lower(definition)) > 0 then
    raise exception 'AUDIT FAILED: quantity-mode hotfix 056 is not installed';
  end if;

  -- Authenticated users call only the trusted public APIs; the primitive
  -- normalizer stays internal to SECURITY DEFINER functions.
  if not has_function_privilege('authenticated',
      'public.calculate_production_requirements(uuid,numeric,public.planning_quantity_mode,uuid)',
      'EXECUTE')
    or not has_function_privilege('authenticated',
      'public.validate_production_plan(uuid)', 'EXECUTE')
    or not has_function_privilege('authenticated',
      'public.list_factory_production_missions(date)', 'EXECUTE') then
    raise exception 'AUDIT FAILED: authenticated API execution grants are incomplete';
  end if;
  if has_function_privilege('authenticated',
      'public.normalize_production_quantity(uuid,numeric,public.planning_quantity_mode)',
      'EXECUTE') then
    raise exception 'AUDIT FAILED: internal quantity normalizer is exposed directly';
  end if;

  -- RLS exposes only SELECT policies. Sequence state has deliberately no policy.
  if exists (select 1 from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename in (
        'products', 'packaging_formats', 'product_formats', 'packaging_rules',
        'production_recipes', 'production_recipe_components', 'production_plans',
        'production_plan_items', 'production_plan_requirements',
        'production_plan_number_sequences'
      ) and policy.cmd <> 'SELECT') then
    raise exception 'AUDIT FAILED: a direct mutation RLS policy exists';
  end if;
  if (select count(distinct policy.tablename) from pg_policies policy
      where policy.schemaname = 'public' and policy.cmd = 'SELECT'
        and policy.tablename in (
          'products', 'packaging_formats', 'product_formats', 'packaging_rules',
          'production_recipes', 'production_recipe_components', 'production_plans',
          'production_plan_items', 'production_plan_requirements'
        )) <> 9 then
    raise exception 'AUDIT FAILED: one or more S4 SELECT policies are missing';
  end if;
  if exists (select 1 from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'production_plan_number_sequences') then
    raise exception 'AUDIT FAILED: numbering sequence table must not be directly visible';
  end if;

  -- Planning functions must not contain S5/S6 stock mutation calls.
  definition := pg_get_functiondef('public.plan_production_plan(uuid)'::regprocedure)
    || pg_get_functiondef('public.validate_production_plan(uuid)'::regprocedure)
    || pg_get_functiondef('public.snapshot_production_plan_requirements(uuid)'::regprocedure);
  if position('record_stock_movement' in lower(definition)) > 0
    or position('create_stock_reservation' in lower(definition)) > 0
    or position('insert into public.stock_movements' in lower(definition)) > 0
    or position('insert into public.stock_reservations' in lower(definition)) > 0 then
    raise exception 'AUDIT FAILED: an S4 planning function mutates stock or reservations';
  end if;
end
$$;

select
  'PASS: Planning S4 installation audit completed.' as result,
  10 as tables_checked,
  14 as functions_checked,
  9 as select_policy_tables_checked,
  'No data was changed.' as safety;

commit;
