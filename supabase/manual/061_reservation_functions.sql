-- SOMA / FACOLUB production module - 061 trusted reservation operations
-- Depends on: 060 plus the stock and planning functions from 024 and 053.
-- Reservation is full-plan/all-or-nothing and never creates stock movements.

create or replace function public.production_plan_reservation_payload(target_plan_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'plan_id', plan.id,
    'plan_number', plan.plan_number,
    'plan_status', plan.status,
    'reservation_status', plan.reservation_status,
    'reserved_by', plan.reserved_by,
    'reserved_at', plan.reserved_at,
    'released_by', plan.released_by,
    'released_at', plan.released_at,
    'active_reservation_count', (
      select count(*)
      from public.stock_reservations reservation
      where reservation.reference_type = 'production_plan'
        and reservation.reference_id = plan.id
        and reservation.status = 'active'
    ),
    'reservations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reservation_id', reservation.id,
        'requirement_id', reservation.production_plan_requirement_id,
        'stock_item_id', reservation.stock_item_id,
        'stock_item_name', stock_item.name,
        'unit', stock_item.unit,
        'quantity', reservation.quantity,
        'status', reservation.status,
        'created_by', reservation.created_by,
        'created_at', reservation.created_at,
        'released_at', reservation.released_at,
        'physical_quantity', quantities.physical_quantity,
        'reserved_quantity', quantities.reserved_quantity,
        'available_quantity', quantities.available_quantity,
        'minimum_stock', stock_item.minimum_stock,
        'below_minimum', stock_item.minimum_stock is not null
          and quantities.available_quantity < stock_item.minimum_stock
      ) order by reservation.created_at, reservation.id)
      from public.stock_reservations reservation
      join public.stock_items stock_item on stock_item.id = reservation.stock_item_id
      cross join lateral public.stock_quantities(
        reservation.stock_item_id, reservation.location_id
      ) quantities
      where reservation.reference_type = 'production_plan'
        and reservation.reference_id = plan.id
    ), '[]'::jsonb)
  )
  from public.production_plans plan
  where plan.id = target_plan_id
$$;

create or replace function public.reserve_production_plan(target_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  plan public.production_plans;
  candidate record;
  quantities record;
  requirement_count bigint;
  active_count bigint;
begin
  actor_id := public.assert_planning_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);

  select current_plan.* into plan
  from public.production_plans current_plan
  where current_plan.id = target_plan_id
  for update;
  if not found then
    raise exception 'Production plan not found' using errcode = 'P0002';
  end if;
  if plan.status <> 'validated'::public.production_plan_status then
    raise exception 'Only a validated production plan can reserve stock'
      using errcode = '55000';
  end if;

  select count(*) into requirement_count
  from public.production_plan_items item
  join public.production_plan_requirements requirement
    on requirement.production_plan_item_id = item.id
  where item.production_plan_id = plan.id;
  if requirement_count = 0 then
    raise exception 'Validated production plan has no requirement snapshot'
      using errcode = '23514';
  end if;

  if plan.reservation_status = 'reserved'::public.production_reservation_status then
    select count(*) into active_count
    from public.stock_reservations reservation
    where reservation.reference_type = 'production_plan'
      and reservation.reference_id = plan.id
      and reservation.status = 'active';
    if active_count <> requirement_count then
      raise exception 'Reserved plan has an incomplete active reservation set'
        using errcode = '55000';
    end if;
    return public.production_plan_reservation_payload(plan.id);
  end if;

  -- Every item/location lock is acquired in UUID order. The second pass reads
  -- availability only after all locks are held, preventing partial success and
  -- deadlocks between overlapping production plans.
  for candidate in
    select requirement.component_stock_item_id,
      sum(requirement.quantity_required)::numeric as quantity_required
    from public.production_plan_items item
    join public.production_plan_requirements requirement
      on requirement.production_plan_item_id = item.id
    where item.production_plan_id = plan.id
    group by requirement.component_stock_item_id
    order by requirement.component_stock_item_id
  loop
    perform public.lock_stock_balance(candidate.component_stock_item_id, plan.location_id);
  end loop;

  for candidate in
    select requirement.component_stock_item_id,
      stock_item.name as component_name,
      sum(requirement.quantity_required)::numeric as quantity_required
    from public.production_plan_items item
    join public.production_plan_requirements requirement
      on requirement.production_plan_item_id = item.id
    join public.stock_items stock_item on stock_item.id = requirement.component_stock_item_id
    where item.production_plan_id = plan.id
    group by requirement.component_stock_item_id, stock_item.name
    order by requirement.component_stock_item_id
  loop
    select * into quantities
    from public.stock_quantities(candidate.component_stock_item_id, plan.location_id);
    if candidate.quantity_required > quantities.available_quantity then
      raise exception 'Insufficient available stock for %: required %, available %',
        candidate.component_name, candidate.quantity_required, quantities.available_quantity
        using errcode = '23514';
    end if;
  end loop;

  insert into public.stock_reservations (
    stock_item_id, location_id, quantity, status,
    reference_type, reference_id, production_plan_requirement_id, created_by
  )
  select
    requirement.component_stock_item_id,
    plan.location_id,
    requirement.quantity_required,
    'active'::public.stock_reservation_status,
    'production_plan',
    plan.id,
    requirement.id,
    actor_id
  from public.production_plan_items item
  join public.production_plan_requirements requirement
    on requirement.production_plan_item_id = item.id
  where item.production_plan_id = plan.id
  order by requirement.component_stock_item_id, requirement.id;

  update public.production_plans current_plan
  set reservation_status = 'reserved'::public.production_reservation_status,
      reserved_by = actor_id,
      reserved_at = now(),
      released_by = null,
      released_at = null
  where current_plan.id = plan.id;

  return public.production_plan_reservation_payload(plan.id);
