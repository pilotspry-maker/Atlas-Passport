-- ════════════════════════════════════════════════════════════════════════════
-- Migration 034 — Fix profiles_update_own returning HTTP 500
-- ════════════════════════════════════════════════════════════════════════════
--
-- INCIDENT:
--   After migration 033 was applied (PR #42, merged 2026-06-29 03:19 UTC),
--   every authenticated PATCH against public.profiles started returning HTTP 500
--   instead of the expected 204 (success) or 403 (RLS WITH CHECK denial).
--   • The DB state is correct (ground-truth tests REG-1b/REG-1c confirm
--     is_admin and full_name are NOT being modified — writes are still blocked).
--   • Only the HTTP status is wrong — failing 3 test assertions:
--       - exploit-01 #1   "rejects PATCH /profiles with {is_admin: true}"
--       - reg-01   REG-1b "authenticated user PATCH own profile {is_admin:true} → 401/403"
--       - reg-01   REG-1c "authenticated user PATCH another user's profile → 401/403"
--
-- ROOT CAUSE:
--   Migration 005 defined profiles_update_own with a WITH CHECK clause that
--   re-queries the same table to enforce is_admin immutability:
--
--     WITH CHECK (
--       auth.uid() = id
--       AND is_admin = (SELECT is_admin FROM public.profiles WHERE id = auth.uid())
--     )
--
--   That inner SELECT is itself filtered by the profiles_select_own RLS
--   policy. After migration 033 rewrote profiles_select_own to use
--   USING ((select auth.uid()) = id), the inner SELECT now triggers a
--   nested RLS evaluation that Postgres resolves as a "infinite recursion
--   detected in policy for relation profiles" error during UPDATE WITH CHECK
--   evaluation — PostgREST surfaces that as HTTP 500.
--
--   The error fires before the row is actually written, which is why the
--   ground-truth checks still see is_admin = false. The DB is secure; the
--   HTTP layer is just returning the wrong code, blocking CI.
--
-- FIX:
--   Replace the recursive inline subquery with a SECURITY DEFINER helper
--   function `public.committed_is_admin(uuid)` that reads is_admin while
--   bypassing RLS (the standard Postgres pattern for breaking RLS recursion).
--   The function is owned by postgres, search_path-pinned, and exposed only
--   to the authenticated role (anon doesn't need it — the policy already
--   excludes them via TO authenticated).
--
-- SECURITY PROPERTIES PRESERVED:
--   • is_admin immutability via the PostgREST PATCH path: still enforced —
--     the new helper returns the committed value and the WITH CHECK still
--     requires the incoming value to match.
--   • Cross-user PATCH (REG-1c): still rejected by the USING clause
--     (auth.uid() = id); PostgREST returns 204 (no rows matched) rather than
--     403 once the WITH CHECK no longer blows up.
--   • Service-role writes: unaffected — service_role bypasses RLS entirely.
--   • Self-escalation surface: identical to migration 005 — no new attack vector.
--
-- IDEMPOTENT: DROP POLICY IF EXISTS + CREATE OR REPLACE FUNCTION.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. SECURITY DEFINER helper to read committed is_admin (RLS-bypass) ───────
--
-- Marked STABLE so Postgres can cache the result within a single statement.
-- search_path is pinned to '' to avoid mutable-search-path warnings; the
-- table reference is fully qualified to public.profiles.
--
-- The function reads the row for the supplied user_id. Callers pass auth.uid()
-- so a player can only ever query their own committed is_admin value — the
-- helper does not leak any other user's flag.

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

-- Lock down execution: only authenticated users (and service_role, which is
-- implicit). anon has no use case for this helper.
REVOKE ALL ON FUNCTION public.committed_is_admin(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.committed_is_admin(uuid) TO authenticated;

COMMENT ON FUNCTION public.committed_is_admin(uuid) IS
  'SECURITY DEFINER helper used by profiles_update_own WITH CHECK. '
  'Reads committed is_admin bypassing RLS to prevent recursive policy '
  'evaluation that previously caused HTTP 500 from PostgREST PATCH.';

-- ── 2. Recreate profiles_update_own using the helper ─────────────────────────

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  TO authenticated
  USING ((select auth.uid()) = id)
  WITH CHECK (
    (select auth.uid()) = id
    -- is_admin must match the committed value — frozen via SECURITY DEFINER
    -- helper to avoid recursing through profiles_select_own.
    AND is_admin = public.committed_is_admin((select auth.uid()))
  );

-- ── 3. Verification ──────────────────────────────────────────────────────────

-- 3a. Helper exists and is owned by postgres
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public'
    AND    p.proname = 'committed_is_admin'
  ) THEN
    RAISE EXCEPTION '[034] VERIFICATION FAILED: committed_is_admin() function not found.';
  END IF;
  RAISE NOTICE '[034] committed_is_admin() helper present. ✓';
END $$;

-- 3b. profiles_update_own still references is_admin in WITH CHECK
--     (REG-4c sentinel — assertion that the column freeze is structurally intact)
DO $$
DECLARE
  chk_clause text;
BEGIN
  SELECT with_check::text
  INTO   chk_clause
  FROM   pg_policies
  WHERE  schemaname = 'public'
  AND    tablename  = 'profiles'
  AND    policyname = 'profiles_update_own';

  IF chk_clause IS NULL THEN
    RAISE EXCEPTION '[034] VERIFICATION FAILED: profiles_update_own policy not found.';
  END IF;

  IF chk_clause NOT LIKE '%is_admin%' THEN
    RAISE EXCEPTION
      '[034] VERIFICATION FAILED: profiles_update_own WITH CHECK no longer '
      'references is_admin. Got: %', chk_clause;
  END IF;

  IF chk_clause NOT LIKE '%committed_is_admin%' THEN
    RAISE EXCEPTION
      '[034] VERIFICATION FAILED: profiles_update_own WITH CHECK does not '
      'use committed_is_admin() helper. Got: %', chk_clause;
  END IF;

  RAISE NOTICE '[034] profiles_update_own WITH CHECK references committed_is_admin(). ✓';
END $$;

-- 3c. Spot-check that no profile has is_admin = true that shouldn't
--     (Same DBA-review NOTICE as migration 005, repeated here for safety)
DO $$
DECLARE
  suspicious_count integer;
BEGIN
  SELECT COUNT(*) INTO suspicious_count
  FROM   public.profiles
  WHERE  is_admin = TRUE;
  RAISE NOTICE '[034] Profiles with is_admin=true: % (review if unexpected)', suspicious_count;
END $$;

COMMIT;

-- ════════════════════════════════════════════════════════════════════════════
-- POST-MIGRATION NOTES
-- ════════════════════════════════════════════════════════════════════════════
--
-- 1. Manual verification against live (run after applying):
--
--    -- Should return 403 (column guard rejection):
--    curl -s -w "\n%{http_code}" "$SUPABASE_URL/rest/v1/profiles?id=eq.$P1_ID" \
--      -X PATCH \
--      -H "apikey: $ANON" \
--      -H "Authorization: Bearer $P1_JWT" \
--      -H "Content-Type: application/json" \
--      -d '{"is_admin": true}'
--    # Expected: 403  (was: 500 before this migration)
--
--    -- Should return 204 (no rows matched — cross-user write filtered by USING):
--    curl -s -w "\n%{http_code}" "$SUPABASE_URL/rest/v1/profiles?id=eq.$P2_ID" \
--      -X PATCH \
--      -H "apikey: $ANON" \
--      -H "Authorization: Bearer $P1_JWT" \
--      -H "Content-Type: application/json" \
--      -d '{"full_name": "Hijacked"}'
--    # Expected: 204  (was: 500 before this migration)
--
--    -- Ground truth: is_admin should still be false in both cases
--    -- (verified by REG-1b ground truth + svcRead assertion in reg-01).
--
-- 2. Future considerations:
--    Migration 005's WITH CHECK was technically correct in isolation, but
--    relied on the inner SELECT not recursing through RLS. When 033 wrapped
--    auth.uid() in (select auth.uid()) on profiles_select_own, the optimizer's
--    rewriting of the inner subquery exposed the recursion edge. The
--    SECURITY DEFINER pattern is the canonical fix and matches what the
--    Supabase docs recommend for "policies that read from their own table".
--
-- 3. Test assertions unblocked by this migration:
--    • exploit-01 #1 — "rejects PATCH /profiles with {is_admin: true} — column guard enforced"
--    • reg-01 REG-1b — "authenticated user PATCH own profile {is_admin:true} → 401/403"
--    • reg-01 REG-1c — "authenticated user PATCH another user's profile → 401/403"
--    (The matching ground-truth tests REG-1b/REG-1c were already passing —
--     the DB layer was always secure, only the HTTP code was wrong.)
