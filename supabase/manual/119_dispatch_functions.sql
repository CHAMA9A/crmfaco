-- SOMA / FACOLUB S8 dispatch - 119 trusted operational functions
-- Run after 118_dispatch_foundation.sql.

create or replace function public.assert_dispatch_actor(allow_internal boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); actor_role public.app_role;
begin
  if actor is null or not public.has_environment_access('FACOLUB') then
    raise exception 'FACOLUB access required' using errcode = '42501';
  end if;
  select p.role into actor_role from public.profiles p where p.id = actor and p.is_active;
  if actor_role not in ('admin'::public.app_role,'management'::public.app_role,'factory'::public.app_role) then
    raise exception 'Dispatch access denied' using errcode = '42501';
  end if;
  if allow_internal and actor_role not in ('admin'::public.app_role,'management'::public.app_role) then
    raise exception 'Only Management/Admin may create internal dispatches' using errcode = '42501';
  end if;
  return actor;
end $$;

create or replace function public.create_dispatch_draft(
  target_order_id uuid, target_location_id uuid,
  target_destination_type public.dispatch_destination_type default 'customer',
  target_destination_name text default null,
  target_delivery_address text default null, target_delivery_city text default null,
  target_delivery_contact text default null
)
returns public.dispatches language plpgsql security definer set search_path = '' as $$
declare actor uuid; target_order public.orders; target_customer public.customers; result public.dispatches;
begin
  actor := public.assert_dispatch_actor(target_destination_type = 'internal');
  if not exists (select 1 from public.stock_locations l where l.id = target_location_id and l.is_active) then
    raise exception 'Active stock location not found' using errcode = 'P0002';
  end if;
  if target_destination_type = 'customer' then
    select o.* into target_order from public.orders o where o.id = target_order_id for update;
    if not found or target_order.status in ('draft','cancelled') then
      raise exception 'Confirmed customer order not found' using errcode = 'P0002';
    end if;
    select c.* into target_customer from public.customers c where c.id = target_order.customer_id;
    insert into public.dispatches(order_id, customer_id, location_id, dispatch_date, destination_type,
      destination_name, delivery_address_snapshot, delivery_city_snapshot, delivery_contact_snapshot, created_by)
    values (target_order.id, target_order.customer_id, target_location_id, current_date, 'customer',
      coalesce(nullif(trim(target_destination_name),''), target_order.customer_name_snapshot, target_customer.company_name),
      coalesce(nullif(trim(target_delivery_address),''), target_order.destination_address,
        target_customer.default_delivery_address, target_customer.address_line1, target_customer.address),
      coalesce(nullif(trim(target_delivery_city),''), target_order.destination_city,
        target_customer.delivery_city, target_customer.city),
      coalesce(nullif(trim(target_delivery_contact),''), target_customer.delivery_contact_name), actor)
    returning * into result;
  else
    if target_order_id is not null or nullif(trim(target_destination_name),'') is null then
      raise exception 'Internal dispatch requires an explicit destination and no order' using errcode = '23514';
    end if;
    insert into public.dispatches(location_id, dispatch_date, destination_type, destination_name,
      delivery_address_snapshot, delivery_city_snapshot, delivery_contact_snapshot, created_by)
    values (target_location_id, current_date, 'internal', trim(target_destination_name),
      nullif(trim(target_delivery_address),''), nullif(trim(target_delivery_city),''),
      nullif(trim(target_delivery_contact),''), actor) returning * into result;
  end if;
  return result;
end $$;

