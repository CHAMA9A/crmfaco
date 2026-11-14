-- SOMA / FACOLUB S8 dispatch - 120 private photos, RLS and grants
-- Run after 119_dispatch_functions.sql.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('facolub-dispatch','facolub-dispatch',false,8388608,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists dispatch_management_read on public.dispatches;
create policy dispatch_management_read on public.dispatches for select to authenticated using (
  public.has_environment_access('FACOLUB') and public.current_app_role() in ('admin','management')
);
drop policy if exists dispatch_factory_operational_read on public.dispatches;
create policy dispatch_factory_operational_read on public.dispatches for select to authenticated using (
  public.has_environment_access('FACOLUB') and public.current_app_role()='factory'
);
drop policy if exists dispatch_items_operational_read on public.dispatch_items;
create policy dispatch_items_operational_read on public.dispatch_items for select to authenticated using (
  public.has_environment_access('FACOLUB') and public.current_app_role() in ('admin','management','factory')
  and exists(select 1 from public.dispatches d where d.id=dispatch_id)
);
drop policy if exists dispatch_attachments_operational_read on public.dispatch_attachments;
create policy dispatch_attachments_operational_read on public.dispatch_attachments for select to authenticated using (
  public.has_environment_access('FACOLUB') and public.current_app_role() in ('admin','management','factory')
  and exists(select 1 from public.dispatches d where d.id=dispatch_id)
);
drop policy if exists dispatch_corrections_management_read on public.dispatch_corrections;
create policy dispatch_corrections_management_read on public.dispatch_corrections for select to authenticated using (
  public.has_environment_access('FACOLUB') and public.current_app_role() in ('admin','management')
);
grant select on public.dispatches,public.dispatch_items,public.dispatch_attachments,public.dispatch_corrections to authenticated;

drop policy if exists dispatch_storage_insert on storage.objects;
create policy dispatch_storage_insert on storage.objects for insert to authenticated with check (
  bucket_id='facolub-dispatch' and public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin','management','factory')
  and exists(select 1 from public.dispatches d where d.id=(storage.foldername(name))[1]::uuid
    and d.status='draft' and (d.created_by=auth.uid() or public.current_app_role() in ('admin','management')))
);
drop policy if exists dispatch_storage_select on storage.objects;
create policy dispatch_storage_select on storage.objects for select to authenticated using (
  bucket_id='facolub-dispatch' and public.has_environment_access('FACOLUB')
  and public.current_app_role() in ('admin','management','factory')
  and exists(select 1 from public.dispatches d where d.id=(storage.foldername(name))[1]::uuid)
);
drop policy if exists dispatch_storage_delete_draft on storage.objects;
create policy dispatch_storage_delete_draft on storage.objects for delete to authenticated using (
  bucket_id='facolub-dispatch' and public.has_environment_access('FACOLUB')
  and exists(select 1 from public.dispatches d where d.id=(storage.foldername(name))[1]::uuid
    and d.status='draft' and (d.created_by=auth.uid() or public.current_app_role() in ('admin','management')))
);

revoke insert,update,delete on public.dispatches,public.dispatch_items,
  public.dispatch_attachments,public.dispatch_corrections from authenticated;

select id,public,file_size_limit,allowed_mime_types from storage.buckets where id='facolub-dispatch';
