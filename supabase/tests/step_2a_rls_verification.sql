-- Run in a disposable/local Supabase database after the migration.
-- This file is a verification plan and intentionally does not create application users.

-- 1. Confirm RLS is enabled.
select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('profiles', 'environments', 'user_environment_access');

-- 2. Confirm no authenticated write grants exist.
select table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'authenticated'
  and table_schema = 'public'
order by table_name, privilege_type;

-- 3. In separate transactions, set request.jwt.claim.sub to UUIDs representing:
--    active admin, active management, active factory, inactive factory.
--    Verify own-profile reads, admin all-profile reads, assigned environment filtering,
--    inactive denial, and INSERT/UPDATE/DELETE failures for authenticated users.

-- Example harness fragment (replace the UUID and roll back):
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
select auth.uid(), public.current_app_role(), public.has_environment_access('FACOLUB');
select * from public.profiles;
select * from public.environments;
select * from public.user_environment_access;
rollback;