create or replace function public.update_dispatch_draft(
  target_dispatch_id uuid, target_vehicle_description text, target_vehicle_registration text,
  target_driver_name text, target_driver_phone text, target_transport_company text, target_notes text
)
returns public.dispatches language plpgsql security definer set search_path = '' as $$
declare actor uuid := public.assert_dispatch_actor(false); result public.dispatches;
begin
  update public.dispatches set vehicle_description = target_vehicle_description,
    vehicle_registration = target_vehicle_registration, driver_name = target_driver_name,
    driver_phone = target_driver_phone, transport_company = target_transport_company, notes = target_notes
  where id = target_dispatch_id and status = 'draft'
    and (created_by = actor or public.current_app_role() in ('admin'::public.app_role,'management'::public.app_role))
  returning * into result;
  if not found then raise exception 'Editable dispatch draft not found' using errcode = 'P0002'; end if;
  return result;
end $$;

create or replace function public.replace_dispatch_items(target_dispatch_id uuid, target_items jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := public.assert_dispatch_actor(false); target public.dispatches; item jsonb; oi public.order_items;
  pf record; stock public.stock_items; loaded numeric(18,3);
begin
  select * into target from public.dispatches d where d.id = target_dispatch_id and d.status = 'draft' for update;
  if not found or (target.created_by <> actor and public.current_app_role() = 'factory'::public.app_role) then
    raise exception 'Editable dispatch draft not found' using errcode = 'P0002';
  end if;
  if target_items is null or jsonb_typeof(target_items) <> 'array' or jsonb_array_length(target_items) = 0 then
    raise exception 'At least one loaded product is required' using errcode = '22023';
  end if;
  delete from public.dispatch_items where dispatch_id = target.id;
  for item in select value from jsonb_array_elements(target_items) loop
    begin loaded := (item->>'quantity_loaded')::numeric(18,3);
    exception when others then raise exception 'Invalid loaded quantity' using errcode = '22023'; end;
    if loaded is null or loaded <= 0 then raise exception 'Loaded quantity must be greater than zero' using errcode = '23514'; end if;
    if target.order_id is not null then
      select * into oi from public.order_items x where x.id = (item->>'order_item_id')::uuid and x.order_id = target.order_id;
      if not found or oi.product_format_id is null then raise exception 'Dispatch line is not a catalogued order product' using errcode = '23514'; end if;
      select f.id, f.sku into pf from public.product_formats f where f.id = oi.product_format_id;
    else
      select f.id, f.sku into pf from public.product_formats f where f.id = (item->>'product_format_id')::uuid;
      if not found then raise exception 'Product format not found' using errcode = 'P0002'; end if;
      oi := null;
    end if;
    select s.* into stock from public.stock_items s where s.product_format_id = pf.id
      and s.category = 'finished_product' and s.unit = 'piece' and s.is_active;
    if not found then raise exception 'Active finished-product stock item is missing for %', pf.sku using errcode = '23514'; end if;
    insert into public.dispatch_items(dispatch_id, order_item_id, product_format_id, stock_item_id,
      sku_snapshot, description_snapshot, ordered_quantity_snapshot, quantity_loaded)
    values(target.id, case when target.order_id is null then null else oi.id end, pf.id, stock.id,
      pf.sku, case when target.order_id is null then stock.name else oi.description end,
      case when target.order_id is null then null else oi.quantity end, loaded);
  end loop;
end $$;

create or replace function public.attach_dispatch_photo(target_dispatch_id uuid,
  target_category public.dispatch_attachment_category, target_storage_path text,
  target_file_name text, target_mime_type text, target_file_size bigint)
returns public.dispatch_attachments language plpgsql security definer set search_path = '' as $$
declare actor uuid := public.assert_dispatch_actor(false); target public.dispatches; result public.dispatch_attachments;
begin
  select * into target from public.dispatches d where d.id = target_dispatch_id and d.status = 'draft' for update;
  if not found or (target.created_by <> actor and public.current_app_role() = 'factory'::public.app_role) then
    raise exception 'Editable dispatch draft not found' using errcode = 'P0002';
  end if;
  if split_part(trim(target_storage_path),'/',1) <> target.id::text then
    raise exception 'Photo path must belong to dispatch' using errcode = '23514';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'facolub-dispatch' and o.name = trim(target_storage_path)) then
    raise exception 'Private dispatch photo was not uploaded' using errcode = 'P0002';
  end if;
  insert into public.dispatch_attachments(dispatch_id, category, storage_path, file_name, mime_type, file_size, uploaded_by)
  values(target.id, target_category, trim(target_storage_path), nullif(trim(target_file_name),''),
    lower(trim(target_mime_type)), target_file_size, actor)
  on conflict (storage_path) do update set category = excluded.category returning * into result;
  return result;
