-- SOMA / FACOLUB production execution - 073 read scope and RPC grants
-- Depends on: 070-072.

create or replace function public.get_production_execution(target_execution_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.assert_execution_actor(target_execution_id, array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  return public.production_execution_payload(target_execution_id);
end;
$$;

create or replace function public.list_production_executions(
  target_date_from date default null,
  target_date_to date default null,
  target_status public.production_execution_status default null,
  target_limit integer default 200
)
returns table (
  execution_id uuid, execution_number text, plan_id uuid, plan_number text,
  production_date date, status public.production_execution_status,
  product_summary text, planned_bottles numeric, actual_bottles numeric,
  variance_bottles numeric, started_by_name text, completed_by_name text,
  started_at timestamptz, completed_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.assert_planning_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  return query
  select execution.id, execution.execution_number, plan.id, plan.plan_number,
    plan.production_date, execution.status,
    string_agg(item.product_name_snapshot || ' ' || item.format_name_snapshot,
      ', ' order by item.position),
    sum(execution_item.planned_bottles), sum(execution_item.actual_bottles),
    case when execution.status = 'done' then
      sum(execution_item.actual_bottles) - sum(execution_item.planned_bottles) end,
    starter.display_name, completer.display_name,
    execution.started_at, execution.completed_at
  from public.production_executions execution
  join public.production_plans plan on plan.id = execution.production_plan_id
  join public.production_execution_items execution_item
    on execution_item.production_execution_id = execution.id
  join public.production_plan_items item on item.id = execution_item.production_plan_item_id
  left join public.profiles starter on starter.id = execution.started_by
  left join public.profiles completer on completer.id = execution.completed_by
  where (target_date_from is null or plan.production_date >= target_date_from)
    and (target_date_to is null or plan.production_date <= target_date_to)
    and (target_status is null or execution.status = target_status)
  group by execution.id, plan.id, starter.display_name, completer.display_name
  order by plan.production_date desc, execution.created_at desc
  limit least(greatest(coalesce(target_limit, 200), 1), 500);
end;
$$;

create or replace function public.list_factory_production_execution_missions(
  target_date date default current_date
)
returns table (
  plan_id uuid, plan_number text, execution_id uuid, execution_number text,
  production_date date, priority integer, product_name text, format_name text,
  planned_bottles numeric, planned_cartons numeric,
  execution_status public.production_execution_status,
  reservation_status public.production_reservation_status
)
language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid;
begin
  actor_id := public.assert_planning_actor(array['factory'::public.app_role]);
  return query
  select plan.id, plan.plan_number, execution.id, execution.execution_number,
    plan.production_date, plan.priority,
    plan_item.product_name_snapshot, plan_item.format_name_snapshot,
    plan_item.planned_bottles, plan_item.planned_cartons,
    coalesce(execution.status, 'to_do'::public.production_execution_status),
    plan.reservation_status
  from public.production_plans plan
  join public.production_plan_items plan_item on plan_item.production_plan_id = plan.id
  left join public.production_executions execution on execution.production_plan_id = plan.id
  where plan.production_date = coalesce(target_date, current_date)
    and plan.status = 'validated'
    and plan.reservation_status in ('reserved','consumed')
    and (plan.assigned_to is null or plan.assigned_to = actor_id)
  order by coalesce(plan.priority, 5), plan.created_at, plan_item.position;
end;
$$;

alter table public.production_executions enable row level security;
alter table public.production_execution_items enable row level security;
alter table public.production_issues enable row level security;
alter table public.production_reservation_resolutions enable row level security;

drop policy if exists production_executions_facolub_read on public.production_executions;
create policy production_executions_facolub_read on public.production_executions
for select to authenticated using (
  public.has_environment_access('FACOLUB') and (
    public.current_app_role() in ('admin','management')
    or (public.current_app_role() = 'factory' and exists (
      select 1 from public.production_plans plan
      where plan.id = production_plan_id
        and (plan.assigned_to is null or plan.assigned_to = auth.uid())
    ))
  )
);

drop policy if exists production_execution_items_facolub_read
  on public.production_execution_items;
create policy production_execution_items_facolub_read on public.production_execution_items
for select to authenticated using (
  public.has_environment_access('FACOLUB') and exists (
    select 1 from public.production_executions execution
    where execution.id = production_execution_id
  )
);

drop policy if exists production_issues_facolub_read on public.production_issues;
create policy production_issues_facolub_read on public.production_issues
for select to authenticated using (
  public.has_environment_access('FACOLUB') and exists (
    select 1 from public.production_executions execution
    where execution.id = production_execution_id
  )
);

drop policy if exists production_reservation_resolutions_facolub_read
  on public.production_reservation_resolutions;
create policy production_reservation_resolutions_facolub_read
on public.production_reservation_resolutions
for select to authenticated using (
  public.has_environment_access('FACOLUB') and exists (
    select 1 from public.production_execution_items item
    join public.production_executions execution on execution.id = item.production_execution_id
    where item.id = production_execution_item_id
  )
);

revoke all on public.production_executions from anon, authenticated;
revoke all on public.production_execution_items from anon, authenticated;
revoke all on public.production_issues from anon, authenticated;
revoke all on public.production_reservation_resolutions from anon, authenticated;
grant select on public.production_executions to authenticated;
grant select on public.production_execution_items to authenticated;
grant select on public.production_issues to authenticated;
grant select on public.production_reservation_resolutions to authenticated;

-- Internal primitives.
revoke all on function public.production_execution_payload(uuid)
  from public, anon, authenticated;
revoke all on function public.assert_execution_actor(uuid,public.app_role[])
  from public, anon, authenticated;
revoke all on function public.normalize_production_execution_actuals(uuid,jsonb)
  from public, anon, authenticated;

-- Authenticated entry points; each verifies role, membership, assignment, and state.
grant execute on function public.prepare_production_execution(uuid) to authenticated;
grant execute on function public.start_production_execution(uuid) to authenticated;
grant execute on function public.report_production_issue(
  uuid,public.production_issue_category,text) to authenticated;
grant execute on function public.resolve_production_issue(
  uuid,public.production_execution_status,text) to authenticated;
grant execute on function public.calculate_production_execution_completion(uuid,jsonb)
  to authenticated;
grant execute on function public.complete_production_execution(uuid,jsonb,text)
  to authenticated;
grant execute on function public.get_production_execution(uuid) to authenticated;
grant execute on function public.list_production_executions(
  date,date,public.production_execution_status,integer) to authenticated;
grant execute on function public.list_factory_production_execution_missions(date)
  to authenticated;

revoke all on function public.prepare_production_execution(uuid) from public, anon;
revoke all on function public.start_production_execution(uuid) from public, anon;
revoke all on function public.report_production_issue(
  uuid,public.production_issue_category,text) from public, anon;
revoke all on function public.resolve_production_issue(
  uuid,public.production_execution_status,text) from public, anon;
revoke all on function public.calculate_production_execution_completion(uuid,jsonb)
  from public, anon;
revoke all on function public.complete_production_execution(uuid,jsonb,text)
  from public, anon;
revoke all on function public.get_production_execution(uuid) from public, anon;
revoke all on function public.list_production_executions(
  date,date,public.production_execution_status,integer) from public, anon;
revoke all on function public.list_factory_production_execution_missions(date)
  from public, anon;

select tablename, policyname, cmd, roles from pg_policies
where schemaname = 'public' and tablename in (
  'production_executions','production_execution_items','production_issues',
  'production_reservation_resolutions'
) order by tablename, policyname;
