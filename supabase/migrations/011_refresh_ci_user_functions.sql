-- ════════════════════════════════════════════════════════════════════════════
-- Migration 011 — refresh CI user helper functions (force production update)
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   Migrations 008 and 009 were first applied to the production database before
--   the token-column and auth.identities fixes landed. Because Supabase runs
--   each numbered migration exactly once, editing 008/009 on disk does not
--   update the stored functions in production.
--
--   This migration forces CREATE OR REPLACE FUNCTION for both helpers with the
--   definitive correct body so the production database picks up all fixes in
--   one idempotent run:
--     • All 6 token columns explicitly set to '' in every INSERT INTO auth.users
--     • Defensive COALESCE UPDATE immediately after INSERT (GoTrue v2 safety)
--     • auth.identities rows inserted for GoTrue email/password sign-in
--     • DELETE identities before DELETE users (FK order)
--     • SECURITY DEFINER + search_path includes extensions (crypt/gen_salt)
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. create_test_users (exploit-suite: ci_player / ci_admin) ──────────────

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
  -- Table alias required: RETURNS TABLE(user_id uuid,...) creates a PL/pgSQL
  -- output variable named user_id; without the alias, WHERE user_id IN (...)
  -- is ambiguous between the variable and the column (error 42702).
  DELETE FROM auth.identities AS ai
  WHERE ai.user_id IN (
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
    created_at, updated_at, is_super_admin, is_sso_user, deleted_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change_token_current, reauthentication_token, phone_change_token
  ) VALUES
  (
    'aaaaaaaa-0001-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_player@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', ''
  ),
  (
    'aaaaaaaa-0002-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_admin@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"is_admin":true}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', ''
  );

  -- Defensive NULL-token patch: GoTrue v2 scans these into non-nullable Go
  -- strings; NULL causes 500 "Database error querying schema" on every sign-in.
  UPDATE auth.users SET
    confirmation_token         = COALESCE(confirmation_token, ''),
    recovery_token             = COALESCE(recovery_token, ''),
    email_change_token_new     = COALESCE(email_change_token_new, ''),
    email_change_token_current = COALESCE(email_change_token_current, ''),
    reauthentication_token     = COALESCE(reauthentication_token, ''),
    phone_change_token         = COALESCE(phone_change_token, '')
  WHERE id IN (
    'aaaaaaaa-0001-0000-0000-000000000000'::uuid,
    'aaaaaaaa-0002-0000-0000-000000000000'::uuid
  );

  -- GoTrue v2 requires an auth.identities row for email/password sign-in.
  -- id = user UUID as text; provider_id = same UUID text (GoTrue v2 convention).
  -- DO NOT include `email` column — GENERATED ALWAYS AS (lower(identity_data->>'email')).
  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES
  (
    'aaaaaaaa-0001-0000-0000-000000000000',
    'aaaaaaaa-0001-0000-0000-000000000000'::uuid,
    'aaaaaaaa-0001-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'aaaaaaaa-0001-0000-0000-000000000000',
      'ci_player@test.local')::jsonb,
    'email', v_now, v_now, v_now
  ),
  (
    'aaaaaaaa-0002-0000-0000-000000000000',
    'aaaaaaaa-0002-0000-0000-000000000000'::uuid,
    'aaaaaaaa-0002-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'aaaaaaaa-0002-0000-0000-000000000000',
      'ci_admin@test.local')::jsonb,
    'email', v_now, v_now, v_now
  );

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

-- ── 2. create_regression_users (regression-suite: reg_player_one/two) ────────

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
    created_at, updated_at, is_super_admin, is_sso_user, deleted_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change_token_current, reauthentication_token, phone_change_token
  ) VALUES
  (
    'bbbbbbbb-0001-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_one@test.atlasci.com',
    crypt('RegPlayer1!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"CI Regression Player One"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', ''
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_two@test.atlasci.com',
    crypt('RegPlayer2!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"CI Regression Player Two"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', ''
  );

  -- Defensive NULL-token patch (same guard as create_test_users).
  UPDATE auth.users SET
    confirmation_token         = COALESCE(confirmation_token, ''),
    recovery_token             = COALESCE(recovery_token, ''),
    email_change_token_new     = COALESCE(email_change_token_new, ''),
    email_change_token_current = COALESCE(email_change_token_current, ''),
    reauthentication_token     = COALESCE(reauthentication_token, ''),
    phone_change_token         = COALESCE(phone_change_token, '')
  WHERE id IN (
    'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0002-0000-0000-000000000000'::uuid
  );

  -- GoTrue v2 requires auth.identities for email/password sign-in.
  -- DO NOT include `email` column — GENERATED ALWAYS AS (lower(identity_data->>'email')).
  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES
  (
    'bbbbbbbb-0001-0000-0000-000000000000',
    'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0001-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'bbbbbbbb-0001-0000-0000-000000000000',
      'reg_player_one@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000000',
    'bbbbbbbb-0002-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0002-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'bbbbbbbb-0002-0000-0000-000000000000',
      'reg_player_two@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
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
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_test_users'
  ) THEN
    RAISE EXCEPTION '[011] VERIFICATION FAILED: create_test_users not found.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_regression_users'
  ) THEN
    RAISE EXCEPTION '[011] VERIFICATION FAILED: create_regression_users not found.';
  END IF;

  RAISE NOTICE '[011] create_test_users + create_regression_users refreshed with token-column fix. ✓';
END;
$$;
