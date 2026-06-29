-- ════════════════════════════════════════════════════════════════════════════
-- Migration 036 — Task 6: wrap bare auth.uid() in (select auth.uid()) for
--                         Supabase advisor auth_rls_initplan
-- ════════════════════════════════════════════════════════════════════════════
--
-- CONTEXT (Supabase advisor: auth_rls_initplan):
--   A bare auth.uid() call in a policy USING/WITH CHECK expression is
--   re-evaluated for every row examined — it cannot be hoisted to a
--   once-per-query initplan. Wrapping as (select auth.uid()) lets Postgres
--   cache the value as a startup initplan, avoiding the per-row overhead on
--   tables with many rows.
--
--   Migration 033 fixed 15 policies. This migration closes the remaining gaps
--   not yet touched by an earlier migration.
--
-- POLICIES REWRITTEN (5):
--
--   public.profiles — profiles_update_own (last defined in 005)
--     USING:      auth.uid() = id
--     WITH CHECK: auth.uid() = id AND is_admin = (SELECT ... WHERE id = auth.uid())
--
--   public.passports — passports_insert_own (last defined in 007)
--     WITH CHECK: user_id = auth.uid() AND EXISTS (...)
--
--   storage.objects — check_in_proofs_insert (last defined in 002)
--     WITH CHECK: ... (storage.foldername(name))[1] = auth.uid()::text
--
--   storage.objects — check_in_proofs_select_own (last defined in 002)
--     USING: ... (storage.foldername(name))[1] = auth.uid()::text
--
--   storage.objects — check_in_proofs_delete_own (last defined in 002)
--     USING: ... (storage.foldername(name))[1] = auth.uid()::text
--
-- Already correctly wrapped (no action needed):
--   profiles_select_own, passports_select_own, check_ins_select_own (033)
--   check_ins_insert_own (031), rewards_select_own (031)
--   Travelers insert/read/update own * (033), Travelers read own checkins (033)
--   get_public_rls_policies(), get_public_rls_status() (030)
--   handle_new_user() trigger (018 — search_path, not auth.uid())
--
-- VIEW:
--   check_ins_player_view WHERE clause also uses bare auth.uid().
--   Though views are not policies, the same per-row re-evaluation applies.
--   Redefine the view with (select auth.uid()) for consistency.
--
-- IDEMPOTENT: DROP POLICY IF EXISTS before each CREATE POLICY.
--
-- DOWN:
--   Reverse by re-issuing each CREATE POLICY with bare auth.uid().
--   No data loss — policies are behaviorally equivalent.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. profiles — profiles_update_own ────────────────────────────────────────
-- Preserves the is_admin column freeze from migration 005 exactly.

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  TO authenticated
  USING ((select auth.uid()) = id)
  WITH CHECK (
    (select auth.uid()) = id
    AND is_admin = (
      SELECT is_admin
      FROM   public.profiles
      WHERE  id = (select auth.uid())
    )
  );


-- ── 2. passports — passports_insert_own ──────────────────────────────────────
-- Preserves the active corridor guard from migration 007 exactly.

DROP POLICY IF EXISTS "passports_insert_own" ON public.passports;

CREATE POLICY "passports_insert_own" ON public.passports
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (select auth.uid())
    AND EXISTS (
      SELECT 1
      FROM   public.corridors c
      WHERE  c.id        = passports.corridor_id
      AND    c.is_active = TRUE
    )
  );


-- ── 3. storage.objects — check_in_proofs_insert ──────────────────────────────

DROP POLICY IF EXISTS "check_in_proofs_insert" ON storage.objects;

CREATE POLICY "check_in_proofs_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'check-in-proofs' AND
    (storage.foldername(name))[1] = (select auth.uid())::text
  );


-- ── 4. storage.objects — check_in_proofs_select_own ──────────────────────────

DROP POLICY IF EXISTS "check_in_proofs_select_own" ON storage.objects;

CREATE POLICY "check_in_proofs_select_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'check-in-proofs' AND
    (storage.foldername(name))[1] = (select auth.uid())::text
  );


-- ── 5. storage.objects — check_in_proofs_delete_own ──────────────────────────

DROP POLICY IF EXISTS "check_in_proofs_delete_own" ON storage.objects;

CREATE POLICY "check_in_proofs_delete_own" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'check-in-proofs' AND
    (storage.foldername(name))[1] = (select auth.uid())::text
  );


-- ── 6. check_ins_player_view — replace bare auth.uid() in WHERE ──────────────
-- Views are not RLS policies, but the per-row re-evaluation applies equally.
-- The view is SECURITY BARRIER to prevent filter-pushdown leakage; the
-- ownership WHERE must remain the first evaluated predicate.

CREATE OR REPLACE VIEW public.check_ins_player_view
WITH (security_barrier = true)
AS
SELECT
  id,
  passport_id,
  user_id,
  node_id,
  status,
  proof_url,
  proof_storage_path,
  notes,
  admin_notes,
  reviewed_at,
  submitted_at,
  created_at
FROM public.check_ins
WHERE user_id = (select auth.uid());

-- Re-affirm grants and ownership (CREATE OR REPLACE resets them)
ALTER VIEW public.check_ins_player_view OWNER TO postgres;
GRANT SELECT ON public.check_ins_player_view TO authenticated;


-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  bare_count integer;
BEGIN
  -- Check that the rewritten policies no longer have bare auth.uid() in qual
  SELECT COUNT(*) INTO bare_count
    FROM pg_policies
   WHERE schemaname IN ('public', 'storage')
     AND policyname IN (
       'profiles_update_own',
       'passports_insert_own',
       'check_in_proofs_insert',
       'check_in_proofs_select_own',
       'check_in_proofs_delete_own'
     )
     AND (
       (qual       IS NOT NULL AND qual       LIKE '%auth.uid()%'
                                AND qual       NOT LIKE '%(select auth.uid())%')
       OR
       (with_check IS NOT NULL AND with_check LIKE '%auth.uid()%'
                                AND with_check NOT LIKE '%(select auth.uid())%')
     );

  IF bare_count > 0 THEN
    RAISE EXCEPTION '[036] VERIFICATION FAILED: % policy/ies still contain bare auth.uid()', bare_count;
  END IF;

  RAISE NOTICE '[036] OK: 5 policies wrapped with (select auth.uid()); check_ins_player_view updated';
END $$;

COMMIT;
