-- SOMA invoice module - 008 read-only role/RLS verification
-- Selects one active FACOLUB user for each role automatically.
-- No real user UUID is stored in this file.
-- Safe to run: yes. Production data is read-only; temporary results are rolled back.
-- Idempotent: yes.
-- Depends on: 001 through 007 and at least one active FACOLUB user per role.

begin;

create temporary table invoice_role_verification_results (
  tested_role text not null,
  tested_user_id uuid not null,
  visible_invoice_count bigint not null
) on commit drop;

grant insert on table pg_temp.invoice_role_verification_results to authenticated;

-- pg_temp is a session alias and cannot be used directly in GRANT ON SCHEMA.
-- Resolve the physical temporary schema name for this SQL Editor session.
do $$
declare
  temporary_schema_name text;
begin
  select namespace.nspname into temporary_schema_name
  from pg_namespace namespace
  where namespace.oid = pg_my_temp_schema();

  execute format('grant usage on schema %I to authenticated', temporary_schema_name);
end $$;

-- Preflight: fail clearly if any required test role is unavailable.
do $$
declare
  missing_role public.app_role;
begin
  select required.role into missing_role
  from unnest(enum_range(null::public.app_role)) required(role)
  where not exists (
    select 1
    from public.profiles profile
    join public.user_environment_access access on access.user_id = profile.id
    join public.environments environment on environment.id = access.environment_id
    where profile.role = required.role
      and profile.is_active
      and access.is_active
      and environment.is_active
      and environment.code = 'FACOLUB'
  )
  limit 1;

  if missing_role is not null then
    raise exception 'No active FACOLUB user exists for role %', missing_role;
  end if;
end $$;

-- ADMIN: expected visible_invoice_count = 1.
select set_config(
  'request.jwt.claim.sub',
  (
    select profile.id::text
    from public.profiles profile
    join public.user_environment_access access on access.user_id = profile.id
    join public.environments environment on environment.id = access.environment_id
    where profile.role = 'admin'::public.app_role
      and profile.is_active and access.is_active and environment.is_active
      and environment.code = 'FACOLUB'
    order by profile.id
    limit 1
  ),
  true
);
set local role authenticated;
insert into pg_temp.invoice_role_verification_results
select 'admin', auth.uid(), count(*)
from public.invoices
where purchase_order = 'TEST-INVOICE-VALIDATION-2026-09-23';
reset role;

-- MANAGEMENT: expected visible_invoice_count = 1.
select set_config(
  'request.jwt.claim.sub',
  (
    select profile.id::text
    from public.profiles profile
    join public.user_environment_access access on access.user_id = profile.id
    join public.environments environment on environment.id = access.environment_id
    where profile.role = 'management'::public.app_role
      and profile.is_active and access.is_active and environment.is_active
      and environment.code = 'FACOLUB'
    order by profile.id
    limit 1
  ),
  true
);
set local role authenticated;
insert into pg_temp.invoice_role_verification_results
select 'management', auth.uid(), count(*)
from public.invoices
where purchase_order = 'TEST-INVOICE-VALIDATION-2026-09-23';
reset role;

-- FACTORY: expected visible_invoice_count = 0.
select set_config(
  'request.jwt.claim.sub',
  (
    select profile.id::text
    from public.profiles profile
    join public.user_environment_access access on access.user_id = profile.id
    join public.environments environment on environment.id = access.environment_id
    where profile.role = 'factory'::public.app_role
      and profile.is_active and access.is_active and environment.is_active
      and environment.code = 'FACOLUB'
    order by profile.id
    limit 1
  ),
  true
);
set local role authenticated;
insert into pg_temp.invoice_role_verification_results
select 'factory', auth.uid(), count(*)
from public.invoices
where purchase_order = 'TEST-INVOICE-VALIDATION-2026-09-23';
reset role;

-- Single verification grid: expected admin=1, management=1, factory=0.
select
  tested_role,
  tested_user_id,
  visible_invoice_count
from pg_temp.invoice_role_verification_results
order by case tested_role
  when 'admin' then 1
  when 'management' then 2
  when 'factory' then 3
end;

rollback;


