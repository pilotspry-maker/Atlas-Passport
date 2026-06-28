-- ════════════════════════════════════════════════════════════════════════════
-- Migration 023 — Extend exploit-user Clean slate to public child rows
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   PR #40 CI surfaced a residual idempotency gap. Migrations 020/021 added
--   a Clean slate block that deletes auth.identities then auth.users for the
--   two exploit UUIDs:
--
--       P1 = aaaaaaaa-0011-0000-0000-000000000000
--       P2 = aaaaaaaa-0022-0000-0000-000000000000
--
--   public.profiles.id is ON DELETE CASCADE from auth.users.id, so deleting
--   auth.users cascades to profiles automatically. However:
--
--       public.check_ins.user_id  → public.profiles.id  (NO action)
--       public.passports.user_id  → public.profiles.id  (NO action)
--
--   So when a prior CI run left rows behind in check_ins / passports for
--   those exploit users, the auth.users DELETE in migration 021 fails with:
--
--       23503 update or delete on table "profiles" violates foreign key
--       constraint "check_ins_user_id_fkey" on table "check_ins"
--
--   Observed in PR #40 run 28330934936 on 2026-06-28T19:01:45Z.
--
-- WHAT THIS FIX DOES:
--   Re-deploys create_exploit_test_users() with an extended Clean slate that
--   deletes child rows in the public schema BEFORE removing auth.users.
--   Order: check_ins → passports → auth.identities → auth.users.
--   profiles is left to the CASCADE from auth.users (preserves the existing
--   contract; the trigger handle_new_user re-creates them on INSERT).
--
-- SAFETY:
--   - CREATE OR REPLACE — re-applicable any number of times.
--   - DELETEs target only the two reserved CI-only UUIDs.
--   - No data loss outside CI fixtures.
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
  -- ── Clean slate (idempotency root, extended for FK fanout) ────────────────
  -- Order is critical: public child rows first, then auth.identities (FK to
  -- auth.users), then auth.users (cascades to public.profiles).
  DELETE FROM public.check_ins
   WHERE user_id     IN (P1_ID, P2_ID)
      OR reviewed_by IN (P1_ID, P2_ID);

  DELETE FROM public.passports
   WHERE user_id IN (P1_ID, P2_ID);

  DELETE FROM auth.identities WHERE user_id IN (P1_ID, P2_ID);
  DELETE FROM auth.users      WHERE id      IN (P1_ID, P2_ID);

  -- ── Insert exploit test users ─────────────────────────────────────────────
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

  -- ── Dynamic comprehensive NULL fix (carry-over from migration 021) ───────
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
    RAISE NOTICE '[023] Columns fixed to '''' for exploit users: %', v_fixed;
  END IF;

  RETURN jsonb_build_object(
    'player_one_rls_id', P1_ID,
    'player_two_rls_id', P2_ID,
    'status',            'ok',
    'migration',         '023'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_exploit_test_users() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_exploit_test_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_exploit_test_users() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.create_exploit_test_users() TO service_role;

DO $$
BEGIN
  RAISE NOTICE '[023] create_exploit_test_users Clean slate extended to public.check_ins + public.passports';
END;
$$;
