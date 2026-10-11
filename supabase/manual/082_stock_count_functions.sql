-- SOMA / FACOLUB stock counts - 082 trusted lifecycle and adjustment functions
-- Depends on: 080-081 and stock primitives from 024.

create or replace function public.assert_stock_count_actor(required_roles public.app_role[])
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  return public.assert_stock_actor(required_roles);
end;
$$;

create or replace function public.allocate_stock_count_number(target_date date)
returns text language plpgsql security definer set search_path = '' as $$
declare next_value integer;
begin
  insert into public.stock_count_number_sequences (count_date, last_value)
  values (target_date, 1)
  on conflict (count_date) do update
    set last_value = public.stock_count_number_sequences.last_value + 1
  returning last_value into next_value;
  return 'CNT-' || to_char(target_date, 'DDMMYY') || '-' || lpad(next_value::text, 2, '0');
end;
$$;

create or replace function public.stock_count_payload(target_count_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'count', to_jsonb(count),
    'location_name', location.name,
    'created_by_name', creator.display_name,
    'submitted_by_name', submitter.display_name,
    'approved_by_name', approver.display_name,
    'rejected_by_name', rejecter.display_name,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'item', to_jsonb(line),
      'stock_item_name', stock_item.name,
      'unit', stock_item.unit,
      'adjustment', case when adjustment.id is null then null else to_jsonb(adjustment) end,
      'movement', case when movement.id is null then null else to_jsonb(movement) end,
      'current_balance', jsonb_build_object(
        'physical_quantity', quantities.physical_quantity,
        'reserved_quantity', quantities.reserved_quantity,
        'available_quantity', quantities.available_quantity,
        'reservation_shortage', quantities.reserved_quantity > quantities.physical_quantity
      )
    ) order by line.position, line.id)
    from public.stock_count_items line
    join public.stock_items stock_item on stock_item.id = line.stock_item_id
    cross join lateral public.stock_quantities(line.stock_item_id, line.location_id) quantities
    left join public.stock_adjustments adjustment on adjustment.stock_count_item_id = line.id
    left join public.stock_movements movement on movement.id = adjustment.stock_movement_id
    where line.stock_count_id = count.id), '[]'::jsonb),
    'attachments', coalesce((select jsonb_agg(to_jsonb(attachment)
      order by attachment.created_at, attachment.id)
      from public.stock_count_attachments attachment
      where attachment.stock_count_id = count.id), '[]'::jsonb)
  )
  from public.stock_counts count
  join public.stock_locations location on location.id = count.location_id
  join public.profiles creator on creator.id = count.created_by
  left join public.profiles submitter on submitter.id = count.submitted_by
  left join public.profiles approver on approver.id = count.approved_by
  left join public.profiles rejecter on rejecter.id = count.rejected_by
  where count.id = target_count_id
$$;

create or replace function public.create_stock_count_draft(
  target_location_id uuid default null,
  target_count_date date default current_date,
  target_comment text default null
)
returns public.stock_counts language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
declare result public.stock_counts;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  if target_count_date is null then
    raise exception 'Count date is required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;
  insert into public.stock_counts (location_id, count_date, comment, created_by)
  values (effective_location_id, target_count_date, nullif(trim(target_comment), ''), actor_id)
  returning * into result;
  return result;
end;
$$;