end $$;

create or replace function public.detach_dispatch_photo(target_attachment_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare actor uuid := public.assert_dispatch_actor(false); a public.dispatch_attachments; path text;
begin
  select x.* into a from public.dispatch_attachments x join public.dispatches d on d.id=x.dispatch_id
  where x.id=target_attachment_id and d.status='draft'
    and (d.created_by=actor or public.current_app_role() in ('admin'::public.app_role,'management'::public.app_role));
  if not found then raise exception 'Editable attachment not found' using errcode='P0002'; end if;
  delete from public.dispatch_attachments where id=a.id returning storage_path into path;
  return path;
end $$;

create or replace function public.confirm_dispatch(target_dispatch_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := public.assert_dispatch_actor(false); target public.dispatches; line public.dispatch_items;
  already numeric(20,3); physical numeric(20,3); movement_id uuid; balances jsonb := '[]'::jsonb;
begin
  select * into target from public.dispatches d where d.id=target_dispatch_id for update;
  if not found then raise exception 'Dispatch not found' using errcode='P0002'; end if;
  if target.status='confirmed' then
    return jsonb_build_object('dispatch_id',target.id,'dispatch_number',target.dispatch_number,
      'status','confirmed','confirmed_at',target.confirmed_at,'idempotent_retry',true);
  end if;
  if target.status<>'draft' then raise exception 'Only a draft dispatch can be confirmed' using errcode='23514'; end if;
  if target.created_by<>actor and public.current_app_role()='factory'::public.app_role then
    raise exception 'Factory users may confirm only their own draft' using errcode='42501';
  end if;
  if target.vehicle_registration is null or target.driver_name is null then
    raise exception 'Driver and vehicle registration are required' using errcode='23514';
  end if;
  if not exists(select 1 from public.dispatch_attachments a where a.dispatch_id=target.id and a.category='goods')
    or not exists(select 1 from public.dispatch_attachments a where a.dispatch_id=target.id and a.category in ('vehicle','registration')) then
    raise exception 'Goods and vehicle/registration photo evidence are required' using errcode='23514';
  end if;
  if not exists(select 1 from public.dispatch_items i where i.dispatch_id=target.id) then
    raise exception 'At least one loaded product is required' using errcode='23514';
  end if;
  if target.order_id is not null then
    perform 1 from public.orders o where o.id=target.order_id and o.status not in ('draft','cancelled') for update;
    if not found then raise exception 'Dispatch order is unavailable' using errcode='23514'; end if;
  end if;
  -- Sorted transaction advisory locks serialize the same physical item/location across different orders.
  for line in select distinct on (i.stock_item_id) i.* from public.dispatch_items i
    where i.dispatch_id=target.id order by i.stock_item_id, i.id loop
    perform pg_advisory_xact_lock(hashtextextended(line.stock_item_id::text||':'||target.location_id::text,0));
  end loop;
  for line in select * from public.dispatch_items i where i.dispatch_id=target.id order by i.id loop
    if line.quantity_loaded<=0 then raise exception 'Loaded quantity must be greater than zero' using errcode='23514'; end if;
    if not exists(select 1 from public.stock_items s where s.id=line.stock_item_id
      and s.product_format_id=line.product_format_id and s.category='finished_product' and s.unit='piece') then
      raise exception 'Dispatch may consume only its mapped finished product' using errcode='23514';
    end if;
    if target.order_id is not null then
      if not exists(select 1 from public.order_items oi where oi.id=line.order_item_id
        and oi.order_id=target.order_id and oi.product_format_id=line.product_format_id) then
        raise exception 'Dispatch line is not part of the order' using errcode='23514';
      end if;
      select coalesce(sum(i.quantity_loaded),0) into already from public.dispatch_items i
      join public.dispatches d on d.id=i.dispatch_id
      where i.order_item_id=line.order_item_id and d.status='confirmed';
      if already+line.quantity_loaded>line.ordered_quantity_snapshot then
        raise exception 'Loaded quantity exceeds the authoritative remaining order quantity' using errcode='23514';
      end if;
    end if;
    select coalesce(sum(case when m.direction='in' then m.quantity else -m.quantity end),0)
      into physical from public.stock_movements m
      where m.stock_item_id=line.stock_item_id and m.location_id=target.location_id;
    if physical<line.quantity_loaded then
      raise exception 'Insufficient finished-product stock for % (physical %, requested %)', line.sku_snapshot, physical, line.quantity_loaded
        using errcode='23514';
    end if;
    insert into public.stock_movements(stock_item_id,location_id,movement_type,quantity,direction,
      reference_type,reference_id,reason,created_by,metadata)
    values(line.stock_item_id,target.location_id,'dispatch',line.quantity_loaded,'out','dispatch',target.id,
      'Physical loading '||coalesce(target.dispatch_number,'draft'),actor,
      jsonb_build_object('dispatch_id',target.id,'dispatch_item_id',line.id,'order_id',target.order_id,
        'customer_id',target.customer_id,'destination',target.destination_name))
    returning id into movement_id;
    balances := balances||jsonb_build_array(jsonb_build_object('dispatch_item_id',line.id,
      'movement_id',movement_id,'stock_item_id',line.stock_item_id,'physical_before',physical,
      'quantity_loaded',line.quantity_loaded,'physical_after',physical-line.quantity_loaded));
  end loop;
  update public.dispatches set dispatch_number=public.allocate_dispatch_number(target.dispatch_date),
    status='confirmed',confirmed_by=actor,confirmed_at=now() where id=target.id returning * into target;
  return jsonb_build_object('dispatch_id',target.id,'dispatch_number',target.dispatch_number,
    'status','confirmed','confirmed_at',target.confirmed_at,'idempotent_retry',false,'balances',balances);
end $$;

create or replace function public.cancel_dispatch_draft(target_dispatch_id uuid)
returns public.dispatches language plpgsql security definer set search_path = '' as $$
declare actor uuid := public.assert_dispatch_actor(false); result public.dispatches;
begin
  update public.dispatches set status='cancelled' where id=target_dispatch_id and status='draft'
    and (created_by=actor or public.current_app_role() in ('admin'::public.app_role,'management'::public.app_role))
    returning * into result;
  if not found then raise exception 'Cancellable dispatch draft not found' using errcode='P0002'; end if;
  return result;
end $$;

create or replace function public.get_order_dispatch_remaining(target_order_id uuid)
returns table(order_item_id uuid,product_format_id uuid,sku text,description text,ordered numeric,
  dispatched numeric,remaining numeric) language plpgsql security definer set search_path='' stable as $$
begin
  perform public.assert_dispatch_actor(false);
  return query select oi.id,oi.product_format_id,pf.sku,oi.description,oi.quantity,
    coalesce(sum(di.quantity_loaded) filter(where d.status='confirmed'),0)::numeric,
    (oi.quantity-coalesce(sum(di.quantity_loaded) filter(where d.status='confirmed'),0))::numeric
  from public.order_items oi left join public.product_formats pf on pf.id=oi.product_format_id
  left join public.dispatch_items di on di.order_item_id=oi.id
  left join public.dispatches d on d.id=di.dispatch_id
  where oi.order_id=target_order_id group by oi.id,pf.sku having oi.quantity-coalesce(sum(di.quantity_loaded) filter(where d.status='confirmed'),0)>0
  order by oi.position,oi.id;
end $$;

create or replace function public.get_factory_dispatch_missions()
returns jsonb language plpgsql security definer set search_path='' stable as $$
begin
  perform public.assert_dispatch_actor(false);
  return coalesce((select jsonb_agg(row_data order by row_data->>'order_date',row_data->>'order_number') from (
    select jsonb_build_object('order_id',o.id,'order_number',o.order_number,'order_date',o.order_date,
      'destination_name',o.customer_name_snapshot,'destination_city',o.destination_city,
      'remaining_total',sum(r.remaining),'remaining_lines',count(*),
      'draft_dispatch_id',(select d.id from public.dispatches d where d.order_id=o.id and d.status='draft'
        and (d.created_by=auth.uid() or public.current_app_role() in ('admin'::public.app_role,'management'::public.app_role))
        order by d.created_at desc limit 1)) row_data
    from public.orders o join lateral public.get_order_dispatch_remaining(o.id) r on true
    where o.status not in ('draft','cancelled') group by o.id
  ) q),'[]'::jsonb);
end $$;

create or replace function public.get_dispatch_detail(target_dispatch_id uuid)
returns jsonb language plpgsql security definer set search_path='' stable as $$
declare actor uuid := public.assert_dispatch_actor(false); result jsonb;
begin
  select jsonb_build_object('dispatch',to_jsonb(d),'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at)
    from public.dispatch_items i where i.dispatch_id=d.id),'[]'::jsonb),'attachments',coalesce((select jsonb_agg(to_jsonb(a) order by a.uploaded_at)
    from public.dispatch_attachments a where a.dispatch_id=d.id),'[]'::jsonb),'movements',coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at)
    from public.stock_movements m where m.reference_type='dispatch' and m.reference_id=d.id),'[]'::jsonb)) into result
  from public.dispatches d where d.id=target_dispatch_id;
  if result is null then raise exception 'Dispatch not found' using errcode='P0002'; end if;
  return result;
