-- SOMA invoice module - 009 atomic draft invoice creation
-- Run in Supabase SQL Editor after 001 through 008.
-- Safe to run once: yes.
-- Idempotent: yes. CREATE OR REPLACE keeps the same function signature.
-- Depends on: invoice tables from 001, authoritative total trigger from 002,
-- and FACOLUB authorization helpers used by 004.
-- The browser supplies descriptions, quantities, and unit prices only.
-- It cannot supply invoice totals, line totals, statuses, or invoice numbers.

create or replace function public.create_invoice_draft(
  target_customer_id uuid,
  target_invoice_date date,
  target_purchase_order text,
  target_items jsonb
)
returns public.invoices
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_customer public.customers;
  created_invoice public.invoices;
  item_record record;
  item_description text;
  item_quantity numeric(18, 3);
  item_unit_price numeric(18, 2);
begin
  if auth.uid() is null
    or not public.has_environment_access('FACOLUB')
    or public.current_app_role() not in (
      'admin'::public.app_role,
      'management'::public.app_role
    )
  then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  if target_customer_id is null or target_invoice_date is null then
    raise exception 'Customer and invoice date are required' using errcode = '23502';
  end if;

  select customer.* into target_customer
  from public.customers customer
  where customer.id = target_customer_id
    and customer.is_active;

  if not found then
    raise exception 'Active customer not found' using errcode = 'P0002';
  end if;

  if target_items is null
    or jsonb_typeof(target_items) <> 'array'
    or jsonb_array_length(target_items) = 0
  then
    raise exception 'An invoice must contain at least one line' using errcode = '23514';
  end if;

  if jsonb_array_length(target_items) > 100 then
    raise exception 'An invoice cannot contain more than 100 lines' using errcode = '23514';
  end if;

  insert into public.invoices (
    invoice_date,
    customer_id,
    purchase_order,
    customer_name_snapshot,
    customer_city_snapshot,
    customer_address_snapshot,
    customer_ice_snapshot,
    status,
    currency,
    created_by
  )
  values (
    target_invoice_date,
    target_customer.id,
    nullif(trim(target_purchase_order), ''),
    target_customer.company_name,
    target_customer.city,
    target_customer.address,
    target_customer.ice,
    'draft'::public.invoice_status,
    'MAD',
    auth.uid()
  )
  returning * into created_invoice;

  for item_record in
    select item.value, item.ordinality
    from jsonb_array_elements(target_items) with ordinality as item(value, ordinality)
  loop
    if jsonb_typeof(item_record.value) <> 'object' then
      raise exception 'Every invoice line must be an object' using errcode = '22023';
    end if;

    item_description := trim(item_record.value ->> 'description');

    begin
      item_quantity := (item_record.value ->> 'quantity')::numeric(18, 3);
      item_unit_price := (item_record.value ->> 'unit_price')::numeric(18, 2);
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid quantity or unit price on line %', item_record.ordinality
          using errcode = '22023';
    end;

    if item_description is null or item_description = '' then
      raise exception 'Description is required on line %', item_record.ordinality
        using errcode = '23514';
    end if;
    if item_quantity is null or item_quantity <= 0 then
      raise exception 'Quantity must be greater than zero on line %', item_record.ordinality
        using errcode = '23514';
    end if;
    if item_unit_price is null or item_unit_price < 0 then
      raise exception 'Unit price cannot be negative on line %', item_record.ordinality
        using errcode = '23514';
    end if;

    insert into public.invoice_items (
      invoice_id,
      description,
      quantity,
      unit_price,
      position
    )
    values (
      created_invoice.id,
      item_description,
      item_quantity,
      item_unit_price,
      item_record.ordinality::integer
    );
  end loop;

  select invoice.* into created_invoice
  from public.invoices invoice
  where invoice.id = created_invoice.id;

  return created_invoice;
end;
$$;

comment on function public.create_invoice_draft(uuid, date, text, jsonb) is
  'Atomically creates a draft invoice and its lines from an active customer; totals remain database-authoritative.';

revoke all on function public.create_invoice_draft(uuid, date, text, jsonb)
  from public, anon;
grant execute on function public.create_invoice_draft(uuid, date, text, jsonb)
  to authenticated;

-- Verification query (expected: function exists, security_definer=true,
-- authenticated_can_execute=true, anon_can_execute=false):
select
  to_regprocedure('public.create_invoice_draft(uuid,date,text,jsonb)') as create_function,
  procedure.prosecdef as security_definer,
  has_function_privilege(
    'authenticated',
    'public.create_invoice_draft(uuid,date,text,jsonb)',
    'EXECUTE'
  ) as authenticated_can_execute,
  has_function_privilege(
    'anon',
    'public.create_invoice_draft(uuid,date,text,jsonb)',
    'EXECUTE'
  ) as anon_can_execute
from pg_proc procedure
where procedure.oid = 'public.create_invoice_draft(uuid,date,text,jsonb)'::regprocedure;
