-- SOMA order document bundle - 014 trusted transactional workflow
-- Run after 013_order_documents_rls.sql.
-- All public mutations re-check authenticated, active FACOLUB Admin/Management access.

create or replace function public.assert_order_document_manager()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null
    or not public.has_environment_access('FACOLUB')
    or public.current_app_role() not in (
      'admin'::public.app_role, 'management'::public.app_role
    ) then
    raise exception 'Forbidden' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.replace_draft_order_items(
  target_order_id uuid, target_items jsonb
)
returns void language plpgsql security definer set search_path = '' as $$
declare item record; item_description text; item_quantity numeric(18,3); item_product uuid;
begin
  if target_items is null or jsonb_typeof(target_items) <> 'array'
    or jsonb_array_length(target_items) = 0
    or jsonb_array_length(target_items) > 100 then
    raise exception 'Orders require between 1 and 100 items' using errcode = '23514';
  end if;

  delete from public.order_items where order_id = target_order_id;
  for item in
    select value, ordinality
    from jsonb_array_elements(target_items) with ordinality
  loop
    if jsonb_typeof(item.value) <> 'object' then
      raise exception 'Every order item must be an object' using errcode = '22023';
    end if;
    item_description := trim(item.value ->> 'description');
    begin
      item_quantity := (item.value ->> 'quantity')::numeric(18,3);
      item_product := nullif(item.value ->> 'product_format_id', '')::uuid;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Invalid item value on line %', item.ordinality using errcode = '22023';
    end;
    if item_description is null or item_description = '' or item_quantity is null or item_quantity <= 0 then
      raise exception 'Description and quantity > 0 are required on line %', item.ordinality
        using errcode = '23514';
    end if;
    insert into public.order_items (
      order_id, product_format_id, description, quantity, position
    ) values (
      target_order_id, item_product, item_description, item_quantity, item.ordinality::integer
    );
  end loop;
end;
$$;

create or replace function public.create_order(
  target_customer_id uuid,
  target_order_date date,
  target_purchase_order text,
  target_destination_city text,
  target_destination_address text,
  target_items jsonb
)
returns public.orders language plpgsql security definer set search_path = '' as $$
declare created_order public.orders;
begin
  perform public.assert_order_document_manager();
  if target_order_date is null then raise exception 'Order date is required' using errcode = '23502'; end if;
  if not exists (select 1 from public.customers c where c.id = target_customer_id and c.is_active) then
    raise exception 'Active customer not found' using errcode = 'P0002';
  end if;

  insert into public.orders (
    customer_id, order_date, purchase_order, destination_city,
    destination_address, status, created_by
  ) values (
    target_customer_id, target_order_date, nullif(trim(target_purchase_order), ''),
    nullif(trim(target_destination_city), ''), nullif(trim(target_destination_address), ''),
    'draft'::public.order_status, auth.uid()
  ) returning * into created_order;

  perform public.replace_draft_order_items(created_order.id, target_items);
  return created_order;
end;
$$;

create or replace function public.update_draft_order(
  target_order_id uuid,
  target_customer_id uuid,
  target_order_date date,
  target_purchase_order text,
  target_destination_city text,
  target_destination_address text,
  target_items jsonb
)
returns public.orders language plpgsql security definer set search_path = '' as $$
declare updated_order public.orders;
begin
  perform public.assert_order_document_manager();
  perform 1 from public.orders o where o.id = target_order_id and o.status = 'draft' for update;
  if not found then raise exception 'Draft order not found' using errcode = 'P0002'; end if;
  if target_order_date is null then raise exception 'Order date is required' using errcode = '23502'; end if;
  if not exists (select 1 from public.customers c where c.id = target_customer_id and c.is_active) then
    raise exception 'Active customer not found' using errcode = 'P0002';
  end if;

  update public.orders set
    customer_id = target_customer_id,
    order_date = target_order_date,
    purchase_order = nullif(trim(target_purchase_order), ''),
    destination_city = nullif(trim(target_destination_city), ''),
    destination_address = nullif(trim(target_destination_address), '')
  where id = target_order_id returning * into updated_order;
  perform public.replace_draft_order_items(target_order_id, target_items);
  return updated_order;
end;
$$;

