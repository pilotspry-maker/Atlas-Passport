# Atlas Passport — Launch-Day Stability Checklist

**Owner:** Ramon Spry (Relevant Artist LLC)
**Last revised:** 2026-06-28
**Scope:** Commercial launch readiness immediately after the 2026-06 security
lockdown lands. Consolidates the hardening work shipped via PR #29, PR #30,
and PR #31 and prescribes the standing operating procedure that keeps the
system stable for paying users.

> **Read order:** This doc supersedes the ad-hoc instructions in
> `docs/HANDOFF_2026-06-27.md` and `docs/HANDOFF_2026-06-28.md` for live
> operations. The handoff docs remain the historical record of *how* we got
> here; this is the runbook for *staying* here.

---

## 0. Pre-flight — confirm the lockdown is actually live

Before treating this checklist as authoritative, the three lockdown PRs must
be merged in this exact order to satisfy migration dependencies and the
RLS-test gate:

1. **PR #29** — `lockdown/engine-sweep-2026-06-27` — migrations 020–025
   - 020–022: idempotent seed helpers, phone collision fix, UUID alignment
   - 023: initial advisor fixes
   - **024**: the lockdown core — restricts `Service inserts` policies on
     `ap_events` and `referral_events` to `service_role` (closes the
     anon-inserts-AP-points vulnerability), pins `search_path` on three
     flagged functions, wraps `auth.<fn>()` calls in `(select …)` for planner
     caching across 13 policies, adds covering indexes on hot FKs, makes
     `corridor.audit_log` and `corridor.jobs` service-role-only explicit,
     turns off LIST on the `corridor-covers` bucket
   - 025: `get_public_stats` SECURITY DEFINER + security_invoker view for the
     Kaelo Atlas Command public dashboard (intentional anon-callable contract)
2. **PR #30** — `fix/vitest-pool-restore-2026-06-28` — restores sequential
   execution for the RLS exploit and regression suites under Vitest 4
   (`pool: "forks"`, `fileParallelism: false`). Also pins the
   `vitest@4.1.9 + vite@8.1.0 + esbuild@0.28.1` triple that closes all five
   open Dependabot alerts including the critical vitest UI RCE
   (CVE-2026-47429).
3. **PR #31** — `chore/026-advisor-cleanup` — migration 026 hardens the
   `public.waitlist_entries` "Public join waitlist" INSERT policy to
   `anon`-only with a shape-checked `WITH CHECK` that blocks
   `invited=true` forgery and arbitrary `position_tier`. Carries a
   `RAISE EXCEPTION` preflight that refuses to run if 024 hasn't landed.

**Hard gate:** Do not declare commercial-ready until:
- All three PRs are merged to `main`.
- `RLS Exploit Tests` and `RLS Regression Tests` workflows are green on
  `main` (confirms the rotated `SUPABASE_SERVICE_ROLE_KEY` is a valid
  3-segment JWT — see `docs/HANDOFF_2026-06-28.md` for the rotation
  procedure).
- The Supabase database linter shows zero ERROR-level findings.
- Vercel production deploy state is `Ready` and both
  `atlas-passport.vercel.app` and `atlas-passport.pplx.app` return HTTP 200.

---

## 1. RLS policy verification script

Drop this in `scripts/verify_rls.sh`. It's a single-pass, read-only check
that re-asserts every invariant migrations 024 and 026 establish, plus the
SECURITY DEFINER advisor contract from 025. Exit code is non-zero if any
invariant is violated, so it's safe to wire into a cron or pre-deploy hook.

