# SOMA Lubrifiants — FACOLUB

Internal FACOLUB management system built with TanStack Start, React, TypeScript, Tailwind CSS, Nitro/Cloudflare, and Supabase.

Step 2A provides email/password authentication, profiles, authoritative database roles, environment assignment, server-rendered route protection, and row-level security. Operational modules remain placeholders; no stock, reservation, production, pricing, or costing engine is implemented.

## Development

Requirements: Bun and a Supabase project (or the Supabase CLI for a local stack).

```sh
bun install
copy .env.example .env.local
bun run dev
```

Only public Supabase configuration belongs in `.env.local`:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

Every `VITE_` value is embedded into browser-accessible code. Never add a database password, JWT secret, or Supabase `service_role` key. The app intentionally uses the signed-in user's JWT and RLS for all database reads.

## Supabase setup

1. Create or select a Supabase project.
2. Disable public sign-up in Authentication settings. Accounts are created by an authorized administrator in the Supabase dashboard.
3. Apply [`supabase/migrations/202609200001_step_2a_auth_foundation.sql`](supabase/migrations/202609200001_step_2a_auth_foundation.sql), either through the SQL editor or the CLI:

   ```sh
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

4. Copy the project URL and public publishable key into `.env.local`.
5. Add the deployed application URL to the Supabase Auth URL configuration. The current password-only flow does not expose an OAuth callback route.

The migration creates only:

- `profiles` with `admin`, `management`, and `factory` roles;
- `environments`, seeded with active `FACOLUB`;
- `user_environment_access` memberships;
- conservative SELECT-only RLS for application clients;
- a new-user trigger that always defaults to `factory` and ignores role claims in user metadata.

Profile, role, activation, and environment-assignment writes are deliberately unavailable to signed-in browser clients. Perform them through the Supabase dashboard or a tightly controlled administrative process.

## First users and bootstrap

Create each Auth user in the Supabase dashboard first. Copy its UUID, then run UUID-based SQL. Do not identify bootstrap users by assumed email addresses.

First administrator:

```sql
update public.profiles
set display_name = 'YOUR ADMIN NAME', username = 'your.admin', role = 'admin', is_active = true
where id = 'ADMIN_AUTH_USER_UUID';

insert into public.user_environment_access (user_id, environment_id, is_active)
select 'ADMIN_AUTH_USER_UUID', id, true
from public.environments
where code = 'FACOLUB'
on conflict (user_id, environment_id)
do update set is_active = excluded.is_active;
```

Management bootstrap example for Abdelhadi Farid:

```sql
update public.profiles
set display_name = 'Abdelhadi Farid', username = 'abdelhadi.farid', role = 'management', is_active = true
where id = 'ABDELHADI_AUTH_USER_UUID';

insert into public.user_environment_access (user_id, environment_id, is_active)
select 'ABDELHADI_AUTH_USER_UUID', id, true
from public.environments
where code = 'FACOLUB'
on conflict (user_id, environment_id)
do update set is_active = excluded.is_active;
```

New Auth users receive an active `factory` profile but no environment assignment. This fail-closed default prevents entry into FACOLUB until membership is explicitly granted.

## Authorization matrix

| Role       | FACOLUB access                                                             |
| ---------- | -------------------------------------------------------------------------- |
| Admin      | All current routes, including Users and Settings                           |
| Management | Home and business placeholder routes; not Users or Settings                |
| Factory    | Today, Stock, Receiving, Planning, Production, Dispatch, History, Problems |

All roles also require an active profile and an active FACOLUB membership. `/facolub` redirects Factory users to `/facolub/today`. Navigation visibility follows the same centralized matrix, but the server route guard and RLS remain authoritative.

## Verification

```sh
bun run lint
bun run typecheck
bun run test:unit
bun run build
bun run test:smoke
bun run test
bun audit
```

The smoke test runs the built Cloudflare worker with no credentials and confirms that public login renders while protected pages redirect before content is returned. Run [`supabase/tests/step_2a_rls_verification.sql`](supabase/tests/step_2a_rls_verification.sql) against a disposable database, then exercise the role matrix with dedicated Admin, Management, Factory, inactive, and unassigned test users.

The production preview command uses the generated Nitro/Cloudflare artifact:

```sh
bun run preview
```

## Security notes

- SSR session refreshes are cookie-backed through `@supabase/ssr`; server authorization validates the user with `supabase.auth.getUser()`.
- Identity-dependent responses use `Cache-Control: private, no-store` and vary by cookie/authorization to prevent shared-cache session leakage.
- The CSP allows connections only to the app origin plus the configured Supabase HTTP and WebSocket origins.
- CSRF checks remain enabled for TanStack Start server functions.
- Login errors avoid account enumeration; inactive accounts receive a deliberate support message.
- The Admin Users page is read-only and omits email because `auth.users` is not exposed with a service-role key.
- `.env` files, Supabase temporary state, Wrangler state, and generated output are ignored.

The Supabase CLI is not bundled with the application. If it is unavailable locally, apply and verify the migration through the Supabase dashboard before accepting the deployment.
