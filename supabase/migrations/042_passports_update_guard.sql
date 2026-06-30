-- ════════════════════════════════════════════════════════════════════════════
-- Migration 042 — passports_update_own: explicit authenticated UPDATE guard
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   The passports table has SELECT + INSERT policies but no UPDATE policy.
--   PostgreSQL's default-deny means authenticated users cannot currently UPDATE
--   passports directly — but the denial is implicit. This migration makes it
--   explicit and auditable, adding the correct policy shape expected by the
--   weekday RLS drift watch (INV-4).
--
--   All legitimate passport state transitions in the app use createAdminClient()
--   (service_role), which bypasses RLS. This policy only governs direct
--   PostgREST UPDATE calls by authenticated users.
--
--   Fields locked as immutable (WITH CHECK subquery against existing row):
--     user_id      — cannot transfer ownership
--     corridor_id  — cannot switch corridors
--     activated_at — immutable timestamp
--     expires_at   — cannot self-extend the 72-hour window
--
--   reward_claimed is protected separately by the prevent_reward_unclaim
--   BEFORE-UPDATE trigger installed in migration 005.
--
-- INVARIANT (checked by rls-drift-watch INV-4):
--   roles = '{authenticated}' AND qual contains 'user_id' AND 'auth.uid'
--   AND with_check contains 'user_id' AND 'auth.uid'
-- ════════════════════════════════════════════════════════════════════════════

-- Idempotent: drop before recreate.
DROP POLICY IF EXISTS "passports_update_own" ON public.passports;

-- Authenticated users may UPDATE only their own passports, and only if the
-- immutable structural fields remain unchanged.
CREATE POLICY "passports_update_own" ON public.passports
  FOR UPDATE TO authenticated
  USING (
    (select auth.uid()) = user_id
  )
  WITH CHECK (
    -- Own row only (new values must still belong to the same user)
    (select auth.uid()) = user_id
    -- Immutable: corridor cannot change
    AND corridor_id  = (SELECT p2.corridor_id  FROM public.passports p2 WHERE p2.id = passports.id)
    -- Immutable: activation timestamp cannot change
    AND activated_at = (SELECT p2.activated_at FROM public.passports p2 WHERE p2.id = passports.id)
    -- Immutable: cannot self-extend the expiry window
    AND expires_at   = (SELECT p2.expires_at   FROM public.passports p2 WHERE p2.id = passports.id)
    -- Immutable: cannot transfer ownership
    AND user_id      = (SELECT p2.user_id      FROM public.passports p2 WHERE p2.id = passports.id)
  );

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'passports'
      AND policyname = 'passports_update_own'
      AND cmd        = 'UPDATE'
  ) THEN
    RAISE EXCEPTION '[042] VERIFICATION FAILED: passports_update_own policy not found.';
  END IF;
  -- Confirm no anon/public UPDATE policy exists (the CRITICAL exploit class).
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'passports'
      AND cmd        = 'UPDATE'
      AND (roles::text LIKE '%anon%' OR roles::text LIKE '%public%')
  ) THEN
    RAISE EXCEPTION '[042] VERIFICATION FAILED: anon or public UPDATE policy found on passports — CRITICAL.';
  END IF;
  RAISE NOTICE '[042] OK: passports_update_own verified. No anon/public UPDATE policies on passports.';
END;
$$;