create or replace function public.prepare_document_bundle(target_order_id uuid)
returns public.orders language plpgsql security definer set search_path = '' as $$
declare target_order public.orders; target_invoice_id uuid;
begin
  perform public.assert_order_document_manager();
  select o.* into target_order from public.orders o where o.id = target_order_id for update;
  if not found then raise exception 'Order not found' using errcode = 'P0002'; end if;
  if target_order.status in ('draft'::public.order_status, 'cancelled'::public.order_status) then
    raise exception 'Order must be confirmed before preparing documents' using errcode = '23514';
  end if;

  insert into public.invoices (
    order_id, invoice_number, invoice_date, customer_id, purchase_order,
    customer_name_snapshot, customer_city_snapshot, customer_address_snapshot,
    customer_ice_snapshot, status, currency, created_by
  ) values (
    target_order.id, 'FAC-' || target_order.order_reference, target_order.order_date,
    target_order.customer_id, target_order.purchase_order, target_order.customer_name_snapshot,
    target_order.customer_city_snapshot, target_order.customer_address_snapshot,
    target_order.customer_ice_snapshot, 'draft'::public.invoice_status, 'MAD', auth.uid()
  ) on conflict do nothing;

  select i.id into target_invoice_id from public.invoices i
  where i.order_id = target_order.id
    and i.invoice_number = 'FAC-' || target_order.order_reference;
  if target_invoice_id is null then
    raise exception 'Order invoice could not be created consistently' using errcode = '23505';
  end if;
  insert into public.invoice_items (
    invoice_id, order_item_id, description, quantity, unit_price, position
  )
  select target_invoice_id, oi.id, oi.description, oi.quantity, 0, oi.position
  from public.order_items oi
  where oi.order_id = target_order.id
    and not exists (
      select 1 from public.invoice_items ii
      where ii.invoice_id = target_invoice_id and ii.order_item_id = oi.id
    );

  insert into public.delivery_notes (
    order_id, delivery_note_number, delivery_date, prepared_for, object,
    handover_date, transport_reception_name, status
  ) values (
    target_order.id, 'BL-' || target_order.order_reference, target_order.order_date,
    target_order.customer_name_snapshot, 'acheminement de marchandises',
    target_order.order_date, target_order.customer_name_snapshot, 'draft'::public.document_status
  ) on conflict do nothing;

  insert into public.transport_notes (
    order_id, transport_note_number, transport_date, sender, pickup_date,
    loading_location, destination, status
  ) values (
    target_order.id, 'BT-' || target_order.order_reference, target_order.order_date,
    'SOMA LUBRIFIANTS', target_order.order_date, 'CASABLANCA',
    coalesce(target_order.destination_city, target_order.destination_address),
    'draft'::public.document_status
  ) on conflict do nothing;

  if not exists (
      select 1 from public.delivery_notes d
      where d.order_id = target_order.id
        and d.delivery_note_number = 'BL-' || target_order.order_reference
    )
    or not exists (
      select 1 from public.transport_notes t
      where t.order_id = target_order.id
        and t.transport_note_number = 'BT-' || target_order.order_reference
    ) then
    raise exception 'Document bundle could not be created consistently'
      using errcode = '23505';
  end if;

  if target_order.status = 'confirmed'::public.order_status then
    update public.orders set status = 'documents_ready'::public.order_status
    where id = target_order.id returning * into target_order;
  end if;
  return target_order;
end;
$$;

create or replace function public.confirm_order(target_order_id uuid)
returns public.orders language plpgsql security definer set search_path = '' as $$
declare target_order public.orders; target_customer public.customers; common_reference text;
begin
  perform public.assert_order_document_manager();
  select o.* into target_order from public.orders o where o.id = target_order_id for update;
  if not found then raise exception 'Order not found' using errcode = 'P0002'; end if;
  if target_order.status <> 'draft'::public.order_status then
    -- Confirmation is idempotent for an order that already owns a complete bundle.
    if target_order.status in ('confirmed'::public.order_status, 'documents_ready'::public.order_status, 'completed'::public.order_status) then
      return public.prepare_document_bundle(target_order.id);
    end if;
    raise exception 'Cancelled orders cannot be confirmed' using errcode = '23514';
  end if;
  if not exists (select 1 from public.order_items oi where oi.order_id = target_order.id) then
    raise exception 'Order must contain at least one item' using errcode = '23514';
  end if;
  select c.* into target_customer from public.customers c where c.id = target_order.customer_id;
  common_reference := public.allocate_order_reference(target_order.order_date);

  update public.orders set
    order_reference = common_reference,
    order_number = 'CMD-' || common_reference,
    customer_name_snapshot = target_customer.company_name,
    customer_city_snapshot = target_customer.city,
    customer_address_snapshot = target_customer.address,
    customer_ice_snapshot = target_customer.ice,
    status = 'confirmed'::public.order_status,
    confirmed_by = auth.uid(), confirmed_at = now()
  where id = target_order.id returning * into target_order;

  return public.prepare_document_bundle(target_order.id);
