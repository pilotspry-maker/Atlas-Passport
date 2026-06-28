#!/usr/bin/env bash
# scripts/verify_rls.sh
# ──────────────────────────────────────────────────────────────────────────
# Atlas Passport — RLS posture check.
#
# Connects to the Supabase database using the read-only `rls_verifier`
# role (see docs/LAUNCH_STABILITY.md §2 and scripts/create_rls_verifier_role.sql)
# and performs two phases of checks against pg_catalog:
#
#   PHASE A — Policy PRESENCE on critical tables
#     Every critical table must have RLS enabled AND every expected
#     policy name must exist. Catches "policy was dropped and never
#     replaced" regressions.
#
#   PHASE B — Policy SHAPE invariants from the 2026-06 lockdown
#     Seven invariants from migrations 024, 025, 026. Catches "policy
#     was loosened (e.g. WITH CHECK (true), roles widened)" regressions.
#
# Connection
#   Uses SUPABASE_DB_URL — a postgres connection string for the
#   `rls_verifier` role. In CI this is wired via the repo secret of the
#   same name. Locally, export it inline.
#
# Exit codes
#   0 — every check passed
#   1 — at least one check failed
#   2 — usage error (missing env, psql not installed, connect failed)
#
# References
#   docs/LAUNCH_STABILITY.md §1 (invariant catalog)
#   scripts/create_rls_verifier_role.sql (DB role provisioning)
#   .github/workflows/verify-rls.yml (CI wiring)
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Preconditions ─────────────────────────────────────────────────────────
if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "ERROR: SUPABASE_DB_URL is required (postgres connection string for rls_verifier)." >&2
  echo "       In CI: add it as a repo secret." >&2
  echo "       Locally: export SUPABASE_DB_URL='postgresql://rls_verifier:...@db.<ref>.supabase.co:5432/postgres'" >&2
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "ERROR: psql not found in PATH. Install postgresql-client." >&2
  exit 2
fi

echo "── Atlas Passport RLS verification ──"
# Redact the password before logging the target.
echo "Target: $(printf '%s' "$SUPABASE_DB_URL" | sed -E 's#(://[^:]+:)[^@]+@#\1****@#')"
echo

# Probe the connection first with a clear error if `rls_verifier` cannot
# log in (most common failure during initial wiring).
if ! psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 --no-psqlrc -Atqc "select 1" >/dev/null; then
  echo "ERROR: Could not connect with SUPABASE_DB_URL." >&2
  echo "       Verify the password matches the one set in create_rls_verifier_role.sql." >&2
  exit 2
fi

# ── Run all checks in a single psql session for atomic ON_ERROR_STOP ──────
psql "$SUPABASE_DB_URL" \
  -v ON_ERROR_STOP=1 \
  --no-psqlrc \
  --quiet \
  --tuples-only \
  --no-align <<'SQL'
\set VERBOSITY terse

