# Atlas Passport

Real-world travel activation game by Relevant Artist. Users collect stamped check-ins across city corridors within a 72-hour window.

## Stack

- Next.js 14.2 App Router, TypeScript strict
- Supabase (Postgres + Auth + Storage + Realtime)
- Resend + React Email
- Tailwind CSS (dark atlas theme — black/gold palette)
- Vercel (hosting + cron)

## Commands

```bash
npm run dev       # local dev server
npm run build     # production build
npm run lint      # ESLint
npx tsc --noEmit  # type check
```

## Project Structure

```
src/
  app/            # Next.js App Router pages and API routes
    admin/        # Admin panel (server components, requireAdmin guard)
    api/          # API routes
      admin/      # Admin CRUD (corridors, nodes, check-ins)
      checkins/   # Check-in submit + approve/reject
      cron/       # timer-warning (runs hourly via Vercel cron)
      passport/   # activate, status
      upload/     # signed upload URL generation
    auth/         # login page + callback route
    corridors/    # corridor browse + detail
    nodes/        # node detail + check-in page
    passport/     # dashboard, activate, complete
  components/     # UI components
  lib/            # supabase clients, email, auth helpers
  types/          # database.ts — all DB types with Relationships
emails/           # React Email templates
supabase/
  migrations/     # SQL migrations (run in order)
```

## Environment Variables

Exactly 7 variables are required. No others are read by the codebase.

```bash
# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
SUPABASE_SERVICE_ROLE_KEY=<service role key>   # server-only, never NEXT_PUBLIC_

# Resend
RESEND_API_KEY=re_<key>                        # server-only
RESEND_FROM_EMAIL=kaelo@<verified-domain>      # server-only

# App
NEXT_PUBLIC_APP_URL=https://atlas-passport.vercel.app

# Cron
CRON_SECRET=<openssl rand -hex 32>             # server-only
```

`ADMIN_EMAILS` and `RESEND_FROM_NAME` are **not used** — do not set them.

## Key Architecture Rules

- `createAdminClient()` (service role) — server routes and server components only
- `createClient()` (anon + session) — all user-facing data access, respects RLS
- Admin Server Components call both middleware AND `requireAdmin()` in-component
- All email sends are non-blocking (`.catch(console.error)`)
- `safeNext()` in auth callback validates `?next=` — no open redirects

## Database Migrations

Apply in order via Supabase SQL Editor or CLI:

1. `supabase/migrations/001_initial_schema.sql` — all tables, RLS, trigger
2. `supabase/migrations/002_storage_and_realtime.sql` — storage policies
3. `supabase/migrations/003_profile_referral_code.sql` — adds `referral_code` column

## Deployment Checklist

1. Set all 7 env vars in Vercel → Settings → Environment Variables → Production
2. Add `https://atlas-passport.vercel.app/auth/callback` to Supabase → Auth → Redirect URLs
3. Set Supabase Site URL to `https://atlas-passport.vercel.app`
4. Run migration 003 if not yet applied
5. Confirm `check-in-proofs` storage bucket exists (private)
6. Verify Resend domain DNS (SPF + DKIM green)
7. Create first admin: `UPDATE profiles SET is_admin = true WHERE email = 'your@email.com'`
8. Smoke test: sign up → magic link → activate passport → check in → admin approve → reward unlock
