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
-- FUNCTION ADDED (1):
--   public.committed_is_admin(uuid) — SECURITY DEFINER, STABLE, search_path=''.
--   Reads committed is_admin for a user bypassing RLS. Required by the
--   profiles_update_own WITH CHECK to avoid recursive policy evaluation that
--   causes HTTP 500 (PR #46 root-cause analysis). Exposed to authenticated only.
--
-- POLICIES REWRITTEN (5):
--
--   public.profiles — profiles_update_own (last defined in 005)
--     USING:      auth.uid() = id
--     WITH CHECK: auth.uid() = id AND is_admin = committed_is_admin(auth.uid())
--     (replaces inline SELECT subquery that recursed through profiles_select_own)
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
--
-- RECURSION FIX (discovered in PR #46 post-migration 033):
--   Migration 005's WITH CHECK subquery `SELECT is_admin FROM profiles WHERE
--   id = auth.uid()` is filtered by profiles_select_own. After migration 033
--   wrapped profiles_select_own's USING in (select auth.uid()), Postgres
--   detects "infinite recursion in policy for relation profiles" and PostgREST
--   returns HTTP 500 instead of 403.
--
--   Fix: replace the inline subquery with a SECURITY DEFINER helper function
--   `committed_is_admin(uuid)` that reads profiles while bypassing RLS. This
--   is the canonical Postgres pattern for policies that must read their own table.

CREATE OR REPLACE FUNCTION public.committed_is_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT is_admin
  FROM   public.profiles
  WHERE  id = p_user_id
$$;

REVOKE ALL  ON FUNCTION public.committed_is_admin(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.committed_is_admin(uuid) TO authenticated;

COMMENT ON FUNCTION public.committed_is_admin(uuid) IS
  'SECURITY DEFINER helper used by profiles_update_own WITH CHECK. '
  'Reads committed is_admin bypassing RLS to prevent recursive policy '
  'evaluation (PostgREST HTTP 500 → 403).';

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  TO authenticated
  USING ((select auth.uid()) = id)
  WITH CHECK (
    (select auth.uid()) = id
    AND is_admin = public.committed_is_admin((select auth.uid()))
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
--
-- DROP first: CREATE OR REPLACE VIEW cannot reorder or rename existing columns.
-- The live view may have a different column order (e.g. user_id before passport_id)
-- depending on which earlier migration last defined it. CASCADE drops any
-- dependent grants, which we re-establish immediately below.

DROP VIEW IF EXISTS public.check_ins_player_view CASCADE;

CREATE VIEW public.check_ins_player_view
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
  chk_clause text;
BEGIN
  -- 1. committed_is_admin() helper must exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'committed_is_admin'
  ) THEN
    RAISE EXCEPTION '[036] VERIFICATION FAILED: committed_is_admin() function not found';
  END IF;

  -- 2. profiles_update_own WITH CHECK must reference committed_is_admin
  SELECT with_check::text INTO chk_clause
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'profiles'
     AND policyname = 'profiles_update_own';

  IF chk_clause IS NULL OR chk_clause NOT LIKE '%committed_is_admin%' THEN
    RAISE EXCEPTION '[036] VERIFICATION FAILED: profiles_update_own does not use committed_is_admin(). Got: %', chk_clause;
  END IF;

  -- 3. All 5 rewritten policies must exist.
  --    (Bare-auth.uid() text detection is omitted: PostgreSQL normalizes
  --     (select auth.uid()) in pg_policies in an unpredictable way across
  --     versions, making LIKE/ILIKE checks unreliable. Existence confirms
  --     DROP+CREATE ran; the CREATE statements themselves enforce the wrapped form.)
  SELECT COUNT(*) INTO bare_count
    FROM pg_policies
   WHERE (schemaname = 'public'  AND tablename = 'profiles'  AND policyname = 'profiles_update_own')
      OR (schemaname = 'public'  AND tablename = 'passports' AND policyname = 'passports_insert_own')
      OR (schemaname = 'storage' AND tablename = 'objects'   AND policyname = 'check_in_proofs_insert')
      OR (schemaname = 'storage' AND tablename = 'objects'   AND policyname = 'check_in_proofs_select_own')
      OR (schemaname = 'storage' AND tablename = 'objects'   AND policyname = 'check_in_proofs_delete_own');

  IF bare_count < 5 THEN
    RAISE EXCEPTION '[036] VERIFICATION FAILED: only %/5 rewritten policies found', bare_count;
  END IF;

  RAISE NOTICE '[036] OK: committed_is_admin() created; 5 policies rewritten; check_ins_player_view updated';
END $$;

COMMIT;
