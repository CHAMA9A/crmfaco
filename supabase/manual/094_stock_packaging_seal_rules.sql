-- FACOLUB post-catalog patch - 094 configurable carton and seal rules
-- Depends on applied 090-093 and the existing Stock/Planning schema.
-- Additive/idempotent. Creates configuration stock references only; no quantities.

do $$
begin
  if to_regclass('public.product_ranges') is null
    or to_regclass('public.product_formats') is null
    or to_regclass('public.stock_items') is null then
    raise exception 'Applied FACOLUB catalog migrations 090-093 are required.';
  end if;
end
$$;

create or replace function public.ensure_packaging_stock_item(
  target_code text,
  target_name text,
  target_category public.stock_item_category
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result public.stock_items;
declare normalized_code text := upper(trim(target_code));
begin
  select item.* into result from public.stock_items item
  where item.code = normalized_code
     or lower(trim(item.name)) = lower(trim(target_name))
  order by case when item.code = normalized_code then 0 else 1 end
  limit 1;

  if found then
    if result.category <> target_category or result.unit <> 'piece'::public.stock_unit then
      raise exception 'Existing stock reference % has incompatible category/unit.', target_name;
    end if;
    if result.code is null then
      update public.stock_items set code = normalized_code, is_active = true
      where id = result.id returning * into result;
    elsif result.code <> normalized_code and exists (
      select 1 from public.stock_items item where item.code = normalized_code
    ) then
      raise exception 'Stock code % conflicts with existing reference %.', normalized_code, result.code;
    else
      update public.stock_items set is_active = true where id = result.id returning * into result;
    end if;
    return result.id;
  end if;

  insert into public.stock_items (
    code, name, category, unit, product_format_id, is_active, minimum_stock, notes
  ) values (
    normalized_code, trim(target_name), target_category, 'piece'::public.stock_unit,
    null, true, null, 'FACOLUB configurable packaging reference - no opening balance'
  ) returning id into result.id;
  return result.id;
end;
$$;

create table if not exists public.product_packaging_rules (
  id uuid primary key default gen_random_uuid(),
  product_range_id uuid references public.product_ranges(id) on delete restrict,
  product_id uuid references public.products(id) on delete restrict,
  format_id uuid not null references public.packaging_formats(id) on delete restrict,
  carton_stock_item_id uuid references public.stock_items(id) on delete restrict,
  seal_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  bottles_per_carton integer,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_packaging_rules_scope check (
    not (product_range_id is not null and product_id is not null)
  ),
  constraint product_packaging_rules_carton_consistency check (
    (carton_stock_item_id is null and bottles_per_carton is null)
    or (carton_stock_item_id is not null and bottles_per_carton > 0)
  )
);

create unique index if not exists product_packaging_rules_default_unique
  on public.product_packaging_rules (format_id)
  where product_range_id is null and product_id is null and is_active;
create unique index if not exists product_packaging_rules_range_unique
  on public.product_packaging_rules (product_range_id, format_id)
  where product_range_id is not null and product_id is null and is_active;
create unique index if not exists product_packaging_rules_product_unique
  on public.product_packaging_rules (product_id, format_id)
  where product_id is not null and is_active;

drop trigger if exists product_packaging_rules_set_updated_at on public.product_packaging_rules;
create trigger product_packaging_rules_set_updated_at
before update on public.product_packaging_rules
for each row execute function public.set_updated_at();

create or replace function public.validate_product_packaging_rule()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare carton public.stock_items;
declare seal public.stock_items;
begin
  if new.product_id is not null and not exists (
    select 1 from public.products product
    where product.id = new.product_id
      and (new.product_range_id is null or product.product_range_id = new.product_range_id)
  ) then
    raise exception 'Packaging product scope is invalid.' using errcode = '23514';
  end if;
  select item.* into seal from public.stock_items item where item.id = new.seal_stock_item_id;
  if seal.id is null or seal.category <> 'seal'::public.stock_item_category
    or seal.unit <> 'piece'::public.stock_unit then
    raise exception 'Seal rule requires a seal stock item in pieces.' using errcode = '23514';
  end if;
  if new.carton_stock_item_id is not null then
    select item.* into carton from public.stock_items item where item.id = new.carton_stock_item_id;
    if carton.id is null or carton.category <> 'carton'::public.stock_item_category
      or carton.unit <> 'piece'::public.stock_unit then
      raise exception 'Carton rule requires a carton stock item in pieces.' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists product_packaging_rules_validate on public.product_packaging_rules;
create trigger product_packaging_rules_validate
before insert or update on public.product_packaging_rules
for each row execute function public.validate_product_packaging_rule();

create or replace function public.resolve_product_packaging_rule(target_product_format_id uuid)
returns table (
  rule_id uuid,
  carton_stock_item_id uuid,
  seal_stock_item_id uuid,
  bottles_per_carton integer,
  scope text
) language sql stable security definer set search_path = '' as $$
  select rule.id, rule.carton_stock_item_id, rule.seal_stock_item_id,
    rule.bottles_per_carton,
    case when rule.product_id is not null then 'product'
         when rule.product_range_id is not null then 'range'
         else 'format' end
  from public.product_formats product_format
  join public.products product on product.id = product_format.product_id
  join public.product_packaging_rules rule
    on rule.format_id = product_format.format_id
   and rule.is_active
   and (rule.product_id is null or rule.product_id = product.id)
   and (rule.product_range_id is null or rule.product_range_id = product.product_range_id)
  where product_format.id = target_product_format_id
  order by case when rule.product_id is not null then 1
                when rule.product_range_id is not null then 2 else 3 end
  limit 1
$$;

do $$
declare carton_1l uuid := public.ensure_packaging_stock_item('CARTON-STD-1L', 'Carton Standard 1L', 'carton');
declare carton_2l uuid := public.ensure_packaging_stock_item('CARTON-STD-2L', 'Carton Standard 2L', 'carton');
declare carton_5l uuid := public.ensure_packaging_stock_item('CARTON-STD-5L', 'Carton Standard 5L', 'carton');
declare carton_4t uuid := public.ensure_packaging_stock_item('CARTON-4T-1L', 'Carton 4T 1L', 'carton');
declare seal_standard uuid := public.ensure_packaging_stock_item('SEAL-STANDARD', 'Seal Standard', 'seal');
declare seal_4t uuid := public.ensure_packaging_stock_item('SEAL-4T', 'Seal 4T', 'seal');
declare seal_25l uuid := public.ensure_packaging_stock_item('SEAL-25L', 'Seal 25L', 'seal');
declare format_1l uuid;
declare format_2l uuid;
declare format_5l uuid;
declare format_25l uuid;
declare range_4t uuid;
begin
  select id into strict format_1l from public.packaging_formats where code = '1L';
  select id into strict format_2l from public.packaging_formats where code = '2L';
  select id into strict format_5l from public.packaging_formats where code = '5L';
  select id into strict format_25l from public.packaging_formats where code = '25L';
  select id into strict range_4t from public.product_ranges where code = '4T';

  insert into public.product_packaging_rules
    (format_id, carton_stock_item_id, seal_stock_item_id, bottles_per_carton)
  values
    (format_1l, carton_1l, seal_standard, 24),
    (format_2l, carton_2l, seal_standard, 12),
    (format_5l, carton_5l, seal_standard, 4),
    (format_25l, null, seal_25l, null)
  on conflict (format_id) where product_range_id is null and product_id is null and is_active
  do update set carton_stock_item_id = excluded.carton_stock_item_id,
    seal_stock_item_id = excluded.seal_stock_item_id,
    bottles_per_carton = excluded.bottles_per_carton;

  insert into public.product_packaging_rules
    (product_range_id, format_id, carton_stock_item_id, seal_stock_item_id, bottles_per_carton)
  values (range_4t, format_1l, carton_4t, seal_4t, 24)
  on conflict (product_range_id, format_id)
    where product_range_id is not null and product_id is null and is_active
  do update set carton_stock_item_id = excluded.carton_stock_item_id,
    seal_stock_item_id = excluded.seal_stock_item_id,
    bottles_per_carton = excluded.bottles_per_carton;
end
$$;

alter table public.product_packaging_rules enable row level security;
drop policy if exists product_packaging_rules_facolub_read on public.product_packaging_rules;
create policy product_packaging_rules_facolub_read on public.product_packaging_rules
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role)
);
revoke all on public.product_packaging_rules from public, anon, authenticated;
grant select on public.product_packaging_rules to authenticated;
revoke all on function public.ensure_packaging_stock_item(text,text,public.stock_item_category) from public, anon, authenticated;
revoke all on function public.validate_product_packaging_rule() from public, anon, authenticated;
revoke all on function public.resolve_product_packaging_rule(uuid) from public, anon;
grant execute on function public.resolve_product_packaging_rule(uuid) to authenticated;

comment on table public.product_packaging_rules is
  'Prospective carton/seal selection with product override, then range override, then format default.';

select range.code as range, product.name as product, format.code as format,
  product_format.sku, resolved.scope, carton.name as carton, seal.name as seal,
  resolved.bottles_per_carton
from public.product_formats product_format
join public.products product on product.id = product_format.product_id
join public.product_ranges range on range.id = product.product_range_id
join public.packaging_formats format on format.id = product_format.format_id
cross join lateral public.resolve_product_packaging_rule(product_format.id) resolved
left join public.stock_items carton on carton.id = resolved.carton_stock_item_id
join public.stock_items seal on seal.id = resolved.seal_stock_item_id
where product_format.official_catalog_number between 1 and 41
order by product_format.official_catalog_number;