```bash
#!/usr/bin/env bash
# scripts/verify_rls.sh — read-only RLS posture check.
# Requires: SUPABASE_DB_URL (postgres connection string with read access).
# Exits 0 if all invariants hold, 1 otherwise. Prints a compact table.
set -euo pipefail

: "${SUPABASE_DB_URL:?SUPABASE_DB_URL is required}"

psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -Atq <<'SQL'
-- ── Invariant 1: ap_events INSERT is service_role-only (from 024 block A) ──
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='public' and tablename='ap_events' and cmd='INSERT'
    and (roles <> '{service_role}' or with_check <> 'true');
  if bad > 0 then raise exception 'FAIL ap_events INSERT not locked to service_role'; end if;
  raise notice 'OK   ap_events INSERT = service_role only';
end$$;

-- ── Invariant 2: referral_events INSERT is service_role-only (024 block A) ──
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='public' and tablename='referral_events' and cmd='INSERT'
    and (roles <> '{service_role}' or with_check <> 'true');
  if bad > 0 then raise exception 'FAIL referral_events INSERT not locked to service_role'; end if;
  raise notice 'OK   referral_events INSERT = service_role only';
end$$;

-- ── Invariant 3: waitlist_entries INSERT is shape-checked anon (026) ──────
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='public' and tablename='waitlist_entries' and cmd='INSERT'
    and (roles <> '{anon}' or with_check = 'true');
  if bad > 0 then raise exception 'FAIL waitlist_entries INSERT not shape-checked anon'; end if;
  raise notice 'OK   waitlist_entries INSERT = shape-checked anon';
end$$;

-- ── Invariant 4: search_path pinned on the three functions flagged in 024 ─
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where (n.nspname,p.proname) in (
          ('public','prevent_reward_unclaim'),
          ('corridor','claim_jobs'),
          ('corridor','set_updated_at'))
    and (p.proconfig is null
         or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'));
  if bad > 0 then raise exception 'FAIL one or more functions missing pinned search_path'; end if;
  raise notice 'OK   search_path pinned on prevent_reward_unclaim, claim_jobs, set_updated_at';
end$$;

-- ── Invariant 5: get_public_stats is the documented anon contract (025) ──
do $$
declare ok int;
begin
  select count(*) into ok
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname='get_public_stats'
    and p.prosecdef = true
    and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  if ok = 0 then raise exception 'FAIL get_public_stats missing SECURITY DEFINER + locked search_path'; end if;
  raise notice 'OK   get_public_stats = SECURITY DEFINER, search_path locked';
end$$;

-- ── Invariant 6: corridor.audit_log and corridor.jobs explicit ALL policy ──
do $$
declare missing int;
begin
  select 2 - count(distinct tablename) into missing
  from pg_policies
  where schemaname='corridor' and tablename in ('audit_log','jobs')
    and cmd='ALL' and roles='{service_role}';
  if missing > 0 then raise exception 'FAIL corridor.audit_log/jobs missing service_role ALL policy'; end if;
  raise notice 'OK   corridor.audit_log + corridor.jobs = service_role ALL';
end$$;

-- ── Invariant 7: corridor-covers bucket has no anon SELECT * policy ───────
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='storage' and tablename='objects'
    and policyname like '%corridor_covers%list%';
  if bad > 0 then raise exception 'FAIL corridor-covers LIST policy still present'; end if;
  raise notice 'OK   corridor-covers LIST disabled (by-name lookups still work)';
end$$;

SELECT '── All RLS invariants satisfied ──' AS result;
SQL
```

Run it locally, in CI before any production deploy, and once per day from
the operations cron. A failed run is a release blocker.

---

## 2. Key rotation schedule (post-launch)

The launch hardening moved Atlas Passport off the legacy anon JWT pattern.
This is the standing rotation cadence going forward — calendar these in
Google Calendar with a 48-hour heads-up reminder.

| Key | Where it lives | Cadence | Trigger to rotate sooner |
|---|---|---|---|
| **`SUPABASE_SERVICE_ROLE_KEY` (legacy JWT)** | GitHub Actions secret on `pilotspry-maker/Atlas-Passport`; Vercel env (Production only) on `atlas-passport` | **Every 90 days** | Any contractor offboarded who had repo or Vercel access; any suspected leak in CI logs; any rejected `gh secret set` whose source isn't clearly you |
| **`SUPABASE_ANON_KEY` (publishable `sb_publishable_...`)** | Vercel env on `atlas-passport` across **Production, Preview, Development**; `.env.local` for devs | **Every 180 days** | Any time a published client bundle leaks an old key; any time the marketing site is migrated to a new host |
| **Supabase database password (`DB_PASSWORD`)** | GitHub Actions secret only (for migrations) | **Every 90 days, aligned with service-role rotation** | Any direct-DB incident; any time a `psql` session is run from a contractor laptop |
| **Vercel deploy hooks / build hooks** | Vercel project settings | **Every 180 days** | Any time the webhook URL surfaces in a public artifact |
| **`SUPABASE_ACCESS_TOKEN` (management API)** | Local only — never in CI | **Every 90 days** | Any time you suspect a CLI dump leaked it |

