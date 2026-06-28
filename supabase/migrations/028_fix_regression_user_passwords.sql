-- 028: fix regression user passwords to match test client expectations
--
-- Background: migration 014 originally provisioned reg_player_one/two with
-- passwords RegPlayer1!RLS / RegPlayer2!RLS, which is what
-- tests/rls/regression/regression.client.ts (lines 53-57) signs in with.
-- Migration 024 churned those passwords to TestRegression1!/TestRegression2!
-- while doing the dynamic NULL backfill, which broke the regression suite
-- with 400 invalid_credentials on signIn.
--
-- This migration:
--   1. Rebuilds public.create_regression_users() with the correct password
--      literals (otherwise identical body to migration 024) so fresh CI
--      runs from a clean DB do the right thing.
--   2. Resets the bcrypt hashes on any currently-deployed auth.users rows
--      so the live prod DB signs in again without waiting for a re-run.
--
-- Idempotent: CREATE OR REPLACE handles the RPC, UPDATEs are safe to
-- re-run, and the RPC itself is DELETE-then-INSERT.

-- ── 1. Rebuild create_regression_users with correct passwords ────────────────
-- Note: return type changes from migration 024's TABLE(user_id, email) to
-- jsonb. The only caller (tests/rls/regression/regression.setup.ts) discards
-- the return value, so this is safe.
DROP FUNCTION IF EXISTS public.create_regression_users();

CREATE OR REPLACE FUNCTION public.create_regression_users()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  P1_ID UUID := 'bbbbbbbb-0001-0000-0000-000000000000';
  P2_ID UUID := 'bbbbbbbb-0002-0000-0000-000000000000';
  v_now TIMESTAMPTZ := now();
  v_col TEXT;
BEGIN
  DELETE FROM auth.identities WHERE user_id IN (P1_ID, P2_ID);
  DELETE FROM auth.users      WHERE id      IN (P1_ID, P2_ID);

  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    is_super_admin, is_sso_user, deleted_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change_token_current, reauthentication_token, phone_change_token,
    phone, email_change, phone_change
  ) VALUES
  (
    P1_ID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_one@test.atlasci.com',
    crypt('RegPlayer1!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Regression Player One"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    NULL, '', ''
  ),
  (
    P2_ID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_two@test.atlasci.com',
    crypt('RegPlayer2!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Regression Player Two"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    NULL, '', ''
  );

  -- Dynamic NULL backfill on every nullable text column except phone
  -- (the only column with a UNIQUE constraint). phone_change has no
  -- unique constraint, so we MUST set it to '' or GoTrue's list-users
  -- SELECT throws sql: Scan error on column index 22.
  FOR v_col IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'auth'
      AND table_name   = 'users'
      AND data_type IN ('character varying', 'text')
      AND is_nullable  = 'YES'
      AND column_name <> 'phone'
    ORDER BY ordinal_position
  LOOP
    BEGIN
      EXECUTE format(
        $sql$
          UPDATE auth.users
          SET    %I = ''
          WHERE  id IN (%L::uuid, %L::uuid)
          AND    %I IS NULL
        $sql$,
        v_col, P1_ID, P2_ID, v_col
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;

  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES
  (
    P1_ID, P1_ID, P1_ID::text,
    format('{"sub":"%s","email":"%s"}', P1_ID::text, 'reg_player_one@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
  ),
  (
    P2_ID, P2_ID, P2_ID::text,
    format('{"sub":"%s","email":"%s"}', P2_ID::text, 'reg_player_two@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
  );

  INSERT INTO public.profiles (id, email, full_name, is_admin)
  VALUES
    (P1_ID, 'reg_player_one@test.atlasci.com', 'Regression Player One', false),
    (P2_ID, 'reg_player_two@test.atlasci.com', 'Regression Player Two', false)
  ON CONFLICT (id) DO NOTHING;

  RETURN jsonb_build_object(
    'p1_id', P1_ID,
    'p2_id', P2_ID,
    'migration', '028'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.create_regression_users() TO service_role;

-- ── 2. Reset live passwords on any existing reg user rows ────────────────────
-- Safe no-op if the rows don't exist; harmless re-hash if they do.
UPDATE auth.users
   SET encrypted_password = crypt('RegPlayer1!RLS', gen_salt('bf')),
       updated_at         = v_now_outer
  FROM (SELECT now() AS v_now_outer) t
 WHERE auth.users.id = 'bbbbbbbb-0001-0000-0000-000000000000'::uuid;

UPDATE auth.users
   SET encrypted_password = crypt('RegPlayer2!RLS', gen_salt('bf')),
       updated_at         = v_now_outer
  FROM (SELECT now() AS v_now_outer) t
 WHERE auth.users.id = 'bbbbbbbb-0002-0000-0000-000000000000'::uuid;
