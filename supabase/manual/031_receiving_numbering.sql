-- SOMA / FACOLUB receiving module - 031 concurrency-safe numbering
-- Depends on: 030_receiving_foundation.sql
-- Official numbers are allocated only by confirm_receipt in 033.

create table if not exists public.receipt_number_sequences (
  receipt_date date primary key,
  last_value bigint not null,
  constraint receipt_number_sequences_positive check (last_value > 0)
);

alter table public.receipt_number_sequences enable row level security;
revoke all on public.receipt_number_sequences from anon, authenticated;

create or replace function public.allocate_receipt_number(target_receipt_date date)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_value bigint;
begin
  if target_receipt_date is null then
    raise exception 'Receipt date is required for numbering' using errcode = '22023';
  end if;

  -- INSERT .. ON CONFLICT serializes callers on the date row. MAX()+1 is never used.
  insert into public.receipt_number_sequences (receipt_date, last_value)
  values (target_receipt_date, 1)
  on conflict (receipt_date) do update
    set last_value = public.receipt_number_sequences.last_value + 1
  returning last_value into next_value;

  -- The FACOLUB example is REC-071026-01 for 07/10/2026, hence DDMMYY.
  return format(
    'REC-%s-%s',
    to_char(target_receipt_date, 'DDMMYY'),
    lpad(next_value::text, 2, '0')
  );
end;
$$;

-- Number allocation is an internal confirmation primitive, never a browser RPC.
revoke all on function public.allocate_receipt_number(date) from public, anon, authenticated;

comment on table public.receipt_number_sequences is
  'Atomic daily counters for official receipt numbers; drafts do not consume values.';
comment on function public.allocate_receipt_number(date) is
  'Internal allocator producing REC-DDMMYY-NN according to the approved FACOLUB example.';

-- Verification query (read-only; does not consume a number):
select receipt_date, last_value
from public.receipt_number_sequences
order by receipt_date desc
limit 20;
