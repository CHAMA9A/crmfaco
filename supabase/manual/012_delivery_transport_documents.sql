-- SOMA order document bundle - 012 delivery and transport document records
-- Run after 011_order_document_numbering.sql.
-- Lines are intentionally not duplicated: BL/BT render immutable order_items.

create table if not exists public.delivery_notes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id),
  delivery_note_number text unique,
  delivery_date date,
  prepared_for text,
  object text not null default 'acheminement de marchandises',
  handover_date date,
  transport_reception_name text,
  status public.document_status not null default 'draft',
  issued_by uuid references public.profiles(id),
  issued_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint delivery_note_number_format check (
    delivery_note_number is null or delivery_note_number ~ '^BL-[0-9]{6}-[0-9]{2,}$'
  ),
  constraint delivery_note_issue_state check (
    (status = 'issued' and issued_by is not null and issued_at is not null)
    or status <> 'issued'
  )
);

create table if not exists public.transport_notes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id),
  transport_note_number text unique,
  transport_date date,
  transport_person text,
  sender text not null default 'SOMA LUBRIFIANTS',
  pickup_date date,
  loading_location text not null default 'CASABLANCA',
  destination text,
  vehicle_registration text,
  status public.document_status not null default 'draft',
  issued_by uuid references public.profiles(id),
  issued_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transport_note_number_format check (
    transport_note_number is null or transport_note_number ~ '^BT-[0-9]{6}-[0-9]{2,}$'
  ),
  constraint transport_note_issue_state check (
    (status = 'issued' and issued_by is not null and issued_at is not null)
    or status <> 'issued'
  )
);

create index if not exists delivery_notes_status_date_idx
  on public.delivery_notes (status, delivery_date desc);
create index if not exists transport_notes_status_date_idx
  on public.transport_notes (status, transport_date desc);

drop trigger if exists delivery_notes_set_updated_at on public.delivery_notes;
create trigger delivery_notes_set_updated_at before update on public.delivery_notes
for each row execute function public.set_updated_at();

drop trigger if exists transport_notes_set_updated_at on public.transport_notes;
create trigger transport_notes_set_updated_at before update on public.transport_notes
for each row execute function public.set_updated_at();

create or replace function public.protect_final_document()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if old.status <> 'draft' and (
    to_jsonb(new) - array['status', 'cancelled_at', 'updated_at']
    is distinct from
    to_jsonb(old) - array['status', 'cancelled_at', 'updated_at']
  ) then
    raise exception 'Issued/cancelled document data is immutable' using errcode = '23514';
  end if;
  if old.status = 'cancelled' and new.status <> 'cancelled' then
    raise exception 'Cancelled documents cannot be restored' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists delivery_notes_protect_final on public.delivery_notes;
create trigger delivery_notes_protect_final before update on public.delivery_notes
for each row execute function public.protect_final_document();

drop trigger if exists transport_notes_protect_final on public.transport_notes;
create trigger transport_notes_protect_final before update on public.transport_notes
for each row execute function public.protect_final_document();

comment on table public.delivery_notes is
  'One BL header per order; line descriptions and quantities come from immutable order_items.';
comment on table public.transport_notes is
  'One BT header per order; future dispatch/loading entities can become the line source without changing this header.';

-- Verification query:
select
  to_regclass('public.delivery_notes') as delivery_notes_table,
  to_regclass('public.transport_notes') as transport_notes_table,
  (select count(*) from public.delivery_notes) as delivery_note_count,
  (select count(*) from public.transport_notes) as transport_note_count;
