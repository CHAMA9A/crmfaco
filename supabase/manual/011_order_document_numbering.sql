-- SOMA order document bundle - 011 atomic daily common-reference numbering
-- Run after 010_orders_architecture.sql.
-- Uses INSERT ... ON CONFLICT ... DO UPDATE, never MAX(...) + 1.

create table if not exists public.order_number_sequences (
  sequence_date date primary key,
  last_value bigint not null check (last_value > 0)
);

create or replace function public.allocate_order_reference(target_date date)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare next_value bigint;
begin
  if target_date is null then
    raise exception 'Order date is required' using errcode = '23502';
  end if;

  insert into public.order_number_sequences (sequence_date, last_value)
  values (target_date, 1)
  on conflict (sequence_date) do update
    set last_value = public.order_number_sequences.last_value + 1
  returning public.order_number_sequences.last_value into next_value;

  return to_char(target_date, 'YYMMDD') || '-' || lpad(next_value::text, 2, '0');
end;
$$;

comment on function public.allocate_order_reference(date) is
  'Internal atomic daily allocator. Values above 99 expand naturally and are never truncated.';

revoke all on public.order_number_sequences from public, anon, authenticated;
revoke all on function public.allocate_order_reference(date) from public, anon, authenticated;

-- Verification query (do not call the allocator merely to test it; that consumes a number):
select
  to_regclass('public.order_number_sequences') as sequence_table,
  to_regprocedure('public.allocate_order_reference(date)') as allocator,
  position('on conflict' in lower(pg_get_functiondef(
    'public.allocate_order_reference(date)'::regprocedure
  ))) > 0 as uses_atomic_upsert;
