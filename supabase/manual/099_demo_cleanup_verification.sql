-- FACOLUB post-catalog patch - 099 safe demo cleanup and verification
-- Depends on 094-098. Clearly identified optional demo fixtures are hidden from
-- active configuration. Confirmed historical documents/movements are preserved.

begin;

-- Optional 035 fixtures: remove from active selectors without deleting ledger history.
update public.stock_reservations reservation
set status = 'cancelled'::public.stock_reservation_status,
    released_at = coalesce(reservation.released_at, now())
where reservation.status = 'active'::public.stock_reservation_status
  and reservation.reference_type like 'facolub_demo%';

update public.receipts receipt
set status = 'cancelled'::public.receipt_status
where receipt.status = 'draft'::public.receipt_status
  and receipt.reference like 'DEMO-%';

update public.stock_items item set is_active = false
where item.code like 'DEMO-%'
   or item.name like '[DEMO]%'
   or item.notes ilike '%demonstration FACOLUB%';

update public.suppliers supplier set is_active = false
where supplier.name like '[DEMO]%'
   or supplier.email like 'demo.%@example.com';

-- Optional 005 invoice fixture customer is excluded from new documents. Issued
-- test invoices remain immutable and auditable.
update public.customers customer set is_active = false
where customer.company_name like '[TEST]%'
   or customer.purchase_order_default like 'TEST-%';

commit;

-- Carton selection: expected 5 rows and every passed boolean true.
select
  bool_and(case
    when range.code = '4T' and format.code = '1L'
      then carton.code = 'CARTON-4T-1L' and resolved.bottles_per_carton = 24
    when range.code <> '4T' and format.code = '1L'
      then carton.code = 'CARTON-STD-1L' and resolved.bottles_per_carton = 24
    when range.code <> '4T' and format.code = '2L'
      then carton.code = 'CARTON-STD-2L' and resolved.bottles_per_carton = 12
    when range.code <> '4T' and format.code = '5L'
      then carton.code = 'CARTON-STD-5L' and resolved.bottles_per_carton = 4
    when format.code = '25L' then carton.id is null and resolved.bottles_per_carton is null
    else true end
  ) as carton_rules_pass,
  bool_and(case
    when range.code = '4T' then seal.code = 'SEAL-4T'
    when format.code = '25L' then seal.code = 'SEAL-25L'
    when format.code in ('1L','2L','5L') then seal.code = 'SEAL-STANDARD'
    else true end
  ) as seal_rules_pass
from public.product_formats product_format
join public.products product on product.id = product_format.product_id
join public.product_ranges range on range.id = product.product_range_id
join public.packaging_formats format on format.id = product_format.format_id
cross join lateral public.resolve_product_packaging_rule(product_format.id) resolved
left join public.stock_items carton on carton.id = resolved.carton_stock_item_id
join public.stock_items seal on seal.id = resolved.seal_stock_item_id
where product_format.official_catalog_number between 1 and 41;

-- 25L companion rule: expected exactly one row with ratio 1.
select source.code as source_code, generated.code as generated_code, rule.ratio, rule.is_active
from public.stock_auto_receipt_rules rule
join public.stock_items source on source.id = rule.source_stock_item_id
join public.stock_items generated on generated.id = rule.generated_stock_item_id
where source.code = 'EMPTY-BOTTLE-25L' and generated.code = 'SEAL-25L' and rule.is_active;

-- Every already-confirmed receipt movement remains unchanged. New automatic
-- movements must be paired 1:1 with their source receipt line quantity.
select movement.reference_id as receipt_id,
  movement.metadata ->> 'source_receipt_item_id' as source_receipt_item_id,
  movement.quantity as generated_quantity,
  line.quantity as source_quantity,
  movement.created_by = receipt.confirmed_by as same_confirming_user,
  movement.metadata ->> 'auto_generated' = 'true' as traceable_as_generated
from public.stock_movements movement
join public.receipt_items line
  on line.id::text = movement.metadata ->> 'source_receipt_item_id'
join public.receipts receipt on receipt.id = movement.reference_id
where movement.reference_type = 'receipt'
  and movement.metadata ->> 'auto_generated' = 'true'
order by movement.created_at desc;

-- Invoice semantics and configuration status. A null default is intentional
-- until SOMA confirms the percentage.
select settings.default_tax_rate,
  case when settings.default_tax_rate is null
    then 'Default TVA rate requires client confirmation.' else 'Configured' end as tax_status,
  count(*) filter (where invoice.status = 'issued' and invoice.tax_rate is null)
    as preserved_legacy_invoice_count
from public.invoice_tax_settings settings
cross join public.invoices invoice
where settings.singleton
group by settings.default_tax_rate;

-- Expected official catalog count remains 41. Active demo counts must be zero.
select
  (select count(*) from public.product_formats where official_catalog_number between 1 and 41)
    as official_sku_count,
  (select count(*) from public.stock_items
   where is_active and (code like 'DEMO-%' or name like '[DEMO]%')) as active_demo_stock_items,
  (select count(*) from public.suppliers
   where is_active and (name like '[DEMO]%' or email like 'demo.%@example.com'))
    as active_demo_suppliers,
  (select count(*) from public.customers
   where is_active and (company_name like '[TEST]%' or purchase_order_default like 'TEST-%'))
    as active_test_customers;

-- Inventory only: these rows are intentionally preserved historical records,
-- not cleanup failures. Review before any future archival decision.
select 'confirmed_demo_receipts_preserved' as classification, count(*) as record_count
from public.receipts where status = 'confirmed' and reference like 'DEMO-%'
union all
select 'demo_stock_movements_preserved', count(*)
from public.stock_movements
where reference_type = 'facolub_demo_seed' or metadata ->> 'demo' = 'true'
union all
select 'issued_test_invoices_preserved', count(*)
from public.invoices
where status = 'issued' and purchase_order like 'TEST-%';

do $$
begin
  if (select count(*) from public.product_formats
      where official_catalog_number between 1 and 41) <> 41 then
    raise exception 'Verification failed: official 41-SKU catalog changed.';
  end if;
  if exists (select 1 from public.stock_items
      where is_active and (code like 'DEMO-%' or name like '[DEMO]%')) then
    raise exception 'Verification failed: active demo stock remains.';
  end if;
  if (select count(*) from public.stock_auto_receipt_rules rule
      join public.stock_items source on source.id = rule.source_stock_item_id
      join public.stock_items generated on generated.id = rule.generated_stock_item_id
      where source.code = 'EMPTY-BOTTLE-25L' and generated.code = 'SEAL-25L'
        and rule.ratio = 1 and rule.is_active) <> 1 then
    raise exception 'Verification failed: 25L companion rule is missing or ambiguous.';
  end if;
  if to_regprocedure('public.invoice_authoritative_totals(uuid)') is null
    or not exists (select 1 from pg_trigger
      where tgrelid = 'public.invoices'::regclass
        and tgname = 'invoices_enforce_financials' and not tgisinternal)
    or not exists (select 1 from pg_trigger
      where tgrelid = 'public.invoices'::regclass
        and tgname = 'invoices_protect_final' and not tgisinternal) then
    raise exception 'Verification failed: authoritative or immutable invoice controls are missing.';
  end if;
  if not exists (select 1 from pg_indexes
      where schemaname = 'public'
        and indexname = 'stock_movements_auto_receipt_companion_unique') then
    raise exception 'Verification failed: companion receipt idempotency index is missing.';
  end if;
end
$$;

select 'POST-CATALOG PATCH VERIFIED' as result;