-- ════════════════════════════════════════════════════════════════════════
-- PHASE A — Policy PRESENCE on critical tables
-- ════════════════════════════════════════════════════════════════════════
-- For each critical table we assert:
--   (1) RLS is enabled on the table.
--   (2) Every expected policy name exists.
-- The expected-policy list is the post-lockdown state after migrations
-- 024 (PR #29) and 026 (PR #31).

-- ── A.1  public.ap_events ────────────────────────────────────────────────
do $$
declare rls_on boolean;
declare missing text[];
declare expected text[] := array[
  'service_role_inserts_ap_events'   -- 024 block A
];
declare p text;
begin
  select c.relrowsecurity into rls_on
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relname='ap_events';

  if not coalesce(rls_on, false) then
    raise exception 'FAIL [A.1] RLS is not enabled on public.ap_events';
  end if;

  missing := array[]::text[];
  foreach p in array expected loop
    if not exists (
      select 1 from pg_policies
      where schemaname='public' and tablename='ap_events' and policyname=p
    ) then
      missing := missing || p;
    end if;
  end loop;
  if array_length(missing,1) > 0 then
    raise exception 'FAIL [A.1] public.ap_events missing policy(s): %', array_to_string(missing, ', ');
  end if;
  raise notice 'OK   [A.1] public.ap_events — RLS on, expected policies present';
end$$;

-- ── A.2  public.referral_events ──────────────────────────────────────────
do $$
declare rls_on boolean;
declare missing text[];
declare expected text[] := array[
  'service_role_inserts_referrals'   -- 024 block A
];
declare p text;
begin
  select c.relrowsecurity into rls_on
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relname='referral_events';

  if not coalesce(rls_on, false) then
    raise exception 'FAIL [A.2] RLS is not enabled on public.referral_events';
  end if;

  missing := array[]::text[];
  foreach p in array expected loop
    if not exists (
      select 1 from pg_policies
      where schemaname='public' and tablename='referral_events' and policyname=p
    ) then
      missing := missing || p;
    end if;
  end loop;
  if array_length(missing,1) > 0 then
    raise exception 'FAIL [A.2] public.referral_events missing policy(s): %', array_to_string(missing, ', ');
  end if;
  raise notice 'OK   [A.2] public.referral_events — RLS on, expected policies present';
end$$;

-- ── A.3  public.waitlist_entries ─────────────────────────────────────────
-- The expected policy name is the one created by migration 026. If you
-- rename the policy in a future migration, update this expectation in
-- the same PR.
do $$
declare rls_on boolean;
declare ins_policy_count int;
begin
  select c.relrowsecurity into rls_on
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relname='waitlist_entries';

  if not coalesce(rls_on, false) then
    raise exception 'FAIL [A.3] RLS is not enabled on public.waitlist_entries';
  end if;

  -- After 026 there must be exactly one INSERT policy and it must
  -- target anon. We verify name presence by counting INSERT policies
  -- scoped to anon; the shape is asserted in PHASE B.
  select count(*) into ins_policy_count
  from pg_policies
  where schemaname='public' and tablename='waitlist_entries'
    and cmd='INSERT' and roles='{anon}';
  if ins_policy_count = 0 then
    raise exception 'FAIL [A.3] public.waitlist_entries has no anon INSERT policy (post-026)';
  end if;
  raise notice 'OK   [A.3] public.waitlist_entries — RLS on, anon INSERT policy present';
end$$;

-- ── A.4  corridor.audit_log ──────────────────────────────────────────────
do $$
declare rls_on boolean;
declare all_policy_count int;
begin
  select c.relrowsecurity into rls_on
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='corridor' and c.relname='audit_log';

  if not coalesce(rls_on, false) then
    raise exception 'FAIL [A.4] RLS is not enabled on corridor.audit_log';
  end if;

  select count(*) into all_policy_count
  from pg_policies
  where schemaname='corridor' and tablename='audit_log'
    and cmd='ALL' and roles='{service_role}';
  if all_policy_count = 0 then
    raise exception 'FAIL [A.4] corridor.audit_log missing service_role ALL policy';
  end if;
  raise notice 'OK   [A.4] corridor.audit_log — RLS on, service_role ALL policy present';
end$$;

-- ── A.5  corridor.jobs ───────────────────────────────────────────────────
do $$
declare rls_on boolean;
declare all_policy_count int;
begin
  select c.relrowsecurity into rls_on
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='corridor' and c.relname='jobs';

  if not coalesce(rls_on, false) then
    raise exception 'FAIL [A.5] RLS is not enabled on corridor.jobs';
  end if;

  select count(*) into all_policy_count
  from pg_policies
  where schemaname='corridor' and tablename='jobs'
    and cmd='ALL' and roles='{service_role}';
  if all_policy_count = 0 then
    raise exception 'FAIL [A.5] corridor.jobs missing service_role ALL policy';
  end if;
  raise notice 'OK   [A.5] corridor.jobs — RLS on, service_role ALL policy present';
end$$;

-- ════════════════════════════════════════════════════════════════════════
-- PHASE B — Policy SHAPE invariants (the original 7)
-- ════════════════════════════════════════════════════════════════════════

-- ── B.1: ap_events INSERT is service_role-only (024 block A) ─────────────
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='public' and tablename='ap_events' and cmd='INSERT'
    and (roles <> '{service_role}' or with_check is distinct from 'true');
  if bad > 0 then
    raise exception 'FAIL [B.1] public.ap_events INSERT is not locked to service_role';
  end if;
  raise notice 'OK   [B.1] public.ap_events INSERT = service_role only';
end$$;

-- ── B.2: referral_events INSERT is service_role-only (024 block A) ───────
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='public' and tablename='referral_events' and cmd='INSERT'
    and (roles <> '{service_role}' or with_check is distinct from 'true');
  if bad > 0 then
    raise exception 'FAIL [B.2] public.referral_events INSERT is not locked to service_role';
  end if;
  raise notice 'OK   [B.2] public.referral_events INSERT = service_role only';
end$$;

-- ── B.3: waitlist_entries INSERT is shape-checked anon (026) ─────────────
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='public' and tablename='waitlist_entries' and cmd='INSERT'
    and (roles <> '{anon}' or with_check = 'true');
  if bad > 0 then
    raise exception 'FAIL [B.3] public.waitlist_entries INSERT is not shape-checked anon';
  end if;
  raise notice 'OK   [B.3] public.waitlist_entries INSERT = shape-checked anon';
end$$;

-- ── B.4: search_path pinned on three flagged functions (024 block B) ─────
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where (n.nspname, p.proname) in (
          ('public',   'prevent_reward_unclaim'),
          ('corridor', 'claim_jobs'),
          ('corridor', 'set_updated_at'))
    and (p.proconfig is null
         or not exists (
              select 1 from unnest(p.proconfig) c where c like 'search_path=%'));
  if bad > 0 then
    raise exception 'FAIL [B.4] one or more flagged functions are missing pinned search_path';
  end if;
  raise notice 'OK   [B.4] search_path pinned on prevent_reward_unclaim, claim_jobs, set_updated_at';
end$$;

-- ── B.5: get_public_stats is the documented anon contract (025) ──────────
do $$
declare ok int;
begin
  select count(*) into ok
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_public_stats'
    and p.prosecdef = true
    and p.proconfig is not null
    and exists (
      select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  if ok = 0 then
    raise exception 'FAIL [B.5] public.get_public_stats missing SECURITY DEFINER + locked search_path';
  end if;
  raise notice 'OK   [B.5] public.get_public_stats = SECURITY DEFINER, search_path locked';
end$$;

-- ── B.6: corridor.audit_log + corridor.jobs explicit ALL policy (024E) ───
do $$
declare missing int;
begin
  select 2 - count(distinct tablename) into missing
  from pg_policies
  where schemaname = 'corridor'
    and tablename in ('audit_log', 'jobs')
    and cmd = 'ALL'
    and roles = '{service_role}';
  if missing > 0 then
    raise exception 'FAIL [B.6] corridor.audit_log / corridor.jobs missing service_role ALL policy';
  end if;
  raise notice 'OK   [B.6] corridor.audit_log + corridor.jobs = service_role ALL';
end$$;

-- ── B.7: corridor-covers bucket has no LIST policy (024 block F) ─────────
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname = 'storage'
    and tablename = 'objects'
    and policyname ilike '%corridor_covers%list%';
  if bad > 0 then
    raise exception 'FAIL [B.7] corridor-covers LIST policy still present (by-name lookups must be the only access path)';
  end if;
  raise notice 'OK   [B.7] corridor-covers LIST disabled (by-name lookups still work)';
end$$;

\echo
\echo '── All checks satisfied: 5 presence + 7 shape invariants ──'
SQL

echo
echo "✓ RLS verification passed."