end;
$$;

create or replace function public.update_invoice_prices(
  target_invoice_id uuid, target_prices jsonb
)
returns public.invoices language plpgsql security definer set search_path = '' as $$
declare target_invoice public.invoices; price record; parsed_price numeric(18,2); updated_count integer := 0;
begin
  perform public.assert_order_document_manager();
  select i.* into target_invoice from public.invoices i where i.id = target_invoice_id for update;
  if not found or target_invoice.order_id is null then raise exception 'Order invoice not found' using errcode = 'P0002'; end if;
  if target_invoice.status <> 'draft'::public.invoice_status then raise exception 'Only draft prices can change' using errcode = '23514'; end if;
  if target_prices is null or jsonb_typeof(target_prices) <> 'array' then raise exception 'Prices must be an array' using errcode = '22023'; end if;
  if jsonb_array_length(target_prices) <> (select count(*) from public.invoice_items ii where ii.invoice_id = target_invoice_id) then
    raise exception 'A price is required for every invoice line' using errcode = '23514';
  end if;

  for price in select value from jsonb_array_elements(target_prices) loop
    begin parsed_price := (price.value ->> 'unit_price')::numeric(18,2);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Invalid unit price' using errcode = '22023';
    end;
    if parsed_price is null or parsed_price < 0 then raise exception 'Unit price cannot be negative' using errcode = '23514'; end if;
    update public.invoice_items set unit_price = parsed_price
    where invoice_id = target_invoice_id
      and order_item_id = (price.value ->> 'order_item_id')::uuid;
    if not found then raise exception 'Invoice line does not belong to this order invoice' using errcode = '23514'; end if;
    updated_count := updated_count + 1;
  end loop;

  if updated_count <> (select count(distinct (value ->> 'order_item_id')) from jsonb_array_elements(target_prices)) then
    raise exception 'Each invoice line must appear exactly once' using errcode = '23514';
  end if;
  update public.invoices set prices_confirmed_by = auth.uid(), prices_confirmed_at = now()
  where id = target_invoice_id returning * into target_invoice;
  return target_invoice;
end;
$$;

create or replace function public.refresh_order_document_status(target_order_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.invoices i where i.order_id = target_order_id and i.status = 'issued')
    and exists (select 1 from public.delivery_notes d where d.order_id = target_order_id and d.status = 'issued')
    and exists (select 1 from public.transport_notes t where t.order_id = target_order_id and t.status = 'issued') then
    update public.orders set status = 'completed' where id = target_order_id and status <> 'cancelled';
  elsif exists (select 1 from public.invoices i where i.order_id = target_order_id)
    and exists (select 1 from public.delivery_notes d where d.order_id = target_order_id)
    and exists (select 1 from public.transport_notes t where t.order_id = target_order_id) then
    update public.orders set status = 'documents_ready'
    where id = target_order_id and status not in ('draft', 'cancelled');
  end if;
end;
$$;

create or replace function public.protect_final_invoice()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if old.status <> 'draft' and (
    to_jsonb(new) - array['status', 'cancelled_at', 'updated_at']
    is distinct from to_jsonb(old) - array['status', 'cancelled_at', 'updated_at']
  ) then raise exception 'Issued/cancelled invoice data is immutable' using errcode = '23514'; end if;
  if old.status = 'cancelled' and new.status <> 'cancelled' then
    raise exception 'Cancelled invoices cannot be restored' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists invoices_protect_final on public.invoices;
create trigger invoices_protect_final before update on public.invoices
for each row execute function public.protect_final_invoice();

create or replace function public.require_draft_invoice_for_item_change()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare parent_invoice_id uuid := coalesce(new.invoice_id, old.invoice_id);
begin
  if not exists (select 1 from public.invoices i where i.id = parent_invoice_id and i.status = 'draft') then
    raise exception 'Invoice lines can only change while the invoice is draft' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists invoice_items_require_draft on public.invoice_items;
create trigger invoice_items_require_draft before insert or update or delete on public.invoice_items
for each row execute function public.require_draft_invoice_for_item_change();

