-- SOMA / FACOLUB receiving module - 033 trusted receiving operations
-- Depends on: 030-032 and Stock S1 020-024.
-- Draft writes and confirmation are RPC-only. Confirming is one PostgreSQL
-- transaction: number allocation, status change, and stock movements all commit
-- together or all roll back together.

create or replace function public.assert_receiving_actor()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.assert_stock_actor(array[
    'admin'::public.app_role,
    'management'::public.app_role,
    'factory'::public.app_role
  ]);
end;
$$;

create or replace function public.lock_editable_receipt(target_receipt_id uuid)
returns public.receipts
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := public.assert_receiving_actor();
  actor_role public.app_role := public.current_app_role();
  result public.receipts;
begin
  select receipt.* into result
  from public.receipts receipt
  where receipt.id = target_receipt_id
  for update;

  if not found then
    raise exception 'Receipt not found' using errcode = 'P0002';
  end if;
  if actor_role = 'factory'::public.app_role and result.created_by <> actor_id then
    raise exception 'Factory users may edit only their own receipt drafts'
      using errcode = '42501';
  end if;
  if result.status <> 'draft'::public.receipt_status then
    raise exception 'Only a draft receipt can be edited' using errcode = '23514';
  end if;
  return result;
end;
$$;

create or replace function public.save_supplier(
  target_id uuid,
  target_name text,
  target_phone text default null,
  target_email text default null,
  target_address text default null,
  target_is_active boolean default true
)
returns public.suppliers
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.suppliers;
begin
  perform public.assert_stock_actor(array['admin'::public.app_role]);
  if target_name is null or char_length(trim(target_name)) < 1 then
    raise exception 'Supplier name is required' using errcode = '22023';
  end if;

  if target_id is null then
    insert into public.suppliers (name, phone, email, address, is_active)
    values (
      trim(target_name), nullif(trim(target_phone), ''), nullif(lower(trim(target_email)), ''),
      nullif(trim(target_address), ''), coalesce(target_is_active, true)
    ) returning * into result;
  else
    update public.suppliers supplier
    set name = trim(target_name),
        phone = nullif(trim(target_phone), ''),
        email = nullif(lower(trim(target_email)), ''),
        address = nullif(trim(target_address), ''),
        is_active = coalesce(target_is_active, supplier.is_active)
    where supplier.id = target_id
    returning * into result;
    if not found then
      raise exception 'Supplier not found' using errcode = 'P0002';
    end if;
  end if;
  return result;
end;
$$;

create or replace function public.create_receipt_draft(
  target_receipt_date date default current_date,
  target_location_id uuid default null,
  target_supplier_id uuid default null,
  target_supplier_name text default null,
  target_reference text default null,
  target_comment text default null
)
returns public.receipts
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := public.assert_receiving_actor();
  effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
  supplier_snapshot text := nullif(trim(target_supplier_name), '');
  result public.receipts;
