# Atlas Passport — Migration Rollback Runbook

**Scope:** Migrations `004_rls_hardening_and_node_integrity` and `005_rls_exploit_patches`  
**Target recovery time:** ≤ 10 minutes  
**Supabase project:** `gaavynmmysdhovpatzlp`  
**SQL Editor:** https://supabase.com/dashboard/project/gaavynmmysdhovpatzlp/sql/new  
**Last updated:** 2026-06-23

---

## Quick-Reference Decision Tree

```
Production issue after migration?
│
├─ App errors / users locked out?
│   └─ GO TO → Section 1: Triage
│
├─ RLS policy rejecting valid requests?
│   └─ GO TO → Section 3: Rollback 005
│
├─ Nodes/corridors visible to anonymous users again?
│   └─ DO NOT rollback — re-apply 004 (Section 5)
│
└─ Reward exploit or privilege escalation confirmed?
    └─ GO TO → Section 4: Emergency RLS Lockdown
```

---

## Section 1 — Triage (2 min)

Run this diagnostic block first. It tells you exactly what is and isn't applied before you touch anything.

```sql
-- ── DIAGNOSTIC: Run in Supabase SQL Editor ──────────────────────────────

-- 1a. Which migration-004 policies are live?
SELECT tablename, policyname, cmd, roles, qual::text
FROM   pg_policies
WHERE  schemaname = 'public'
AND    policyname IN (
  'nodes_select_active',
  'rewards_select_own',
  'rewards_select_admin'
)
ORDER BY tablename, policyname;

-- 1b. Which migration-005 policies/triggers are live?
SELECT tablename, policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
AND    policyname IN ('profiles_update_own', 'check_ins_insert_own')
ORDER BY tablename;

SELECT tgname, tgrelid::regclass AS table_name, tgenabled
FROM   pg_trigger
WHERE  tgname = 'check_reward_claimed_immutable';

-- 1c. Are any users currently self-escalated? (expect 0 in normal operation)
SELECT id, email, is_admin, created_at
FROM   public.profiles
WHERE  is_admin = TRUE;

-- 1d. Confirm anon-access state — should return [] after 004, rows before 004
-- (Run from an HTTP client; this query alone won't reveal anon exposure)
-- curl -s "https://gaavynmmysdhovpatzlp.supabase.co/rest/v1/nodes?select=id&limit=1" \
--      -H "apikey: sb_publishable_1BPrFxSYIb__I7JZUbgimQ_RZcVR_oU"
```

**Interpreting results:**

| Scenario | Meaning | Action |
|---|---|---|
| `nodes_select_active` missing | Migration 004 never applied | Apply 004 (Section 5) |
| `nodes_select_active` present, anon still reads nodes | Policy not blocking anon — RLS may be disabled | Section 4 → re-enable RLS |
| `profiles_update_own` WITH CHECK has no `is_admin` guard | Migration 005 not applied | Apply 005 (Section 5) |
| `check_reward_claimed_immutable` trigger missing | Migration 005 not applied | Apply 005 (Section 5) |
| `is_admin = TRUE` for unexpected users | Pre-patch self-escalation occurred | Section 2 |

---

## Section 2 — Pre-Rollback: Remediate Any Self-Escalation

If triage (1c) shows unexpected `is_admin = TRUE` rows, demote them before doing anything else. Leaving a compromised admin account active while you modify policies is dangerous.

```sql
-- ── STEP 2: Demote suspicious admins ────────────────────────────────────
-- Replace the UUIDs below with any known-legitimate admin IDs.
-- Leave this list empty if you have NO legitimate admins yet.

UPDATE public.profiles
SET    is_admin = FALSE,
       updated_at = NOW()
WHERE  is_admin = TRUE
AND    id NOT IN (
  -- Add known-legitimate admin UUIDs here, e.g.:
  -- 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
  -- If you have no legitimate admins, remove this NOT IN clause entirely
  '00000000-0000-0000-0000-000000000000'  -- placeholder — replace or remove
);

-- Confirm the result
SELECT id, email, is_admin FROM public.profiles WHERE is_admin = TRUE;
```

---

## Section 3 — Rollback Migration 005 (target: 3 min)

Use this when the migration-005 policies are causing problems with legitimate user flows (e.g. valid profile updates being rejected, valid check-ins blocked).

**This rolls back to the post-004 state.** All migration-004 protections remain intact.