create or replace function public.add_stock_count_item(
  target_count_id uuid,
  target_stock_item_id uuid,
  target_position integer default null
)
returns public.stock_count_items language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
declare target_count public.stock_counts;
declare quantities record;
declare movement_count bigint;
declare result public.stock_count_items;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  select count.* into target_count from public.stock_counts count
  where count.id = target_count_id for update;
  if not found then raise exception 'Stock count not found' using errcode = 'P0002'; end if;
  if target_count.status <> 'draft' then
    raise exception 'Only a draft stock count can be edited' using errcode = '55000';
  end if;
  if actor_role = 'factory' and target_count.created_by <> actor_id then
    raise exception 'Factory may edit only its own stock count' using errcode = '42501';
  end if;
  if not exists (select 1 from public.stock_items item
    where item.id = target_stock_item_id and item.is_active) then
    raise exception 'Active stock item not found' using errcode = 'P0002';
  end if;
  perform public.lock_stock_balance(target_stock_item_id, target_count.location_id);
  select * into quantities from public.stock_quantities(
    target_stock_item_id, target_count.location_id);
  select count(*) into movement_count from public.stock_movements movement
  where movement.stock_item_id = target_stock_item_id
    and movement.location_id = target_count.location_id;
  insert into public.stock_count_items (
    stock_count_id, stock_item_id, location_id, expected_physical_quantity,
    snapshot_at, snapshot_movement_count, position
  ) values (
    target_count.id, target_stock_item_id, target_count.location_id,
    quantities.physical_quantity, clock_timestamp(), movement_count,
    coalesce(target_position, (select coalesce(max(line.position), 0) + 1
      from public.stock_count_items line where line.stock_count_id = target_count.id))
  ) on conflict (stock_count_id, stock_item_id, location_id) do update
    set position = excluded.position
  returning * into result;
  return result;
end;
$$;

create or replace function public.update_counted_quantity(
  target_count_item_id uuid,
  target_counted_quantity numeric,
  target_comment text default null
)
returns public.stock_count_items language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
declare target_count public.stock_counts;
declare result public.stock_count_items;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  if target_counted_quantity is null or target_counted_quantity < 0 then
    raise exception 'Counted quantity must be zero or greater' using errcode = '22023';
  end if;
  select count.* into target_count
  from public.stock_counts count
  join public.stock_count_items line on line.stock_count_id = count.id
  where line.id = target_count_item_id for update of count;
  if not found then raise exception 'Stock count item not found' using errcode = 'P0002'; end if;
  if target_count.status <> 'draft' then
    raise exception 'Only a draft stock count can be edited' using errcode = '55000';
  end if;
  if actor_role = 'factory' and target_count.created_by <> actor_id then
    raise exception 'Factory may edit only its own stock count' using errcode = '42501';
  end if;
  update public.stock_count_items line
  set counted_quantity = target_counted_quantity,
      comment = nullif(trim(target_comment), '')
  where line.id = target_count_item_id returning * into result;
  return result;
end;
$$;

