-- SOMA / FACOLUB production execution - 071 lifecycle and preview functions
-- Depends on: 070 plus planning/reservation APIs through 061.

create or replace function public.production_execution_payload(target_execution_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'execution', to_jsonb(execution),
    'plan', to_jsonb(plan),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'item', to_jsonb(item),
      'plan_item', to_jsonb(plan_item),
      'resolutions', coalesce((select jsonb_agg(to_jsonb(resolution)
        order by resolution.resolved_at, resolution.id)
        from public.production_reservation_resolutions resolution
        where resolution.production_execution_item_id = item.id), '[]'::jsonb)
    ) order by plan_item.position)
    from public.production_execution_items item
    join public.production_plan_items plan_item on plan_item.id = item.production_plan_item_id
    where item.production_execution_id = execution.id), '[]'::jsonb),
    'issues', coalesce((select jsonb_agg(to_jsonb(issue) order by issue.created_at, issue.id)
      from public.production_issues issue
      where issue.production_execution_id = execution.id), '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(movement)
      order by movement.created_at, movement.id)
      from public.stock_movements movement
      where movement.reference_type = 'production_execution'
        and movement.reference_id = execution.id), '[]'::jsonb)
  )
  from public.production_executions execution
  join public.production_plans plan on plan.id = execution.production_plan_id
  where execution.id = target_execution_id
$$;

