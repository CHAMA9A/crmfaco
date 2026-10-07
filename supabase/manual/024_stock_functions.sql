-- SOMA / FACOLUB stock module - 024 trusted stock operations
-- Depends on: 020-023
-- All balance-changing operations use the same per-item/per-location advisory
-- transaction lock. Concurrent OUT movements and reservations are serialized.

create or replace function public.assert_stock_actor(required_roles public.app_role[])
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  actor_role public.app_role;
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select profile.role
  into actor_role
  from public.profiles profile
  join public.user_environment_access access
    on access.user_id = profile.id and access.is_active
  join public.environments environment
    on environment.id = access.environment_id and environment.is_active
  where profile.id = actor_id
    and profile.is_active
    and environment.code = 'FACOLUB';

  if actor_role is null or not (actor_role = any(required_roles)) then
    raise exception 'FACOLUB stock operation is not permitted for this user'
      using errcode = '42501';
  end if;
  return actor_id;
end;
$$;

create or replace function public.lock_stock_balance(
  target_stock_item_id uuid,
  target_location_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A hash collision can only cause extra serialization, never an unsafe write.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_stock_item_id::text || ':' || target_location_id::text, 0)
  );
end;
$$;

create or replace function public.stock_quantities(
  target_stock_item_id uuid,
  target_location_id uuid
)
returns table (
  physical_quantity numeric,
  reserved_quantity numeric,
  available_quantity numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with quantities as (
    select
      coalesce((
        select sum(case movement.direction
          when 'in'::public.stock_direction then movement.quantity
          else -movement.quantity
        end)
        from public.stock_movements movement
        where movement.stock_item_id = target_stock_item_id
          and movement.location_id = target_location_id
      ), 0)::numeric as physical_quantity,
      coalesce((
        select sum(reservation.quantity)
        from public.stock_reservations reservation
        where reservation.stock_item_id = target_stock_item_id
          and reservation.location_id = target_location_id
          and reservation.status = 'active'::public.stock_reservation_status
      ), 0)::numeric as reserved_quantity
  )
  select
    quantities.physical_quantity,
    quantities.reserved_quantity,
    quantities.physical_quantity - quantities.reserved_quantity
  from quantities
$$;

create or replace function public.default_stock_location_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select location.id
  from public.stock_locations location
  where location.code = 'FACOLUB-MAIN' and location.is_active
$$;

create or replace function public.record_stock_movement(
  target_stock_item_id uuid,
  target_location_id uuid,
  target_movement_type public.stock_movement_type,
  target_quantity numeric,
  target_direction public.stock_direction,
  target_reference_type text default null,
  target_reference_id uuid default null,
  target_reason text default null,
  target_metadata jsonb default '{}'::jsonb,
  target_allow_negative boolean default false
)
returns table (
  movement_id uuid,
  physical_quantity numeric,
  reserved_quantity numeric,
  available_quantity numeric
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  actor_role public.app_role;
  effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
  current_physical numeric;
  current_reserved numeric;
  new_physical numeric;
  inserted_movement_id uuid;
begin
  actor_id := public.assert_stock_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  actor_role := public.current_app_role();

  if target_quantity is null or target_quantity <= 0 then
    raise exception 'Stock movement quantity must be greater than zero' using errcode = '22023';
  end if;
  if target_movement_type = 'correction'::public.stock_movement_type then
    raise exception 'Use record_stock_correction to preserve correction linkage'
      using errcode = '22023';
  end if;
  if target_movement_type = 'reservation_release_related'::public.stock_movement_type then
    raise exception 'Reservation changes are non-physical and must use reservation functions'
      using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(target_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'Stock movement metadata must be a JSON object' using errcode = '22023';
  end if;

  if target_movement_type in (
      'opening_balance'::public.stock_movement_type,
      'receipt'::public.stock_movement_type,
      'preparation_output'::public.stock_movement_type,
      'production_output'::public.stock_movement_type,
      'adjustment_in'::public.stock_movement_type
    ) and target_direction <> 'in'::public.stock_direction then
    raise exception 'Movement type % requires direction IN', target_movement_type
      using errcode = '22023';
  end if;
  if target_movement_type in (
      'preparation_consumption'::public.stock_movement_type,
      'production_consumption'::public.stock_movement_type,
      'dispatch'::public.stock_movement_type,
      'adjustment_out'::public.stock_movement_type,
      'loss'::public.stock_movement_type,
      'damage'::public.stock_movement_type
    ) and target_direction <> 'out'::public.stock_direction then
    raise exception 'Movement type % requires direction OUT', target_movement_type
      using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.stock_items item
    where item.id = target_stock_item_id and item.is_active
  ) then
    raise exception 'Active stock item not found' using errcode = 'P0002';
  end if;
  if effective_location_id is null or not exists (
    select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active
  ) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;

  if target_allow_negative and (
    actor_role <> 'admin'::public.app_role
    or target_movement_type <> 'adjustment_out'::public.stock_movement_type
  ) then
    raise exception 'Only Admin adjustment reconciliation may allow negative physical stock'
      using errcode = '42501';
  end if;

  perform public.lock_stock_balance(target_stock_item_id, effective_location_id);
  select quantities.physical_quantity, quantities.reserved_quantity
  into current_physical, current_reserved
  from public.stock_quantities(target_stock_item_id, effective_location_id) quantities;

  if target_direction = 'out'::public.stock_direction
    and target_quantity > current_physical
    and not target_allow_negative then
    raise exception 'Insufficient physical stock: requested %, physical %',
      target_quantity, current_physical using errcode = '23514';
  end if;

  insert into public.stock_movements (
    stock_item_id, location_id, movement_type, quantity, direction,
    reference_type, reference_id, reason, created_by, metadata
  ) values (
    target_stock_item_id,
    effective_location_id,
    target_movement_type,
    target_quantity,
    target_direction,
    nullif(trim(target_reference_type), ''),
    target_reference_id,
    nullif(trim(target_reason), ''),
    actor_id,
    coalesce(target_metadata, '{}'::jsonb)
  )
  returning id into inserted_movement_id;

  new_physical := current_physical + case target_direction
    when 'in'::public.stock_direction then target_quantity
    else -target_quantity
  end;

  return query select
    inserted_movement_id,
    new_physical,
    current_reserved,
    new_physical - current_reserved;
end;
$$;

create or replace function public.record_stock_correction(
  target_movement_id uuid,
  target_quantity numeric,
  target_reason text,
  target_allow_negative boolean default false
)
returns table (
  movement_id uuid,
  physical_quantity numeric,
  reserved_quantity numeric,
  available_quantity numeric
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  original public.stock_movements;
  correction_direction public.stock_direction;
  existing_correction_quantity numeric;
  current_physical numeric;
  current_reserved numeric;
  new_physical numeric;
  inserted_movement_id uuid;
begin
  actor_id := public.assert_stock_actor(array['admin'::public.app_role]);
  if target_quantity is null or target_quantity <= 0 then
    raise exception 'Correction quantity must be greater than zero' using errcode = '22023';
  end if;
  if target_reason is null or char_length(trim(target_reason)) < 1 then
    raise exception 'Correction reason is required' using errcode = '22023';
  end if;

  select movement.* into original
  from public.stock_movements movement
  where movement.id = target_movement_id
  for update;
  if not found then
    raise exception 'Original stock movement not found' using errcode = 'P0002';
  end if;

  perform public.lock_stock_balance(original.stock_item_id, original.location_id);
  select coalesce(sum(movement.quantity), 0)
  into existing_correction_quantity
  from public.stock_movements movement
  where movement.corrected_movement_id = original.id;
  if existing_correction_quantity + target_quantity > original.quantity then
    raise exception 'Correction exceeds the remaining original movement quantity'
      using errcode = '23514';
  end if;

  correction_direction := case original.direction
    when 'in'::public.stock_direction then 'out'::public.stock_direction
    else 'in'::public.stock_direction
  end;
  select quantities.physical_quantity, quantities.reserved_quantity
  into current_physical, current_reserved
  from public.stock_quantities(original.stock_item_id, original.location_id) quantities;

  if correction_direction = 'out'::public.stock_direction
    and target_quantity > current_physical
    and not target_allow_negative then
    raise exception 'Correction would make physical stock negative; Admin must explicitly allow reconciliation'
      using errcode = '23514';
  end if;

  insert into public.stock_movements (
    stock_item_id, location_id, movement_type, quantity, direction,
    reference_type, reference_id, reason, created_by, corrected_movement_id, metadata
  ) values (
    original.stock_item_id,
    original.location_id,
    'correction'::public.stock_movement_type,
    target_quantity,
    correction_direction,
    'stock_movement',
    original.id,
    trim(target_reason),
    actor_id,
    original.id,
    jsonb_build_object('original_movement_type', original.movement_type)
  )
  returning id into inserted_movement_id;

  new_physical := current_physical + case correction_direction
    when 'in'::public.stock_direction then target_quantity
    else -target_quantity
  end;
  return query select
    inserted_movement_id,
    new_physical,
    current_reserved,
    new_physical - current_reserved;
end;
$$;

create or replace function public.get_stock_balance(
  target_stock_item_id uuid,
  target_location_id uuid default null
)
returns table (
  stock_item_id uuid,
  location_id uuid,
  physical_quantity numeric,
  reserved_quantity numeric,
  available_quantity numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
begin
  perform public.assert_stock_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  return query
  select
    target_stock_item_id,
    effective_location_id,
    quantities.physical_quantity,
    quantities.reserved_quantity,
    quantities.available_quantity
  from public.stock_quantities(target_stock_item_id, effective_location_id) quantities;
end;
$$;

create or replace function public.get_stock_movement_history(
  target_stock_item_id uuid default null,
  target_category public.stock_item_category default null,
  target_date_from date default null,
  target_date_to date default null,
  target_movement_type public.stock_movement_type default null,
  target_created_by uuid default null,
  target_limit integer default 250
)
returns table (
  id uuid,
  created_at timestamptz,
  stock_item_id uuid,
  stock_item_name text,
  category public.stock_item_category,
  location_id uuid,
  location_name text,
  movement_type public.stock_movement_type,
  direction public.stock_direction,
  quantity numeric,
  created_by uuid,
  created_by_name text,
  reason text,
  reference_type text,
  reference_id uuid,
  corrected_movement_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.assert_stock_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  return query
  select
    movement.id,
    movement.created_at,
    item.id,
    item.name,
    item.category,
    location.id,
    location.name,
    movement.movement_type,
    movement.direction,
    movement.quantity,
    movement.created_by,
    profile.display_name,
    movement.reason,
    movement.reference_type,
    movement.reference_id,
    movement.corrected_movement_id
  from public.stock_movements movement
  join public.stock_items item on item.id = movement.stock_item_id
  join public.stock_locations location on location.id = movement.location_id
  join public.profiles profile on profile.id = movement.created_by
  where (target_stock_item_id is null or movement.stock_item_id = target_stock_item_id)
    and (target_category is null or item.category = target_category)
    and (target_date_from is null or movement.created_at >= target_date_from::timestamptz)
    and (target_date_to is null or movement.created_at < (target_date_to + 1)::timestamptz)
    and (target_movement_type is null or movement.movement_type = target_movement_type)
    and (target_created_by is null or movement.created_by = target_created_by)
  order by movement.created_at desc, movement.id desc
  limit least(greatest(coalesce(target_limit, 250), 1), 1000);
end;
$$;

create or replace function public.create_stock_reservation(
  target_stock_item_id uuid,
  target_location_id uuid,
  target_quantity numeric,
  target_reference_type text,
  target_reference_id uuid
)
returns public.stock_reservations
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
  quantities record;
  result public.stock_reservations;
begin
  actor_id := public.assert_stock_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  if target_quantity is null or target_quantity <= 0 then
    raise exception 'Reservation quantity must be greater than zero' using errcode = '22023';
  end if;
  if target_reference_id is null
    or target_reference_type is null
    or char_length(trim(target_reference_type)) < 1 then
    raise exception 'Reservation reference type and ID are required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.stock_items item
    where item.id = target_stock_item_id and item.is_active
  ) then
    raise exception 'Active stock item not found' using errcode = 'P0002';
  end if;
  if effective_location_id is null or not exists (
    select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active
  ) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;

  perform public.lock_stock_balance(target_stock_item_id, effective_location_id);
  if exists (
    select 1
    from public.stock_reservations reservation
    where reservation.stock_item_id = target_stock_item_id
      and reservation.location_id = effective_location_id
      and reservation.reference_type = trim(target_reference_type)
      and reservation.reference_id = target_reference_id
      and reservation.status = 'active'::public.stock_reservation_status
  ) then
    raise exception 'An active reservation already exists for this reference'
      using errcode = '23505';
  end if;

  select * into quantities
  from public.stock_quantities(target_stock_item_id, effective_location_id);
  if target_quantity > quantities.available_quantity then
    raise exception 'Reservation exceeds available stock: requested %, available %',
      target_quantity, quantities.available_quantity using errcode = '23514';
  end if;

  insert into public.stock_reservations (
    stock_item_id, location_id, quantity, status,
    reference_type, reference_id, created_by
  ) values (
    target_stock_item_id,
    effective_location_id,
    target_quantity,
    'active'::public.stock_reservation_status,
    trim(target_reference_type),
    target_reference_id,
    actor_id
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.release_stock_reservation(target_reservation_id uuid)
returns public.stock_reservations
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.stock_reservations;
begin
  perform public.assert_stock_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  select reservation.* into result
  from public.stock_reservations reservation
  where reservation.id = target_reservation_id
  for update;
  if not found then
    raise exception 'Stock reservation not found' using errcode = 'P0002';
  end if;
  perform public.lock_stock_balance(result.stock_item_id, result.location_id);
  if result.status <> 'active'::public.stock_reservation_status then
    raise exception 'Only an active reservation can be released' using errcode = '23514';
  end if;
  update public.stock_reservations reservation
  set status = 'released'::public.stock_reservation_status, released_at = now()
  where reservation.id = target_reservation_id
  returning * into result;
  return result;
end;
$$;

create or replace function public.consume_stock_reservation(target_reservation_id uuid)
returns public.stock_reservations
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.stock_reservations;
begin
  perform public.assert_stock_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  select reservation.* into result
  from public.stock_reservations reservation
  where reservation.id = target_reservation_id
  for update;
  if not found then
    raise exception 'Stock reservation not found' using errcode = 'P0002';
  end if;
  perform public.lock_stock_balance(result.stock_item_id, result.location_id);
  if result.status <> 'active'::public.stock_reservation_status then
    raise exception 'Only an active reservation can be consumed' using errcode = '23514';
  end if;
  -- Consuming a reservation releases only the allocation. Future dispatch or
  -- production code must record its physical OUT movement separately/atomically.
  update public.stock_reservations reservation
  set status = 'consumed'::public.stock_reservation_status, consumed_at = now()
  where reservation.id = target_reservation_id
  returning * into result;
  return result;
end;
$$;

create or replace function public.save_stock_item(
  target_id uuid,
  target_code text,
  target_name text,
  target_category public.stock_item_category,
  target_unit public.stock_unit,
  target_product_format_id uuid,
  target_minimum_stock numeric,
  target_notes text,
  target_is_active boolean
)
returns public.stock_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.stock_items;
begin
  perform public.assert_stock_actor(array['admin'::public.app_role]);
  if target_name is null or char_length(trim(target_name)) < 1 then
    raise exception 'Stock item name is required' using errcode = '22023';
  end if;
  if target_minimum_stock is not null and target_minimum_stock < 0 then
    raise exception 'Minimum stock cannot be negative' using errcode = '22023';
  end if;

  if target_id is null then
    insert into public.stock_items (
      code, name, category, unit, product_format_id, minimum_stock, notes, is_active
    ) values (
      nullif(upper(trim(target_code)), ''), trim(target_name), target_category, target_unit,
      target_product_format_id, target_minimum_stock, nullif(trim(target_notes), ''),
      coalesce(target_is_active, true)
    ) returning * into result;
  else
    update public.stock_items item
    set code = nullif(upper(trim(target_code)), ''),
        name = trim(target_name),
        category = target_category,
        unit = target_unit,
        product_format_id = target_product_format_id,
        minimum_stock = target_minimum_stock,
        notes = nullif(trim(target_notes), ''),
        is_active = coalesce(target_is_active, item.is_active)
    where item.id = target_id
    returning * into result;
    if not found then
      raise exception 'Stock item not found' using errcode = 'P0002';
    end if;
  end if;
  return result;
end;
$$;

-- Internal helpers are not callable from the API.
revoke all on function public.assert_stock_actor(public.app_role[]) from public, anon, authenticated;
revoke all on function public.lock_stock_balance(uuid, uuid) from public, anon, authenticated;
revoke all on function public.stock_quantities(uuid, uuid) from public, anon, authenticated;
revoke all on function public.default_stock_location_id() from public, anon, authenticated;

-- Public stock API: authenticated callers still pass authorization checks inside each function.
revoke all on function public.record_stock_movement(uuid, uuid, public.stock_movement_type, numeric, public.stock_direction, text, uuid, text, jsonb, boolean) from public, anon;
revoke all on function public.record_stock_correction(uuid, numeric, text, boolean) from public, anon;
revoke all on function public.get_stock_balance(uuid, uuid) from public, anon;
revoke all on function public.get_stock_movement_history(uuid, public.stock_item_category, date, date, public.stock_movement_type, uuid, integer) from public, anon;
revoke all on function public.create_stock_reservation(uuid, uuid, numeric, text, uuid) from public, anon;
revoke all on function public.release_stock_reservation(uuid) from public, anon;
revoke all on function public.consume_stock_reservation(uuid) from public, anon;
revoke all on function public.save_stock_item(uuid, text, text, public.stock_item_category, public.stock_unit, uuid, numeric, text, boolean) from public, anon;

grant execute on function public.record_stock_movement(uuid, uuid, public.stock_movement_type, numeric, public.stock_direction, text, uuid, text, jsonb, boolean) to authenticated;
grant execute on function public.record_stock_correction(uuid, numeric, text, boolean) to authenticated;
grant execute on function public.get_stock_balance(uuid, uuid) to authenticated;
grant execute on function public.get_stock_movement_history(uuid, public.stock_item_category, date, date, public.stock_movement_type, uuid, integer) to authenticated;
grant execute on function public.create_stock_reservation(uuid, uuid, numeric, text, uuid) to authenticated;
grant execute on function public.release_stock_reservation(uuid) to authenticated;
grant execute on function public.consume_stock_reservation(uuid) to authenticated;
grant execute on function public.save_stock_item(uuid, text, text, public.stock_item_category, public.stock_unit, uuid, numeric, text, boolean) to authenticated;

-- Verification query:
select routine_name, security_type
from information_schema.routines
where routine_schema = 'public' and routine_name in (
  'record_stock_movement', 'record_stock_correction', 'get_stock_balance',
  'get_stock_movement_history', 'create_stock_reservation',
  'release_stock_reservation', 'consume_stock_reservation', 'save_stock_item'
)
order by routine_name;
