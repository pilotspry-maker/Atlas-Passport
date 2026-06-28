#!/usr/bin/env bash
# scripts/verify_rls.sh
# ──────────────────────────────────────────────────────────────────────────
# Read-only RLS posture check for Atlas Passport.
#
# Re-asserts every invariant the 2026-06 security lockdown established:
#   1. public.ap_events INSERT     = service_role only          (024 block A)
#   2. public.referral_events INS  = service_role only          (024 block A)
#   3. public.waitlist_entries INS = shape-checked anon         (026)
#   4. search_path pinned on three flagged functions            (024 block B)
#   5. public.get_public_stats     = SECURITY DEFINER + pin     (025)
#   6. corridor.audit_log + corridor.jobs = service_role ALL    (024 block E)
#   7. storage.corridor-covers     = no LIST policy             (024 block F)
#
# Requires: SUPABASE_DB_URL — a postgres connection string with read access
# to the target project. In CI this is wired through a repo secret; locally,
# pass it inline.
#
# Exit code:
#   0 — all 7 invariants satisfied
#   1 — at least one invariant failed (raised inside psql, propagated here)
#   2 — usage error (missing env, psql not installed, connection refused)
#
# Reference: docs/LAUNCH_STABILITY.md §1.
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "ERROR: SUPABASE_DB_URL is required (postgres connection string)." >&2
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "ERROR: psql not found in PATH. Install postgresql-client." >&2
  exit 2
fi

echo "── Atlas Passport RLS verification ──"
echo "Target: $(printf '%s' "$SUPABASE_DB_URL" | sed -E 's#(://[^:]+:)[^@]+@#\1****@#')"
echo

# ON_ERROR_STOP=1 makes the first RAISE EXCEPTION abort the session with a
# non-zero exit, which `set -e` then propagates as the script's exit code.
psql "$SUPABASE_DB_URL" \
  -v ON_ERROR_STOP=1 \
  --no-psqlrc \
  --quiet \
  --tuples-only \
  --no-align <<'SQL'
\set VERBOSITY terse

-- ── Invariant 1: ap_events INSERT is service_role-only (024 block A) ──
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='public' and tablename='ap_events' and cmd='INSERT'
    and (roles <> '{service_role}' or with_check is distinct from 'true');
  if bad > 0 then
    raise exception 'FAIL [1/7] public.ap_events INSERT is not locked to service_role';
  end if;
  raise notice 'OK   [1/7] public.ap_events INSERT = service_role only';
end$$;

-- ── Invariant 2: referral_events INSERT is service_role-only (024 block A) ──
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='public' and tablename='referral_events' and cmd='INSERT'
    and (roles <> '{service_role}' or with_check is distinct from 'true');
  if bad > 0 then
    raise exception 'FAIL [2/7] public.referral_events INSERT is not locked to service_role';
  end if;
  raise notice 'OK   [2/7] public.referral_events INSERT = service_role only';
end$$;

-- ── Invariant 3: waitlist_entries INSERT is shape-checked anon (026) ──
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname='public' and tablename='waitlist_entries' and cmd='INSERT'
    and (roles <> '{anon}' or with_check = 'true');
  if bad > 0 then
    raise exception 'FAIL [3/7] public.waitlist_entries INSERT is not shape-checked anon';
  end if;
  raise notice 'OK   [3/7] public.waitlist_entries INSERT = shape-checked anon';
end$$;

-- ── Invariant 4: search_path pinned on flagged functions (024 block B) ──
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
    raise exception 'FAIL [4/7] one or more flagged functions are missing pinned search_path';
  end if;
  raise notice 'OK   [4/7] search_path pinned on prevent_reward_unclaim, claim_jobs, set_updated_at';
end$$;

-- ── Invariant 5: get_public_stats is the documented anon contract (025) ──
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
    raise exception 'FAIL [5/7] public.get_public_stats missing SECURITY DEFINER + locked search_path';
  end if;
  raise notice 'OK   [5/7] public.get_public_stats = SECURITY DEFINER, search_path locked';
end$$;

-- ── Invariant 6: corridor.audit_log and corridor.jobs have explicit ALL ──
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
    raise exception 'FAIL [6/7] corridor.audit_log / corridor.jobs missing service_role ALL policy';
  end if;
  raise notice 'OK   [6/7] corridor.audit_log + corridor.jobs = service_role ALL';
end$$;

-- ── Invariant 7: corridor-covers bucket has no LIST policy (024 block F) ──
do $$
declare bad int;
begin
  select count(*) into bad
  from pg_policies
  where schemaname = 'storage'
    and tablename = 'objects'
    and policyname ilike '%corridor_covers%list%';
  if bad > 0 then
    raise exception 'FAIL [7/7] corridor-covers LIST policy still present (by-name lookups must be the only access path)';
  end if;
  raise notice 'OK   [7/7] corridor-covers LIST disabled (by-name lookups still work)';
end$$;

\echo
\echo '── All 7 RLS invariants satisfied ──'
SQL

echo
echo "✓ RLS verification passed."