```sql
-- ── ROLLBACK 005: Remove the three exploit patches ──────────────────────
BEGIN;

-- ── 3a. Restore profiles_update_own to pre-005 state ────────────────────
-- Removes the is_admin column freeze introduced in 005.
-- Post-rollback: players CAN patch their own profile including is_admin.
-- ⚠️  This re-opens GAP 1. Apply migration 005 again as soon as the
--     root cause is resolved.

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  TO authenticated
  USING  (auth.uid() = id)
  WITH CHECK (auth.uid() = id);  -- no is_admin guard (pre-005 baseline)

-- ── 3b. Restore check_ins_insert_own to pre-005 state ───────────────────
-- Removes the passport-ownership EXISTS subquery introduced in 005.
-- Post-rollback: players CAN insert a check-in against any passport_id
-- as long as user_id = auth.uid().
-- ⚠️  This re-opens GAP 2 (cross-passport IDOR). Apply 005 again ASAP.

DROP POLICY IF EXISTS "check_ins_insert_own" ON public.check_ins;

CREATE POLICY "check_ins_insert_own" ON public.check_ins
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());  -- no passport ownership check (pre-005 baseline)

-- ── 3c. Remove reward_claimed immutability trigger ───────────────────────
-- Removes the BEFORE UPDATE trigger that blocks resetting reward_claimed.
-- Post-rollback: reward_claimed CAN be flipped false → true → false again.
-- ⚠️  This re-opens GAP 3. Apply 005 again once root cause is resolved.

DROP TRIGGER IF EXISTS check_reward_claimed_immutable ON public.passports;
DROP FUNCTION IF EXISTS public.prevent_reward_unclaim();

-- ── 3d. Verify rollback is clean ─────────────────────────────────────────
DO $$
BEGIN
  -- profiles_update_own should now NOT contain the is_admin subquery
  -- (we can't inspect QUAL here but we verify it exists)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
    AND   policyname = 'profiles_update_own'
  ) THEN
    RAISE EXCEPTION 'ROLLBACK FAILED: profiles_update_own policy missing after rollback.';
  END IF;

  -- check_ins_insert_own should exist (simpler form)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'check_ins'
    AND   policyname = 'check_ins_insert_own'
  ) THEN
    RAISE EXCEPTION 'ROLLBACK FAILED: check_ins_insert_own policy missing after rollback.';
  END IF;

  -- trigger must be gone
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'check_reward_claimed_immutable'
  ) THEN
    RAISE EXCEPTION 'ROLLBACK FAILED: check_reward_claimed_immutable trigger still present.';
  END IF;

  RAISE NOTICE 'Migration 005 rollback verified. ✓';
  RAISE NOTICE 'GAPs 1, 2, 3 are now RE-OPEN. Re-apply 005 as soon as root cause is resolved.';
END $$;

COMMIT;
```

**After rollback — verify app health:**
```bash
# Nodes still require auth (004 still in effect)
curl -s "https://gaavynmmysdhovpatzlp.supabase.co/rest/v1/nodes?select=id&limit=1" \
     -H "apikey: sb_publishable_1BPrFxSYIb__I7JZUbgimQ_RZcVR_oU"
# Expected: [] (empty — not blocked by 401, silently filtered by RLS)
```

---

## Section 4 — Rollback Migration 004 (target: 4 min)

Use this only if migration 004 itself is causing hard production failures (e.g. authenticated users getting 403 on nodes or corridors they should read, reward reads broken for legitimate completers).

**This is a more significant rollback.** It will re-expose nodes and corridors to unauthenticated access until you re-apply.

```sql
-- ── ROLLBACK 004: Restore pre-hardening RLS policies ────────────────────
-- Also rolls back 005 implicitly (trigger + policy from 005 are dropped first).
BEGIN;

-- ── 4a. Drop all 005 additions first (safe even if 005 was never applied) ──
DROP TRIGGER   IF EXISTS check_reward_claimed_immutable ON public.passports;
DROP FUNCTION  IF EXISTS public.prevent_reward_unclaim();

DROP POLICY IF EXISTS "profiles_update_own"  ON public.profiles;
DROP POLICY IF EXISTS "check_ins_insert_own" ON public.check_ins;

-- ── 4b. Drop all 004 additions ────────────────────────────────────────────
DROP POLICY IF EXISTS "nodes_select_active"   ON public.nodes;
DROP POLICY IF EXISTS "rewards_select_own"    ON public.rewards;
DROP POLICY IF EXISTS "rewards_select_admin"  ON public.rewards;

-- ── 4c. Restore pre-004 policies (from 004_repair_migration.sql baseline) ──

-- nodes: back to authenticated-only without auth.role() check
CREATE POLICY "nodes_select_active" ON public.nodes
  FOR SELECT
  TO authenticated
  USING (is_active = TRUE);  -- no auth.role() guard (pre-004 state)

-- rewards: back to any authenticated user can read all rewards
-- ⚠️  This means authenticated players WITHOUT a complete passport can
--     read redemption codes. Apply 004 again as soon as possible.
CREATE POLICY "rewards_select_auth" ON public.rewards
  FOR SELECT
  TO authenticated
  USING (TRUE);

-- profiles_update_own: restore pre-004 (same as repair migration baseline)
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  TO authenticated
  USING  (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- check_ins_insert_own: restore pre-004 baseline
CREATE POLICY "check_ins_insert_own" ON public.check_ins
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- ── 4d. Verify rollback ────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'nodes'
    AND   policyname = 'nodes_select_active'
  ) THEN
    RAISE EXCEPTION 'ROLLBACK FAILED: nodes_select_active missing after rollback.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'rewards'
    AND   policyname = 'rewards_select_own'
  ) THEN
    RAISE EXCEPTION 'ROLLBACK FAILED: rewards_select_own still present — should have been dropped.';
  END IF;

  RAISE NOTICE 'Migration 004 rollback verified. ✓';
  RAISE NOTICE 'Nodes may now be visible to anon. Re-apply 004 immediately.';
  RAISE NOTICE 'Reward redemption codes now readable by any authenticated user.';
  RAISE NOTICE 'GAPs 1, 2, 3 from 005 are also RE-OPEN.';
END $$;

COMMIT;
```