### Rotation procedure (service_role)

1. **Generate:** Supabase Dashboard → project `gaavynmmysdhovpatzlp` →
   Settings → API → service_role → **Reveal**. Keep the legacy 3-segment
   JWT form (`eyJ…`). The opaque `sb_secret_…` form is **not** accepted
   by the workflows; rotating to it will reproduce the 2026-06-28 outage.
2. **Stage in GitHub:**
   ```bash
   printf '%s' "$SRK" | gh secret set SUPABASE_SERVICE_ROLE_KEY \
     -R pilotspry-maker/Atlas-Passport --body -
   ```
   `printf '%s'` (not `echo`) avoids the trailing newline that has
   corrupted this exact secret before.
3. **Stage in Vercel (Production only):**
   ```bash
   echo "$SRK" | vercel env add SUPABASE_SERVICE_ROLE_KEY production \
     --scope ramon-spry --token "$VERCEL_TOKEN" --force
   ```
   Then `vercel --prod deploy` to roll the env into the running build.
4. **Verify:** trigger `RLS Exploit Tests` and `RLS Regression Tests` on
   `main`. Both must go green on the same SHA before you consider the
   rotation complete. Then run `scripts/verify_rls.sh` against the
   production DB.
5. **Revoke the previous key** from the Supabase dashboard.

### Rotation procedure (anon / publishable)

1. Generate the new publishable key in the Supabase dashboard.
2. Update Vercel env across **Production, Preview, and Development**
   simultaneously — partial scope updates are the root cause of the
   2026-06-28 preview-deploy authentication regression:
   ```bash
   for ENV in production preview development; do
     vercel --non-interactive env add NEXT_PUBLIC_SUPABASE_ANON_KEY "$ENV" "" \
       --value "$NEW_KEY" --force --yes \
       --scope ramon-spry --token "$VERCEL_TOKEN"
   done
   ```
3. Trigger a clean `vercel --prod deploy`; verify the smoke test in §3.
4. Disable the old publishable key in the Supabase dashboard only after
   the smoke test passes.

---

## 3. Narrative-corridor 15-minute smoke test

The goal is to prove, end-to-end, that a real traveler can move through a
narrative corridor and the Kaelo interaction layer stays performant after
the lockdown. Run this every time you:

- Merge a PR that touches `app/`, `lib/`, `supabase/migrations/`, or any
  Vercel env.
- Rotate any key from §2.
- Cut a production release tag.

**Target SLOs during the test** (any single breach fails the smoke):
- Page TTFB < 800 ms p50, < 1.5 s p95 (Vercel Speed Insights).
- Kaelo first-token latency < 1.2 s p50; full-message latency < 6 s p95.
- Zero 5xx responses across the run.
- Zero rows added to `corridor.audit_log` whose `severity = 'error'`.

### T+0 to T+2 — Environment confirmation

1. Open `https://atlas-passport.vercel.app/` in an incognito window.
   Confirm 200, Kaelo Atlas Command public stats load (this exercises
   the `get_public_stats` anon contract from migration 025).
2. Open `https://atlas-passport.pplx.app/` (the Perplexity alias).
   Same checks.
3. Open the Vercel project page in another tab. Note the current
   production deployment id. Open its real-time logs view.

### T+2 to T+5 — Authenticated entry

4. Sign in as the production smoke-test account
   (`smoke-traveler@relevantartist.com`, password in 1Password vault
   "Atlas / Smoke / Production"). Confirm the auth callback completes
   without redirect loops.
5. Land on `/passport`. Confirm:
   - Passport count loads under 1 s.
   - The user's AP balance matches the value in
     `select sum(amount) from public.ap_events where user_id = …`.
   - No `42501` permission errors in the network tab.

### T+5 to T+10 — Corridor traversal