begin
  if target_receipt_date is null then
    raise exception 'Receipt date is required' using errcode = '22023';
  end if;
  if effective_location_id is null or not exists (
    select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active
  ) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;

  if target_supplier_id is not null then
    select supplier.name into supplier_snapshot
    from public.suppliers supplier
    where supplier.id = target_supplier_id and supplier.is_active;
    if not found then
      raise exception 'Active supplier not found' using errcode = 'P0002';
    end if;
  end if;

  insert into public.receipts (
    supplier_id, supplier_name_snapshot, reference, receipt_date,
    location_id, status, comment, created_by
  ) values (
    target_supplier_id, supplier_snapshot, nullif(trim(target_reference), ''),
    target_receipt_date, effective_location_id, 'draft'::public.receipt_status,
    nullif(trim(target_comment), ''), actor_id
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.update_receipt_draft(
  target_receipt_id uuid,
  target_receipt_date date,
  target_location_id uuid,
  target_supplier_id uuid,
  target_supplier_name text,
  target_reference text,
  target_comment text
)
returns public.receipts
language plpgsql
security definer
set search_path = ''
as $$
declare
  locked_receipt public.receipts := public.lock_editable_receipt(target_receipt_id);
  effective_location_id uuid := coalesce(target_location_id, public.default_stock_location_id());
  supplier_snapshot text := nullif(trim(target_supplier_name), '');
  result public.receipts;
begin
  if target_receipt_date is null then
    raise exception 'Receipt date is required' using errcode = '22023';
  end if;
  if effective_location_id is null or not exists (
    select 1 from public.stock_locations location
    where location.id = effective_location_id and location.is_active
  ) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;
  if target_supplier_id is not null then
    select supplier.name into supplier_snapshot
    from public.suppliers supplier
    where supplier.id = target_supplier_id and supplier.is_active;
    if not found then
      raise exception 'Active supplier not found' using errcode = 'P0002';
    end if;
  end if;

  update public.receipts receipt
  set receipt_date = target_receipt_date,
      location_id = effective_location_id,
      supplier_id = target_supplier_id,
      supplier_name_snapshot = supplier_snapshot,
      reference = nullif(trim(target_reference), ''),
      comment = nullif(trim(target_comment), '')
  where receipt.id = locked_receipt.id
  returning * into result;
  return result;
end;
$$;

create or replace function public.add_receipt_item(
  target_receipt_id uuid,
  target_stock_item_id uuid,
  target_quantity numeric,
  target_position integer default null
)
returns public.receipt_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  locked_receipt public.receipts := public.lock_editable_receipt(target_receipt_id);
  canonical_unit public.stock_unit;
  effective_position integer;
  existing_line public.receipt_items;
  result public.receipt_items;
begin
  if target_quantity is null or target_quantity <= 0 then
    raise exception 'Receipt quantity must be greater than zero' using errcode = '22023';
  end if;
  select item.unit into canonical_unit
  from public.stock_items item
  where item.id = target_stock_item_id and item.is_active;
  if not found then
    raise exception 'Active stock item not found' using errcode = 'P0002';
  end if;

  select line.* into existing_line
  from public.receipt_items line
  where line.receipt_id = locked_receipt.id
    and line.stock_item_id = target_stock_item_id;

  if found then
    effective_position := coalesce(target_position, existing_line.position);
    if effective_position <= 0 then
      raise exception 'Receipt item position must be positive' using errcode = '22023';
    end if;
    update public.receipt_items line
    set quantity = target_quantity,
        unit = canonical_unit,
        position = effective_position
    where line.id = existing_line.id
    returning * into result;
  else
    select coalesce(target_position, coalesce(max(line.position), 0) + 1)
    into effective_position
    from public.receipt_items line
    where line.receipt_id = locked_receipt.id;
    if effective_position <= 0 then
      raise exception 'Receipt item position must be positive' using errcode = '22023';
    end if;
    insert into public.receipt_items (
      receipt_id, stock_item_id, quantity, unit, position
    ) values (
      locked_receipt.id, target_stock_item_id, target_quantity, canonical_unit, effective_position
    ) returning * into result;
  end if;
  return result;
end;
$$;

create or replace function public.remove_receipt_item(target_receipt_item_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  parent_receipt_id uuid;
  affected integer;
begin
  perform public.assert_receiving_actor();
  select line.receipt_id into parent_receipt_id
  from public.receipt_items line
  where line.id = target_receipt_item_id;
  if not found then
    raise exception 'Receipt item not found' using errcode = 'P0002';
  end if;
  perform public.lock_editable_receipt(parent_receipt_id);
  delete from public.receipt_items line where line.id = target_receipt_item_id;
  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'Receipt item could not be removed' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.attach_receipt_photo(
  target_receipt_id uuid,
  target_storage_path text,
  target_file_name text,
  target_mime_type text,
  target_file_size bigint default null
)
returns public.receipt_attachments
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := public.assert_receiving_actor();
  locked_receipt public.receipts := public.lock_editable_receipt(target_receipt_id);
  result public.receipt_attachments;
begin
  if public.receipt_id_from_storage_path(target_storage_path) is distinct from locked_receipt.id then
    raise exception 'Photo path must start with the receipt UUID' using errcode = '22023';
  end if;
  if target_mime_type is null or target_mime_type not in (
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
  ) then
    raise exception 'Unsupported receipt photo type' using errcode = '22023';
  end if;
  if target_file_size is not null and (target_file_size <= 0 or target_file_size > 8388608) then
    raise exception 'Receipt photo must be 8 MiB or smaller' using errcode = '22023';
  end if;
  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'facolub-receipts'
      and object.name = trim(target_storage_path)
  ) then
    raise exception 'Upload the private Storage object before attaching its metadata'
      using errcode = 'P0002';
  end if;

  select attachment.* into result
  from public.receipt_attachments attachment
  where attachment.storage_path = trim(target_storage_path);
  if found then
    if result.receipt_id <> locked_receipt.id then
      raise exception 'Photo path is already linked to another receipt' using errcode = '23505';
    end if;
    return result;
  end if;

  insert into public.receipt_attachments (
    receipt_id, storage_path, file_name, mime_type, file_size, uploaded_by
  ) values (
    locked_receipt.id, trim(target_storage_path), nullif(trim(target_file_name), ''),
    target_mime_type, target_file_size, actor_id
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.detach_receipt_photo(target_attachment_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attachment public.receipt_attachments;
begin
  perform public.assert_receiving_actor();
  select attachment.* into target_attachment
  from public.receipt_attachments attachment
  where attachment.id = target_attachment_id;
  if not found then
    raise exception 'Receipt photo not found' using errcode = 'P0002';
  end if;
  perform public.lock_editable_receipt(target_attachment.receipt_id);
  delete from public.receipt_attachments attachment
  where attachment.id = target_attachment.id;
  -- The browser may now remove this unlinked object through the Storage API.
  return target_attachment.storage_path;
end;
$$;

create or replace function public.cancel_receipt(target_receipt_id uuid)
returns public.receipts
language plpgsql
security definer
set search_path = ''
as $$
declare
  locked_receipt public.receipts := public.lock_editable_receipt(target_receipt_id);
  result public.receipts;
begin
  update public.receipts receipt
  set status = 'cancelled'::public.receipt_status
  where receipt.id = locked_receipt.id
  returning * into result;
  return result;
end;
$$;

-- Extend the S1 authoritative movement API so Factory can create exactly one
-- validated receipt movement per line, and nothing else. Management/Admin keep
-- their S1 permissions. Browser clients still cannot insert into the ledger.
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
  movement_metadata jsonb := coalesce(target_metadata, '{}'::jsonb);
begin
  actor_id := public.assert_stock_actor(array[
    'admin'::public.app_role,
    'management'::public.app_role,
    'factory'::public.app_role
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
  if jsonb_typeof(movement_metadata) <> 'object' then
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

  if actor_role = 'factory'::public.app_role and not (
    target_movement_type = 'receipt'::public.stock_movement_type
    and target_direction = 'in'::public.stock_direction
    and trim(coalesce(target_reference_type, '')) = 'receipt'
    and target_reference_id is not null
    and not target_allow_negative
    and exists (
      select 1
      from public.receipts receipt
      join public.receipt_items line on line.receipt_id = receipt.id
      where receipt.id = target_reference_id
        and receipt.status = 'confirmed'::public.receipt_status
        and receipt.confirmed_by = actor_id
        and receipt.location_id = effective_location_id
        and line.stock_item_id = target_stock_item_id
        and line.quantity = target_quantity
        and line.id::text = movement_metadata ->> 'receipt_item_id'
    )
  ) then
    raise exception 'Factory may create stock only through an exact confirmed receipt line'
      using errcode = '42501';
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

  new_physical := current_physical + case target_direction
    when 'in'::public.stock_direction then target_quantity
    else -target_quantity
  end;
  if target_movement_type = 'receipt'::public.stock_movement_type
    and trim(coalesce(target_reference_type, '')) = 'receipt' then
    movement_metadata := movement_metadata || jsonb_build_object(
      'physical_before', current_physical,
      'reserved_before', current_reserved,
      'physical_after', new_physical,
      'available_after', new_physical - current_reserved
    );
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
    movement_metadata
  ) returning id into inserted_movement_id;

  return query select
    inserted_movement_id,
    new_physical,
    current_reserved,
    new_physical - current_reserved;
end;
$$;

create or replace function public.receipt_confirmation_payload(target_receipt_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'receipt_id', receipt.id,
    'receipt_number', receipt.receipt_number,
    'status', receipt.status,
    'confirmed_at', receipt.confirmed_at,
    'balances', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'receipt_item_id', line.id,
          'stock_item_id', line.stock_item_id,
          'quantity_received', line.quantity,
          'unit', line.unit,
          'movement_id', movement.id,
          'physical_before', movement.metadata -> 'physical_before',
          'reserved_before', movement.metadata -> 'reserved_before',
          'physical_after', movement.metadata -> 'physical_after',
          'reserved_after', movement.metadata -> 'reserved_before',
          'available_after', movement.metadata -> 'available_after',
          'current_physical', quantities.physical_quantity,
          'current_reserved', quantities.reserved_quantity,
          'current_available', quantities.available_quantity
        ) order by line.position, line.id
      )
      from public.receipt_items line
      join public.stock_movements movement
        on movement.reference_type = 'receipt'
       and movement.reference_id = receipt.id
       and movement.metadata ->> 'receipt_item_id' = line.id::text
      cross join lateral public.stock_quantities(line.stock_item_id, receipt.location_id) quantities
      where line.receipt_id = receipt.id
    ), '[]'::jsonb)
  )
  from public.receipts receipt
  where receipt.id = target_receipt_id
