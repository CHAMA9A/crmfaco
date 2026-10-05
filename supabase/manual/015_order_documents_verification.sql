-- SOMA order document bundle - 015 rollback-only behavioral/security verification
-- Run only after 010-014 succeed. This script commits no test data and consumes no numbers.
-- Requires at least one active FACOLUB Admin, Management, Factory, and active customer.

begin;

create temporary table order_bundle_test_context (
  admin_id uuid,
  management_id uuid,
  factory_id uuid,
  customer_id uuid,
  legacy_invoices_before jsonb
) on commit drop;

insert into order_bundle_test_context
select
  (select p.id from public.profiles p join public.user_environment_access a on a.user_id = p.id
   join public.environments e on e.id = a.environment_id
   where p.role = 'admin' and p.is_active and a.is_active and e.is_active and e.code = 'FACOLUB' limit 1),
  (select p.id from public.profiles p join public.user_environment_access a on a.user_id = p.id
   join public.environments e on e.id = a.environment_id
   where p.role = 'management' and p.is_active and a.is_active and e.is_active and e.code = 'FACOLUB' limit 1),
  (select p.id from public.profiles p join public.user_environment_access a on a.user_id = p.id
   join public.environments e on e.id = a.environment_id
   where p.role = 'factory' and p.is_active and a.is_active and e.is_active and e.code = 'FACOLUB' limit 1),
  (select c.id from public.customers c where c.is_active order by c.created_at limit 1),
  (select coalesce(jsonb_agg(to_jsonb(i) order by i.id), '[]'::jsonb)
   from public.invoices i where i.order_id is null);

create temporary table order_bundle_test_ids (
  order_id uuid, invoice_id uuid, delivery_note_id uuid, transport_note_id uuid,
  reference_one text, reference_two text
) on commit drop;
insert into order_bundle_test_ids default values;

grant select, update on pg_temp.order_bundle_test_context, pg_temp.order_bundle_test_ids to authenticated;
do $$
declare temporary_schema_name text;
begin
  select nspname into temporary_schema_name from pg_namespace where oid = pg_my_temp_schema();
  execute format('grant usage on schema %I to authenticated', temporary_schema_name);
end $$;

-- Abort with a useful message instead of producing misleading partial results.
do $$
begin
  if exists (
    select 1 from order_bundle_test_context
    where admin_id is null or management_id is null or factory_id is null or customer_id is null
  ) then
    raise exception 'Verification needs active FACOLUB Admin/Management/Factory users and an active customer';
  end if;
end $$;

select set_config('request.jwt.claim.sub', (select management_id::text from order_bundle_test_context), true);
set local role authenticated;

update order_bundle_test_ids set order_id = (
  select (public.create_order(
    (select customer_id from order_bundle_test_context), date '2026-09-25',
    '[TEST-ROLLBACK] ORDER BUNDLE', 'CASABLANCA', 'TEST ADDRESS',
    '[{"description":"[TEST] PRODUCT A","quantity":10},{"description":"[TEST] PRODUCT B","quantity":5.5}]'::jsonb
  )).id
);

-- quantity > 0 must fail at the trusted mutation boundary.
do $$
begin
  perform public.update_draft_order(
    (select order_id from order_bundle_test_ids),
    (select customer_id from order_bundle_test_context), date '2026-09-25',
    '[TEST-ROLLBACK] ORDER BUNDLE', 'CASABLANCA', 'TEST ADDRESS',
    '[{"description":"INVALID","quantity":0}]'::jsonb
  );
  raise exception 'TEST FAILED: zero quantity was accepted';
exception when check_violation then null;
end $$;

-- Confirmation allocates the common reference and transactionally creates all three documents.
select public.confirm_order((select order_id from order_bundle_test_ids));
update order_bundle_test_ids ids set
  invoice_id = i.id, delivery_note_id = d.id, transport_note_id = t.id,
  reference_one = o.order_reference
from public.orders o
join public.invoices i on i.order_id = o.id
join public.delivery_notes d on d.order_id = o.id
join public.transport_notes t on t.order_id = o.id
where o.id = ids.order_id;

-- Calling both actions again proves bundle/confirmation idempotency.
select public.prepare_document_bundle((select order_id from order_bundle_test_ids));
select public.confirm_order((select order_id from order_bundle_test_ids));

-- Allocate a second rolled-back order to verify unique, incrementing daily references.
update order_bundle_test_ids set reference_two = (
  select (public.confirm_order((public.create_order(
    (select customer_id from order_bundle_test_context), date '2026-09-25',
    '[TEST-ROLLBACK] SECOND ORDER', 'CASABLANCA', 'TEST ADDRESS',
    '[{"description":"[TEST] PRODUCT C","quantity":1}]'::jsonb
  )).id)).order_reference
);

