-- ════════════════════════════════════════════════════════════════════════════
-- Migration 020 — Idempotent seed helpers (PR #27 follow-up)
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   PR #27 surfaced a latent class of CI flakes: seed RPCs were not durably
--   idempotent against re-runs. Two concrete failures observed on
--   2026-06-27 against project gaavynmmysdhovpatzlp:
--
--   1. create_exploit_test_users() → 23505 duplicate key on
--      auth.users_phone_key (phone='').
--      The repo version of migration 016 already contains a "Clean slate"
--      DELETE block, but the live function in the database was an earlier
--      revision without it (migration registry drift — see commit 8502fa1
--      and supabase_migrations.schema_migrations, which only records 3 of
--      the ~19 migrations actually applied). This migration redeploys the
--      function with the Clean slate block + a defensive backfill of
--      public.profiles immediately after auth.users insertion.
--
--   2. seed_ci_passports() → 23503 passports_user_id_fkey violation
--      because public.profiles rows for the exploit users were not
--      materialised before the passports insert ran. The handle_new_user
--      trigger on auth.users normally backfills profiles, but the trigger
--      did not fire (or fired in the wrong txn boundary) in this seed path.
--      Fix: backfill profiles explicitly inside seed_ci_passports() with
--      ON CONFLICT DO NOTHING before inserting passports.
--
-- SAFETY:
--   - All operations use CREATE OR REPLACE and ON CONFLICT clauses.
--   - Re-applicable any number of times against any environment.
--   - No data loss: the Clean slate DELETE only targets the two CI-only
--     UUIDs (aaaaaaaa-0011-... and aaaaaaaa-0022-...), which by convention
--     are reserved for the exploit suite.
--
-- VERIFICATION:
--   After applying, the following must succeed twice in a row from a fresh
--   psql session connected as service_role (or via PostgREST):
--     SELECT public.create_exploit_test_users();
--     SELECT public.seed_ci_fixtures();
--     SELECT public.seed_ci_passports();
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. create_exploit_test_users — restore Clean slate + add profiles backfill
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
  -- auth.identities first to satisfy FK to auth.users.
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
    '', '', ''
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
    '', '', ''
  );

  -- ── Dynamic comprehensive NULL fix (carry-over from migration 014) ───────
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
  -- The handle_new_user trigger on auth.users normally creates these rows,
  -- but the trigger may not fire in this seed path (SECURITY DEFINER + search
  -- path manipulation). Backfill explicitly so seed_ci_passports never trips
  -- the passports_user_id_fkey.
  INSERT INTO public.profiles (id, email, full_name, is_admin)
  VALUES
    (P1_ID, 'player_one_rls@test.atlasci.com', 'RLS Exploit Player One', false),
    (P2_ID, 'player_two_rls@test.atlasci.com', 'RLS Exploit Player Two', false)
  ON CONFLICT (id) DO UPDATE SET
    email     = EXCLUDED.email,
    full_name = EXCLUDED.full_name;

  IF array_length(v_fixed, 1) > 0 THEN
    RAISE NOTICE '[020] Columns fixed to '''' for exploit users: %', v_fixed;
  END IF;

  RETURN jsonb_build_object(
    'player_one_rls_id', P1_ID,
    'player_two_rls_id', P2_ID,
    'status', 'ok',
    'migration', '020'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_exploit_test_users() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_exploit_test_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_exploit_test_users() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.create_exploit_test_users() TO service_role;


-- ── 2. seed_ci_passports — backfill profiles defensively before passports ──
DROP FUNCTION IF EXISTS public.seed_ci_passports();

CREATE OR REPLACE FUNCTION public.seed_ci_passports()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  P1_ID                UUID := 'aaaaaaaa-0011-0000-0000-000000000000';
  P2_ID                UUID := 'aaaaaaaa-0022-0000-0000-000000000000';
  CORRIDOR_ID          UUID := 'aaaaaaaa-0000-0000-0000-000000000001';
  NODE_ID              UUID := 'bbbbbbbb-0000-0000-0000-000000000001';
  PASSPORT_ACTIVE_ID   UUID := 'dddddddd-0000-0000-0000-000000000001';
  PASSPORT_COMPLETE_ID UUID := 'dddddddd-0000-0000-0000-000000000002';
  CHECKIN_ID           UUID := 'eeeeeeee-0000-0000-0000-000000000001';
BEGIN
  -- Defensive profiles backfill — in case create_exploit_test_users was
  -- run before migration 020 was applied (or under a configuration where
  -- handle_new_user did not fire).
  INSERT INTO public.profiles (id, email, full_name, is_admin)
  VALUES
    (P1_ID, 'player_one_rls@test.atlasci.com', 'RLS Exploit Player One', false),
    (P2_ID, 'player_two_rls@test.atlasci.com', 'RLS Exploit Player Two', false)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.passports (id, user_id, corridor_id, status)
  VALUES
    (PASSPORT_ACTIVE_ID,   P1_ID, CORRIDOR_ID, 'active'),
    (PASSPORT_COMPLETE_ID, P2_ID, CORRIDOR_ID, 'complete')
  ON CONFLICT (id) DO UPDATE SET
    user_id     = EXCLUDED.user_id,
    corridor_id = EXCLUDED.corridor_id,
    status      = EXCLUDED.status;

  INSERT INTO public.check_ins (
    id, passport_id, user_id, node_id, status, proof_url, proof_storage_path
  ) VALUES (
    CHECKIN_ID,
    PASSPORT_ACTIVE_ID, P1_ID, NODE_ID, 'pending',
    'https://example.com/ci-seed-proof.jpg',
    'ci-seed/proof.jpg'
  )
  ON CONFLICT (id) DO UPDATE SET
    passport_id        = EXCLUDED.passport_id,
    user_id            = EXCLUDED.user_id,
    node_id            = EXCLUDED.node_id,
    status             = EXCLUDED.status,
    proof_url          = EXCLUDED.proof_url,
    proof_storage_path = EXCLUDED.proof_storage_path;

  RETURN jsonb_build_object(
    'passport_active_id',   PASSPORT_ACTIVE_ID,
    'passport_complete_id', PASSPORT_COMPLETE_ID,
    'checkin_id',           CHECKIN_ID,
    'status',               'ok',
    'migration',            '020'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM anon;
REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.seed_ci_passports() TO service_role;


-- ── 3. seed_regression_passports — same defensive profiles backfill ────────
DROP FUNCTION IF EXISTS public.seed_regression_passports();

CREATE OR REPLACE FUNCTION public.seed_regression_passports()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  P1_ID                UUID := 'bbbbbbbb-0001-0000-0000-000000000000';
  P2_ID                UUID := 'bbbbbbbb-0002-0000-0000-000000000000';
  CORRIDOR_ACTIVE_ID   UUID := 'cccc0001-0000-0000-0000-000000000001';
  CORRIDOR_INACTIVE_ID UUID := 'cccc0001-0000-0000-0000-000000000002';
  NODE_ID              UUID := 'cccc0002-0000-0000-0000-000000000001';
  REWARD_ID            UUID := 'cccc0005-0000-0000-0000-000000000001';
  PASSPORT_ACTIVE_ID   UUID := 'cccc0003-0000-0000-0000-000000000001';
  PASSPORT_COMPLETE_ID UUID := 'cccc0003-0000-0000-0000-000000000002';
  PASSPORT_OTHER_ID    UUID := 'cccc0003-0000-0000-0000-000000000003';
  CHECKIN_SEED_ID      UUID := 'cccc0004-0000-0000-0000-000000000001';
BEGIN
  -- Defensive profiles backfill (mirror of seed_ci_passports rationale)
  INSERT INTO public.profiles (id, email, full_name, is_admin)
  VALUES
    (P1_ID, 'reg_player_one@test.atlasci.com', 'Regression Player One', false),
    (P2_ID, 'reg_player_two@test.atlasci.com', 'Regression Player Two', false)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.corridors (id, name, city, country, is_active)
  VALUES
    (CORRIDOR_ACTIVE_ID,   'Regression Corridor Active',   'Test City', 'US', TRUE),
    (CORRIDOR_INACTIVE_ID, 'Regression Corridor Inactive', 'Test City', 'US', FALSE)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.nodes (id, corridor_id, name, sequence, latitude, longitude, is_active)
  VALUES (NODE_ID, CORRIDOR_ACTIVE_ID, 'Regression Node', 1, 38.9, -77.0, TRUE)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.rewards (id, corridor_id, title, description, redemption_code)
  VALUES (REWARD_ID, CORRIDOR_ACTIVE_ID, 'Regression Reward', 'Regression test reward', 'REG-TEST-001')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.passports (id, user_id, corridor_id, status)
  VALUES
    (PASSPORT_ACTIVE_ID,   P1_ID, CORRIDOR_ACTIVE_ID, 'active'),
    (PASSPORT_COMPLETE_ID, P2_ID, CORRIDOR_ACTIVE_ID, 'complete'),
    (PASSPORT_OTHER_ID,    P2_ID, CORRIDOR_ACTIVE_ID, 'active')
  ON CONFLICT (id) DO UPDATE SET
    user_id     = EXCLUDED.user_id,
    corridor_id = EXCLUDED.corridor_id,
    status      = EXCLUDED.status;

  INSERT INTO public.check_ins (
    id, passport_id, user_id, node_id, status, proof_url, proof_storage_path
  ) VALUES (
    CHECKIN_SEED_ID,
    PASSPORT_ACTIVE_ID, P1_ID, NODE_ID, 'pending',
    'https://example.com/reg-ci.jpg',
    'regression/ci.jpg'
  )
  ON CONFLICT (id) DO UPDATE SET
    passport_id        = EXCLUDED.passport_id,
    user_id            = EXCLUDED.user_id,
    node_id            = EXCLUDED.node_id,
    status             = EXCLUDED.status,
    proof_url          = EXCLUDED.proof_url,
    proof_storage_path = EXCLUDED.proof_storage_path;

  RETURN jsonb_build_object(
    'corridor_active_id',   CORRIDOR_ACTIVE_ID,
    'corridor_inactive_id', CORRIDOR_INACTIVE_ID,
    'node_id',              NODE_ID,
    'reward_id',            REWARD_ID,
    'passport_active_id',   PASSPORT_ACTIVE_ID,
    'passport_complete_id', PASSPORT_COMPLETE_ID,
    'passport_other_id',    PASSPORT_OTHER_ID,
    'checkin_id',           CHECKIN_SEED_ID,
    'status',               'ok',
    'migration',            '020'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_regression_passports() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.seed_regression_passports() FROM anon;
REVOKE EXECUTE ON FUNCTION public.seed_regression_passports() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.seed_regression_passports() TO service_role;


DO $$
BEGIN
  RAISE NOTICE '[020] Seed helpers redeployed with idempotency + profiles backfill. ✓';
  RAISE NOTICE '[020] create_exploit_test_users, seed_ci_passports, seed_regression_passports';
END;
$$;