$$;

create or replace function public.confirm_receipt(target_receipt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := public.assert_receiving_actor();
  actor_role public.app_role := public.current_app_role();
  target_receipt public.receipts;
  line public.receipt_items;
  official_number text;
begin
  select receipt.* into target_receipt
  from public.receipts receipt
  where receipt.id = target_receipt_id
  for update;
  if not found then
    raise exception 'Receipt not found' using errcode = 'P0002';
  end if;
  if actor_role = 'factory'::public.app_role and target_receipt.created_by <> actor_id then
    raise exception 'Factory users may confirm only their own receipt drafts'
      using errcode = '42501';
  end if;

  -- Idempotent retry/double-click path: the row lock guarantees the first
  -- transaction completed before this branch is evaluated.
  if target_receipt.status = 'confirmed'::public.receipt_status then
    return public.receipt_confirmation_payload(target_receipt.id);
  end if;
  if target_receipt.status <> 'draft'::public.receipt_status then
    raise exception 'Cancelled receipts cannot be confirmed' using errcode = '23514';
  end if;
  if target_receipt.location_id is null or not exists (
    select 1 from public.stock_locations location
    where location.id = target_receipt.location_id and location.is_active
  ) then
    raise exception 'Active receipt location not found' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.receipt_items item where item.receipt_id = target_receipt.id
  ) then
    raise exception 'Receipt must contain at least one item' using errcode = '23514';
  end if;
  if exists (
    select 1
    from public.receipt_items line_to_check
    left join public.stock_items item on item.id = line_to_check.stock_item_id
    where line_to_check.receipt_id = target_receipt.id
      and (line_to_check.quantity <= 0 or item.id is null or not item.is_active)
  ) then
    raise exception 'Every receipt line requires a positive quantity and active stock item'
      using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.receipt_attachments attachment
    where attachment.receipt_id = target_receipt.id
  ) then
    raise exception 'At least one receiving photo is required before confirmation'
      using errcode = '23514';
  end if;

  official_number := public.allocate_receipt_number(target_receipt.receipt_date);
  update public.receipts receipt
  set receipt_number = official_number,
      status = 'confirmed'::public.receipt_status,
      confirmed_by = actor_id,
      confirmed_at = now()
  where receipt.id = target_receipt.id
  returning * into target_receipt;

  -- UUID order makes concurrent multi-line confirmations take shared stock
  -- locks consistently, avoiding cross-receipt lock-order deadlocks.
  for line in
    select receipt_line.*
    from public.receipt_items receipt_line
    where receipt_line.receipt_id = target_receipt.id
    order by receipt_line.stock_item_id, receipt_line.id
  loop
    perform public.record_stock_movement(
      line.stock_item_id,
      target_receipt.location_id,
      'receipt'::public.stock_movement_type,
      line.quantity,
      'in'::public.stock_direction,
      'receipt',
      target_receipt.id,
      'Goods receipt ' || target_receipt.receipt_number,
      jsonb_build_object(
        'receipt_item_id', line.id,
        'receipt_number', target_receipt.receipt_number,
        'unit', line.unit
      ),
      false
    );
  end loop;

  return public.receipt_confirmation_payload(target_receipt.id);
