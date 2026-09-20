-- STEP 2A only: identity, roles, environment access, and RLS.
-- No stock, production, reservation, pricing, or costing data is introduced here.

create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.app_role as enum ('admin', 'management', 'factory');
exception
  when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 120),
  username text unique,
  role public.app_role not null default 'factory',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (
    username is null or (
      username = lower(trim(username)) and
      username ~ '^[a-z0-9._-]{3,50}$'
    )
  )
);

create table if not exists public.environments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code = upper(trim(code)) and code ~ '^[A-Z0-9_-]{2,40}$'),
  name text not null check (char_length(trim(name)) between 1 and 120),
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_environment_access (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  environment_id uuid not null references public.environments(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, environment_id)
);

create index if not exists user_environment_access_user_idx
  on public.user_environment_access (user_id) where is_active;
create index if not exists user_environment_access_environment_idx
  on public.user_environment_access (environment_id) where is_active;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.normalize_profile_username()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.display_name = trim(new.display_name);
  new.username = nullif(lower(trim(new.username)), '');
  return new;
end;
$$;

drop trigger if exists profiles_normalize_username on public.profiles;
create trigger profiles_normalize_username
before insert or update of display_name, username on public.profiles
for each row execute function public.normalize_profile_username();

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
drop trigger if exists environments_set_updated_at on public.environments;
create trigger environments_set_updated_at before update on public.environments
for each row execute function public.set_updated_at();
drop trigger if exists user_environment_access_set_updated_at on public.user_environment_access;
create trigger user_environment_access_set_updated_at before update on public.user_environment_access
for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  inferred_name text;
begin
  inferred_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'FACOLUB User'
  );

  insert into public.profiles (id, display_name, role, is_active)
  values (new.id, inferred_name, 'factory'::public.app_role, true)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- Backfill Auth users that predate this migration. Role metadata is not trusted.
insert into public.profiles (id, display_name, role, is_active)
select
  user_record.id,
  coalesce(
    nullif(trim(user_record.raw_user_meta_data ->> 'display_name'), ''),
    nullif(split_part(coalesce(user_record.email, ''), '@', 1), ''),
    'FACOLUB User'
  ),
  'factory'::public.app_role,
  true
from auth.users user_record
on conflict (id) do nothing;

create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p
  where p.id = auth.uid() and p.is_active
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_app_role() = 'admin'::public.app_role, false)
$$;

create or replace function public.has_environment_access(environment_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_environment_access access
    join public.environments environment on environment.id = access.environment_id
    join public.profiles profile on profile.id = access.user_id
    where access.user_id = auth.uid()
      and access.is_active
      and environment.is_active
      and environment.code = upper(trim(environment_code))
      and profile.is_active
  )
$$;

revoke all on function public.current_app_role() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.has_environment_access(text) from public, anon;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.has_environment_access(text) to authenticated;

alter table public.profiles enable row level security;
alter table public.environments enable row level security;
alter table public.user_environment_access enable row level security;

drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin on public.profiles
for select to authenticated
using (id = auth.uid() or public.is_admin());

drop policy if exists environments_select_assigned on public.environments;
create policy environments_select_assigned on public.environments
for select to authenticated
using (is_active and public.has_environment_access(code));

drop policy if exists environment_access_select_own_or_admin on public.user_environment_access;
create policy environment_access_select_own_or_admin on public.user_environment_access
for select to authenticated
using ((user_id = auth.uid() and is_active) or public.is_admin());

revoke all on public.profiles from anon;
revoke all on public.environments from anon;
revoke all on public.user_environment_access from anon;
revoke insert, update, delete on public.profiles from authenticated;
revoke insert, update, delete on public.environments from authenticated;
revoke insert, update, delete on public.user_environment_access from authenticated;
grant select on public.profiles to authenticated;
grant select on public.environments to authenticated;
grant select on public.user_environment_access to authenticated;

insert into public.environments (code, name, description, is_active)
values ('FACOLUB', 'FACOLUB', 'Production, stock and internal operations', true)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  is_active = true;

comment on table public.profiles is 'Application identities and authoritative roles; role metadata from auth.users is intentionally ignored.';
comment on table public.environments is 'SOMA operational environments available for explicit assignment.';
comment on table public.user_environment_access is 'Explicit user-to-environment access grants.';