end;
$$;

create or replace function public.release_production_plan_reservations_internal(
  target_plan_id uuid,
  actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare candidate record;
begin
  for candidate in
    select distinct reservation.stock_item_id
    from public.stock_reservations reservation
    join public.production_plans plan on plan.id = reservation.reference_id
    where reservation.reference_type = 'production_plan'
      and reservation.reference_id = target_plan_id
      and reservation.location_id = plan.location_id
      and reservation.status = 'active'
    order by reservation.stock_item_id
  loop
    perform public.lock_stock_balance(candidate.stock_item_id,
      (select plan.location_id from public.production_plans plan where plan.id = target_plan_id));
  end loop;

  update public.stock_reservations reservation
  set status = 'released'::public.stock_reservation_status,
      released_at = now()
  where reservation.reference_type = 'production_plan'
    and reservation.reference_id = target_plan_id
    and reservation.status = 'active';

  update public.production_plans plan
  set reservation_status = 'released'::public.production_reservation_status,
      released_by = actor_id,
      released_at = now()
  where plan.id = target_plan_id;
end;
$$;

create or replace function public.release_production_plan_reservations(target_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  plan public.production_plans;
begin
  actor_id := public.assert_planning_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  select current_plan.* into plan
  from public.production_plans current_plan
  where current_plan.id = target_plan_id
  for update;
  if not found then
    raise exception 'Production plan not found' using errcode = 'P0002';
  end if;
  if plan.status = 'cancelled'::public.production_plan_status then
    return public.production_plan_reservation_payload(plan.id);
  end if;
  if plan.status <> 'validated'::public.production_plan_status then
    raise exception 'Only a validated production plan can release reservations'
      using errcode = '55000';
  end if;
  if plan.reservation_status = 'released'::public.production_reservation_status then
    return public.production_plan_reservation_payload(plan.id);
  end if;
  if plan.reservation_status <> 'reserved'::public.production_reservation_status then
    raise exception 'Production plan has no active reservation set'
      using errcode = '55000';
  end if;

  perform public.release_production_plan_reservations_internal(plan.id, actor_id);
  return public.production_plan_reservation_payload(plan.id);
end;
$$;

-- S5 replaces the S4 cancellation body so cancellation and release are one
-- transaction. Retrying cancellation remains idempotent.
create or replace function public.cancel_production_plan(target_plan_id uuid)
returns public.production_plans
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  result public.production_plans;
begin
  actor_id := public.assert_planning_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  select plan.* into result
  from public.production_plans plan
  where plan.id = target_plan_id
  for update;
  if not found then
    raise exception 'Production plan not found' using errcode = 'P0002';
  end if;
  if result.status = 'cancelled'::public.production_plan_status then
    return result;
  end if;
  if result.reservation_status = 'reserved'::public.production_reservation_status then
    perform public.release_production_plan_reservations_internal(result.id, actor_id);
  end if;
  update public.production_plans plan
  set status = 'cancelled'::public.production_plan_status
  where plan.id = result.id
  returning * into result;
  return result;
end;
$$;

create or replace function public.get_production_plan_reservations(target_plan_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  actor_role public.app_role;
  plan public.production_plans;
  payload jsonb;
begin
  actor_id := public.assert_planning_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  select candidate.* into plan
  from public.production_plans candidate
  where candidate.id = target_plan_id;
  if not found then
    raise exception 'Production plan not found' using errcode = 'P0002';
  end if;
  if actor_role = 'factory'::public.app_role and not (
    plan.status in ('planned'::public.production_plan_status,
                    'validated'::public.production_plan_status)
    and (plan.assigned_to is null or plan.assigned_to = actor_id)
  ) then
    raise exception 'Production mission is not visible to this Factory user'
      using errcode = '42501';
  end if;

  payload := public.production_plan_reservation_payload(plan.id);
  if actor_role = 'factory'::public.app_role then
    return jsonb_build_object(
      'plan_id', plan.id,
      'plan_number', plan.plan_number,
      'plan_status', plan.status,
      'reservation_status', plan.reservation_status,
      'active_reservation_count', payload -> 'active_reservation_count'
    );
  end if;
  return payload;
end;
$$;

create or replace function public.list_production_plan_reservation_history(
  target_plan_id uuid default null,
  target_limit integer default 200
)
returns table (
  reservation_id uuid,
  plan_id uuid,
  plan_number text,
  requirement_id uuid,
  stock_item_id uuid,
  stock_item_name text,
  quantity numeric,
  unit public.stock_unit,
  status public.stock_reservation_status,
  created_by uuid,
  created_by_name text,
  created_at timestamptz,
  released_at timestamptz,
  consumed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.assert_planning_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  return query
  select reservation.id, plan.id, plan.plan_number,
    reservation.production_plan_requirement_id,
    reservation.stock_item_id, stock_item.name,
    reservation.quantity, stock_item.unit, reservation.status,
    reservation.created_by, creator.display_name,
    reservation.created_at, reservation.released_at, reservation.consumed_at
  from public.stock_reservations reservation
  join public.production_plans plan on plan.id = reservation.reference_id
  join public.stock_items stock_item on stock_item.id = reservation.stock_item_id
  join public.profiles creator on creator.id = reservation.created_by
  where reservation.reference_type = 'production_plan'
    and (target_plan_id is null or plan.id = target_plan_id)
  order by reservation.created_at desc, reservation.id desc
  limit least(greatest(coalesce(target_limit, 200), 1), 500);
end;
$$;

revoke all on function public.production_plan_reservation_payload(uuid)
  from public, anon, authenticated;
revoke all on function public.release_production_plan_reservations_internal(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.reserve_production_plan(uuid) from public, anon, authenticated;
revoke all on function public.release_production_plan_reservations(uuid)
  from public, anon, authenticated;
revoke all on function public.get_production_plan_reservations(uuid)
  from public, anon, authenticated;
revoke all on function public.list_production_plan_reservation_history(uuid,integer)
  from public, anon, authenticated;

-- Verification query: all S5 routines must be SECURITY DEFINER.
select routine_name, security_type
from information_schema.routines
where routine_schema = 'public' and routine_name in (
  'reserve_production_plan', 'release_production_plan_reservations',
  'get_production_plan_reservations',
  'list_production_plan_reservation_history'
)
order by routine_name;
