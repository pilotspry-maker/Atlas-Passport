-- ════════════════════════════════════════════════════════════════════════════
-- Migration 008 — create_test_users + create_regression_users helpers
-- ════════════════════════════════════════════════════════════════════════════
--
-- Contains two SECURITY DEFINER helper functions called by CI workflows:
--
--   create_test_users       — seeds exploit-suite users (ci_player / ci_admin)
--   create_regression_users — seeds regression-suite users (reg_player_one/two)
--
-- Design invariants:
--   - Fixed UUIDs so DELETE-by-UUID is reliable across runs
--   - DELETE auth.identities by user_id first (FK order), then DELETE auth.users
--   - INSERT both auth.users AND auth.identities
--     GoTrue v2 requires an auth.identities row (provider='email') for every
--     user that signs in with email/password.  Direct auth.users INSERT without
--     a corresponding auth.identities row causes GoTrue to return:
--       500 "Database error querying schema"
--     on every sign-in attempt for that user.
--   - No ON CONFLICT clause — surfaces real conflicts as hard errors
--   - No confirmed_at write (GoTrue v2 GENERATED ALWAYS column — cannot be set)
--   - auth.identities.email is also GENERATED ALWAYS — not included in INSERT
--   - SET search_path includes extensions so crypt/gen_salt resolve
--   - auth.identities.id = user UUID as text; provider_id = same UUID text
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. create_test_users ─────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.create_test_users();

CREATE OR REPLACE FUNCTION public.create_test_users()
RETURNS TABLE(user_id uuid, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  v_now timestamptz := now();
BEGIN
  -- Delete identities first (FK order), then users.
  DELETE FROM auth.identities
  WHERE user_id IN (
    'aaaaaaaa-0001-0000-0000-000000000000'::uuid,
    'aaaaaaaa-0002-0000-0000-000000000000'::uuid
  );

  DELETE FROM auth.users
  WHERE id IN (
    'aaaaaaaa-0001-0000-0000-000000000000'::uuid,
    'aaaaaaaa-0002-0000-0000-000000000000'::uuid
  );

  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, is_super_admin, is_sso_user, deleted_at
  ) VALUES
  (
    'aaaaaaaa-0001-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_player@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    v_now, v_now, false, false, NULL
  ),
  (
    'aaaaaaaa-0002-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_admin@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"is_admin":true}'::jsonb,
    v_now, v_now, false, false, NULL
  );

  -- GoTrue v2 requires an auth.identities row for email/password sign-in.
  -- id = user UUID as text; provider_id = same UUID text (GoTrue v2 convention).
  -- DO NOT include `email` column — it is GENERATED ALWAYS AS
  -- (lower(identity_data->>'email')) STORED.
  INSERT INTO auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES
  (
    'aaaaaaaa-0001-0000-0000-000000000000',
    'aaaaaaaa-0001-0000-0000-000000000000'::uuid,
    'aaaaaaaa-0001-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'aaaaaaaa-0001-0000-0000-000000000000',
      'ci_player@test.local')::jsonb,
    'email',
    v_now,
    v_now,
    v_now
  ),
  (
    'aaaaaaaa-0002-0000-0000-000000000000',
    'aaaaaaaa-0002-0000-0000-000000000000'::uuid,
    'aaaaaaaa-0002-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'aaaaaaaa-0002-0000-0000-000000000000',
      'ci_admin@test.local')::jsonb,
    'email',
    v_now,
    v_now,
    v_now
  );

  -- Return by UUID (not by email) to avoid stale-email lookup race
  RETURN QUERY
    SELECT u.id, u.email::text FROM auth.users u
    WHERE u.id IN (
      'aaaaaaaa-0001-0000-0000-000000000000'::uuid,
      'aaaaaaaa-0002-0000-0000-000000000000'::uuid
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_test_users() TO anon;
GRANT EXECUTE ON FUNCTION public.create_test_users() TO authenticated;

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_test_users'
  ) THEN
    RAISE EXCEPTION '[008] VERIFICATION FAILED: create_test_users function not found.';
  END IF;
  RAISE NOTICE '[008] create_test_users: present. ✓';
END;
$$;

-- ── 2. create_regression_users ───────────────────────────────────────────────

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
  -- Delete identities first (FK order), then users.
  DELETE FROM auth.identities
  WHERE user_id IN (
    'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0002-0000-0000-000000000000'::uuid
  );

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

  -- GoTrue v2 requires auth.identities for email/password sign-in.
  -- id = user UUID as text; provider_id = same UUID text.
  -- DO NOT include `email` column — it is GENERATED ALWAYS AS
  -- (lower(identity_data->>'email')) STORED.
  INSERT INTO auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES
  (
    'bbbbbbbb-0001-0000-0000-000000000000',
    'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0001-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'bbbbbbbb-0001-0000-0000-000000000000',
      'reg_player_one@test.atlasci.com')::jsonb,
    'email',
    v_now,
    v_now,
    v_now
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000000',
    'bbbbbbbb-0002-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0002-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'bbbbbbbb-0002-0000-0000-000000000000',
      'reg_player_two@test.atlasci.com')::jsonb,
    'email',
    v_now,
    v_now,
    v_now
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
    RAISE EXCEPTION '[008] VERIFICATION FAILED: create_regression_users function not found.';
  END IF;
  RAISE NOTICE '[008] create_regression_users: present. ✓';
END;
$$;
