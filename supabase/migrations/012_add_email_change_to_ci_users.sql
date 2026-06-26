-- ════════════════════════════════════════════════════════════════════════════
-- Migration 012 — add email_change + phone to CI user INSERT (GoTrue fix)
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   GoTrue v2 maps auth.users.email_change → EmailChange (plain string, not
--   nullable). The auth schema defines email_change as VARCHAR(255) with no
--   DEFAULT and no NOT NULL, so our INSERT (which omits it) leaves it NULL.
--   GoTrue scans NULL → string → scan error → 500 "Database error querying
--   schema" on every sign-in attempt for directly-inserted CI users.
--
--   Similarly, phone TEXT DEFAULT NULL may cause scan issues on some GoTrue
--   versions depending on whether Phone is mapped as string vs NullString.
--
--   This migration adds email_change='' and phone='' to both function INSERTs
--   and extends the COALESCE guard to cover them.
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
    email_change_token_current, reauthentication_token, phone_change_token,
    phone, email_change
  ) VALUES
  (
    'aaaaaaaa-0001-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_player@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    '', ''
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
    '', ''
  );

  UPDATE auth.users SET
    confirmation_token         = COALESCE(confirmation_token, ''),
    recovery_token             = COALESCE(recovery_token, ''),
    email_change_token_new     = COALESCE(email_change_token_new, ''),
    email_change_token_current = COALESCE(email_change_token_current, ''),
    reauthentication_token     = COALESCE(reauthentication_token, ''),
    phone_change_token         = COALESCE(phone_change_token, ''),
    phone                      = COALESCE(phone, ''),
    email_change               = COALESCE(email_change, '')
  WHERE id IN (
    'aaaaaaaa-0001-0000-0000-000000000000'::uuid,
    'aaaaaaaa-0002-0000-0000-000000000000'::uuid
  );

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
  v_now TIMESTAMPTZ := now();
BEGIN
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
    email_change_token_current, reauthentication_token, phone_change_token,
    phone, email_change
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
    '', ''
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
    '', ''
  );

  UPDATE auth.users SET
    confirmation_token         = COALESCE(confirmation_token, ''),
    recovery_token             = COALESCE(recovery_token, ''),
    email_change_token_new     = COALESCE(email_change_token_new, ''),
    email_change_token_current = COALESCE(email_change_token_current, ''),
    reauthentication_token     = COALESCE(reauthentication_token, ''),
    phone_change_token         = COALESCE(phone_change_token, ''),
    phone                      = COALESCE(phone, ''),
    email_change               = COALESCE(email_change, '')
  WHERE id IN (
    'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0002-0000-0000-000000000000'::uuid
  );

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
  RAISE NOTICE '[012] create_test_users + create_regression_users updated with email_change + phone fix. ✓';
END;
$$;
