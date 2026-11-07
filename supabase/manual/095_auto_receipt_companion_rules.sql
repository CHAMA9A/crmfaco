-- FACOLUB post-catalog patch - 095 atomic companion stock on receiving
-- Depends on 094 and existing Receiving 030-033.
-- Adds the confirmed Empty Bottle 25L -> Seal 25L ratio 1 rule.

create table if not exists public.stock_auto_receipt_rules (
  id uuid primary key default gen_random_uuid(),
  source_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  generated_stock_item_id uuid not null references public.stock_items(id) on delete restrict,
  ratio numeric(20,6) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_auto_receipt_rules_distinct_items check (
    source_stock_item_id <> generated_stock_item_id
  ),
  constraint stock_auto_receipt_rules_ratio_positive check (ratio > 0)
);

create unique index if not exists stock_auto_receipt_rules_active_pair_unique
  on public.stock_auto_receipt_rules (source_stock_item_id, generated_stock_item_id)
  where is_active;

drop trigger if exists stock_auto_receipt_rules_set_updated_at on public.stock_auto_receipt_rules;
create trigger stock_auto_receipt_rules_set_updated_at
before update on public.stock_auto_receipt_rules
for each row execute function public.set_updated_at();

create or replace function public.validate_stock_auto_receipt_rule()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare source_item public.stock_items;
declare generated_item public.stock_items;
begin
  select item.* into source_item from public.stock_items item
  where item.id = new.source_stock_item_id and item.is_active;
  select item.* into generated_item from public.stock_items item
  where item.id = new.generated_stock_item_id and item.is_active;
  if source_item.id is null or generated_item.id is null then
    raise exception 'Automatic receipt rules require active stock items.' using errcode = '23514';
  end if;
  if source_item.unit <> generated_item.unit then
    raise exception 'Companion receipt source/generated units must match.' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists stock_auto_receipt_rules_validate on public.stock_auto_receipt_rules;
create trigger stock_auto_receipt_rules_validate
before insert or update on public.stock_auto_receipt_rules
for each row execute function public.validate_stock_auto_receipt_rule();

-- Protect retries even if confirmation is called concurrently or a future
-- implementation re-enters companion generation.
create unique index if not exists stock_movements_auto_receipt_companion_unique
  on public.stock_movements (
    reference_id,
    (metadata ->> 'auto_receipt_rule_id'),
    (metadata ->> 'source_receipt_item_id')
  )
  where movement_type = 'receipt'::public.stock_movement_type
    and reference_type = 'receipt'
    and metadata ->> 'auto_generated' = 'true';

do $$
declare bottle_25l uuid := public.ensure_packaging_stock_item(
  'EMPTY-BOTTLE-25L', 'Empty Bottle 25L', 'empty_bottle'
);
declare seal_25l uuid := public.ensure_packaging_stock_item('SEAL-25L', 'Seal 25L', 'seal');
begin
  insert into public.stock_auto_receipt_rules (
    source_stock_item_id, generated_stock_item_id, ratio, is_active
  ) values (bottle_25l, seal_25l, 1, true)
  on conflict (source_stock_item_id, generated_stock_item_id) where is_active
  do update set ratio = excluded.ratio;
end
$$;

-- Same established signature. The receipt row lock preserves double-click
-- idempotency. Direct and generated movements share this PostgreSQL transaction.
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
  companion record;
  official_number text;
begin
  select receipt.* into target_receipt
  from public.receipts receipt
  where receipt.id = target_receipt_id
  for update;
  if not found then raise exception 'Receipt not found' using errcode = 'P0002'; end if;
  if actor_role = 'factory'::public.app_role and target_receipt.created_by <> actor_id then
    raise exception 'Factory users may confirm only their own receipt drafts' using errcode = '42501';
  end if;
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
  if not exists (select 1 from public.receipt_items item where item.receipt_id = target_receipt.id) then
    raise exception 'Receipt must contain at least one item' using errcode = '23514';
  end if;
  if exists (
    select 1 from public.receipt_items line_to_check
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

  for line in
    select receipt_line.* from public.receipt_items receipt_line
    where receipt_line.receipt_id = target_receipt.id
    order by receipt_line.stock_item_id, receipt_line.id
  loop
    perform public.record_stock_movement(
      line.stock_item_id, target_receipt.location_id,
      'receipt'::public.stock_movement_type, line.quantity,
      'in'::public.stock_direction, 'receipt', target_receipt.id,
      'Goods receipt ' || target_receipt.receipt_number,
      jsonb_build_object(
        'receipt_item_id', line.id,
        'receipt_number', target_receipt.receipt_number,
        'unit', line.unit,
        'auto_generated', false
      ), false
    );

    for companion in
      select rule.id as rule_id, rule.generated_stock_item_id, rule.ratio
      from public.stock_auto_receipt_rules rule
      where rule.source_stock_item_id = line.stock_item_id and rule.is_active
      order by rule.id
    loop
      perform public.record_stock_movement(
        companion.generated_stock_item_id, target_receipt.location_id,
        'receipt'::public.stock_movement_type, line.quantity * companion.ratio,
        'in'::public.stock_direction, 'receipt', target_receipt.id,
        'Automatic companion for ' || target_receipt.receipt_number,
        jsonb_build_object(
          'auto_generated', true,
          'auto_receipt_rule_id', companion.rule_id,
          'source_receipt_item_id', line.id,
          'source_stock_item_id', line.stock_item_id,
          'receipt_number', target_receipt.receipt_number,
          'receipt_reference', target_receipt.reference,
          'confirmed_by', actor_id,
          'ratio', companion.ratio
        ), false
      );
    end loop;
  end loop;

  return public.receipt_confirmation_payload(target_receipt.id);
end;
$$;

alter table public.stock_auto_receipt_rules enable row level security;
drop policy if exists stock_auto_receipt_rules_facolub_read on public.stock_auto_receipt_rules;
create policy stock_auto_receipt_rules_facolub_read on public.stock_auto_receipt_rules
for select to authenticated using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role)
);
revoke all on public.stock_auto_receipt_rules from public, anon, authenticated;
grant select on public.stock_auto_receipt_rules to authenticated;
revoke all on function public.validate_stock_auto_receipt_rule() from public, anon, authenticated;
revoke all on function public.confirm_receipt(uuid) from public, anon;
grant execute on function public.confirm_receipt(uuid) to authenticated;

select source.name as source_item, generated.name as generated_item, rule.ratio, rule.is_active
from public.stock_auto_receipt_rules rule
join public.stock_items source on source.id = rule.source_stock_item_id
join public.stock_items generated on generated.id = rule.generated_stock_item_id
where rule.is_active
order by source.name, generated.name;
