-- ════════════════════════════════════════════════════════════════════════════
-- Migration 021 — Fix phone='' collision in create_exploit_test_users (PR #27)
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   Migration 020 redeployed create_exploit_test_users() with literal phone=''
--   for both inserted rows. The auth.users_phone_key UNIQUE index treats two
--   empty-string values as a duplicate, so the multi-row INSERT inside the
--   function self-collides:
--
--     ERROR: 23505: duplicate key value violates unique constraint
--            "users_phone_key"
--     DETAIL: Key (phone)=() already exists.
--
--   Verified on 2026-06-27 in project gaavynmmysdhovpatzlp.
--
-- FIX:
--   - Insert phone as NULL (not ''). NULL values are not compared by the
--     UNIQUE index, so two rows can coexist with phone IS NULL.
--   - Same correction for phone_change which is also a text column subject
--     to a partial uniqueness check via auth's internal triggers.
--   - Same fix mirrored into the dynamic NULL-fix loop carry-over from
--     migration 014: skip 'phone' and 'phone_change' so we don't reintroduce
--     the '' value the unique index objects to.
--
-- SAFETY:
--   - CREATE OR REPLACE — re-applicable any number of times.
--   - No data changes outside the two CI-only UUIDs.
-- ════════════════════════════════════════════════════════════════════════════

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
  -- ── Clean slate (idempotency root) ───────────────────────────────────────
  DELETE FROM auth.identities WHERE user_id IN (P1_ID, P2_ID);
  DELETE FROM auth.users      WHERE id      IN (P1_ID, P2_ID);

  -- ── Insert exploit test users ─────────────────────────────────────────────
  -- NOTE: phone and phone_change are NULL (not '') because the unique index
  -- on auth.users.phone treats '' values as colliding with each other.
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
    NULL, '', NULL          -- phone, email_change, phone_change
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
    NULL, '', NULL          -- phone, email_change, phone_change
  );

  -- ── Dynamic comprehensive NULL fix (carry-over from migration 014) ───────
  -- Skip phone and phone_change so we don't reintroduce '' on the unique-
  -- constrained columns.
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

  -- ── auth.identities rows (re-inserted after the clean slate) ─────────────
  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES
  (
    P1_ID, P1_ID, P1_ID::text,
    format('{"sub":"%s","email":"%s"}',
      P1_ID::text, 'player_one_rls@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
  ),
  (
    P2_ID, P2_ID, P2_ID::text,
    format('{"sub":"%s","email":"%s"}',
      P2_ID::text, 'player_two_rls@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
  );

  -- ── Defensive profiles backfill ──────────────────────────────────────────
  INSERT INTO public.profiles (id, email, full_name, is_admin)
  VALUES
    (P1_ID, 'player_one_rls@test.atlasci.com', 'RLS Exploit Player One', false),
    (P2_ID, 'player_two_rls@test.atlasci.com', 'RLS Exploit Player Two', false)
  ON CONFLICT (id) DO UPDATE SET
    email     = EXCLUDED.email,
    full_name = EXCLUDED.full_name;

  IF array_length(v_fixed, 1) > 0 THEN
    RAISE NOTICE '[021] Columns fixed to '''' for exploit users: %', v_fixed;
  END IF;

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

DO $$
BEGIN
  RAISE NOTICE '[021] create_exploit_test_users patched: phone=NULL to avoid unique collision';
END;
$$;
