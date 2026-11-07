-- SOMA FACOLUB customer CRM - 114 read-only/rollback verification
-- Run after 113. Requires active FACOLUB Admin, Management, Factory users.
-- All created test records are rolled back.

begin;
create temporary table customer_test_context(admin_id uuid, management_id uuid, factory_id uuid, customer_id uuid);
create temporary table customer_invoice_snapshot_test as
select i.id, i.customer_id, i.customer_name_snapshot
from public.invoices i where i.status = 'issued' limit 1;
insert into customer_test_context
select
 (select p.id from public.profiles p join public.user_environment_access a on a.user_id=p.id join public.environments e on e.id=a.environment_id where p.role='admin' and p.is_active and a.is_active and e.code='FACOLUB' limit 1),
 (select p.id from public.profiles p join public.user_environment_access a on a.user_id=p.id join public.environments e on e.id=a.environment_id where p.role='management' and p.is_active and a.is_active and e.code='FACOLUB' limit 1),
 (select p.id from public.profiles p join public.user_environment_access a on a.user_id=p.id join public.environments e on e.id=a.environment_id where p.role='factory' and p.is_active and a.is_active and e.code='FACOLUB' limit 1),
 null::uuid;

do $$ begin
  if exists(select 1 from customer_test_context where admin_id is null or management_id is null or factory_id is null)
  then raise exception 'Verification requires active FACOLUB Admin, Management and Factory users'; end if;
end $$;

select set_config('request.jwt.claim.sub',(select admin_id::text from customer_test_context),true);
update customer_test_context set customer_id = (public.save_customer(null,
  jsonb_build_object('company_name','[TEST] CRM CUSTOMER','ice','001234567890123',
    'phone','+212600000000','default_price_category','wholesale'))).id;
select public.save_customer((select customer_id from customer_test_context),
  jsonb_build_object('company_name','[TEST] CRM CUSTOMER UPDATED','ice','001234567890123','phone','+212600000000','default_price_category','wholesale'));

do $$ declare cid uuid := (select customer_id from customer_test_context); before_count bigint;
begin
  select count(*) into before_count from public.customers;
  if not exists(select 1 from public.get_customer_possible_duplicates(null,'001234567890123',null,null,cid) where 'ice'=any(matched_on))
  then
    -- Excluded row should yield none; create a second rollback-only candidate for duplicate check.
    perform public.save_customer(null,jsonb_build_object('company_name','[TEST] DUP','ice','001234567890123'));
    if not exists(select 1 from public.get_customer_possible_duplicates('[TEST] CRM CUSTOMER UPDATED','001234567890123',null,null,cid) where 'ice'=any(matched_on))
    then raise exception 'TEST FAILED: duplicate ICE detection'; end if;
  end if;
  if not exists(select 1 from public.get_customer_possible_duplicates('[TEST] CRM CUSTOMER UPDATED',null,null,null,null) where 'company_name'=any(matched_on))
  then raise exception 'TEST FAILED: duplicate company detection'; end if;
  if not exists(select 1 from public.list_customers('[TEST] CRM CUSTOMER UPDATED',null,null,null,20) where id=cid)
  then raise exception 'TEST FAILED: search by company'; end if;
  if not exists(select 1 from public.list_customers('001234567890123',null,null,null,20) where id=cid)
  then raise exception 'TEST FAILED: search by ICE'; end if;
  if not exists(select 1 from public.list_customers('+212600000000',null,null,null,20) where id=cid)
  then raise exception 'TEST FAILED: search by phone'; end if;
  perform public.deactivate_customer(cid);
  if not exists(select 1 from public.customers where id=cid and not is_active)
  then raise exception 'TEST FAILED: deactivation'; end if;
  if not exists(select 1 from public.list_customers(null,false,null,'wholesale',20) where id=cid and default_price_category='wholesale')
  then raise exception 'TEST FAILED: inactive customer/category preservation'; end if;
  begin
    perform public.create_order(cid, current_date, null, null, null,
      '[{"description":"ROLLBACK TEST","quantity":1}]'::jsonb);
    raise exception 'TEST FAILED: inactive customer selected for a new order';
  exception when no_data_found then null; end;

  -- If production has an issued invoice, prove its frozen identity survives a master edit.
  update public.customers set company_name = company_name || ' [ROLLBACK TEST]'
  where id = (select customer_id from customer_invoice_snapshot_test);
  if exists (
    select 1 from customer_invoice_snapshot_test snap
    join public.invoices current_invoice on current_invoice.id = snap.id
    where current_invoice.customer_name_snapshot is distinct from snap.customer_name_snapshot
  ) then raise exception 'TEST FAILED: issued invoice snapshot changed after customer edit'; end if;
end $$;

select set_config('request.jwt.claim.sub',(select management_id::text from customer_test_context),true);
select count(*) >= 1 as management_allowed from public.list_customers(null,null,null,null,10);

select set_config('request.jwt.claim.sub',(select factory_id::text from customer_test_context),true);
do $$ begin
  perform public.list_customers(null,null,null,null,10);
  raise exception 'TEST FAILED: Factory read CRM through trusted function';
exception when insufficient_privilege then null; end $$;

select
  (select count(*) from public.customers) as customers_preserved,
  (select count(*) from public.orders o left join public.customers c on c.id=o.customer_id where c.id is null) as broken_order_customer_refs,
  (select count(*) from public.invoices i left join public.customers c on c.id=i.customer_id where c.id is null) as broken_invoice_customer_refs,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='customers' and column_name='if_number') as legal_fields_exist,
  exists(select 1 from pg_indexes where schemaname='public' and indexname='customers_customer_code_unique') as customer_code_unique;

select
  count(*) filter (where unit_price_ht < 0) = 0 as custom_prices_are_non_negative_ht,
  count(*) filter (where currency !~ '^[A-Z]{3}$') = 0 as custom_price_currency_valid
from public.customer_product_prices;
rollback;