**Post-rollback anon test:**
```bash
# After rolling back 004, nodes will be readable by anon again:
curl -s "https://gaavynmmysdhovpatzlp.supabase.co/rest/v1/nodes?select=id,name&limit=3" \
     -H "apikey: sb_publishable_1BPrFxSYIb__I7JZUbgimQ_RZcVR_oU"
# If this returns rows, anon exposure is confirmed — re-apply 004 immediately
```

---

## Section 5 — Emergency RLS Lockdown

Use only if you suspect a live exploit is in progress and you need to immediately block all table reads to stop the bleeding, regardless of breaking the app.

```sql
-- ── EMERGENCY: Disable all public-schema RLS (BREAKS THE APP) ───────────
-- This stops all PostgREST data access — the app will show empty states
-- or errors to all users. Use only to halt an active attack.
-- Re-enable by running the RESTORE block below.

-- STEP 1: Disable RLS on all tables (run immediately)
ALTER TABLE public.profiles   DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.passports  DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.check_ins  DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.nodes      DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.corridors  DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.rewards    DISABLE ROW LEVEL SECURITY;

-- ⚠️  Service role still has full access. Only PostgREST JWT-authenticated
-- requests are affected. The app's Next.js server routes continue working.
```

```sql
-- ── RESTORE: Re-enable RLS after investigation ───────────────────────────
-- Run this after you've identified and fixed the issue.
-- This DOES NOT re-create policies — it just re-arms the existing ones.

ALTER TABLE public.profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.passports  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.check_ins  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nodes      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.corridors  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rewards    ENABLE ROW LEVEL SECURITY;

-- Verify all 6 tables have RLS enabled:
SELECT tablename, rowsecurity
FROM   pg_tables
WHERE  schemaname = 'public'
AND    tablename  IN ('profiles','passports','check_ins','nodes','corridors','rewards')
ORDER BY tablename;
-- All rows should show rowsecurity = true
```

---

## Section 6 — Re-Apply Migrations (target: 2 min each)

After a rollback, re-apply in order once the root cause is resolved.

### Re-apply Migration 004

