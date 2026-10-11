-- SOMA / FACOLUB stock counts - 083 RLS, API grants, and private evidence storage
-- Depends on: 080-082 and Supabase Storage.

create or replace function public.can_access_stock_count(target_count_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
declare actor_role public.app_role;
begin
  if actor_id is null then return false; end if;
  select profile.role into actor_role from public.profiles profile
  join public.user_environment_access access on access.user_id = profile.id and access.is_active
  join public.environments environment on environment.id = access.environment_id
    and environment.is_active and environment.code = 'FACOLUB'
  where profile.id = actor_id and profile.is_active;
  return actor_role in ('admin','management') or exists (
    select 1 from public.stock_counts count
    where count.id = target_count_id and count.created_by = actor_id
  );
end;
$$;

create or replace function public.can_edit_stock_count(target_count_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
declare actor_role public.app_role;
begin
  if actor_id is null then return false; end if;
  select profile.role into actor_role from public.profiles profile
  join public.user_environment_access access on access.user_id = profile.id and access.is_active
  join public.environments environment on environment.id = access.environment_id
    and environment.is_active and environment.code = 'FACOLUB'
  where profile.id = actor_id and profile.is_active;
  return exists (select 1 from public.stock_counts count
    where count.id = target_count_id and count.status = 'draft'
      and (actor_role in ('admin','management') or count.created_by = actor_id));
end;
$$;

create or replace function public.can_access_stock_adjustment(target_adjustment_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
declare actor_role public.app_role;
begin
  if actor_id is null then return false; end if;
  select profile.role into actor_role from public.profiles profile
  join public.user_environment_access access on access.user_id = profile.id and access.is_active
  join public.environments environment on environment.id = access.environment_id
    and environment.is_active and environment.code = 'FACOLUB'
  where profile.id = actor_id and profile.is_active;
  return actor_role in ('admin','management') or exists (
    select 1 from public.stock_adjustments adjustment
    where adjustment.id = target_adjustment_id and adjustment.requested_by = actor_id
  );
end;
$$;

create or replace function public.can_edit_stock_adjustment(target_adjustment_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
declare actor_role public.app_role;
begin
  if actor_id is null then return false; end if;
  select profile.role into actor_role from public.profiles profile
  join public.user_environment_access access on access.user_id = profile.id and access.is_active
  join public.environments environment on environment.id = access.environment_id
    and environment.is_active and environment.code = 'FACOLUB'
  where profile.id = actor_id and profile.is_active;
  return exists (select 1 from public.stock_adjustments adjustment
    where adjustment.id = target_adjustment_id and adjustment.status = 'pending'
      and (actor_role in ('admin','management') or adjustment.requested_by = actor_id));
end;
$$;

create or replace function public.stock_evidence_id_from_path(target_path text)
returns uuid language plpgsql immutable security invoker set search_path = '' as $$
declare segment text := split_part(coalesce(target_path, ''), '/', 3);
begin
  if segment !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' then
    return null;
  end if;
  return segment::uuid;
exception when invalid_text_representation then return null;
end;
$$;

alter table public.stock_counts enable row level security;
alter table public.stock_count_items enable row level security;
alter table public.stock_count_number_sequences enable row level security;
alter table public.stock_count_attachments enable row level security;
alter table public.stock_adjustments enable row level security;
alter table public.stock_adjustment_attachments enable row level security;

drop policy if exists stock_counts_facolub_read on public.stock_counts;
create policy stock_counts_facolub_read on public.stock_counts
for select to authenticated using (public.can_access_stock_count(id));
drop policy if exists stock_count_items_facolub_read on public.stock_count_items;
create policy stock_count_items_facolub_read on public.stock_count_items
for select to authenticated using (public.can_access_stock_count(stock_count_id));
drop policy if exists stock_count_attachments_facolub_read on public.stock_count_attachments;
create policy stock_count_attachments_facolub_read on public.stock_count_attachments
for select to authenticated using (public.can_access_stock_count(stock_count_id));

-- Replace the broad S1 adjustment policy: Factory sees only its own requests.
drop policy if exists stock_adjustments_facolub_read on public.stock_adjustments;
create policy stock_adjustments_facolub_read on public.stock_adjustments
for select to authenticated using (public.can_access_stock_adjustment(id));
drop policy if exists stock_adjustment_attachments_facolub_read
  on public.stock_adjustment_attachments;
create policy stock_adjustment_attachments_facolub_read on public.stock_adjustment_attachments
for select to authenticated using (public.can_access_stock_adjustment(stock_adjustment_id));

-- No sequence visibility and no direct mutation policies.
revoke all on public.stock_counts from anon, authenticated;
revoke all on public.stock_count_items from anon, authenticated;
revoke all on public.stock_count_number_sequences from anon, authenticated;
revoke all on public.stock_count_attachments from anon, authenticated;
revoke all on public.stock_adjustments from anon, authenticated;
revoke all on public.stock_adjustment_attachments from anon, authenticated;
grant select on public.stock_counts to authenticated;
grant select on public.stock_count_items to authenticated;
grant select on public.stock_count_attachments to authenticated;
grant select on public.stock_adjustments to authenticated;
grant select on public.stock_adjustment_attachments to authenticated;

revoke all on function public.can_access_stock_count(uuid) from public, anon;
revoke all on function public.can_edit_stock_count(uuid) from public, anon;
revoke all on function public.can_access_stock_adjustment(uuid) from public, anon;
revoke all on function public.can_edit_stock_adjustment(uuid) from public, anon;
revoke all on function public.stock_evidence_id_from_path(text) from public, anon;
grant execute on function public.can_access_stock_count(uuid) to authenticated;
grant execute on function public.can_edit_stock_count(uuid) to authenticated;
grant execute on function public.can_access_stock_adjustment(uuid) to authenticated;
grant execute on function public.can_edit_stock_adjustment(uuid) to authenticated;
grant execute on function public.stock_evidence_id_from_path(text) to authenticated;

-- Public RPC entry points. Each function performs its own auth, role, ownership,
-- lifecycle, and quantity checks before any SECURITY DEFINER write.
grant execute on function public.create_stock_count_draft(uuid,date,text) to authenticated;
grant execute on function public.add_stock_count_item(uuid,uuid,integer) to authenticated;
grant execute on function public.update_counted_quantity(uuid,numeric,text) to authenticated;
grant execute on function public.initialize_stock_count(uuid,public.stock_item_category,uuid[])
  to authenticated;
grant execute on function public.submit_stock_count(uuid) to authenticated;
grant execute on function public.approve_stock_count(uuid) to authenticated;
grant execute on function public.reject_stock_count(uuid,text) to authenticated;
grant execute on function public.cancel_stock_count(uuid) to authenticated;
grant execute on function public.report_stock_loss(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.report_stock_damage(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.request_other_stock_adjustment(uuid,uuid,numeric,text)
  to authenticated;
grant execute on function public.request_stock_correction(uuid,numeric,text) to authenticated;
grant execute on function public.approve_stock_adjustment(uuid) to authenticated;
grant execute on function public.reject_stock_adjustment(uuid,text) to authenticated;
grant execute on function public.attach_stock_count_evidence(uuid,uuid,text,text,text,bigint)
  to authenticated;
grant execute on function public.attach_stock_adjustment_evidence(uuid,text,text,text,bigint)
  to authenticated;
grant execute on function public.get_stock_count(uuid) to authenticated;
grant execute on function public.list_stock_counts(date,date,public.stock_count_status,uuid,uuid,integer)
  to authenticated;
grant execute on function public.list_stock_adjustments(date,date,public.stock_adjustment_status,public.stock_adjustment_type,uuid,integer)
  to authenticated;

revoke all on function public.create_stock_count_draft(uuid,date,text) from public, anon;
revoke all on function public.add_stock_count_item(uuid,uuid,integer) from public, anon;
revoke all on function public.update_counted_quantity(uuid,numeric,text) from public, anon;
revoke all on function public.initialize_stock_count(uuid,public.stock_item_category,uuid[])
  from public, anon;
revoke all on function public.submit_stock_count(uuid) from public, anon;
revoke all on function public.approve_stock_count(uuid) from public, anon;
revoke all on function public.reject_stock_count(uuid,text) from public, anon;
revoke all on function public.cancel_stock_count(uuid) from public, anon;
revoke all on function public.report_stock_loss(uuid,uuid,numeric,text) from public, anon;
revoke all on function public.report_stock_damage(uuid,uuid,numeric,text) from public, anon;
revoke all on function public.request_other_stock_adjustment(uuid,uuid,numeric,text)
  from public, anon;
revoke all on function public.request_stock_correction(uuid,numeric,text) from public, anon;
revoke all on function public.approve_stock_adjustment(uuid) from public, anon;
revoke all on function public.reject_stock_adjustment(uuid,text) from public, anon;
revoke all on function public.attach_stock_count_evidence(uuid,uuid,text,text,text,bigint)
  from public, anon;
revoke all on function public.attach_stock_adjustment_evidence(uuid,text,text,text,bigint)
  from public, anon;
revoke all on function public.get_stock_count(uuid) from public, anon;
revoke all on function public.list_stock_counts(date,date,public.stock_count_status,uuid,uuid,integer)
  from public, anon;
revoke all on function public.list_stock_adjustments(date,date,public.stock_adjustment_status,public.stock_adjustment_type,uuid,integer)
  from public, anon;

do $$ begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise exception 'Supabase Storage is unavailable; enable Storage before running 083';
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('facolub-stock-evidence','facolub-stock-evidence',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf']::text[])
on conflict (id) do update set public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Paths: <actor-id>/counts/<count-id>/<random-name>
--     or <actor-id>/adjustments/<adjustment-id>/<random-name>
drop policy if exists facolub_stock_evidence_select on storage.objects;
create policy facolub_stock_evidence_select on storage.objects for select to authenticated using (
  bucket_id = 'facolub-stock-evidence' and (
    (split_part(name,'/',2) = 'counts'
      and public.can_access_stock_count(public.stock_evidence_id_from_path(name)))
    or (split_part(name,'/',2) = 'adjustments'
      and public.can_access_stock_adjustment(public.stock_evidence_id_from_path(name)))
  )
);
drop policy if exists facolub_stock_evidence_insert on storage.objects;
create policy facolub_stock_evidence_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'facolub-stock-evidence' and split_part(name,'/',1) = auth.uid()::text and (
    (split_part(name,'/',2) = 'counts'
      and public.can_edit_stock_count(public.stock_evidence_id_from_path(name)))
    or (split_part(name,'/',2) = 'adjustments'
      and public.can_edit_stock_adjustment(public.stock_evidence_id_from_path(name)))
  )
);
drop policy if exists facolub_stock_evidence_delete on storage.objects;
create policy facolub_stock_evidence_delete on storage.objects for delete to authenticated using (
  bucket_id = 'facolub-stock-evidence' and split_part(name,'/',1) = auth.uid()::text and (
    (split_part(name,'/',2) = 'counts'
      and public.can_edit_stock_count(public.stock_evidence_id_from_path(name)))
    or (split_part(name,'/',2) = 'adjustments'
      and public.can_edit_stock_adjustment(public.stock_evidence_id_from_path(name)))
  ) and not exists (
    select 1 from public.stock_count_attachments attachment where attachment.storage_path = name
    union all
    select 1 from public.stock_adjustment_attachments attachment where attachment.storage_path = name
  )
);

select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets where id = 'facolub-stock-evidence';
