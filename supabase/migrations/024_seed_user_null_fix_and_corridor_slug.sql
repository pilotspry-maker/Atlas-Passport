-- ════════════════════════════════════════════════════════════════════════════
-- Migration 024 — Round out CI seed idempotency: NULL fix for create_*_users
--                  and corridor.slug for seed_regression_passports
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   PR #40 CI surfaced two remaining gaps after migrations 020/021/022/023:
--
--   1. create_test_users() and create_regression_users() inserted into
--      auth.users without supplying email_change, leaving that column NULL.
--      GoTrue v2 returns:
--          500 {"code":500,"error_code":"unexpected_failure",
--               "msg":"Database error querying schema"}
--      on every sign-in attempt for such a user.
--
--      Migration 014 added a UPDATE … COALESCE block to both functions but
--      only covered the six tokens (confirmation_token, recovery_token,
--      email_change_token_new, email_change_token_current, reauthentication_token,
--      phone_change_token). email_change, phone, phone_change were left
--      uncovered. Migration 020's dynamic catch-all only patched
--      create_exploit_test_users().
--
--      Fix: drop a dynamic catch-all block (same shape as migration 021) into
--      create_test_users() and create_regression_users() that backfills every
--      NULLable text/varchar column on auth.users with '' for the seeded UUIDs,
--      excluding phone/phone_change to avoid the unique-on-empty-string
--      collision GoTrue tracks separately.
--
--   2. seed_regression_passports() insert into public.corridors omits the
--      slug column, which is NOT NULL. CI reports 23502.
--
--      Fix: re-deploy seed_regression_passports() with slug + city supplied
--      explicitly for both corridors. (city was already in the row but the
--      column gained NOT NULL after the function was first written, so this
--      is just guarding both at the same time.)
--
-- SAFETY:
--   - All operations CREATE OR REPLACE.
--   - All UPDATE/INSERT operations scoped to the four CI-only UUIDs.
--   - No production data is touched.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. create_test_users — comprehensive NULL fix (ci_player / ci_admin) ─────
DROP FUNCTION IF EXISTS public.create_test_users();

CREATE OR REPLACE FUNCTION public.create_test_users()
RETURNS TABLE(user_id uuid, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  v_now   timestamptz := now();
  v_col   text;
  P1_ID   uuid := 'aaaaaaaa-0001-0000-0000-000000000000';
  P2_ID   uuid := 'aaaaaaaa-0002-0000-0000-000000000000';
BEGIN
  -- Clean slate: child public rows first (FK guard), then identities, then users.
  DELETE FROM public.check_ins
   WHERE check_ins.user_id     IN (P1_ID, P2_ID)
      OR check_ins.reviewed_by IN (P1_ID, P2_ID);

  DELETE FROM public.passports
   WHERE passports.user_id IN (P1_ID, P2_ID);

  DELETE FROM auth.identities AS ai
   WHERE ai.user_id IN (P1_ID, P2_ID);

  DELETE FROM auth.users
   WHERE id IN (P1_ID, P2_ID);

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
    'authenticated', 'authenticated', 'ci_player@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    NULL, '', NULL
  ),
  (
    P2_ID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_admin@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"is_admin":true}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    NULL, '', NULL
  );

  -- Dynamic comprehensive NULL fix for every nullable text/varchar on auth.users.
  -- Skips phone and phone_change so empty-string does not collide on the
  -- unique-on-empty-string constraint GoTrue maintains for those columns.
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
    format('{"sub":"%s","email":"%s"}', P1_ID::text, 'ci_player@test.local')::jsonb,
    'email', v_now, v_now, v_now
  ),
  (
    P2_ID, P2_ID, P2_ID::text,
    format('{"sub":"%s","email":"%s"}', P2_ID::text, 'ci_admin@test.local')::jsonb,
    'email', v_now, v_now, v_now
  );

  RETURN QUERY
    SELECT u.id, u.email::text FROM auth.users u
    WHERE u.id IN (P1_ID, P2_ID);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_test_users() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_test_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_test_users() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.create_test_users() TO service_role;