create or replace function public.prepare_production_execution(target_plan_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid;
  actor_role public.app_role;
  plan public.production_plans;
  execution_id uuid;
  requirement_count bigint;
  active_count bigint;
begin
  actor_id := public.assert_planning_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  select candidate.* into plan from public.production_plans candidate
  where candidate.id = target_plan_id for update;
  if not found then raise exception 'Production plan not found' using errcode = 'P0002'; end if;
  if actor_role = 'factory' and plan.assigned_to is not null and plan.assigned_to <> actor_id then
    raise exception 'Production plan is assigned to another Factory user' using errcode = '42501';
  end if;
  if plan.status <> 'validated' or plan.reservation_status <> 'reserved' then
    raise exception 'Execution requires a validated and fully reserved plan'
      using errcode = '55000';
  end if;

  select count(*) into requirement_count
  from public.production_plan_items item
  join public.production_plan_requirements requirement
    on requirement.production_plan_item_id = item.id
  where item.production_plan_id = plan.id;
  select count(*) into active_count from public.stock_reservations reservation
  where reservation.reference_type = 'production_plan'
    and reservation.reference_id = plan.id and reservation.status = 'active'
    and reservation.production_plan_requirement_id is not null;
  if requirement_count = 0 or active_count <> requirement_count then
    raise exception 'Plan reservation set is incomplete' using errcode = '55000';
  end if;

  insert into public.production_executions (
    execution_number, production_plan_id, status, created_by
  ) values (
    regexp_replace(plan.plan_number, '^PLAN-', 'PROD-'), plan.id, 'to_do', actor_id
  ) on conflict (production_plan_id) do nothing;
  select execution.id into execution_id from public.production_executions execution
  where execution.production_plan_id = plan.id;

  insert into public.production_execution_items (
    production_execution_id, production_plan_item_id,
    planned_bottles, planned_cartons, bottles_per_carton, output_stock_item_id
  )
  select execution_id, item.id, item.planned_bottles, item.planned_cartons,
    item.bottles_per_carton, item.output_stock_item_id
  from public.production_plan_items item
  where item.production_plan_id = plan.id
  on conflict (production_plan_item_id) do nothing;
  return public.production_execution_payload(execution_id);
end;
$$;

create or replace function public.assert_execution_actor(
  target_execution_id uuid,
  required_roles public.app_role[]
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
declare assigned_user uuid;
begin
  actor_id := public.assert_planning_actor(required_roles);
  actor_role := public.current_app_role();
  if actor_role = 'factory' then
    select plan.assigned_to into assigned_user
    from public.production_executions execution
    join public.production_plans plan on plan.id = execution.production_plan_id
    where execution.id = target_execution_id;
    if not found then raise exception 'Production execution not found' using errcode = 'P0002'; end if;
    if assigned_user is not null and assigned_user <> actor_id then
      raise exception 'Production execution is assigned to another Factory user'
        using errcode = '42501';
    end if;
  end if;
  return actor_id;
end;
$$;

create or replace function public.start_production_execution(target_execution_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare execution public.production_executions;
declare plan public.production_plans;
begin
  actor_id := public.assert_execution_actor(target_execution_id, array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  select candidate.* into execution from public.production_executions candidate
  where candidate.id = target_execution_id for update;
  if not found then raise exception 'Production execution not found' using errcode = 'P0002'; end if;
  if execution.status = 'in_progress' then
    return public.production_execution_payload(execution.id);
  end if;
  if execution.status <> 'to_do' then
    raise exception 'Only a To Do execution can be started' using errcode = '55000';
  end if;
  select candidate.* into plan from public.production_plans candidate
  where candidate.id = execution.production_plan_id for update;
  if plan.status <> 'validated' or plan.reservation_status <> 'reserved'
    or not exists (select 1 from public.stock_reservations reservation
      where reservation.reference_type = 'production_plan'
        and reservation.reference_id = plan.id and reservation.status = 'active') then
    raise exception 'Active production reservations are required to start'
      using errcode = '55000';
  end if;
  update public.production_executions candidate
  set status = 'in_progress', started_by = actor_id, started_at = now()
  where candidate.id = execution.id;
  return public.production_execution_payload(execution.id);
end;
$$;

create or replace function public.report_production_issue(
  target_execution_id uuid,
  target_category public.production_issue_category,
  target_description text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare execution public.production_executions;
begin
  actor_id := public.assert_execution_actor(target_execution_id, array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  if target_category is null or target_description is null or trim(target_description) = '' then
    raise exception 'Issue category and description are required' using errcode = '22023';
  end if;
  select candidate.* into execution from public.production_executions candidate
  where candidate.id = target_execution_id for update;
  if not found then raise exception 'Production execution not found' using errcode = 'P0002'; end if;
  if execution.status <> 'in_progress' then
    raise exception 'Only an In Progress execution can be blocked' using errcode = '55000';
  end if;
  insert into public.production_issues (
    production_execution_id, category, description, reported_by
  ) values (execution.id, target_category, trim(target_description), actor_id);
  update public.production_executions candidate set status = 'blocked'
  where candidate.id = execution.id;
  return public.production_execution_payload(execution.id);
end;
$$;

create or replace function public.resolve_production_issue(
  target_issue_id uuid,
  target_resume_status public.production_execution_status,
  target_resolution_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare issue public.production_issues;
begin
  actor_id := public.assert_planning_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  if target_resume_status not in ('to_do', 'in_progress') then
    raise exception 'Resolved execution must return to To Do or In Progress'
      using errcode = '22023';
  end if;
  select candidate.* into issue from public.production_issues candidate
  where candidate.id = target_issue_id for update;
  if not found then raise exception 'Production issue not found' using errcode = 'P0002'; end if;
  if issue.resolved_at is not null then
    return public.production_execution_payload(issue.production_execution_id);
  end if;
  update public.production_issues candidate set resolved_by = actor_id, resolved_at = now(),
    resolution_note = nullif(trim(target_resolution_note), '')
  where candidate.id = issue.id;
  update public.production_executions execution
  set status = target_resume_status,
      started_by = case when target_resume_status = 'to_do' then null else execution.started_by end,
      started_at = case when target_resume_status = 'to_do' then null else execution.started_at end
  where execution.id = issue.production_execution_id and execution.status = 'blocked';
  return public.production_execution_payload(issue.production_execution_id);
end;
$$;

create or replace function public.normalize_production_execution_actuals(
  target_execution_id uuid,
  target_actuals jsonb
)
returns table (
  execution_item_id uuid, actual_bottles numeric, actual_cartons numeric
)
language plpgsql stable security definer set search_path = '' as $$
declare item public.production_execution_items;
declare entry jsonb;
declare input_quantity numeric;
declare input_mode text;
declare matched_count integer;
declare item_count integer := 0;
begin
  if jsonb_typeof(target_actuals) <> 'array' or jsonb_array_length(target_actuals) = 0 then
    raise exception 'Actual production entries are required' using errcode = '22023';
  end if;
  for item in select candidate.* from public.production_execution_items candidate
    where candidate.production_execution_id = target_execution_id order by candidate.id
  loop
    item_count := item_count + 1;
    select count(*), (jsonb_agg(value) -> 0) into matched_count, entry
    from jsonb_array_elements(target_actuals) value
    where value ->> 'execution_item_id' = item.id::text;
    if matched_count <> 1 then
      raise exception 'Each execution item requires exactly one actual quantity'
        using errcode = '22023';
    end if;
    input_quantity := (entry ->> 'quantity')::numeric;
    input_mode := entry ->> 'mode';
    if input_quantity is null or input_quantity <= 0 or mod(input_quantity, 1) <> 0 then
      raise exception 'Actual quantity must be a positive whole number' using errcode = '22023';
    end if;
    execution_item_id := item.id;
    if input_mode = 'cartons' then
      if item.bottles_per_carton is null then
        raise exception 'Carton capacity is unavailable for this execution item'
          using errcode = '23514';
      end if;
      actual_cartons := input_quantity;
      actual_bottles := input_quantity * item.bottles_per_carton;
    elsif input_mode = 'bottles' then
      actual_bottles := input_quantity;
      actual_cartons := case when item.bottles_per_carton is null then input_quantity
        else round(input_quantity / item.bottles_per_carton, 3) end;
    else
      raise exception 'Actual quantity mode must be bottles or cartons' using errcode = '22023';
    end if;
    if actual_bottles > item.planned_bottles then
      raise exception 'Actual production cannot exceed planned production'
        using errcode = '23514';
    end if;
    return next;
  end loop;
  if item_count = 0 or jsonb_array_length(target_actuals) <> item_count then
    raise exception 'Actual production entries do not match execution items'
      using errcode = '22023';
  end if;
end;
$$;

create or replace function public.calculate_production_execution_completion(
  target_execution_id uuid,
  target_actuals jsonb
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  perform public.assert_execution_actor(target_execution_id, array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  with actual as (
    select * from public.normalize_production_execution_actuals(target_execution_id, target_actuals)
  )
  select jsonb_build_object(
    'execution_id', target_execution_id,
    'items', jsonb_agg(jsonb_build_object(
      'execution_item_id', item.id,
      'planned_bottles', item.planned_bottles,
      'planned_cartons', item.planned_cartons,
      'actual_bottles', actual.actual_bottles,
      'actual_cartons', actual.actual_cartons,
      'output_stock_item_id', item.output_stock_item_id,
      'materials', (select jsonb_agg(jsonb_build_object(
        'requirement_id', requirement.id,
        'stock_item_id', requirement.component_stock_item_id,
        'name', requirement.component_name_snapshot,
        'unit', requirement.unit,
        'reserved_quantity', reservation.quantity,
        'consumed_quantity', round(requirement.quantity_required
          * actual.actual_bottles / item.planned_bottles, 3),
        'released_quantity', reservation.quantity - round(requirement.quantity_required
          * actual.actual_bottles / item.planned_bottles, 3)
      ) order by requirement.component_role, requirement.id)
      from public.production_plan_requirements requirement
      join public.stock_reservations reservation
        on reservation.production_plan_requirement_id = requirement.id
       and reservation.status = 'active'
      where requirement.production_plan_item_id = item.production_plan_item_id)
    ) order by item.id)
  ) into result
  from public.production_execution_items item
  join actual on actual.execution_item_id = item.id
  where item.production_execution_id = target_execution_id;
  return result;
end;
$$;

revoke all on function public.production_execution_payload(uuid) from public, anon, authenticated;
revoke all on function public.assert_execution_actor(uuid,public.app_role[])
  from public, anon, authenticated;
revoke all on function public.normalize_production_execution_actuals(uuid,jsonb)
  from public, anon, authenticated;
revoke all on function public.prepare_production_execution(uuid) from public, anon, authenticated;
revoke all on function public.start_production_execution(uuid) from public, anon, authenticated;
revoke all on function public.report_production_issue(uuid,public.production_issue_category,text)
  from public, anon, authenticated;
revoke all on function public.resolve_production_issue(uuid,public.production_execution_status,text)
  from public, anon, authenticated;
revoke all on function public.calculate_production_execution_completion(uuid,jsonb)
  from public, anon, authenticated;

select routine_name, security_type from information_schema.routines
where routine_schema = 'public' and routine_name in (
  'prepare_production_execution','start_production_execution','report_production_issue',
  'resolve_production_issue','calculate_production_execution_completion'
) order by routine_name;