end $$;

revoke all on function public.assert_dispatch_actor(boolean) from public,anon,authenticated;
revoke all on function public.create_dispatch_draft(uuid,uuid,public.dispatch_destination_type,text,text,text,text) from public,anon;
revoke all on function public.update_dispatch_draft(uuid,text,text,text,text,text,text) from public,anon;
revoke all on function public.replace_dispatch_items(uuid,jsonb) from public,anon;
revoke all on function public.attach_dispatch_photo(uuid,public.dispatch_attachment_category,text,text,text,bigint) from public,anon;
revoke all on function public.detach_dispatch_photo(uuid) from public,anon;
revoke all on function public.confirm_dispatch(uuid) from public,anon;
revoke all on function public.cancel_dispatch_draft(uuid) from public,anon;
revoke all on function public.get_order_dispatch_remaining(uuid) from public,anon;
revoke all on function public.get_factory_dispatch_missions() from public,anon;
revoke all on function public.get_dispatch_detail(uuid) from public,anon;
grant execute on function public.create_dispatch_draft(uuid,uuid,public.dispatch_destination_type,text,text,text,text) to authenticated;
grant execute on function public.update_dispatch_draft(uuid,text,text,text,text,text,text) to authenticated;
grant execute on function public.replace_dispatch_items(uuid,jsonb) to authenticated;
grant execute on function public.attach_dispatch_photo(uuid,public.dispatch_attachment_category,text,text,text,bigint) to authenticated;
grant execute on function public.detach_dispatch_photo(uuid) to authenticated;
grant execute on function public.confirm_dispatch(uuid) to authenticated;
grant execute on function public.cancel_dispatch_draft(uuid) to authenticated;
grant execute on function public.get_order_dispatch_remaining(uuid) to authenticated;
grant execute on function public.get_factory_dispatch_missions() to authenticated;
grant execute on function public.get_dispatch_detail(uuid) to authenticated;
