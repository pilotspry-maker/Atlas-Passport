-- ════════════════════════════════════════════════════════════════════════════
-- Migration 029 — Extend regression-user Clean slate to public child rows
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   create_regression_users() deletes auth.users for the two regression-test
--   UUIDs (bbbbbbbb-0001-... and bbbbbbbb-0002-...).  Deleting auth.users
--   cascades to public.profiles (via profiles.id ON DELETE CASCADE).  However:
--
--       public.check_ins.user_id  → public.profiles.id  (NO ON DELETE action)
--       public.passports.user_id  → public.profiles.id  (ON DELETE CASCADE)
--
--   Postgres checks the RESTRICT constraint on check_ins.user_id before the
--   CASCADE from passports can remove the referencing check_ins rows, so when
--   a prior CI run left check_ins behind the auth.users DELETE fails with:
--
--       23503 update or delete on table "profiles" violates foreign key
--       constraint "check_ins_user_id_fkey" on table "check_ins"
--
--   Observed in PR #40 CI run on 2026-06-28T20:19:41Z.
--
--   Migration 023 applied the same fix to create_exploit_test_users.
--   This migration applies it to create_regression_users (migration 028 body).
--
-- SAFETY:
--   - CREATE OR REPLACE — re-applicable.
--   - DELETEs target only the two reserved regression-CI UUIDs.
-- ════════════════════════════════════════════════════════════════════════════

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
  -- ── Clean slate (extended for FK fanout) ─────────────────────────────────
  -- Order: public child rows first, then auth.identities (FK to auth.users),
  -- then auth.users (cascades to public.profiles).
  DELETE FROM public.check_ins
   WHERE user_id IN (P1_ID, P2_ID);

  DELETE FROM public.passports
   WHERE user_id IN (P1_ID, P2_ID);

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
  -- (unique constraint). phone_change must be '' to avoid GoTrue scan error.
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
    'p1_id',     P1_ID,
    'p2_id',     P2_ID,
    'migration', '029'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.create_regression_users() TO service_role;

DO $$
BEGIN
  RAISE NOTICE '[029] create_regression_users Clean slate extended to public.check_ins + public.passports ✓';
END;
$$;
