-- SOMA / FACOLUB production execution - 072 atomic stock completion
-- Depends on: 070-071 and the stock lock/quantity primitives from 024.

alter table public.production_plans
  drop constraint if exists production_plans_reservation_lifecycle_consistent;
alter table public.production_plans
  add constraint production_plans_reservation_lifecycle_consistent check (
    (reservation_status = 'not_reserved' and reserved_by is null and reserved_at is null
      and released_by is null and released_at is null
      and consumed_by is null and consumed_at is null)
    or (reservation_status = 'reserved' and reserved_by is not null and reserved_at is not null
      and released_by is null and released_at is null
      and consumed_by is null and consumed_at is null)
    or (reservation_status = 'released' and reserved_by is not null and reserved_at is not null
      and released_by is not null and released_at is not null
      and consumed_by is null and consumed_at is null)
    or (reservation_status = 'consumed' and reserved_by is not null and reserved_at is not null
      and released_by is null and released_at is null
      and consumed_by is not null and consumed_at is not null)
  );

create or replace function public.protect_production_plan_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare old_core jsonb;
declare new_core jsonb;
declare reservation_transition_allowed boolean := false;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'Only draft production plans can be deleted' using errcode = '55000';
    end if;
    return old;
  end if;
  if old.status = 'cancelled' then
    raise exception 'Cancelled production plans are immutable' using errcode = '55000';
  end if;
  if old.status = 'validated' and new.status <> 'cancelled' then
    old_core := to_jsonb(old) - array[
      'reservation_status','reserved_by','reserved_at','released_by','released_at',
      'consumed_by','consumed_at','updated_at'
    ];
    new_core := to_jsonb(new) - array[
      'reservation_status','reserved_by','reserved_at','released_by','released_at',
      'consumed_by','consumed_at','updated_at'
    ];
    reservation_transition_allowed := old_core = new_core and (
      new.reservation_status = old.reservation_status
      or (old.reservation_status in ('not_reserved','released')
        and new.reservation_status = 'reserved')
      or (old.reservation_status = 'reserved'
        and new.reservation_status in ('released','consumed'))
    );
    if not reservation_transition_allowed then
      raise exception 'Validated production plans are immutable outside reservation lifecycle'
        using errcode = '55000';
    end if;
  end if;
  if old.status = 'planned' and new.status not in ('planned','validated','cancelled') then
    raise exception 'A planned production plan cannot return to draft' using errcode = '55000';
  end if;
  return new;
end;
$$;

