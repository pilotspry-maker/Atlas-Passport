# Atlas Passport — Operating Manual for Claude

> **Last updated:** 2026-06-25 — incorporates findings from the June 22–25 dependency + RLS audits.
> **Active security branch:** `fix/005-rls-exploit-patches` ([PR #18](https://github.com/pilotspry-maker/Atlas-Passport/pull/18))
> **Status:** PR #18 is the working branch. Do not branch off `main` until #18 is merged.

Real-world travel activation game by Relevant Artist. Users collect stamped check-ins across city corridors within a 72-hour window.

---

## 1. Stack

- **Next.js** App Router, TypeScript strict
  - Currently `14.2.35`. **Pending upgrade to `^15.5.19`** (P1 from audit — RCE + auth-bypass CVEs).
- **Supabase** (Postgres + Auth + RLS + Storage + Realtime). Production project ref: `gaavynmmysdhovpatzlp`.
- **Resend + React Email** (transactional). All sends are non-blocking (`.catch(console.error)`).
- **Tailwind CSS** — dark atlas theme (black / gold palette).
- **Vercel** — hosting + cron (production = `main`, previews per PR).
- **Vercel Analytics** installed (PR #19 merged).

---

## 2. Commands

```bash
npm run dev          # local dev server
npm run build        # production build
npm run lint         # ESLint
npx tsc --noEmit     # type check
npm run email        # email dev server (react-email)
npm audit --omit=dev # production-only vuln scan
```

---

## 3. Project Structure

```
src/
  app/
    admin/              # Admin panel — server components, requireAdmin guard
    api/
      admin/            # Admin CRUD (corridors, nodes, check-ins)
      checkins/         # Check-in submit + approve/reject
      cron/             # timer-warning — hourly via Vercel cron, EXCLUDED from middleware
      passport/         # activate, status
      upload/           # signed upload URL generation
    auth/               # login + callback
    corridors/          # browse + detail
    nodes/              # detail + check-in
    passport/           # dashboard, activate, complete
  components/
  lib/
    supabase/client.ts  # createClient()        — anon + session, respects RLS
    supabase/server.ts  # createAdminClient()   — service role, server only
    email/
    auth/
  middleware.ts         # Matcher MUST exclude /api/cron/*
  types/database.ts     # All DB types with Relationships
emails/                 # React Email templates
supabase/
  migrations/           # SQL migrations — run in order, idempotent
```

---

## 4. Environment Variables

Exactly **7** variables. Nothing else is read.

```bash
# Supabase (project ref: gaavynmmysdhovpatzlp)
NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
SUPABASE_SERVICE_ROLE_KEY=<service role key>     # server-only — NEVER NEXT_PUBLIC_

# Resend
RESEND_API_KEY=re_<key>                          # server-only
RESEND_FROM_EMAIL=kaelo@<verified-domain>        # server-only

# App
NEXT_PUBLIC_APP_URL=https://atlas-passport.vercel.app

# Cron
CRON_SECRET=<openssl rand -hex 32>               # server-only
```

`ADMIN_EMAILS` and `RESEND_FROM_NAME` are **not used** — do not set them.

**Vercel target rules (audit finding INF-1):**
- All 7 must exist on **Production**.
- All `NEXT_PUBLIC_*` and `NEXT_PUBLIC_APP_URL` must also exist on **Preview**, or PR builds will silently fail at first Supabase call.
- Development target may use `.env.local`, which **must remain in `.gitignore`**.

---

## 5. Database — Migration State

Apply in order via Supabase SQL Editor or CLI. All migrations are idempotent.

| # | File | Purpose | Live status |
|---|---|---|---|
| 001 | `001_initial_schema.sql` | All tables, RLS, trigger | ✅ applied |
| 002 | `002_storage_and_realtime.sql` | Storage policies | ✅ applied |
| 003 | `003_profile_referral_code.sql` | `profiles.referral_code` | ✅ applied |
| 004 | `004_repair_migration.sql` | Schema repair — `rewards.name`, `rewards.claimed`, storage policies | ⏳ **PENDING** |
| 005 | `005_rls_exploit_patches.sql` | `profiles_update_own` is_admin freeze; `check_ins_insert_own` ownership guard | ⏳ **PENDING** |
| 006 | `006_test_helpers.sql` | `confirm_test_users`, `seed_ci_fixtures`, `seed_ci_fixtures_v2` RPCs | ✅ applied (CI confirmed) |
| 007 | `007_rls_column_guards.sql` | `passports_insert_own` corridor guard; `check_ins_player_view` SECURITY BARRIER | ⏳ **PENDING** |
| 008 | `008_create_test_users_helper.sql` | `create_test_users()` — original CI helper (superseded by 011–013) | ✅ applied (CI confirmed) |
| 009 | `009_create_regression_users.sql` | `create_regression_users()` — regression suite users | ⏳ **PENDING** |
| 010 | `010_fix_null_token_columns.sql` | COALESCE patch for null token columns in existing users | ⏳ **PENDING** |
| 011 | `011_refresh_ci_user_functions.sql` | Refresh both CI user helpers + auth.identities row for GoTrue v2 | ✅ applied |
| 012 | `012_add_email_change_to_ci_users.sql` | Add `email_change=''` and `phone=''` to CI user INSERT | ✅ applied |
| 013 | `013_add_phone_change_to_ci_users.sql` | Add `phone_change=''` to CI user INSERT (GoTrue PhoneChange fix) | ⏳ **PENDING — apply next** |

**Sentinel checks** to verify post-apply:
- `POST /rpc/create_test_users` → 200
- `POST /rpc/confirm_test_users` → 200
- `GET  /check_ins_player_view` → 200
- `GET  /rewards?select=name` → valid JSON

---

## 6. Security Posture & RLS Rules

RLS is the launch gate. The June 23 audit found 5 of 6 exploit categories live; PR #18 fixes them. Until migrations 004–008 are applied, **assume the production DB is exploitable.**

### Public read tables (anon SELECT allowed)
- `corridors` (active rows)
- `nodes` (active rows)

### Private tables (anon SELECT must return `[]`)
- `profiles`, `passports`, `check_ins`, `rewards`

### Required policies (from PR #18)

| Table | Policy | Critical clause |
|---|---|---|
| `profiles` | `profiles_update_own` | `WITH CHECK (auth.uid()=id AND is_admin=(SELECT is_admin FROM profiles WHERE id=auth.uid()))` — freezes is_admin |
| `check_ins` | `check_ins_insert_own` | `EXISTS(... passports p WHERE p.id=passport_id AND p.user_id=auth.uid() AND p.status='active')` — ownership + active gate |
| `passports` | `passports_insert_own` | `EXISTS(... corridors c WHERE c.id=corridor_id AND c.is_active=TRUE)` — active corridor gate |
| `rewards` | `prevent_reward_unclaim` trigger | blocks `claimed: true → false` |

### Behavioral assertions (probes that must all pass)
- `PATCH /profiles {"is_admin": true}` as anon → **403** (not 204).
- Authenticated `INSERT check_ins` against foreign `passport_id` → **403**.
- `INSERT passport` on `is_active=false` corridor → **403**.
- `INSERT check_in` on `status!='active'` passport → **403**.

---

## 7. Client Architecture Rules

- `createAdminClient()` (service role) — server routes and server components only. Never imported into client components.
- `createClient()` (anon + session) — all user-facing data access. Respects RLS.
- Admin server components MUST call **both** middleware AND `requireAdmin()` in-component (defense in depth).
- All email sends are non-blocking: `.catch(console.error)`.
- `safeNext()` in auth callback validates `?next=` — no open redirects.
- Middleware matcher **must exclude** `/api/cron/*` (otherwise Vercel cron 401s).

---

## 8. CI / CD

### Required status checks on `main` (post-PR #18 merge)
- `Lint · Build · Bundle Size`
- `RLS Exploit Tests (24 assertions)` ← **critical merge gate**
- `Verify required env vars in Vercel`

### Workflows
- `.github/workflows/ci.yml` — lint, build, bundle size, RLS Security Tests
- `.github/workflows/rls-exploit-tests.yml` — 24 assertions across 6 exploit files
- `.github/workflows/rls-regression-tests.yml` — reg-01 → reg-04
- `.github/workflows/check-vercel-env.yml` — env var presence

### Test fixtures
CI test users are created via **`rpc/create_test_users`** (service role, direct `auth.users` insert).
**Do not** use Supabase email signup in CI — it hits free-tier email rate limits and breaks the suite. This was the failure mode that cascaded through last night's runs.

### Solo-dev branch protection
- Required status checks: ON.
- Required reviewers: **0** (you cannot self-approve).
- `enforce_admins`: ON by default; toggle OFF only for the moment of merging PR #18, then back ON.

---

## 9. Deployment Checklist

Run in order. Do **not** skip the sentinel checks.

1. Apply migrations 004 → 008 to production Supabase via SQL Editor.
2. Run sentinel probes (Section 5) — all must pass.
3. Add the 7 env vars to Vercel → Production. Mirror `NEXT_PUBLIC_*` to Preview.
4. Add `https://atlas-passport.vercel.app/auth/callback` to Supabase → Auth → Redirect URLs.
5. Set Supabase Site URL → `https://atlas-passport.vercel.app`.
6. Confirm `check-in-proofs` storage bucket exists (private).
7. Verify Resend domain DNS (SPF + DKIM green).
8. Create first admin: `UPDATE profiles SET is_admin = true WHERE email = 'pilotspry@gmail.com';`
9. Smoke test: sign up → magic link → activate passport → check in → admin approve → reward unlock.
10. Confirm `Lint · Build · Bundle Size` and `RLS Exploit Tests (24 assertions)` are required checks on `main`.

---

## 10. Safety Constraints — Hard Rules for Claude

These are non-negotiable. Most of them were promoted from audit findings.

### Secrets & env
- **Never** commit real keys. `.env.local` must be in `.gitignore`. Pause and request credentials if needed; do not invent placeholders that survive into commits.
- **Never** prefix server-only keys with `NEXT_PUBLIC_`. Specifically: `SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `CRON_SECRET`.
- Workflows reference secrets via `secrets.*` only. Never hardcode.
- If service-role key rotates, update Vercel Production immediately and invalidate any local `.env.local` copy.

### Migrations & DB
- Migrations must be **idempotent**: `CREATE OR REPLACE`, `ADD COLUMN IF NOT EXISTS`, `DROP POLICY IF EXISTS`, `ON CONFLICT DO NOTHING`.
- **Never** mark an RLS fix as "done" based on PR diff alone. Run sentinel probes against the live DB.
- **Never** ship a schema change that depends on a column the migration has not yet added — the rewards trigger failure showed why.
- Do not run destructive SQL (DROP TABLE, TRUNCATE, DELETE without WHERE) on production without explicit confirmation from `pilotspry@gmail.com`.

### Deploy & build
- A green Vercel build is **not** proof of health. Always verify env vars and Supabase connectivity separately.
- If env vars are the issue, fix env vars — do **not** modify source to compensate.
- **Never** deploy if the Supabase connectivity test fails. Delete any temporary test script after it succeeds.
- `/api/cron/*` must remain excluded from the middleware matcher.
- `vercel.json` must **not** set `outputDirectory: "public"`.

### CI & merging
- Solo-dev rule: keep status checks required, reviewers at 0. Use `enforce_admins` toggle only for the merge instant.
- Required-checks list must include `RLS Exploit Tests (24 assertions)` once PR #18 is merged.
- Do **not** merge PR #18 until: migrations applied, sentinels green, 24-assertion suite green, regression suite green.

### Dependencies
- Treat the Next.js auth-bypass + RCE CVEs as **launch blockers**. The Next 15 upgrade is P1, not optional.
- Strip the `x-middleware-subrequest` header in `next.config.mjs` as immediate mitigation while the upgrade is pending.
- Pin `ws` to `^8.21.0` via `package.json` `overrides`.

### Behavior
- When in doubt about an irreversible action (destructive SQL, secret rotation, force-push, branch deletion, env-var overwrite on production), **stop and ask the user.**
- Only modify scope explicitly granted. If the user asked for an env-var fix, do not also refactor unrelated source.
- Quote sentinel probe results verbatim in any "RLS is fixed" claim.

---

## 11. Known Outstanding Work (post-audit)

| Item | Owner | Notes |
|---|---|---|
| Apply migrations 004 → 008 to production | User (manual SQL paste) | Combined file ready |
| Re-run CI on PR #18 | Auto on push | Should pass once migrations are live |
| Merge PR #18 | User | Use `enforce_admins` bypass flow |
| Add required status checks to `main` | User | GitHub → Settings → Branches |
| Upgrade `next` to `^15.5.19` | Claude | Test RSC pages, auth callback, cron route |
| Pin `ws` to `^8.21.0` | Claude | `package.json` overrides |
| Upgrade `@supabase/ssr` to `^0.12.0` | Claude | Codebase already forward-compatible |
| Enrich 14 DC corridor nodes | User | Sequence, address, hint, description, coordinates |
| Verify Resend SPF + DKIM | User | Pre-launch gate |
| PWA + Capacitor track | Branch `feat/pwa-ios-capacitor` | Resume after PR #18 merge |

---

## 12. References

- Repo: https://github.com/pilotspry-maker/Atlas-Passport
- Active PR: https://github.com/pilotspry-maker/Atlas-Passport/pull/18
- Production app: https://atlas-passport.vercel.app
- Supabase project: https://supabase.com/dashboard/project/gaavynmmysdhovpatzlp
- Branch protection: https://github.com/pilotspry-maker/Atlas-Passport/settings/branches
- Companion audit summary: `AUDIT_SUMMARY.md` (in this handoff bundle)