end;
$$;

create or replace function public.get_receipt(target_receipt_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := public.assert_receiving_actor();
  actor_role public.app_role := public.current_app_role();
  target_receipt public.receipts;
  result jsonb;
begin
  select receipt.* into target_receipt
  from public.receipts receipt
  where receipt.id = target_receipt_id;
  if not found then
    raise exception 'Receipt not found' using errcode = 'P0002';
  end if;
  if actor_role = 'factory'::public.app_role and target_receipt.created_by <> actor_id then
    raise exception 'Receipt is not visible to this Factory user' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'receipt', to_jsonb(receipt),
    'location_name', location.name,
    'created_by_name', creator.display_name,
    'confirmed_by_name', confirmer.display_name,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', line.id,
          'stock_item_id', line.stock_item_id,
          'stock_item_name', item.name,
          'category', item.category,
          'quantity', line.quantity,
          'unit', line.unit,
          'position', line.position
        ) order by line.position, line.id
      )
      from public.receipt_items line
      join public.stock_items item on item.id = line.stock_item_id
      where line.receipt_id = receipt.id
    ), '[]'::jsonb),
    'attachments', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', attachment.id,
          'storage_path', attachment.storage_path,
          'file_name', attachment.file_name,
          'mime_type', attachment.mime_type,
          'file_size', attachment.file_size,
          'uploaded_by', attachment.uploaded_by,
          'created_at', attachment.created_at
        ) order by attachment.created_at, attachment.id
      )
      from public.receipt_attachments attachment
      where attachment.receipt_id = receipt.id
    ), '[]'::jsonb),
    'movements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', movement.id,
          'stock_item_id', movement.stock_item_id,
          'quantity', movement.quantity,
          'direction', movement.direction,
          'created_by', movement.created_by,
          'created_at', movement.created_at,
          'receipt_item_id', movement.metadata ->> 'receipt_item_id'
        ) order by movement.created_at, movement.id
      )
      from public.stock_movements movement
      where movement.reference_type = 'receipt'
        and movement.reference_id = receipt.id
    ), '[]'::jsonb)
  ) into result
  from public.receipts receipt
  join public.stock_locations location on location.id = receipt.location_id
  join public.profiles creator on creator.id = receipt.created_by
  left join public.profiles confirmer on confirmer.id = receipt.confirmed_by
  where receipt.id = target_receipt.id;
  return result;
