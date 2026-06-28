-- Migration 021 — Fix seed phone-collision in create_exploit_test_users
-- Recovered from production schema_migrations on 2026-06-27

DROP FUNCTION IF EXISTS public.create_exploit_test_users();

CREATE OR REPLACE FUNCTION public.create_exploit_test_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  v_now   TIMESTAMPTZ := now();
  v_col   text;
  v_fixed text[] := '{}';
  P1_ID   UUID := 'aaaaaaaa-0011-0000-0000-000000000000';
  P2_ID   UUID := 'aaaaaaaa-0022-0000-0000-000000000000';
BEGIN
  DELETE FROM auth.identities WHERE user_id IN (P1_ID, P2_ID);
  DELETE FROM auth.users      WHERE id      IN (P1_ID, P2_ID);

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
    P1_ID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'player_one_rls@test.atlasci.com',
    crypt('TestPlayer1!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"RLS Exploit Player One"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    NULL, '', NULL
  ),
  (
    P2_ID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'player_two_rls@test.atlasci.com',
    crypt('TestPlayer2!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"RLS Exploit Player Two"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    NULL, '', NULL
  );

  FOR v_col IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'auth'
      AND table_name   = 'users'
      AND data_type IN ('character varying', 'text')
      AND is_nullable  = 'YES'
      AND column_name NOT IN ('phone', 'phone_change')
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
      IF FOUND THEN
        v_fixed := v_fixed || v_col;
      END IF;
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
    format('{"sub":"%s","email":"%s"}', P1_ID::text, 'player_one_rls@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
  ),
  (
    P2_ID, P2_ID, P2_ID::text,
    format('{"sub":"%s","email":"%s"}', P2_ID::text, 'player_two_rls@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
  );

  INSERT INTO public.profiles (id, email, full_name, is_admin)
  VALUES
    (P1_ID, 'player_one_rls@test.atlasci.com', 'RLS Exploit Player One', false),
    (P2_ID, 'player_two_rls@test.atlasci.com', 'RLS Exploit Player Two', false)
  ON CONFLICT (id) DO UPDATE SET
    email     = EXCLUDED.email,
    full_name = EXCLUDED.full_name;

  RETURN jsonb_build_object(
    'player_one_rls_id', P1_ID,
    'player_two_rls_id', P2_ID,
    'status', 'ok',
    'migration', '021'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_exploit_test_users() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_exploit_test_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_exploit_test_users() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.create_exploit_test_users() TO service_role;