create or replace function public.complete_production_execution(
  target_execution_id uuid,
  target_actuals jsonb,
  target_comment text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid;
  execution public.production_executions;
  plan public.production_plans;
  actual record;
  material record;
  candidate record;
  quantities record;
  consumption_quantity numeric;
  movement_id uuid;
begin
  actor_id := public.assert_execution_actor(target_execution_id, array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  select current_execution.* into execution
  from public.production_executions current_execution
  where current_execution.id = target_execution_id for update;
  if not found then raise exception 'Production execution not found' using errcode = 'P0002'; end if;
  if execution.status = 'done' then
    return public.production_execution_payload(execution.id);
  end if;
  if execution.status <> 'in_progress' then
    raise exception 'Only an In Progress execution can be completed' using errcode = '55000';
  end if;
  if exists (select 1 from public.production_issues issue
    where issue.production_execution_id = execution.id and issue.resolved_at is null) then
    raise exception 'Unresolved production issue blocks completion' using errcode = '55000';
  end if;
  select current_plan.* into plan from public.production_plans current_plan
  where current_plan.id = execution.production_plan_id for update;
  if plan.status <> 'validated' or plan.reservation_status <> 'reserved' then
    raise exception 'Production plan is no longer validated and fully reserved'
      using errcode = '55000';
  end if;

  -- Normalize and validate every item before any ledger write.
  perform 1 from public.normalize_production_execution_actuals(execution.id, target_actuals);

  -- Materials and finished outputs share the stock engine advisory lock. All
  -- item/location pairs are locked in UUID order before physical checks/writes.
  for candidate in
    select distinct locked.stock_item_id
    from (
      select requirement.component_stock_item_id as stock_item_id
      from public.production_execution_items item
      join public.production_plan_requirements requirement
        on requirement.production_plan_item_id = item.production_plan_item_id
      where item.production_execution_id = execution.id
      union
      select item.output_stock_item_id from public.production_execution_items item
      where item.production_execution_id = execution.id
    ) locked order by locked.stock_item_id
  loop
    perform public.lock_stock_balance(candidate.stock_item_id, plan.location_id);
  end loop;

  -- Lock and validate the exact S5 reservation rows.
  perform 1
  from public.stock_reservations reservation
  join public.production_plan_requirements requirement
    on requirement.id = reservation.production_plan_requirement_id
  join public.production_plan_items plan_item
    on plan_item.id = requirement.production_plan_item_id
  where plan_item.production_plan_id = plan.id
    and reservation.reference_type = 'production_plan'
    and reservation.reference_id = plan.id
    and reservation.location_id = plan.location_id
    and reservation.status = 'active'
  order by reservation.stock_item_id, reservation.id
  for update of reservation;

  if exists (
    select 1 from public.production_plan_items plan_item
    join public.production_plan_requirements requirement
      on requirement.production_plan_item_id = plan_item.id
    left join public.stock_reservations reservation
      on reservation.production_plan_requirement_id = requirement.id
     and reservation.reference_type = 'production_plan'
     and reservation.reference_id = plan.id
     and reservation.status = 'active'
    where plan_item.production_plan_id = plan.id
      and (reservation.id is null or reservation.quantity <> requirement.quantity_required)
  ) then
    raise exception 'Active reservation coverage is incomplete or changed'
      using errcode = '55000';
  end if;

  -- Even reserved stock may have been damaged or corrected later. Recheck
  -- aggregate physical coverage under the same ordered locks.
  for candidate in
    with normalized as (
      select * from public.normalize_production_execution_actuals(execution.id, target_actuals)
    )
    select requirement.component_stock_item_id as stock_item_id,
      sum(round(requirement.quantity_required * normalized.actual_bottles
        / item.planned_bottles, 3))::numeric as quantity_required
    from public.production_execution_items item
    join normalized on normalized.execution_item_id = item.id
    join public.production_plan_requirements requirement
      on requirement.production_plan_item_id = item.production_plan_item_id
    where item.production_execution_id = execution.id
    group by requirement.component_stock_item_id
    order by requirement.component_stock_item_id
  loop
    select * into quantities from public.stock_quantities(candidate.stock_item_id, plan.location_id);
    if candidate.quantity_required > quantities.physical_quantity then
      raise exception 'Insufficient physical stock at production completion: required %, physical %',
        candidate.quantity_required, quantities.physical_quantity using errcode = '23514';
    end if;
  end loop;

  for actual in select * from public.normalize_production_execution_actuals(
    execution.id, target_actuals) order by execution_item_id
  loop
    update public.production_execution_items item
    set actual_bottles = actual.actual_bottles,
        actual_cartons = actual.actual_cartons
    where item.id = actual.execution_item_id;

    for material in
      select requirement.*, reservation.id as reservation_id,
        reservation.quantity as reserved_quantity
      from public.production_execution_items item
      join public.production_plan_requirements requirement
        on requirement.production_plan_item_id = item.production_plan_item_id
      join public.stock_reservations reservation
        on reservation.production_plan_requirement_id = requirement.id
       and reservation.status = 'active'
      where item.id = actual.execution_item_id
      order by requirement.component_stock_item_id, requirement.id
    loop
      consumption_quantity := round(material.quantity_required
        * actual.actual_bottles
        / (select item.planned_bottles from public.production_execution_items item
           where item.id = actual.execution_item_id), 3);
      if consumption_quantity <= 0 or consumption_quantity > material.reserved_quantity then
        raise exception 'Calculated material consumption is outside reservation coverage'
          using errcode = '23514';
      end if;
      insert into public.stock_movements (
        stock_item_id, location_id, movement_type, quantity, direction,
        reference_type, reference_id, reason, created_by, metadata
      ) values (
        material.component_stock_item_id, plan.location_id,
        'production_consumption', consumption_quantity, 'out',
        'production_execution', execution.id, 'Confirmed production consumption', actor_id,
        jsonb_build_object('execution_item_id', actual.execution_item_id,
          'requirement_id', material.id, 'reservation_id', material.reservation_id)
      ) returning id into movement_id;
      insert into public.production_reservation_resolutions (
        production_execution_item_id, production_plan_requirement_id,
        stock_reservation_id, stock_item_id, original_quantity,
        consumed_quantity, released_quantity, consumption_movement_id, resolved_by
      ) values (
        actual.execution_item_id, material.id, material.reservation_id,
        material.component_stock_item_id, material.reserved_quantity,
        consumption_quantity, material.reserved_quantity - consumption_quantity,
        movement_id, actor_id
      );
      update public.stock_reservations reservation
      set status = 'consumed', consumed_at = now()
      where reservation.id = material.reservation_id;
    end loop;

    insert into public.stock_movements (
      stock_item_id, location_id, movement_type, quantity, direction,
      reference_type, reference_id, reason, created_by, metadata
    )
    select item.output_stock_item_id, plan.location_id,
      'production_output', actual.actual_bottles, 'in',
      'production_execution', execution.id, 'Confirmed finished production', actor_id,
      jsonb_build_object('execution_item_id', item.id)
    from public.production_execution_items item where item.id = actual.execution_item_id
    returning id into movement_id;
    update public.production_execution_items item set output_movement_id = movement_id
    where item.id = actual.execution_item_id;
  end loop;

  update public.production_plans current_plan
  set reservation_status = 'consumed', consumed_by = actor_id, consumed_at = now()
  where current_plan.id = plan.id;
  update public.production_executions current_execution
  set status = 'done', completed_by = actor_id, completed_at = now(),
      comment = coalesce(nullif(trim(target_comment), ''), current_execution.comment)
  where current_execution.id = execution.id;
  return public.production_execution_payload(execution.id);
end;
$$;

-- S6 prevents S5 cancellation from releasing or rewriting an execution that
-- has started, is blocked, or is already done.
create or replace function public.cancel_production_plan(target_plan_id uuid)
returns public.production_plans language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare result public.production_plans;
declare execution public.production_executions;
begin
  actor_id := public.assert_planning_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  select plan.* into result from public.production_plans plan
  where plan.id = target_plan_id for update;
  if not found then raise exception 'Production plan not found' using errcode = 'P0002'; end if;
  if result.status = 'cancelled' then return result; end if;
  select candidate.* into execution from public.production_executions candidate
  where candidate.production_plan_id = result.id for update;
  if found and execution.status in ('in_progress','blocked','done') then
    raise exception 'Started, blocked, or completed production cannot be cancelled through planning'
      using errcode = '55000';
  end if;
  if result.reservation_status = 'consumed' then
    raise exception 'Consumed production plan cannot be cancelled' using errcode = '55000';
  end if;
  if result.reservation_status = 'reserved' then
    perform public.release_production_plan_reservations_internal(result.id, actor_id);
  end if;
  if execution.id is not null then
    update public.production_executions candidate set status = 'cancelled'
    where candidate.id = execution.id;
  end if;
  update public.production_plans plan set status = 'cancelled'
  where plan.id = result.id returning * into result;
  return result;
end;
$$;

revoke all on function public.complete_production_execution(uuid,jsonb,text)
  from public, anon, authenticated;
revoke all on function public.protect_production_plan_lifecycle()
  from public, anon, authenticated;

select
  position('lock_stock_balance' in pg_get_functiondef(
    'public.complete_production_execution(uuid,jsonb,text)'::regprocedure)) > 0
    as uses_stock_locks,
  position('production_consumption' in pg_get_functiondef(
    'public.complete_production_execution(uuid,jsonb,text)'::regprocedure)) > 0
    as posts_consumption,
  position('production_output' in pg_get_functiondef(
    'public.complete_production_execution(uuid,jsonb,text)'::regprocedure)) > 0
    as posts_output;