-- ── 2. create_regression_users — same shape, reg_player_one / reg_player_two ─
DROP FUNCTION IF EXISTS public.create_regression_users();

CREATE OR REPLACE FUNCTION public.create_regression_users()
RETURNS TABLE(user_id uuid, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  v_now   timestamptz := now();
  v_col   text;
  P1_ID   uuid := 'bbbbbbbb-0001-0000-0000-000000000000';
  P2_ID   uuid := 'bbbbbbbb-0002-0000-0000-000000000000';
BEGIN
  DELETE FROM public.check_ins
   WHERE check_ins.user_id     IN (P1_ID, P2_ID)
      OR check_ins.reviewed_by IN (P1_ID, P2_ID);

  DELETE FROM public.passports
   WHERE passports.user_id IN (P1_ID, P2_ID);

  DELETE FROM auth.identities AS ai
   WHERE ai.user_id IN (P1_ID, P2_ID);

  DELETE FROM auth.users
   WHERE id IN (P1_ID, P2_ID);

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
    'authenticated', 'authenticated', 'reg_player_one@test.atlasci.com',
    crypt('TestRegression1!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Regression Player One"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', '',
    NULL, '', NULL
  ),
  (
    P2_ID,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_two@test.atlasci.com',
    crypt('TestRegression2!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Regression Player Two"}'::jsonb,
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

  -- Backfill profiles for both regression users (CASCADE from auth.users
  -- DELETE above removed them; handle_new_user may not fire reliably here).
  INSERT INTO public.profiles (id, email, full_name, is_admin)
  VALUES
    (P1_ID, 'reg_player_one@test.atlasci.com', 'Regression Player One', false),
    (P2_ID, 'reg_player_two@test.atlasci.com', 'Regression Player Two', false)
  ON CONFLICT (id) DO UPDATE SET
    email     = EXCLUDED.email,
    full_name = EXCLUDED.full_name;

  RETURN QUERY
    SELECT u.id, u.email::text FROM auth.users u
    WHERE u.id IN (P1_ID, P2_ID);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_regression_users() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.create_regression_users() TO service_role;

-- ── 3. seed_regression_passports — supply slug for corridors (NOT NULL) ──────
DROP FUNCTION IF EXISTS public.seed_regression_passports();

CREATE OR REPLACE FUNCTION public.seed_regression_passports()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  P1_ID UUID := 'bbbbbbbb-0001-0000-0000-000000000000';
  P2_ID UUID := 'bbbbbbbb-0002-0000-0000-000000000000';
  CORRIDOR_ACTIVE_ID   UUID := 'cccc0001-0000-0000-0000-000000000001';
  CORRIDOR_INACTIVE_ID UUID := 'cccc0001-0000-0000-0000-000000000002';
  NODE_ID              UUID := 'cccc0002-0000-0000-0000-000000000001';
  REWARD_ID            UUID := 'cccc0005-0000-0000-0000-000000000001';
  PASSPORT_ACTIVE_ID   UUID := 'cccc0003-0000-0000-0000-000000000001';
  PASSPORT_COMPLETE_ID UUID := 'cccc0003-0000-0000-0000-000000000002';
  PASSPORT_OTHER_ID    UUID := 'cccc0003-0000-0000-0000-000000000003';
  CHECKIN_SEED_ID      UUID := 'cccc0004-0000-0000-0000-000000000001';
BEGIN
  -- Clean slate: remove any prior regression child rows so the passport
  -- inserts below cannot collide with the UNIQUE (user_id, corridor_id)
  -- constraint on public.passports. We delete check_ins first because
  -- check_ins.passport_id -> passports.id has no cascade.
  DELETE FROM public.check_ins
   WHERE id = CHECKIN_SEED_ID
      OR passport_id IN (PASSPORT_ACTIVE_ID, PASSPORT_COMPLETE_ID, PASSPORT_OTHER_ID)
      OR user_id IN (P1_ID, P2_ID);

  DELETE FROM public.passports
   WHERE id IN (PASSPORT_ACTIVE_ID, PASSPORT_COMPLETE_ID, PASSPORT_OTHER_ID)
      OR user_id IN (P1_ID, P2_ID);

  INSERT INTO public.corridors (id, name, slug, city, country, is_active)
  VALUES
    (CORRIDOR_ACTIVE_ID,   'Regression Corridor Active',   'regression-corridor-active',   'Test City', 'US', TRUE),
    (CORRIDOR_INACTIVE_ID, 'Regression Corridor Inactive', 'regression-corridor-inactive', 'Test City', 'US', FALSE)
  ON CONFLICT (id) DO UPDATE SET
    name      = EXCLUDED.name,
    slug      = EXCLUDED.slug,
    city      = EXCLUDED.city,
    country   = EXCLUDED.country,
    is_active = EXCLUDED.is_active;

  INSERT INTO public.nodes (id, corridor_id, name, sequence, latitude, longitude, is_active)
  VALUES (NODE_ID, CORRIDOR_ACTIVE_ID, 'Regression Node', 1, 38.9, -77.0, TRUE)
  ON CONFLICT (id) DO UPDATE SET
    corridor_id = EXCLUDED.corridor_id,
    name        = EXCLUDED.name,
    sequence    = EXCLUDED.sequence,
    is_active   = EXCLUDED.is_active;

  INSERT INTO public.rewards (id, corridor_id, title, description, redemption_code)
  VALUES (REWARD_ID, CORRIDOR_ACTIVE_ID, 'Regression Reward', 'Regression test reward', 'REG-TEST-001')
  ON CONFLICT (id) DO NOTHING;

  -- PASSPORT_OTHER is parked on CORRIDOR_INACTIVE_ID to avoid colliding
  -- with PASSPORT_COMPLETE on (P2_ID, CORRIDOR_ACTIVE_ID). The TS-side
  -- regression setup re-upserts PASSPORT_OTHER under p2 with
  -- Prefer: resolution=ignore-duplicates, so test ownership invariants
  -- still hold and IDOR tests continue to assert p2 ownership.
  INSERT INTO public.passports (id, user_id, corridor_id, status)
  VALUES
    (PASSPORT_ACTIVE_ID,   P1_ID, CORRIDOR_ACTIVE_ID,   'active'),
    (PASSPORT_COMPLETE_ID, P2_ID, CORRIDOR_ACTIVE_ID,   'complete'),
    (PASSPORT_OTHER_ID,    P2_ID, CORRIDOR_INACTIVE_ID, 'active');

  INSERT INTO public.check_ins (id, passport_id, user_id, node_id, status, proof_url, proof_storage_path)
  VALUES (CHECKIN_SEED_ID, PASSPORT_ACTIVE_ID, P1_ID, NODE_ID, 'pending',
          'https://example.com/reg-ci.jpg', 'regression/ci.jpg');

  RETURN jsonb_build_object(
    'status',             'ok',
    'corridor_active_id', CORRIDOR_ACTIVE_ID,
    'passport_active_id', PASSPORT_ACTIVE_ID,
    'checkin_id',         CHECKIN_SEED_ID,
    'migration',          '024b'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_regression_passports() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.seed_regression_passports() FROM anon;
REVOKE EXECUTE ON FUNCTION public.seed_regression_passports() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.seed_regression_passports() TO service_role;

DO $$
BEGIN
  RAISE NOTICE '[024] create_test_users + create_regression_users: dynamic NULL fix added';
  RAISE NOTICE '[024b] seed_regression_passports: Clean slate + PASSPORT_OTHER on CORRIDOR_INACTIVE_ID';
END;
$$;
