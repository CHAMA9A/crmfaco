-- SOMA / FACOLUB receiving module - 032 RLS and private photo storage
-- Depends on: 030-031 and Supabase Storage.

create or replace function public.can_access_receipt(target_receipt_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  actor_role public.app_role;
begin
  if actor_id is null then return false; end if;

  select profile.role into actor_role
  from public.profiles profile
  join public.user_environment_access access
    on access.user_id = profile.id and access.is_active
  join public.environments environment
    on environment.id = access.environment_id and environment.is_active
  where profile.id = actor_id
    and profile.is_active
    and environment.code = 'FACOLUB';

  if actor_role is null or actor_role not in (
    'admin'::public.app_role,
    'management'::public.app_role,
    'factory'::public.app_role
  ) then return false; end if;

  return exists (
    select 1 from public.receipts receipt
    where receipt.id = target_receipt_id
      and (
        actor_role in ('admin'::public.app_role, 'management'::public.app_role)
        or receipt.created_by = actor_id
      )
  );
end;
$$;

create or replace function public.can_edit_receipt_draft(target_receipt_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  actor_role public.app_role;
begin
  if actor_id is null then return false; end if;

  select profile.role into actor_role
  from public.profiles profile
  join public.user_environment_access access
    on access.user_id = profile.id and access.is_active
  join public.environments environment
    on environment.id = access.environment_id and environment.is_active
  where profile.id = actor_id
    and profile.is_active
    and environment.code = 'FACOLUB';

  if actor_role is null or actor_role not in (
    'admin'::public.app_role,
    'management'::public.app_role,
    'factory'::public.app_role
  ) then return false; end if;

  return exists (
    select 1 from public.receipts receipt
    where receipt.id = target_receipt_id
      and receipt.status = 'draft'::public.receipt_status
      and (
        actor_role in ('admin'::public.app_role, 'management'::public.app_role)
        or receipt.created_by = actor_id
      )
  );
end;
$$;

create or replace function public.receipt_id_from_storage_path(target_path text)
returns uuid
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  first_segment text := split_part(coalesce(target_path, ''), '/', 1);
begin
  if first_segment !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' then
    return null;
  end if;
  return first_segment::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

drop policy if exists suppliers_facolub_read on public.suppliers;
create policy suppliers_facolub_read on public.suppliers
for select to authenticated
using (
  public.has_environment_access('FACOLUB')
  and public.current_app_role() in (
    'admin'::public.app_role, 'management'::public.app_role, 'factory'::public.app_role
  )
);

drop policy if exists receipts_facolub_read on public.receipts;
create policy receipts_facolub_read on public.receipts
for select to authenticated
using (public.can_access_receipt(id));

drop policy if exists receipt_items_facolub_read on public.receipt_items;
create policy receipt_items_facolub_read on public.receipt_items
for select to authenticated
using (public.can_access_receipt(receipt_id));

drop policy if exists receipt_attachments_facolub_read on public.receipt_attachments;
create policy receipt_attachments_facolub_read on public.receipt_attachments
for select to authenticated
using (public.can_access_receipt(receipt_id));

-- Browser clients receive read access only. Draft mutation and confirmation use
-- validated SECURITY DEFINER RPCs from 033; the stock ledger remains locked down.
revoke all on public.suppliers from anon, authenticated;
revoke all on public.receipts from anon, authenticated;
revoke all on public.receipt_items from anon, authenticated;
revoke all on public.receipt_attachments from anon, authenticated;

grant select on public.suppliers to authenticated;
grant select on public.receipts to authenticated;
grant select on public.receipt_items to authenticated;
grant select on public.receipt_attachments to authenticated;

-- Policy helper execution is required by PostgreSQL while evaluating RLS. The
-- helpers expose booleans/UUID parsing only and perform no mutation.
revoke all on function public.can_access_receipt(uuid) from public, anon;
revoke all on function public.can_edit_receipt_draft(uuid) from public, anon;
revoke all on function public.receipt_id_from_storage_path(text) from public, anon;
grant execute on function public.can_access_receipt(uuid) to authenticated;
grant execute on function public.can_edit_receipt_draft(uuid) to authenticated;
grant execute on function public.receipt_id_from_storage_path(text) to authenticated;

do $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise exception 'Supabase Storage is unavailable; enable Storage before running 032';
  end if;
end
$$;

-- Private 8 MiB image bucket. Re-running this file also corrects an accidentally
-- public bucket without deleting existing objects.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'facolub-receipts',
  'facolub-receipts',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Object names must start with the receipt UUID:
--   <receipt-id>/<random-id>-<sanitized-file-name>
-- Signed URLs may be generated by authenticated clients after the SELECT policy
-- succeeds. No permanent public URLs are used.
drop policy if exists facolub_receipt_photos_select on storage.objects;
create policy facolub_receipt_photos_select on storage.objects
for select to authenticated
using (
  bucket_id = 'facolub-receipts'
  and public.can_access_receipt(public.receipt_id_from_storage_path(name))
);

drop policy if exists facolub_receipt_photos_insert on storage.objects;
create policy facolub_receipt_photos_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'facolub-receipts'
  and public.can_edit_receipt_draft(public.receipt_id_from_storage_path(name))
);

drop policy if exists facolub_receipt_photos_update on storage.objects;
create policy facolub_receipt_photos_update on storage.objects
for update to authenticated
using (
  bucket_id = 'facolub-receipts'
  and public.can_edit_receipt_draft(public.receipt_id_from_storage_path(name))
  and not exists (
    select 1 from public.receipt_attachments attachment
    where attachment.storage_path = name
  )
)
with check (
  bucket_id = 'facolub-receipts'
  and public.can_edit_receipt_draft(public.receipt_id_from_storage_path(name))
);

drop policy if exists facolub_receipt_photos_delete on storage.objects;
create policy facolub_receipt_photos_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'facolub-receipts'
  and public.can_edit_receipt_draft(public.receipt_id_from_storage_path(name))
  and not exists (
    select 1 from public.receipt_attachments attachment
    where attachment.storage_path = name
  )
);

comment on function public.receipt_id_from_storage_path(text) is
  'Safely extracts the receipt UUID from the first private Storage path segment.';

-- Verification query:
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id = 'facolub-receipts';
