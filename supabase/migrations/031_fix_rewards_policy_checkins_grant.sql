-- ════════════════════════════════════════════════════════════════════════════
-- Migration 031 — RLS inventory repair + CI seed grant
-- Atlas Passport · Relevant Artist
-- ════════════════════════════════════════════════════════════════════════════
--
-- Addresses three findings from the 2026-06-28 launch-protection Cycle 1
-- dashboard. All statements are idempotent (safe to re-run).
--
--   FIX 1 (REG-4a) — public.rewards is missing the canonically-named
--     `rewards_select_own` policy. The live policy is `rewards_select_auth`
--     (migration 027) which already gates SELECT behind a *complete* passport
--     on the reward's corridor. The REG-3 / REG-4 / exploit suites all expect
--     the policy to be named `rewards_select_own`. Rename it by dropping the
--     old name and recreating the identical gate under the expected name.
--
--   FIX 2 (REG-4f) — public.check_ins has a legacy INSERT policy
--     "Travelers insert own checkins" scoped TO public. REG-4f flags any
--     permissive policy on a private table whose roles include `public`
--     and whose USING is null/trivial (INSERT policies have a null USING).
--     Re-scope it TO authenticated. The WITH CHECK keeps the full passport
--     ownership + active-passport gate (identical to `check_ins_insert_own`)
--     so this permissive policy can never widen access beyond owner inserts.
--
--   FIX 3 — public.confirm_test_users(TEXT) is a SECURITY DEFINER CI helper
--     that must remain service_role-only (CLAUDE.md hard rule). Re-affirm the
--     service_role EXECUTE grant idempotently. The CI seed 401 (42501) is
--     fixed in the test harness (regression.setup.ts now calls it with the
--     service-role key, mirroring the exploit setup) — NOT by granting anon.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── FIX 1 — public.rewards: rewards_select_own ───────────────────────────────
-- Owner-equivalent SELECT: rewards has no user_id column, so "own" means the
-- caller holds a COMPLETE passport on the reward's corridor. This matches the
-- behaviour REG-3a/REG-3b and exploit-01/exploit-03 assert against.

DROP POLICY IF EXISTS "rewards_select_own"  ON public.rewards;
DROP POLICY IF EXISTS "rewards_select_auth" ON public.rewards;

CREATE POLICY "rewards_select_own" ON public.rewards
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM   public.passports p
      WHERE  p.user_id     = (select auth.uid())
        AND  p.corridor_id = rewards.corridor_id
        AND  p.status      = 'complete'
    )
  );

-- ── FIX 2 — public.check_ins: "Travelers insert own checkins" TO authenticated ─
-- Re-scope away from the public role. WITH CHECK enforces the same owner +
-- active-passport gate as check_ins_insert_own so OR-combination of the two
-- permissive INSERT policies can never bypass passport ownership (no IDOR).

DROP POLICY IF EXISTS "Travelers insert own checkins" ON public.check_ins;

CREATE POLICY "Travelers insert own checkins" ON public.check_ins
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (select auth.uid())
    AND EXISTS (
      SELECT 1
      FROM   public.passports p
      WHERE  p.id      = check_ins.passport_id
        AND  p.user_id = (select auth.uid())
        AND  p.status  = 'active'
    )
  );

-- ── FIX 3 — re-affirm service_role EXECUTE on confirm_test_users(TEXT) ────────
-- service_role-only per the SECURITY DEFINER grant rule. Idempotent.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'confirm_test_users'
  ) THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.confirm_test_users(TEXT) FROM PUBLIC';
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.confirm_test_users(TEXT) FROM anon';
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.confirm_test_users(TEXT) FROM authenticated';
    EXECUTE 'GRANT  EXECUTE ON FUNCTION public.confirm_test_users(TEXT) TO service_role';
    RAISE NOTICE '[031] confirm_test_users(TEXT) EXECUTE re-granted to service_role ✓';
  ELSE
    RAISE NOTICE '[031] confirm_test_users not found — skipping grant (apply migration 006 first)';
  END IF;
END $$;

-- ── Verify ───────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='rewards' AND policyname='rewards_select_own'
  ) THEN
    RAISE EXCEPTION '[031] VERIFICATION FAILED: rewards_select_own policy not found.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='check_ins'
      AND policyname='Travelers insert own checkins'
      AND 'public' = ANY(roles)
  ) THEN
    RAISE EXCEPTION '[031] VERIFICATION FAILED: "Travelers insert own checkins" still scoped TO public.';
  END IF;

  RAISE NOTICE '[031] rewards_select_own present; check_ins legacy policy re-scoped to authenticated ✓';
END $$;

COMMIT;
