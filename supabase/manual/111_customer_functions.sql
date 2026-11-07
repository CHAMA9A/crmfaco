-- SOMA FACOLUB customer CRM - 111 trusted functions and derived history
-- Run after 110_customer_master_upgrade.sql. Idempotent.

create or replace function public.assert_customer_manager()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null
    or not public.has_environment_access('FACOLUB')
    or public.current_app_role() not in ('admin'::public.app_role, 'management'::public.app_role)
    or not exists (select 1 from public.profiles p where p.id = actor_id and p.is_active)
  then raise exception 'Forbidden' using errcode = '42501'; end if;
  return actor_id;
end;
$$;

create or replace function public.normalize_customer_text(value text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select nullif(trim(value), '')
$$;

create or replace function public.next_customer_code()
returns text language sql volatile security definer set search_path = '' as $$
  select 'CLI-' || lpad(nextval('public.customer_code_seq')::text, 6, '0')
$$;

create or replace function public.customer_snapshot(target_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare customer_record public.customers;
begin
  perform public.assert_customer_manager();
  select * into customer_record from public.customers where id = target_customer_id;
  if not found then raise exception 'Customer not found' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'customer_id', customer_record.id,
    'company_name', customer_record.company_name,
    'address', coalesce(customer_record.address_line1, customer_record.address),
    'city', customer_record.city,
    'ice', customer_record.ice,
    'if_number', customer_record.if_number,
    'rc', customer_record.rc,
    'delivery_address', coalesce(customer_record.default_delivery_address,
      customer_record.address_line1, customer_record.address),
    'delivery_city', coalesce(customer_record.delivery_city, customer_record.city),
    'delivery_contact_name', coalesce(customer_record.delivery_contact_name,
      customer_record.contact_person),
    'delivery_phone', coalesce(customer_record.delivery_phone, customer_record.phone)
  );
end;
$$;

create or replace function public.get_customer_possible_duplicates(
  target_company_name text default null, target_ice text default null,
  target_email text default null, target_phone text default null,
  target_exclude_customer_id uuid default null
)
returns table (id uuid, customer_code text, company_name text, ice text, email text,
  phone text, is_active boolean, matched_on text[])
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.assert_customer_manager();
  return query
  select c.id, c.customer_code, c.company_name, c.ice, c.email, c.phone, c.is_active,
    array_remove(array[
      case when public.normalize_customer_text(target_ice) is not null
        and lower(trim(c.ice)) = lower(trim(target_ice)) then 'ice' end,
      case when public.normalize_customer_text(target_company_name) is not null
        and lower(trim(c.company_name)) = lower(trim(target_company_name)) then 'company_name' end,
      case when public.normalize_customer_text(target_email) is not null
        and lower(trim(c.email)) = lower(trim(target_email)) then 'email' end,
      case when public.normalize_customer_text(target_phone) is not null
        and regexp_replace(c.phone, '[^0-9+]', '', 'g') = regexp_replace(target_phone, '[^0-9+]', '', 'g') then 'phone' end
    ], null)::text[]
  from public.customers c
  where c.id is distinct from target_exclude_customer_id and (
    (public.normalize_customer_text(target_ice) is not null and lower(trim(c.ice)) = lower(trim(target_ice))) or
    (public.normalize_customer_text(target_company_name) is not null and lower(trim(c.company_name)) = lower(trim(target_company_name))) or
    (public.normalize_customer_text(target_email) is not null and lower(trim(c.email)) = lower(trim(target_email))) or
    (public.normalize_customer_text(target_phone) is not null and regexp_replace(c.phone, '[^0-9+]', '', 'g') = regexp_replace(target_phone, '[^0-9+]', '', 'g'))
  ) order by (lower(trim(c.ice)) = lower(trim(target_ice))) desc, c.company_name;
end;
$$;

create or replace function public.save_customer(target_customer_id uuid, target_payload jsonb)
returns public.customers language plpgsql security definer set search_path = '' as $$
declare actor_id uuid; result public.customers; company text; code text; category public.customer_price_category;
begin
  actor_id := public.assert_customer_manager();
  if target_payload is null or jsonb_typeof(target_payload) <> 'object' then
    raise exception 'Customer payload is required' using errcode = '22023';
  end if;
  company := public.normalize_customer_text(target_payload ->> 'company_name');
  if company is null or char_length(company) > 200 then
    raise exception 'Company name is required (maximum 200 characters)' using errcode = '23514';
  end if;
  if public.normalize_customer_text(target_payload ->> 'email') is not null
    and (target_payload ->> 'email') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Invalid email address' using errcode = '23514';
  end if;
  code := upper(public.normalize_customer_text(target_payload ->> 'customer_code'));
  if code is not null and code !~ '^CLI-[0-9]{6,}$' then
    raise exception 'Customer code must use CLI-000001 format' using errcode = '23514';
  end if;
  begin category := nullif(target_payload ->> 'default_price_category', '')::public.customer_price_category;
  exception when invalid_text_representation then raise exception 'Invalid price category' using errcode = '22023'; end;

  if target_customer_id is null then
    insert into public.customers (
      company_name, customer_code, is_active, contact_person, phone, whatsapp, email,
      ice, if_number, rc, address_line1, address, address_line2, city, postal_code,
      country, default_price_category, notes, default_delivery_address, delivery_city,
      delivery_contact_name, delivery_phone, delivery_instructions, purchase_order_default,
      external_customer_id, created_by
    ) values (
      company, coalesce(code, public.next_customer_code()), true,
      public.normalize_customer_text(target_payload ->> 'contact_person'),
      public.normalize_customer_text(target_payload ->> 'phone'),
      public.normalize_customer_text(target_payload ->> 'whatsapp'),
      lower(public.normalize_customer_text(target_payload ->> 'email')),
      public.normalize_customer_text(target_payload ->> 'ice'),
      public.normalize_customer_text(target_payload ->> 'if_number'),
      public.normalize_customer_text(target_payload ->> 'rc'),
      public.normalize_customer_text(target_payload ->> 'address_line1'),
      public.normalize_customer_text(target_payload ->> 'address_line1'),
      public.normalize_customer_text(target_payload ->> 'address_line2'),
      public.normalize_customer_text(target_payload ->> 'city'),
      public.normalize_customer_text(target_payload ->> 'postal_code'),
      public.normalize_customer_text(target_payload ->> 'country'), category,
      public.normalize_customer_text(target_payload ->> 'notes'),
      public.normalize_customer_text(target_payload ->> 'default_delivery_address'),
      public.normalize_customer_text(target_payload ->> 'delivery_city'),
      public.normalize_customer_text(target_payload ->> 'delivery_contact_name'),
      public.normalize_customer_text(target_payload ->> 'delivery_phone'),
      public.normalize_customer_text(target_payload ->> 'delivery_instructions'),
      public.normalize_customer_text(target_payload ->> 'purchase_order_default'),
      public.normalize_customer_text(target_payload ->> 'external_customer_id'), actor_id
    ) returning * into result;
  else
    update public.customers set
      company_name = company, customer_code = coalesce(code, customer_code),
      contact_person = public.normalize_customer_text(target_payload ->> 'contact_person'),
      phone = public.normalize_customer_text(target_payload ->> 'phone'),
      whatsapp = public.normalize_customer_text(target_payload ->> 'whatsapp'),
      email = lower(public.normalize_customer_text(target_payload ->> 'email')),
      ice = public.normalize_customer_text(target_payload ->> 'ice'),
      if_number = public.normalize_customer_text(target_payload ->> 'if_number'),
      rc = public.normalize_customer_text(target_payload ->> 'rc'),
      address_line1 = public.normalize_customer_text(target_payload ->> 'address_line1'),
      address = public.normalize_customer_text(target_payload ->> 'address_line1'),
      address_line2 = public.normalize_customer_text(target_payload ->> 'address_line2'),
      city = public.normalize_customer_text(target_payload ->> 'city'),
      postal_code = public.normalize_customer_text(target_payload ->> 'postal_code'),
      country = public.normalize_customer_text(target_payload ->> 'country'),
      default_price_category = category, notes = public.normalize_customer_text(target_payload ->> 'notes'),
      default_delivery_address = public.normalize_customer_text(target_payload ->> 'default_delivery_address'),
      delivery_city = public.normalize_customer_text(target_payload ->> 'delivery_city'),
      delivery_contact_name = public.normalize_customer_text(target_payload ->> 'delivery_contact_name'),
      delivery_phone = public.normalize_customer_text(target_payload ->> 'delivery_phone'),
      delivery_instructions = public.normalize_customer_text(target_payload ->> 'delivery_instructions'),
      purchase_order_default = public.normalize_customer_text(target_payload ->> 'purchase_order_default'),
      external_customer_id = public.normalize_customer_text(target_payload ->> 'external_customer_id')
    where id = target_customer_id returning * into result;
    if not found then raise exception 'Customer not found' using errcode = 'P0002'; end if;
  end if;
  return result;
exception when unique_violation then
  raise exception 'Customer code or external identifier already exists' using errcode = '23505';
end;
$$;

create or replace function public.deactivate_customer(target_customer_id uuid)
returns public.customers language plpgsql security definer set search_path = '' as $$
declare result public.customers;
begin
  perform public.assert_customer_manager();
  update public.customers set is_active = false where id = target_customer_id returning * into result;
  if not found then raise exception 'Customer not found' using errcode = 'P0002'; end if;
  return result;
end;
$$;

create or replace function public.add_customer_note(target_customer_id uuid, target_note text)
returns public.customer_notes language plpgsql security definer set search_path = '' as $$
declare actor_id uuid; result public.customer_notes;
begin
  actor_id := public.assert_customer_manager();
  if public.normalize_customer_text(target_note) is null or char_length(trim(target_note)) > 4000 then
    raise exception 'Note is required (maximum 4000 characters)' using errcode = '23514';
  end if;
  insert into public.customer_notes(customer_id, note, created_by)
  values (target_customer_id, trim(target_note), actor_id) returning * into result;
  return result;
end;
$$;

create or replace function public.list_customers(
  target_search text default null, target_active boolean default null,
  target_city text default null, target_price_category public.customer_price_category default null,
  target_limit integer default 200
)
returns table (id uuid, company_name text, customer_code text, contact_person text, phone text,
  email text, city text, ice text, if_number text, rc text, default_price_category public.customer_price_category,
  is_active boolean, last_activity timestamptz, order_count bigint, invoice_count bigint,
  delivery_note_count bigint, transport_note_count bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.assert_customer_manager();
  return query
  select c.id, c.company_name, c.customer_code, c.contact_person, c.phone, c.email, c.city,
    c.ice, c.if_number, c.rc, c.default_price_category, c.is_active,
    greatest(max(o.created_at), max(i.created_at), max(d.created_at), max(t.created_at)) as last_activity,
    count(distinct o.id), count(distinct i.id), count(distinct d.id), count(distinct t.id)
  from public.customers c
  left join public.orders o on o.customer_id = c.id
  left join public.invoices i on i.customer_id = c.id
  left join public.delivery_notes d on d.order_id = o.id
  left join public.transport_notes t on t.order_id = o.id
  where (target_active is null or c.is_active = target_active)
    and (public.normalize_customer_text(target_city) is null or lower(c.city) = lower(trim(target_city)))
    and (target_price_category is null or c.default_price_category = target_price_category)
    and (public.normalize_customer_text(target_search) is null or concat_ws(' ', c.company_name,
      c.customer_code, c.contact_person, c.phone, c.email, c.ice, c.if_number, c.rc) ilike '%' || trim(target_search) || '%')
  group by c.id order by c.company_name limit least(greatest(coalesce(target_limit, 200), 1), 500);
end;
$$;

create or replace function public.get_customer_document_history(target_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.assert_customer_manager();
  return jsonb_build_object(
    'orders', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from
      (select id, order_number, order_date, status, created_at from public.orders where customer_id = target_customer_id) x), '[]'::jsonb),
    'invoices', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from
      (select id, invoice_number, invoice_date, status, total_ttc, created_at from public.invoices where customer_id = target_customer_id) x), '[]'::jsonb),
    'delivery_notes', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from
      (select d.id, d.delivery_note_number, d.delivery_date, d.status, d.created_at from public.delivery_notes d join public.orders o on o.id=d.order_id where o.customer_id=target_customer_id) x), '[]'::jsonb),
    'transport_notes', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from
      (select t.id, t.transport_note_number, t.transport_date, t.status, t.created_at from public.transport_notes t join public.orders o on o.id=t.order_id where o.customer_id=target_customer_id) x), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.assert_customer_manager() from public, anon;
revoke all on function public.next_customer_code() from public, anon, authenticated;
revoke all on function public.save_customer(uuid,jsonb), public.deactivate_customer(uuid),
  public.add_customer_note(uuid,text), public.list_customers(text,boolean,text,public.customer_price_category,integer),
  public.get_customer_document_history(uuid), public.get_customer_possible_duplicates(text,text,text,text,uuid),
  public.customer_snapshot(uuid) from public, anon;
grant execute on function public.save_customer(uuid,jsonb), public.deactivate_customer(uuid),
  public.add_customer_note(uuid,text), public.list_customers(text,boolean,text,public.customer_price_category,integer),
  public.get_customer_document_history(uuid), public.get_customer_possible_duplicates(text,text,text,text,uuid),
  public.customer_snapshot(uuid) to authenticated;

select routine_name from information_schema.routines where routine_schema='public'
and routine_name in ('save_customer','deactivate_customer','list_customers',
  'get_customer_document_history','get_customer_possible_duplicates','customer_snapshot')
order by routine_name;