end;
$$;

create or replace function public.list_receipts(
  target_date_from date default null,
  target_date_to date default null,
  target_supplier_id uuid default null,
  target_stock_item_id uuid default null,
  target_created_by uuid default null,
  target_status public.receipt_status default null,
  target_search text default null,
  target_limit integer default 100
)
returns table (
  id uuid,
  receipt_number text,
  receipt_date date,
  status public.receipt_status,
  supplier_id uuid,
  supplier_name text,
  reference text,
  location_id uuid,
  location_name text,
  created_by uuid,
  created_by_name text,
  confirmed_at timestamptz,
  item_count bigint,
  quantity_summary text,
  photo_count bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := public.assert_receiving_actor();
  actor_role public.app_role := public.current_app_role();
  normalized_search text := nullif(trim(target_search), '');
begin
  return query
  select
    receipt.id,
    receipt.receipt_number,
    receipt.receipt_date,
    receipt.status,
    receipt.supplier_id,
    receipt.supplier_name_snapshot,
    receipt.reference,
    receipt.location_id,
    location.name,
    receipt.created_by,
    creator.display_name,
    receipt.confirmed_at,
    coalesce(line_summary.item_count, 0),
    coalesce(line_summary.quantity_summary, ''),
    coalesce(photo_summary.photo_count, 0),
    receipt.created_at
  from public.receipts receipt
  join public.stock_locations location on location.id = receipt.location_id
  join public.profiles creator on creator.id = receipt.created_by
  left join lateral (
    select
      count(*) as item_count,
      string_agg(line.quantity::text || ' ' || line.unit::text, ', ' order by line.position, line.id)
        as quantity_summary
    from public.receipt_items line
    where line.receipt_id = receipt.id
  ) line_summary on true
  left join lateral (
    select count(*) as photo_count
    from public.receipt_attachments attachment
    where attachment.receipt_id = receipt.id
  ) photo_summary on true
  where (
      actor_role in ('admin'::public.app_role, 'management'::public.app_role)
      or receipt.created_by = actor_id
    )
    and (target_date_from is null or receipt.receipt_date >= target_date_from)
    and (target_date_to is null or receipt.receipt_date <= target_date_to)
    and (target_supplier_id is null or receipt.supplier_id = target_supplier_id)
    and (target_created_by is null or receipt.created_by = target_created_by)
    and (target_status is null or receipt.status = target_status)
    and (
      target_stock_item_id is null
      or exists (
        select 1 from public.receipt_items filtered_line
        where filtered_line.receipt_id = receipt.id
          and filtered_line.stock_item_id = target_stock_item_id
      )
    )
    and (
      normalized_search is null
      or receipt.receipt_number ilike '%' || normalized_search || '%'
      or receipt.supplier_name_snapshot ilike '%' || normalized_search || '%'
      or receipt.reference ilike '%' || normalized_search || '%'
    )
  order by receipt.created_at desc, receipt.id desc
  limit least(greatest(coalesce(target_limit, 100), 1), 500);
end;
$$;

-- Internal primitives are callable only by trusted SECURITY DEFINER functions.
revoke all on function public.assert_receiving_actor() from public, anon, authenticated;
revoke all on function public.lock_editable_receipt(uuid) from public, anon, authenticated;
revoke all on function public.receipt_confirmation_payload(uuid) from public, anon, authenticated;
revoke all on function public.allocate_receipt_number(date) from public, anon, authenticated;

-- Receiving API. Each function repeats server-side authentication/authorization.
revoke all on function public.save_supplier(uuid,text,text,text,text,boolean) from public, anon;
revoke all on function public.create_receipt_draft(date,uuid,uuid,text,text,text) from public, anon;
revoke all on function public.update_receipt_draft(uuid,date,uuid,uuid,text,text,text) from public, anon;
revoke all on function public.add_receipt_item(uuid,uuid,numeric,integer) from public, anon;
revoke all on function public.remove_receipt_item(uuid) from public, anon;
revoke all on function public.attach_receipt_photo(uuid,text,text,text,bigint) from public, anon;
revoke all on function public.detach_receipt_photo(uuid) from public, anon;
revoke all on function public.cancel_receipt(uuid) from public, anon;
revoke all on function public.confirm_receipt(uuid) from public, anon;
revoke all on function public.get_receipt(uuid) from public, anon;
revoke all on function public.list_receipts(date,date,uuid,uuid,uuid,public.receipt_status,text,integer) from public, anon;
revoke all on function public.record_stock_movement(uuid,uuid,public.stock_movement_type,numeric,public.stock_direction,text,uuid,text,jsonb,boolean) from public, anon;

grant execute on function public.save_supplier(uuid,text,text,text,text,boolean) to authenticated;
grant execute on function public.create_receipt_draft(date,uuid,uuid,text,text,text) to authenticated;
grant execute on function public.update_receipt_draft(uuid,date,uuid,uuid,text,text,text) to authenticated;
grant execute on function public.add_receipt_item(uuid,uuid,numeric,integer) to authenticated;
grant execute on function public.remove_receipt_item(uuid) to authenticated;
grant execute on function public.attach_receipt_photo(uuid,text,text,text,bigint) to authenticated;
grant execute on function public.detach_receipt_photo(uuid) to authenticated;
grant execute on function public.cancel_receipt(uuid) to authenticated;
grant execute on function public.confirm_receipt(uuid) to authenticated;
grant execute on function public.get_receipt(uuid) to authenticated;
grant execute on function public.list_receipts(date,date,uuid,uuid,uuid,public.receipt_status,text,integer) to authenticated;
grant execute on function public.record_stock_movement(uuid,uuid,public.stock_movement_type,numeric,public.stock_direction,text,uuid,text,jsonb,boolean) to authenticated;

-- Verification query:
select routine_name, security_type
from information_schema.routines
where routine_schema = 'public' and routine_name in (
  'save_supplier', 'create_receipt_draft', 'update_receipt_draft',
  'add_receipt_item', 'remove_receipt_item', 'attach_receipt_photo', 'detach_receipt_photo',
  'cancel_receipt', 'confirm_receipt', 'get_receipt', 'list_receipts'
)
order by routine_name;