-- Keep the established signature. Legacy invoices retain annual FAC-YYYY-###### numbering;
-- order invoices retain the preallocated FAC-YYMMDD-NN common reference.
create or replace function public.issue_invoice(target_invoice_id uuid)
returns public.invoices language plpgsql security definer set search_path = '' as $$
declare target_invoice public.invoices; target_year integer; next_value bigint;
begin
  perform public.assert_order_document_manager();
  select i.* into target_invoice from public.invoices i where i.id = target_invoice_id for update;
  if not found then raise exception 'Invoice not found' using errcode = 'P0002'; end if;
  if target_invoice.status <> 'draft' then raise exception 'Only draft invoices can be issued' using errcode = '23514'; end if;
  if not exists (select 1 from public.invoice_items ii where ii.invoice_id = target_invoice_id) then
    raise exception 'Invoice must contain at least one line' using errcode = '23514';
  end if;
  if target_invoice.order_id is not null and target_invoice.prices_confirmed_at is null then
    raise exception 'Order invoice prices must be confirmed before issue' using errcode = '23514';
  end if;

  if target_invoice.order_id is null and target_invoice.invoice_number is null then
    target_year := extract(year from target_invoice.invoice_date)::integer;
    insert into public.invoice_number_sequences (invoice_year, last_value) values (target_year, 1)
    on conflict (invoice_year) do update set last_value = public.invoice_number_sequences.last_value + 1
    returning public.invoice_number_sequences.last_value into next_value;
    target_invoice.invoice_number := format('FAC-%s-%s', target_year, lpad(next_value::text, 6, '0'));
  elsif target_invoice.order_id is not null and target_invoice.invoice_number is null then
    select 'FAC-' || o.order_reference into target_invoice.invoice_number
    from public.orders o where o.id = target_invoice.order_id;
  end if;

  update public.invoices set invoice_number = target_invoice.invoice_number,
    status = 'issued', total = public.invoice_authoritative_total(target_invoice_id),
    issued_at = now(), updated_at = now()
  where id = target_invoice_id returning * into target_invoice;
  if target_invoice.order_id is not null then perform public.refresh_order_document_status(target_invoice.order_id); end if;
  return target_invoice;
end;
$$;

create or replace function public.update_delivery_note(
  target_delivery_note_id uuid, target_delivery_date date, target_prepared_for text,
  target_object text, target_handover_date date, target_transport_reception_name text
)
returns public.delivery_notes language plpgsql security definer set search_path = '' as $$
declare result public.delivery_notes;
begin
  perform public.assert_order_document_manager();
  update public.delivery_notes set delivery_date = target_delivery_date,
    prepared_for = nullif(trim(target_prepared_for), ''), object = nullif(trim(target_object), ''),
    handover_date = target_handover_date,
    transport_reception_name = nullif(trim(target_transport_reception_name), '')
  where id = target_delivery_note_id and status = 'draft'
  returning * into result;
  if not found then raise exception 'Draft delivery note not found' using errcode = 'P0002'; end if;
  return result;
end;
$$;

create or replace function public.issue_delivery_note(target_delivery_note_id uuid)
returns public.delivery_notes language plpgsql security definer set search_path = '' as $$
declare result public.delivery_notes;
begin
  perform public.assert_order_document_manager();
  update public.delivery_notes set status = 'issued', issued_by = auth.uid(), issued_at = now()
  where id = target_delivery_note_id and status = 'draft'
    and delivery_note_number is not null and delivery_date is not null
    and prepared_for is not null and object is not null and handover_date is not null
  returning * into result;
  if not found then raise exception 'Complete draft delivery note not found' using errcode = '23514'; end if;
  perform public.refresh_order_document_status(result.order_id);
  return result;
end;
$$;

create or replace function public.update_transport_note(
  target_transport_note_id uuid, target_transport_date date, target_transport_person text,
  target_sender text, target_pickup_date date, target_loading_location text,
  target_destination text, target_vehicle_registration text
)
returns public.transport_notes language plpgsql security definer set search_path = '' as $$
declare result public.transport_notes;
begin
  perform public.assert_order_document_manager();
  update public.transport_notes set transport_date = target_transport_date,
    transport_person = nullif(trim(target_transport_person), ''), sender = nullif(trim(target_sender), ''),
    pickup_date = target_pickup_date, loading_location = nullif(trim(target_loading_location), ''),
    destination = nullif(trim(target_destination), ''),
    vehicle_registration = nullif(trim(target_vehicle_registration), '')
  where id = target_transport_note_id and status = 'draft'
  returning * into result;
  if not found then raise exception 'Draft transport note not found' using errcode = 'P0002'; end if;
  return result;
