-- ============================================================
-- Migration: 006_test_helpers.sql
-- Atlas Passport · Relevant Artist
-- Applied: 2026-06-23
--
-- Purpose:
--   Provide a SECURITY DEFINER helper that CI workflows can call
--   via the PostgREST RPC endpoint (/rest/v1/rpc/confirm_test_users)
--   to confirm test user accounts without requiring a JWT-format
--   service-role key.
--
--   Security model:
--     • The function is callable by the 'anon' role (public) ONLY when
--       the calling email matches the hardcoded CI test user allow-list.
--     • It confirms ONLY the six designated CI test accounts.
--     • Attempting to confirm any other email raises an exception.
--     • The function has no effect in production if those emails never
--       sign up (they exist only in the CI fixture seeder).
--
--   All statements are idempotent.
-- ============================================================

-- Drop first to avoid 42P13 (cannot change return type of existing function)
DROP FUNCTION IF EXISTS public.confirm_test_users(TEXT);

CREATE OR REPLACE FUNCTION public.confirm_test_users(user_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
DECLARE
  allowed_emails TEXT[] := ARRAY[
    'player_one_rls@test.atlasci.com',
    'player_two_rls@test.atlasci.com',
    'ci_player@test.local',
    'ci_admin@test.local',
    'reg_player_one@test.atlasci.com',
    'reg_player_two@test.atlasci.com'
  ];
  affected_count INTEGER;
BEGIN
  -- Guard: only allow the CI test accounts
  IF NOT (user_email = ANY(allowed_emails)) THEN
    RAISE EXCEPTION
      'confirm_test_users: email % is not in the CI test allow-list', user_email
      USING ERRCODE = '42501';  -- insufficient_privilege
  END IF;

  -- Confirm the user by setting email_confirmed_at.
  -- NOTE: confirmed_at is a GENERATED ALWAYS column in GoTrue v2 — do NOT write it.
  -- Setting email_confirmed_at is sufficient; GoTrue computes confirmed_at automatically.
  UPDATE auth.users
  SET
    email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
    updated_at         = NOW()
  WHERE email = user_email;

  GET DIAGNOSTICS affected_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'email',    user_email,
    'updated',  affected_count,
    'status',   CASE WHEN affected_count > 0 THEN 'confirmed' ELSE 'not_found' END
  );
END;
$$;

-- Grant execute to the anon role so the test seeder can call it via RPC
-- without needing any JWT (the function itself validates the allow-list)
GRANT EXECUTE ON FUNCTION public.confirm_test_users(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.confirm_test_users(TEXT) TO authenticated;

-- ── VERIFY ────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'confirm_test_users'
  ) THEN
    RAISE EXCEPTION '[006] VERIFICATION FAILED: confirm_test_users function not found.';
  END IF;
  RAISE NOTICE '[006] confirm_test_users: present. ✓';
END $$;