-- Prices remain invoice-specific and do not alter order quantities.
select public.update_invoice_prices(
  (select invoice_id from order_bundle_test_ids),
  (select jsonb_agg(jsonb_build_object('order_item_id', ii.order_item_id, 'unit_price',
    case when ii.position = 1 then 12.50 else 20.00 end) order by ii.position)
   from public.invoice_items ii where ii.invoice_id = (select invoice_id from order_bundle_test_ids))
);

select public.update_delivery_note(
  (select delivery_note_id from order_bundle_test_ids), date '2026-09-25',
  'TEST RECIPIENT', 'acheminement de marchandises', date '2026-09-25', 'TEST RECEPTION'
);
select public.update_transport_note(
  (select transport_note_id from order_bundle_test_ids), date '2026-09-25',
  'TEST DRIVER', 'SOMA LUBRIFIANTS', date '2026-09-25', 'CASABLANCA',
  'TEST DESTINATION', 'TEST-123'
);
select public.issue_invoice((select invoice_id from order_bundle_test_ids));
select public.issue_delivery_note((select delivery_note_id from order_bundle_test_ids));
select public.issue_transport_note((select transport_note_id from order_bundle_test_ids));

-- Management can see the order through RLS.
do $$ begin
  if not exists (select 1 from public.orders where id = (select order_id from order_bundle_test_ids)) then
    raise exception 'TEST FAILED: Management cannot read order';
  end if;
end $$;

reset role;

-- Database triggers, not UI state, enforce historical immutability.
do $$
begin
  update public.order_items set quantity = quantity + 1
  where order_id = (select order_id from order_bundle_test_ids);
  raise exception 'TEST FAILED: issued order item was mutable';
exception when check_violation then null;
end $$;

-- Factory sees none of the commercial bundle tables.
select set_config('request.jwt.claim.sub', (select factory_id::text from order_bundle_test_context), true);
set local role authenticated;
do $$ begin
  if exists (select 1 from public.orders)
    or exists (select 1 from public.order_items)
    or exists (select 1 from public.invoices)
    or exists (select 1 from public.invoice_items)
    or exists (select 1 from public.delivery_notes)
    or exists (select 1 from public.transport_notes) then
    raise exception 'TEST FAILED: Factory can read commercial documents';
  end if;
end $$;
reset role;

-- Admin is also allowed.
select set_config('request.jwt.claim.sub', (select admin_id::text from order_bundle_test_context), true);
set local role authenticated;
do $$ begin
  if not exists (select 1 from public.orders where id = (select order_id from order_bundle_test_ids)) then
    raise exception 'TEST FAILED: Admin cannot read order';
  end if;
end $$;
reset role;

-- Consolidated assertions: 1:1 records, idempotency, snapshots, totals, numbering, legacy safety.
do $$
declare ids order_bundle_test_ids; order_quantity numeric; invoice_quantity numeric;
begin
  select * into ids from order_bundle_test_ids;
  if (select count(*) from public.invoices where order_id = ids.order_id) <> 1
    or (select count(*) from public.delivery_notes where order_id = ids.order_id) <> 1
    or (select count(*) from public.transport_notes where order_id = ids.order_id) <> 1 then
    raise exception 'TEST FAILED: bundle is not one-to-one/idempotent';
  end if;
  if (select count(*) from public.invoice_items where invoice_id = ids.invoice_id) <> 2 then
    raise exception 'TEST FAILED: invoice lines were not copied from order items';
  end if;
  select sum(quantity) into order_quantity from public.order_items where order_id = ids.order_id;
  select sum(quantity) into invoice_quantity from public.invoice_items where invoice_id = ids.invoice_id;
  if order_quantity is distinct from invoice_quantity then
    raise exception 'TEST FAILED: invoice quantities differ from order quantities';
  end if;
  if ids.reference_one = ids.reference_two or ids.reference_one !~ '^[0-9]{6}-[0-9]{2,}$' then
    raise exception 'TEST FAILED: daily references are invalid or duplicated';
  end if;
  if (select status from public.orders where id = ids.order_id) <> 'completed' then
    raise exception 'TEST FAILED: fully issued bundle is not completed';
  end if;
  if (select legacy_invoices_before from order_bundle_test_context) is distinct from
     (select coalesce(jsonb_agg(to_jsonb(i) order by i.id), '[]'::jsonb)
      from public.invoices i where i.order_id is null) then
    raise exception 'TEST FAILED: a legacy invoice changed';
  end if;
end $$;

select
  'PASS (transaction will roll back)' as result,
  ids.reference_one as first_reference,
  ids.reference_two as second_reference,
  (select total from public.invoices where id = ids.invoice_id) as authoritative_total,
  (select count(*) from public.order_items where order_id = ids.order_id) as bl_bt_source_line_count
from order_bundle_test_ids ids;

rollback;

-- Concurrency note: the allocator uses a PK-conflicting UPSERT, so PostgreSQL serializes
-- same-day increments. A true simultaneous-session smoke test belongs in the app test phase.