6. Open the active launch corridor (set via env
   `NEXT_PUBLIC_LAUNCH_CORRIDOR_SLUG`). Confirm the cover image renders
   (validates the `corridor-covers` storage by-name lookup still
   functions after 024 disabled LIST).
7. Walk one node forward. Confirm:
   - Node detail loads under 800 ms.
   - `check_ins_insert_own` accepts the new check-in (this is the
     hardest RLS path — it joins through `passports` and validates
     `status = 'active'`).
   - A new row appears in `public.ap_events` within 2 s, inserted by
     `service_role` (verifies 024 block A is intact — anon must not be
     able to insert here).

### T+10 to T+13 — Kaelo interaction

8. Open the Kaelo dialog from the corridor view. Send one message:
   `"What should I notice about this place that a tourist would miss?"`
9. Confirm:
   - First token arrives under 1.2 s.
   - Streaming completes in one continuous response (no mid-stream
     reconnects in the network tab).
   - No row appears in `corridor.audit_log` with `severity = 'error'`
     for the timestamp window of the request.
   - The thread is persisted (refresh; the message must reappear).

### T+13 to T+15 — Closeout

10. Sign out. Confirm the session cookie is cleared.
11. Re-open `/` anonymously. Confirm public stats still render
    (re-exercises the anon SECURITY DEFINER contract after a
    write-heavy run).
12. Capture the production deployment id and a screenshot of the
    Kaelo response. Drop both in `#launch-ops` (or commit to
    `docs/smoke-reports/SMOKE_YYYY-MM-DD.md`) with the elapsed time.

A failed smoke test is a launch-blocker. If §1's verify script also
fails, roll back the most recent deploy using
`docs/runbooks/migration-rollback.md` and re-run from T+0.

---

## 4. Daily standing checks

The session-owned recurring task `Atlas Passport daily health check` (9 AM
ET) covers GitHub Actions on `main` + Vercel production reachability and
pings only on failure. Keep it on. Add to it manually only if a new
critical workflow is introduced.

Weekly, on Monday morning, additionally:

- Run `scripts/verify_rls.sh` against the production DB.
- Review the past 7 days of `corridor.audit_log` where
  `severity in ('warn','error')`.
- Review Supabase dashboard advisors. Anything new at ERROR severity is
  a same-day fix.
- Review Vercel Speed Insights — investigate any route whose p95 TTFB
  crossed 1.5 s.

---

## 5. Escalation

| Condition | First action | If unresolved in |
|---|---|---|
| Production hostnames return non-2xx | Roll back to last healthy deploy `dpl_DuoR9qyxvJLyWCnYTP7Uhgq6fJab` via Vercel "Promote to Production" | 15 min → engage Claude coworker per `CLAUDE.md` |
| RLS exploit test fails on `main` | Block all merges; run §1 verify; check service-role JWT validity | 30 min → revert the last merge to `main` |
| Kaelo p95 latency > 8 s sustained | Check OpenAI/Anthropic provider status; check `corridor.jobs` queue depth | 30 min → fall back to cached corridor responses (feature flag `kaelo_cache_only`) |
| Suspected key leak | Rotate per §2 immediately; do not wait for the cadence | Same day → notify users if data exposure is suspected |

---

## 6. References

- `docs/HANDOFF_2026-06-27.md` — engine sweep narrative
- `docs/HANDOFF_2026-06-28.md` — security and CI/CD audit
- `docs/security/rls-post-migration-audit.md` — policy inventory baseline
- `docs/runbooks/migration-rollback.md` — rollback procedure
- `CLAUDE.md` — coworker operating manual
- Supabase project: https://supabase.com/dashboard/project/gaavynmmysdhovpatzlp
- Vercel project: https://vercel.com/ramon-spry/atlas-passport

---

*This document is the standing operating procedure for Atlas Passport's
commercial operation. Revise it whenever a hardening migration lands, a
key rotation procedure changes, or the smoke-test SLOs are adjusted. Do
not delete past revisions — append a dated change log at the bottom.*

## Change log

- **2026-06-28** — Initial version. Consolidates PR #29, #30, #31 and
  sets the post-launch rotation cadence. (Ramon Spry / Perplexity Computer.)