Open the [Supabase SQL Editor](https://supabase.com/dashboard/project/gaavynmmysdhovpatzlp/sql/new), paste the full contents of:

```
supabase/migrations/004_rls_hardening_and_node_integrity.sql
```

All statements are idempotent — safe to run even if partially applied.

**Verify after:**
```bash
curl -s "https://gaavynmmysdhovpatzlp.supabase.co/rest/v1/nodes?select=id&limit=1" \
     -H "apikey: sb_publishable_1BPrFxSYIb__I7JZUbgimQ_RZcVR_oU"
# Expected: []
```

### Re-apply Migration 005

Paste the full contents of:

```
supabase/migrations/005_rls_exploit_patches.sql
```

**Verify after:**
```sql
-- All three patches must be present:
SELECT policyname FROM pg_policies
WHERE  schemaname = 'public'
AND    policyname IN ('profiles_update_own', 'check_ins_insert_own');
-- Expected: 2 rows

SELECT tgname FROM pg_trigger
WHERE  tgname = 'check_reward_claimed_immutable';
-- Expected: 1 row
```

---

## Section 7 — State Consistency Checks

Run after any rollback/re-apply to verify no data was corrupted.

```sql
-- ── 7a. Passports: no active passports past their expiry ─────────────────
SELECT id, user_id, status, expires_at,
       NOW() - expires_at AS overdue_by
FROM   public.passports
WHERE  status = 'active'
AND    expires_at < NOW();
-- Expected: 0 rows. If rows exist, run the expiry update from migration 004 section 6.

-- ── 7b. Check-ins: no orphaned records (dangling passport or node FK) ────
SELECT ci.id, ci.passport_id, ci.node_id
FROM   public.check_ins ci
WHERE  NOT EXISTS (SELECT 1 FROM public.passports p WHERE p.id = ci.passport_id)
OR     NOT EXISTS (SELECT 1 FROM public.nodes     n WHERE n.id = ci.node_id);
-- Expected: 0 rows.

-- ── 7c. Passports: no orphaned passports (corridor deleted/deactivated) ──
SELECT p.id, p.user_id, p.corridor_id, p.status
FROM   public.passports p
WHERE  NOT EXISTS (
  SELECT 1 FROM public.corridors c
  WHERE  c.id = p.corridor_id AND c.is_active = TRUE
);
-- Expected: 0 rows. Rows here = investigate before re-activating corridor.

-- ── 7d. Nodes: no active nodes with NULL sequence ─────────────────────────
SELECT id, name, corridor_id, position, sequence
FROM   public.nodes
WHERE  is_active = TRUE AND sequence IS NULL;
-- Expected: 0 rows. If rows exist, run: UPDATE nodes SET sequence = position WHERE sequence IS NULL;

-- ── 7e. reward_claimed integrity: no passport claims with no completed status ─
SELECT id, user_id, corridor_id, status, reward_claimed
FROM   public.passports
WHERE  reward_claimed = TRUE
AND    status != 'complete';
-- Expected: 0 rows. A claimed reward must belong to a complete passport.

-- ── 7f. Admin count sanity check ─────────────────────────────────────────
SELECT COUNT(*) AS admin_count FROM public.profiles WHERE is_admin = TRUE;
-- Expected: only your known admin accounts (typically 0-2 in early production).
-- If > expected, run Section 2 to demote unexpected admins.
```

---

## Section 8 — Policy Reference (What Each Migration Changed)

Use this table to understand the exact pre/post state for any policy.

| Table | Policy | Pre-004 | Post-004 | Post-005 |
|---|---|---|---|---|
| `nodes` | `nodes_select_active` | `TO authenticated USING (is_active = TRUE)` | + `auth.role() = 'authenticated'` check | unchanged |
| `rewards` | `rewards_select_auth` | `TO authenticated USING (TRUE)` — any auth user | DROPPED | DROPPED |
| `rewards` | `rewards_select_own` | — | Requires complete passport for corridor | unchanged |
| `rewards` | `rewards_select_admin` | — | Added: `is_admin = TRUE` override | unchanged |
| `profiles` | `profiles_update_own` | `USING (uid=id) WITH CHECK (uid=id)` | unchanged | + `is_admin` frozen by WITH CHECK subquery |
| `check_ins` | `check_ins_insert_own` | `WITH CHECK (user_id = uid)` | unchanged | + passport ownership + active status EXISTS |
| `passports` | trigger | none | none | `check_reward_claimed_immutable` BEFORE UPDATE |

---

## Section 9 — Key Links

| Resource | URL |
|---|---|
| Supabase SQL Editor | https://supabase.com/dashboard/project/gaavynmmysdhovpatzlp/sql/new |
| Supabase API Settings (rotate keys) | https://supabase.com/dashboard/project/gaavynmmysdhovpatzlp/settings/api |
| Supabase Auth Users | https://supabase.com/dashboard/project/gaavynmmysdhovpatzlp/auth/users |
| Supabase Logs | https://supabase.com/dashboard/project/gaavynmmysdhovpatzlp/logs/postgres-logs |
| GitHub Actions CI | https://github.com/pilotspry-maker/Atlas-Passport/actions |
| PR #17 (Migration 004) | https://github.com/pilotspry-maker/Atlas-Passport/pull/17 |
| PR #18 (Migration 005) | https://github.com/pilotspry-maker/Atlas-Passport/pull/18 |
| Production app | https://atlas-passport.vercel.app |

---

## 10-Minute Recovery Checklist

Copy this checklist when executing a live rollback:

```
[ ] 0:00 — Open Supabase SQL Editor
[ ] 0:30 — Paste and run Section 1 DIAGNOSTIC block
[ ] 1:30 — Identify which migration is the source (004 / 005 / both)
[ ] 2:00 — If self-escalation found: run Section 2 first
[ ] 3:00 — Run targeted rollback (Section 3 for 005-only, Section 4 for 004+005)
[ ] 5:00 — Verify rollback via SQL verify block in chosen section
[ ] 5:30 — Run Section 7 consistency checks (all 6 queries)
[ ] 7:00 — Test app endpoint: curl nodes with anon key
[ ] 7:30 — Check GitHub Actions for CI failures
[ ] 8:00 — Investigate root cause (logs, recent commits, PR diff)
[ ] 9:00 — Fix root cause (policy edit or migration edit)
[ ] 9:30 — Re-apply fixed migration (Section 6)
[ ] 10:00 — Confirm green state: Section 1 diagnostic all passing ✓
```
