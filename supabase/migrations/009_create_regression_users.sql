-- ════════════════════════════════════════════════════════════════════════════
-- Migration 009 — create_regression_users helper
-- ════════════════════════════════════════════════════════════════════════════
--
-- Mirrors migration 008 (create_test_users) but seeds the RLS regression
-- suite users (reg_player_one / reg_player_two) so the regression suite
-- does not collide with the exploit suite's fixtures.
--
-- Same design principles as 008:
--   - Fixed UUIDs so DELETE-by-UUID is reliable across runs
--   - DELETE by UUID before INSERT (not by email) to clear stale rows
--   - No ON CONFLICT clause — surfaces real conflicts as hard errors
--   - No confirmed_at (GoTrue v2 generated column — cannot be set)
--   - SET search_path includes extensions so crypt/gen_salt resolve
-- ════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_regression_users();

CREATE OR REPLACE FUNCTION public.create_regression_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
BEGIN
  -- Delete by UUID (not by email) — removes stale rows regardless of email
  DELETE FROM auth.users
  WHERE id IN (
    'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0002-0000-0000-000000000000'::uuid
  );

  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, is_super_admin, is_sso_user, deleted_at
  ) VALUES
  (
    'bbbbbbbb-0001-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_one@test.atlasci.com',
    crypt('RegPlayer1!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"CI Regression Player One"}'::jsonb,
    v_now, v_now, false, false, NULL
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_two@test.atlasci.com',
    crypt('RegPlayer2!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"CI Regression Player Two"}'::jsonb,
    v_now, v_now, false, false, NULL
  );

  RETURN jsonb_build_object(
    'reg_player_one_id', 'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'reg_player_two_id', 'bbbbbbbb-0002-0000-0000-000000000000'::uuid,
    'status', 'ok'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_regression_users() TO anon;
GRANT EXECUTE ON FUNCTION public.create_regression_users() TO authenticated;

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_regression_users'
  ) THEN
    RAISE EXCEPTION '[009] VERIFICATION FAILED: create_regression_users function not found.';
  END IF;
  RAISE NOTICE '[009] create_regression_users: present. ✓';
END;
$$;