end;
$$;

create or replace function public.issue_transport_note(target_transport_note_id uuid)
returns public.transport_notes language plpgsql security definer set search_path = '' as $$
declare result public.transport_notes;
begin
  perform public.assert_order_document_manager();
  update public.transport_notes set status = 'issued', issued_by = auth.uid(), issued_at = now()
  where id = target_transport_note_id and status = 'draft'
    and transport_note_number is not null and transport_date is not null
    and transport_person is not null and sender is not null and pickup_date is not null
    and loading_location is not null and destination is not null and vehicle_registration is not null
  returning * into result;
  if not found then raise exception 'Complete draft transport note not found' using errcode = '23514'; end if;
  perform public.refresh_order_document_status(result.order_id);
  return result;
end;
$$;

create or replace function public.cancel_document(target_document_type text, target_document_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare affected integer; related_order_id uuid;
begin
  perform public.assert_order_document_manager();
  case lower(trim(target_document_type))
    when 'invoice' then
      update public.invoices set status = 'cancelled', cancelled_at = now()
      where id = target_document_id and status <> 'cancelled' returning order_id into related_order_id;
    when 'delivery_note' then
      update public.delivery_notes set status = 'cancelled', cancelled_at = now()
      where id = target_document_id and status <> 'cancelled' returning order_id into related_order_id;
    when 'transport_note' then
      update public.transport_notes set status = 'cancelled', cancelled_at = now()
      where id = target_document_id and status <> 'cancelled' returning order_id into related_order_id;
    else raise exception 'Unknown document type' using errcode = '22023';
  end case;
  get diagnostics affected = row_count;
  if affected = 0 then raise exception 'Document not found or already cancelled' using errcode = 'P0002'; end if;
  if related_order_id is not null then perform public.refresh_order_document_status(related_order_id); end if;
end;
$$;

revoke all on function public.assert_order_document_manager() from public, anon, authenticated;
revoke all on function public.replace_draft_order_items(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.refresh_order_document_status(uuid) from public, anon, authenticated;

revoke all on function public.create_order(uuid,date,text,text,text,jsonb) from public, anon;
revoke all on function public.update_draft_order(uuid,uuid,date,text,text,text,jsonb) from public, anon;
revoke all on function public.confirm_order(uuid) from public, anon;
revoke all on function public.prepare_document_bundle(uuid) from public, anon;
revoke all on function public.update_invoice_prices(uuid,jsonb) from public, anon;
revoke all on function public.issue_invoice(uuid) from public, anon;
revoke all on function public.update_delivery_note(uuid,date,text,text,date,text) from public, anon;
revoke all on function public.issue_delivery_note(uuid) from public, anon;
revoke all on function public.update_transport_note(uuid,date,text,text,date,text,text,text) from public, anon;
revoke all on function public.issue_transport_note(uuid) from public, anon;
revoke all on function public.cancel_document(text,uuid) from public, anon;

grant execute on function public.create_order(uuid,date,text,text,text,jsonb) to authenticated;
grant execute on function public.update_draft_order(uuid,uuid,date,text,text,text,jsonb) to authenticated;
grant execute on function public.confirm_order(uuid) to authenticated;
grant execute on function public.prepare_document_bundle(uuid) to authenticated;
grant execute on function public.update_invoice_prices(uuid,jsonb) to authenticated;
grant execute on function public.issue_invoice(uuid) to authenticated;
grant execute on function public.update_delivery_note(uuid,date,text,text,date,text) to authenticated;
grant execute on function public.issue_delivery_note(uuid) to authenticated;
grant execute on function public.update_transport_note(uuid,date,text,text,date,text,text,text) to authenticated;
grant execute on function public.issue_transport_note(uuid) to authenticated;
grant execute on function public.cancel_document(text,uuid) to authenticated;

-- Verification query:
select routine_name, security_type
from information_schema.routines
where routine_schema = 'public' and routine_name in (
  'create_order', 'update_draft_order', 'confirm_order', 'prepare_document_bundle',
  'update_invoice_prices', 'issue_invoice', 'update_delivery_note',
  'issue_delivery_note', 'update_transport_note', 'issue_transport_note', 'cancel_document'
)
order by routine_name;
