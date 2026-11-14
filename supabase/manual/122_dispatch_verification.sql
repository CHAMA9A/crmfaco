-- SOMA / FACOLUB S8 dispatch - 122 read-only verification
-- Run after 121_dispatch_document_integration.sql. Changes no data.

do $$ declare failures text[]:=array[]::text[]; begin
  if to_regclass('public.dispatches') is null or to_regclass('public.dispatch_items') is null then failures:=array_append(failures,'dispatch tables missing'); end if;
  if to_regprocedure('public.confirm_dispatch(uuid)') is null then failures:=array_append(failures,'confirm_dispatch missing'); end if;
  if to_regprocedure('public.allocate_shipping_document_reference(date)') is null then failures:=array_append(failures,'shipping document allocator missing'); end if;
  if not exists(select 1 from pg_trigger where tgrelid='public.stock_movements'::regclass and tgname='stock_movements_immutable' and not tgisinternal) then failures:=array_append(failures,'immutable stock ledger trigger missing'); end if;
  if not exists(select 1 from pg_indexes where schemaname='public' and indexname='stock_movements_dispatch_item_unique_idx') then failures:=array_append(failures,'dispatch movement idempotency index missing'); end if;
  if exists(select 1 from public.dispatch_items i join public.stock_items s on s.id=i.stock_item_id where s.category<>'finished_product' or s.unit<>'piece') then failures:=array_append(failures,'dispatch targets non-finished stock'); end if;
  if exists(select 1 from public.dispatches d join public.dispatch_items i on i.dispatch_id=d.id where d.status='confirmed'
    and not exists(select 1 from public.stock_movements m where m.movement_type='dispatch' and m.metadata->>'dispatch_item_id'=i.id::text)) then failures:=array_append(failures,'confirmed line lacks stock OUT'); end if;
  if exists(select 1 from public.dispatches d where d.status='confirmed' and (not exists(select 1 from public.dispatch_attachments a where a.dispatch_id=d.id and a.category='goods') or not exists(select 1 from public.dispatch_attachments a where a.dispatch_id=d.id and a.category in('vehicle','registration')))) then failures:=array_append(failures,'confirmed dispatch lacks photos'); end if;
  if exists(select 1 from public.order_items oi where (select coalesce(sum(di.quantity_loaded),0) from public.dispatch_items di join public.dispatches d on d.id=di.dispatch_id where di.order_item_id=oi.id and d.status='confirmed')>oi.quantity) then failures:=array_append(failures,'order over-dispatched'); end if;
  if exists(select 1 from public.delivery_note_items x join public.dispatch_items di on di.id=x.dispatch_item_id where x.quantity is distinct from di.quantity_loaded) then failures:=array_append(failures,'BL quantity differs'); end if;
  if exists(select 1 from public.transport_note_items x join public.dispatch_items di on di.id=x.dispatch_item_id where x.quantity is distinct from di.quantity_loaded) then failures:=array_append(failures,'BT quantity differs'); end if;
  if cardinality(failures)>0 then raise exception 'S8 verification failed: %',array_to_string(failures,'; '); end if;
end $$;

select (select count(*) from public.dispatches) dispatches,
  (select count(*) from public.dispatches where status='confirmed') confirmed,
  (select count(*) from public.stock_movements where movement_type='dispatch') dispatch_movements,
  (select count(*) from public.delivery_notes where dispatch_id is not null) dispatch_delivery_notes,
  (select count(*) from public.transport_notes where dispatch_id is not null) dispatch_transport_notes,
  (select count(*) from public.dispatches d where d.status='confirmed' and not exists(select 1 from public.stock_movements m where m.reference_id=d.id and m.reference_type='dispatch')) confirmed_without_movement;
