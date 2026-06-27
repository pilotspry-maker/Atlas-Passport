-- ════════════════════════════════════════════════════════════════════════════
-- Migration 014 — comprehensive NULL fix for CI user helpers
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   Migrations 011–013 fixed specific nullable text columns (token columns,
--   email_change, phone, phone_change) one at a time, but "Database error
--   querying schema" from GoTrue on sign-in persisted. The root column is
--   schema-version-dependent — different Supabase deployments may have
--   different defaults on auth.users text columns.
--
--   This migration supersedes the per-column guessing with a dynamic loop
--   that sets EVERY nullable text/varchar column in auth.users to '' for CI
--   users immediately after INSERT. This is safe: GoTrue treats '' and NULL
--   identically for optional fields, and non-optional fields already have
--   NOT NULL constraints or defaults.
--
--   A RAISE NOTICE line reports which columns were actually fixed, giving
--   visible proof when applied in the SQL Editor.
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
  v_now      timestamptz := now();
  v_col      text;
  v_fixed    text[] := '{}';
BEGIN

  -- ── Clean slate ──────────────────────────────────────────────────────────
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

  -- ── Insert users with all known token columns explicit ───────────────────
  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, is_super_admin, is_sso_user, deleted_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change_token_current, reauthentication_token, phone_change_token,
    phone, email_change, phone_change
  ) VALUES
  (
    'aaaaaaaa-0001-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_player@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    '', '', ''
  ),
  (
    'aaaaaaaa-0002-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_admin@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"is_admin":true}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    '', '', ''
  );

  -- ── Dynamic comprehensive NULL fix ───────────────────────────────────────
  -- Iterates every nullable text/varchar column in auth.users and sets it to
  -- '' for our CI users if it is still NULL after the INSERT above.
  -- This catches any column added in newer GoTrue versions that we don't
  -- enumerate explicitly.
  FOR v_col IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'auth'
      AND table_name   = 'users'
      AND data_type IN ('character varying', 'text')
      AND is_nullable  = 'YES'
    ORDER BY ordinal_position
  LOOP
    BEGIN
      EXECUTE format(
        $sql$
          UPDATE auth.users
          SET    %I = ''
          WHERE  id IN (
            'aaaaaaaa-0001-0000-0000-000000000000'::uuid,
            'aaaaaaaa-0002-0000-0000-000000000000'::uuid
          )
          AND %I IS NULL
        $sql$,
        v_col, v_col
      );
      IF FOUND THEN
        v_fixed := v_fixed || v_col;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL; -- skip generated-always or read-only columns
    END;
  END LOOP;

  IF array_length(v_fixed, 1) > 0 THEN
    RAISE NOTICE '[014] Columns fixed to '''' for ci users: %', v_fixed;
  ELSE
    RAISE NOTICE '[014] No NULL text columns found — all columns already set.';
  END IF;

  -- ── auth.identities rows ─────────────────────────────────────────────────
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

REVOKE EXECUTE ON FUNCTION public.create_test_users() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_test_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_test_users() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.create_test_users() TO service_role;

-- ── 2. create_regression_users ───────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.create_regression_users();

CREATE OR REPLACE FUNCTION public.create_regression_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  v_now      TIMESTAMPTZ := now();
  v_col      text;
  v_fixed    text[] := '{}';
BEGIN

  -- ── Clean slate ──────────────────────────────────────────────────────────
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

  -- ── Insert users ─────────────────────────────────────────────────────────
  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, is_super_admin, is_sso_user, deleted_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change_token_current, reauthentication_token, phone_change_token,
    phone, email_change, phone_change
  ) VALUES
  (
    'bbbbbbbb-0001-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_one@test.atlasci.com',
    crypt('RegPlayer1!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"CI Regression Player One"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    '', '', ''
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_two@test.atlasci.com',
    crypt('RegPlayer2!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"CI Regression Player Two"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    '', '', ''
  );

  -- ── Dynamic comprehensive NULL fix ───────────────────────────────────────
  FOR v_col IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'auth'
      AND table_name   = 'users'
      AND data_type IN ('character varying', 'text')
      AND is_nullable  = 'YES'
    ORDER BY ordinal_position
  LOOP
    BEGIN
      EXECUTE format(
        $sql$
          UPDATE auth.users
          SET    %I = ''
          WHERE  id IN (
            'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
            'bbbbbbbb-0002-0000-0000-000000000000'::uuid
          )
          AND %I IS NULL
        $sql$,
        v_col, v_col
      );
      IF FOUND THEN
        v_fixed := v_fixed || v_col;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;

  IF array_length(v_fixed, 1) > 0 THEN
    RAISE NOTICE '[014] Columns fixed to '''' for regression users: %', v_fixed;
  ELSE
    RAISE NOTICE '[014] No NULL text columns found — all columns already set.';
  END IF;

  -- ── auth.identities rows ─────────────────────────────────────────────────
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

REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.create_regression_users() TO service_role;

DO $$
BEGIN
  RAISE NOTICE '[014] create_test_users + create_regression_users updated with comprehensive dynamic NULL fix. ✓';
  RAISE NOTICE '[014] When run, NOTICE lines above will show which columns were patched.';
END;
$$;