create or replace function public.initialize_stock_count(
  target_count_id uuid,
  target_category public.stock_item_category default null,
  target_stock_item_ids uuid[] default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare candidate record;
declare item_position integer := 0;
begin
  perform public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  if target_stock_item_ids is not null and cardinality(target_stock_item_ids) = 0 then
    raise exception 'Selected item list cannot be empty' using errcode = '22023';
  end if;
  for candidate in select item.id from public.stock_items item
    where item.is_active
      and (target_category is null or item.category = target_category)
      and (target_stock_item_ids is null or item.id = any(target_stock_item_ids))
    order by item.name, item.id
  loop
    item_position := item_position + 1;
    perform public.add_stock_count_item(target_count_id, candidate.id, item_position);
  end loop;
  if item_position = 0 then
    raise exception 'No active stock items match the count scope' using errcode = 'P0002';
  end if;
  return public.stock_count_payload(target_count_id);
end;
$$;

create or replace function public.submit_stock_count(target_count_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
declare target_count public.stock_counts;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  select count.* into target_count from public.stock_counts count
  where count.id = target_count_id for update;
  if not found then raise exception 'Stock count not found' using errcode = 'P0002'; end if;
  if target_count.status = 'submitted' then return public.stock_count_payload(target_count.id); end if;
  if target_count.status <> 'draft' then
    raise exception 'Only a draft stock count can be submitted' using errcode = '55000';
  end if;
  if actor_role = 'factory' and target_count.created_by <> actor_id then
    raise exception 'Factory may submit only its own stock count' using errcode = '42501';
  end if;
  if not exists (select 1 from public.stock_count_items line
    where line.stock_count_id = target_count.id) then
    raise exception 'Stock count must contain at least one item' using errcode = '23514';
  end if;
  if exists (select 1 from public.stock_count_items line
    where line.stock_count_id = target_count.id and line.counted_quantity is null) then
    raise exception 'Every stock count item requires a physical count' using errcode = '23514';
  end if;
  update public.stock_counts count set
    count_number = public.allocate_stock_count_number(count.count_date),
    status = 'submitted', submitted_by = actor_id, submitted_at = now()
  where count.id = target_count.id;
  return public.stock_count_payload(target_count.id);
end;
$$;

create or replace function public.apply_stock_adjustment_internal(
  target_adjustment_id uuid,
  target_actor_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare adjustment public.stock_adjustments;
declare original public.stock_movements;
declare quantities record;
declare movement_id_value uuid;
declare movement_type_value public.stock_movement_type;
declare direction_value public.stock_direction;
declare movement_quantity numeric;
declare existing_correction numeric;
declare physical_after numeric;
begin
  select candidate.* into adjustment from public.stock_adjustments candidate
  where candidate.id = target_adjustment_id for update;
  if not found then raise exception 'Stock adjustment not found' using errcode = 'P0002'; end if;
  if adjustment.status = 'posted' then
    select * into quantities from public.stock_quantities(
      adjustment.stock_item_id, adjustment.location_id);
    return jsonb_build_object(
      'adjustment', to_jsonb(adjustment),
      'movement_id', adjustment.stock_movement_id,
      'physical_quantity', quantities.physical_quantity,
      'reserved_quantity', quantities.reserved_quantity,
      'available_quantity', quantities.available_quantity,
      'reservation_shortage', quantities.reserved_quantity > quantities.physical_quantity
    );
  end if;
  if adjustment.status <> 'pending' then
    raise exception 'Only a pending stock adjustment can be approved' using errcode = '55000';
  end if;
  if adjustment.difference_quantity = 0 then
    raise exception 'A zero difference does not require an adjustment' using errcode = '22023';
  end if;
  perform public.lock_stock_balance(adjustment.stock_item_id, adjustment.location_id);
  select * into quantities from public.stock_quantities(
    adjustment.stock_item_id, adjustment.location_id);
  movement_quantity := abs(adjustment.difference_quantity);
  direction_value := case when adjustment.difference_quantity > 0
    then 'in'::public.stock_direction else 'out'::public.stock_direction end;
  movement_type_value := case adjustment.adjustment_type
    when 'loss'::public.stock_adjustment_type then 'loss'::public.stock_movement_type
    when 'damage'::public.stock_adjustment_type then 'damage'::public.stock_movement_type
    when 'correction'::public.stock_adjustment_type then 'correction'::public.stock_movement_type
    else case direction_value when 'in'::public.stock_direction
      then 'adjustment_in'::public.stock_movement_type
      else 'adjustment_out'::public.stock_movement_type end
  end;
  if direction_value = 'out' and movement_quantity > quantities.physical_quantity then
    raise exception 'Adjustment would exceed physical stock: required %, physical %',
      movement_quantity, quantities.physical_quantity using errcode = '23514';
  end if;
  if adjustment.adjustment_type = 'correction' then
    select movement.* into original from public.stock_movements movement
    where movement.id = adjustment.original_movement_id for update;
    if not found then raise exception 'Original stock movement not found' using errcode = 'P0002'; end if;
    if original.stock_item_id <> adjustment.stock_item_id
      or original.location_id <> adjustment.location_id
      or direction_value = original.direction then
      raise exception 'Correction adjustment does not reverse the original movement'
        using errcode = '23514';
    end if;
    select coalesce(sum(movement.quantity), 0) into existing_correction
    from public.stock_movements movement where movement.corrected_movement_id = original.id;
    if existing_correction + movement_quantity > original.quantity then
      raise exception 'Correction exceeds the remaining original movement quantity'
        using errcode = '23514';
    end if;
  end if;
  physical_after := quantities.physical_quantity + case direction_value
    when 'in' then movement_quantity else -movement_quantity end;
  insert into public.stock_movements (
    stock_item_id, location_id, movement_type, quantity, direction,
    reference_type, reference_id, reason, created_by, corrected_movement_id, metadata
  ) values (
    adjustment.stock_item_id, adjustment.location_id, movement_type_value,
    movement_quantity, direction_value, 'stock_adjustment', adjustment.id,
    adjustment.reason, target_actor_id,
    case when adjustment.adjustment_type = 'correction' then adjustment.original_movement_id end,
    jsonb_build_object(
      'adjustment_type', adjustment.adjustment_type,
      'stock_count_id', adjustment.stock_count_id,
      'stock_count_item_id', adjustment.stock_count_item_id,
      'physical_before', quantities.physical_quantity,
      'reserved_before', quantities.reserved_quantity,
      'physical_after', physical_after,
      'available_after', physical_after - quantities.reserved_quantity,
      'reservation_shortage', quantities.reserved_quantity > physical_after
    )
  ) returning id into movement_id_value;
  update public.stock_adjustments candidate set
    status = 'posted', approved_by = target_actor_id, approved_at = now(),
    stock_movement_id = movement_id_value
  where candidate.id = adjustment.id returning * into adjustment;
  return jsonb_build_object(
    'adjustment', to_jsonb(adjustment),
    'movement_id', movement_id_value,
    'physical_quantity', physical_after,
    'reserved_quantity', quantities.reserved_quantity,
    'available_quantity', physical_after - quantities.reserved_quantity,
    'reservation_shortage', quantities.reserved_quantity > physical_after
  );
end;
$$;

create or replace function public.approve_stock_count(target_count_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare target_count public.stock_counts;
declare line public.stock_count_items;
declare adjustment_id uuid;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  select count.* into target_count from public.stock_counts count
  where count.id = target_count_id for update;
  if not found then raise exception 'Stock count not found' using errcode = 'P0002'; end if;
  if target_count.status = 'approved' then return public.stock_count_payload(target_count.id); end if;
  if target_count.status <> 'submitted' then
    raise exception 'Only a submitted stock count can be approved' using errcode = '55000';
  end if;
  -- All shared resources are locked in deterministic order before stale checks or writes.
  for line in select candidate.* from public.stock_count_items candidate
    where candidate.stock_count_id = target_count.id
    order by candidate.stock_item_id, candidate.location_id, candidate.id
  loop
    perform public.lock_stock_balance(line.stock_item_id, line.location_id);
  end loop;
  if exists (
    select 1 from public.stock_count_items counted_line
    where counted_line.stock_count_id = target_count.id
      and counted_line.snapshot_movement_count <> (select count(*)
        from public.stock_movements movement
        where movement.stock_item_id = counted_line.stock_item_id
          and movement.location_id = counted_line.location_id)
  ) then
    raise exception 'Stock changed after count started; restart or review the count'
      using errcode = '55000';
  end if;
  for line in select candidate.* from public.stock_count_items candidate
    where candidate.stock_count_id = target_count.id
    order by candidate.stock_item_id, candidate.location_id, candidate.id
  loop
    if line.difference_quantity <> 0 then
      insert into public.stock_adjustments (
        stock_count_id, stock_count_item_id, stock_item_id, location_id,
        adjustment_type, expected_quantity, counted_quantity, reason, status, requested_by
      ) values (
        target_count.id, line.id, line.stock_item_id, line.location_id,
        'count_difference', line.expected_physical_quantity, line.counted_quantity,
        'Physical count difference ' || target_count.count_number, 'pending', target_count.submitted_by
      ) returning id into adjustment_id;
      perform public.apply_stock_adjustment_internal(adjustment_id, actor_id);
    end if;
  end loop;
  update public.stock_counts count set
    status = 'approved', approved_by = actor_id, approved_at = now()
  where count.id = target_count.id;
  return public.stock_count_payload(target_count.id);
end;
$$;

create or replace function public.reject_stock_count(
  target_count_id uuid, target_reason text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare target_count public.stock_counts;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  if target_reason is null or trim(target_reason) = '' then
    raise exception 'Rejection reason is required' using errcode = '22023';
  end if;
  select count.* into target_count from public.stock_counts count
  where count.id = target_count_id for update;
  if not found then raise exception 'Stock count not found' using errcode = 'P0002'; end if;
  if target_count.status = 'rejected' then return public.stock_count_payload(target_count.id); end if;
  if target_count.status <> 'submitted' then
    raise exception 'Only a submitted stock count can be rejected' using errcode = '55000';
  end if;
  update public.stock_counts count set status = 'rejected', rejected_by = actor_id,
    rejected_at = now(), rejection_reason = trim(target_reason)
  where count.id = target_count.id;
  return public.stock_count_payload(target_count.id);
end;
$$;

create or replace function public.cancel_stock_count(target_count_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
declare target_count public.stock_counts;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  select count.* into target_count from public.stock_counts count
  where count.id = target_count_id for update;
  if not found then raise exception 'Stock count not found' using errcode = 'P0002'; end if;
  if target_count.status = 'cancelled' then return public.stock_count_payload(target_count.id); end if;
  if target_count.status <> 'draft' then
    raise exception 'Only a draft stock count can be cancelled' using errcode = '55000';
  end if;
  if actor_role = 'factory' and target_count.created_by <> actor_id then
    raise exception 'Factory may cancel only its own stock count' using errcode = '42501';
  end if;
  update public.stock_counts count set status = 'cancelled' where count.id = target_count.id;
  return public.stock_count_payload(target_count.id);
end;
$$;

create or replace function public.create_stock_adjustment_request(
  target_stock_item_id uuid,
  target_location_id uuid,
  target_adjustment_type public.stock_adjustment_type,
  target_signed_quantity numeric,
  target_reason text,
  target_original_movement_id uuid default null
)
returns public.stock_adjustments language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
declare quantities record;
declare original public.stock_movements;
declare result public.stock_adjustments;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  if target_adjustment_type is null or target_adjustment_type = 'count_difference' then
    raise exception 'Standalone adjustment type is invalid' using errcode = '22023';
  end if;
  if target_signed_quantity is null or target_signed_quantity = 0 then
    raise exception 'Adjustment quantity must be non-zero' using errcode = '22023';
  end if;
  if target_reason is null or trim(target_reason) = '' then
    raise exception 'Adjustment reason is required' using errcode = '22023';
  end if;
  if target_adjustment_type in ('loss','damage') and target_signed_quantity > 0 then
    raise exception 'Loss and damage quantities must reduce physical stock' using errcode = '22023';
  end if;
  perform public.lock_stock_balance(target_stock_item_id, effective_location_id);
  select * into quantities from public.stock_quantities(target_stock_item_id, effective_location_id);
  if target_adjustment_type = 'correction' then
    select movement.* into original from public.stock_movements movement
    where movement.id = target_original_movement_id;
    if not found or original.stock_item_id <> target_stock_item_id
      or original.location_id <> effective_location_id then
      raise exception 'Original movement does not match correction resource' using errcode = '23514';
    end if;
    if (original.direction = 'in' and target_signed_quantity > 0)
      or (original.direction = 'out' and target_signed_quantity < 0) then
      raise exception 'Correction quantity must reverse the original movement' using errcode = '23514';
    end if;
  elsif target_original_movement_id is not null then
    raise exception 'Original movement is valid only for correction requests' using errcode = '22023';
  end if;
  if quantities.physical_quantity + target_signed_quantity < 0 then
    raise exception 'Requested adjustment exceeds physical stock' using errcode = '23514';
  end if;
  insert into public.stock_adjustments (
    stock_item_id, location_id, adjustment_type, expected_quantity, counted_quantity,
    reason, status, requested_by, original_movement_id
  ) values (
    target_stock_item_id, effective_location_id, target_adjustment_type,
    quantities.physical_quantity, quantities.physical_quantity + target_signed_quantity,
    trim(target_reason), 'pending', actor_id, target_original_movement_id
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.report_stock_loss(
  target_stock_item_id uuid, target_location_id uuid,
  target_quantity numeric, target_reason text
)
returns public.stock_adjustments language plpgsql security definer set search_path = '' as $$
begin
  if target_quantity is null or target_quantity <= 0 then
    raise exception 'Loss quantity must be greater than zero' using errcode = '22023';
  end if;
  return public.create_stock_adjustment_request(target_stock_item_id, target_location_id,
    'loss', -target_quantity, target_reason, null);
end;
$$;

create or replace function public.report_stock_damage(
  target_stock_item_id uuid, target_location_id uuid,
  target_quantity numeric, target_reason text
)
returns public.stock_adjustments language plpgsql security definer set search_path = '' as $$
begin
  if target_quantity is null or target_quantity <= 0 then
    raise exception 'Damage quantity must be greater than zero' using errcode = '22023';
  end if;
  return public.create_stock_adjustment_request(target_stock_item_id, target_location_id,
    'damage', -target_quantity, target_reason, null);
end;
$$;

create or replace function public.request_other_stock_adjustment(
  target_stock_item_id uuid, target_location_id uuid,
  target_signed_quantity numeric, target_reason text
)
returns public.stock_adjustments language plpgsql security definer set search_path = '' as $$
begin
  return public.create_stock_adjustment_request(
    target_stock_item_id, target_location_id, 'other',
    target_signed_quantity, target_reason, null);
end;
$$;

create or replace function public.request_stock_correction(
  target_movement_id uuid, target_quantity numeric, target_reason text
)
returns public.stock_adjustments language plpgsql security definer set search_path = '' as $$
declare original public.stock_movements;
declare signed_quantity numeric;
begin
  perform public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  if target_quantity is null or target_quantity <= 0 then
    raise exception 'Correction quantity must be greater than zero' using errcode = '22023';
  end if;
  select movement.* into original from public.stock_movements movement
  where movement.id = target_movement_id;
  if not found then raise exception 'Original stock movement not found' using errcode = 'P0002'; end if;
  signed_quantity := case original.direction when 'in' then -target_quantity else target_quantity end;
  return public.create_stock_adjustment_request(
    original.stock_item_id, original.location_id, 'correction', signed_quantity,
    target_reason, original.id);
end;
$$;

create or replace function public.approve_stock_adjustment(target_adjustment_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  return public.apply_stock_adjustment_internal(target_adjustment_id, actor_id);
end;
$$;

create or replace function public.reject_stock_adjustment(
  target_adjustment_id uuid, target_reason text
)
returns public.stock_adjustments language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare result public.stock_adjustments;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role
  ]);
  if target_reason is null or trim(target_reason) = '' then
    raise exception 'Rejection reason is required' using errcode = '22023';
  end if;
  select adjustment.* into result from public.stock_adjustments adjustment
  where adjustment.id = target_adjustment_id for update;
  if not found then raise exception 'Stock adjustment not found' using errcode = 'P0002'; end if;
  if result.status = 'rejected' then return result; end if;
  if result.status <> 'pending' then
    raise exception 'Only a pending adjustment can be rejected' using errcode = '55000';
  end if;
  update public.stock_adjustments adjustment set status = 'rejected',
    rejected_by = actor_id, rejected_at = now(), rejection_reason = trim(target_reason)
  where adjustment.id = result.id returning * into result;
  return result;
end;
$$;

create or replace function public.attach_stock_count_evidence(
  target_count_id uuid, target_count_item_id uuid, target_storage_path text,
  target_file_name text, target_mime_type text, target_file_size bigint default null
)
returns public.stock_count_attachments language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
declare target_count public.stock_counts;
declare result public.stock_count_attachments;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  select count.* into target_count from public.stock_counts count where count.id = target_count_id;
  if not found then raise exception 'Stock count not found' using errcode = 'P0002'; end if;
  if target_count.status <> 'draft' then
    raise exception 'Evidence can be attached only to a draft count' using errcode = '55000';
  end if;
  if actor_role = 'factory' and target_count.created_by <> actor_id then
    raise exception 'Factory may attach evidence only to its own count' using errcode = '42501';
  end if;
  if target_count_item_id is not null and not exists (select 1
    from public.stock_count_items line where line.id = target_count_item_id
      and line.stock_count_id = target_count.id) then
    raise exception 'Count item does not belong to this count' using errcode = '23514';
  end if;
  if target_storage_path not like actor_id::text || '/counts/' || target_count.id::text || '/%' then
    raise exception 'Evidence path must be scoped to actor and count' using errcode = '22023';
  end if;
  insert into public.stock_count_attachments (
    stock_count_id, stock_count_item_id, storage_path, file_name,
    mime_type, file_size, uploaded_by
  ) values (
    target_count.id, target_count_item_id, trim(target_storage_path), trim(target_file_name),
    target_mime_type, target_file_size, actor_id
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.attach_stock_adjustment_evidence(
  target_adjustment_id uuid, target_storage_path text, target_file_name text,
  target_mime_type text, target_file_size bigint default null
)
returns public.stock_adjustment_attachments language plpgsql security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
declare adjustment public.stock_adjustments;
declare result public.stock_adjustment_attachments;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  select candidate.* into adjustment from public.stock_adjustments candidate
  where candidate.id = target_adjustment_id;
  if not found then raise exception 'Stock adjustment not found' using errcode = 'P0002'; end if;
  if adjustment.status <> 'pending' then
    raise exception 'Evidence can be attached only to a pending adjustment' using errcode = '55000';
  end if;
  if actor_role = 'factory' and adjustment.requested_by <> actor_id then
    raise exception 'Factory may attach evidence only to its own adjustment' using errcode = '42501';
  end if;
  if target_storage_path not like actor_id::text || '/adjustments/' || adjustment.id::text || '/%' then
    raise exception 'Evidence path must be scoped to actor and adjustment' using errcode = '22023';
  end if;
  insert into public.stock_adjustment_attachments (
    stock_adjustment_id, storage_path, file_name, mime_type, file_size, uploaded_by
  ) values (
    adjustment.id, trim(target_storage_path), trim(target_file_name),
    target_mime_type, target_file_size, actor_id
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.get_stock_count(target_count_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
declare target_count public.stock_counts;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  select count.* into target_count from public.stock_counts count where count.id = target_count_id;
  if not found then raise exception 'Stock count not found' using errcode = 'P0002'; end if;
  if actor_role = 'factory' and target_count.created_by <> actor_id then
    raise exception 'Stock count is not visible to this Factory user' using errcode = '42501';
  end if;
  return public.stock_count_payload(target_count.id);
end;
$$;

create or replace function public.list_stock_counts(
  target_date_from date default null, target_date_to date default null,
  target_status public.stock_count_status default null, target_location_id uuid default null,
  target_created_by uuid default null, target_limit integer default 200
)
returns table (
  id uuid, count_number text, count_date date, location_id uuid, location_name text,
  status public.stock_count_status, created_by uuid, created_by_name text,
  approved_by_name text, item_count bigint, difference_count bigint,
  net_difference numeric, created_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  return query select count.id, count.count_number, count.count_date,
    count.location_id, location.name, count.status, count.created_by, creator.display_name,
    approver.display_name, count(line.id),
    count(line.id) filter (where line.difference_quantity <> 0),
    coalesce(sum(line.difference_quantity), 0), count.created_at
  from public.stock_counts count
  join public.stock_locations location on location.id = count.location_id
  join public.profiles creator on creator.id = count.created_by
  left join public.profiles approver on approver.id = count.approved_by
  left join public.stock_count_items line on line.stock_count_id = count.id
  where (actor_role in ('admin','management') or count.created_by = actor_id)
    and (target_date_from is null or count.count_date >= target_date_from)
    and (target_date_to is null or count.count_date <= target_date_to)
    and (target_status is null or count.status = target_status)
    and (target_location_id is null or count.location_id = target_location_id)
    and (target_created_by is null or count.created_by = target_created_by)
  group by count.id, location.name, creator.display_name, approver.display_name
  order by count.created_at desc, count.id desc
  limit least(greatest(coalesce(target_limit, 200), 1), 500);
end;
$$;

create or replace function public.list_stock_adjustments(
  target_date_from date default null, target_date_to date default null,
  target_status public.stock_adjustment_status default null,
  target_type public.stock_adjustment_type default null,
  target_requested_by uuid default null, target_limit integer default 200
)
returns table (
  id uuid, stock_item_id uuid, stock_item_name text, location_name text,
  adjustment_type public.stock_adjustment_type, difference_quantity numeric,
  reason text, status public.stock_adjustment_status, requested_by uuid,
  requested_by_name text, approved_by_name text, stock_count_id uuid,
  stock_movement_id uuid, original_movement_id uuid, created_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid;
declare actor_role public.app_role;
begin
  actor_id := public.assert_stock_count_actor(array[
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  ]);
  actor_role := public.current_app_role();
  return query select adjustment.id, adjustment.stock_item_id, item.name, location.name,
    adjustment.adjustment_type, adjustment.difference_quantity, adjustment.reason,
    adjustment.status, adjustment.requested_by, requester.display_name, approver.display_name,
    adjustment.stock_count_id, adjustment.stock_movement_id,
    adjustment.original_movement_id, adjustment.created_at
  from public.stock_adjustments adjustment
  join public.stock_items item on item.id = adjustment.stock_item_id
  join public.stock_locations location on location.id = adjustment.location_id
  join public.profiles requester on requester.id = adjustment.requested_by
  left join public.profiles approver on approver.id = adjustment.approved_by
  where (actor_role in ('admin','management') or adjustment.requested_by = actor_id)
    and (target_date_from is null or adjustment.created_at >= target_date_from::timestamptz)
    and (target_date_to is null or adjustment.created_at < (target_date_to + 1)::timestamptz)
    and (target_status is null or adjustment.status = target_status)
    and (target_type is null or adjustment.adjustment_type = target_type)
    and (target_requested_by is null or adjustment.requested_by = target_requested_by)
  order by adjustment.created_at desc, adjustment.id desc
  limit least(greatest(coalesce(target_limit, 200), 1), 500);
end;
$$;

-- Internal primitives are inaccessible from the API.
revoke all on function public.assert_stock_count_actor(public.app_role[]) from public, anon, authenticated;
revoke all on function public.allocate_stock_count_number(date) from public, anon, authenticated;
revoke all on function public.stock_count_payload(uuid) from public, anon, authenticated;
revoke all on function public.apply_stock_adjustment_internal(uuid,uuid) from public, anon, authenticated;
revoke all on function public.create_stock_adjustment_request(uuid,uuid,public.stock_adjustment_type,numeric,text,uuid) from public, anon, authenticated;

select routine_name, security_type from information_schema.routines
where routine_schema = 'public' and routine_name in (
  'create_stock_count_draft','add_stock_count_item','update_counted_quantity',
  'initialize_stock_count',
  'submit_stock_count','approve_stock_count','reject_stock_count',
  'report_stock_loss','report_stock_damage','request_stock_correction',
  'request_other_stock_adjustment',
  'approve_stock_adjustment','get_stock_count','list_stock_counts','list_stock_adjustments'
) order by routine_name;
