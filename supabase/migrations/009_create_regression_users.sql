-- ════════════════════════════════════════════════════════════════════════════
-- Migration 009 — create_regression_users helper
-- ════════════════════════════════════════════════════════════════════════════
--
-- PURPOSE:
--   Add a SECURITY DEFINER function that inserts the RLS *regression* suite
--   test users directly into auth.users, bypassing GoTrue. Mirrors the pattern
--   established in migration 008 (create_test_users) but seeds a distinct
--   pair of users (reg_player_one / reg_player_two) so the regression suite
--   does not collide with the exploit suite's fixtures.
--
--   Without this function the rls-regression.yml workflow tries to sign in as
--   reg_player_one@test.atlasci.com — which does not exist anywhere — and
--   every regression assertion (reg-01 → reg-04) fails on the seed step.
--
-- Called by the CI seeder via:
--   POST /rest/v1/rpc/create_regression_users  (anon key — SECURITY DEFINER)
--
-- SAFE TO RUN MULTIPLE TIMES — uses ON CONFLICT DO NOTHING.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_regression_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  r1_id  UUID;
  r2_id  UUID;
  now_ts TIMESTAMPTZ := NOW();
BEGIN
  -- ── Regression Player One ──────────────────────────────────────────────────
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmed_at,
    raw_user_meta_data,
    raw_app_meta_data,
    created_at,
    updated_at,
    role,
    aud
  )
  VALUES (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000000'::UUID,
    'reg_player_one@test.atlasci.com',
    crypt('RegPlayer1!RLS', gen_salt('bf')),
    now_ts,
    now_ts,
    '{"full_name": "CI Regression Player One"}'::JSONB,
    '{"provider": "email", "providers": ["email"]}'::JSONB,
    now_ts,
    now_ts,
    'authenticated',
    'authenticated'
  )
  ON CONFLICT (email) DO NOTHING;

  -- ── Regression Player Two ──────────────────────────────────────────────────
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmed_at,
    raw_user_meta_data,
    raw_app_meta_data,
    created_at,
    updated_at,
    role,
    aud
  )
  VALUES (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000000'::UUID,
    'reg_player_two@test.atlasci.com',
    crypt('RegPlayer2!RLS', gen_salt('bf')),
    now_ts,
    now_ts,
    '{"full_name": "CI Regression Player Two"}'::JSONB,
    '{"provider": "email", "providers": ["email"]}'::JSONB,
    now_ts,
    now_ts,
    'authenticated',
    'authenticated'
  )
  ON CONFLICT (email) DO NOTHING;

  -- Fetch the IDs (works whether they were just created or already existed)
  SELECT id INTO r1_id FROM auth.users WHERE email = 'reg_player_one@test.atlasci.com';
  SELECT id INTO r2_id FROM auth.users WHERE email = 'reg_player_two@test.atlasci.com';

  RETURN jsonb_build_object(
    'reg_player_one_id', r1_id,
    'reg_player_two_id', r2_id,
    'status', 'ok'
  );
END;
$$;

-- Grant execute to anon so the regression seeder can call it without a JWT.
-- Safe to expose publicly — function only creates the two known allow-listed
-- regression test users with deterministic passwords.
GRANT EXECUTE ON FUNCTION public.create_regression_users() TO anon;
GRANT EXECUTE ON FUNCTION public.create_regression_users() TO authenticated;

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_regression_users'
  ) THEN
    RAISE EXCEPTION '[009] VERIFICATION FAILED: create_regression_users function not found.';
  END IF;
  RAISE NOTICE '[009] create_regression_users: present. ✓';
END;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- USAGE (from rls-regression.yml seeder, before sign_in calls):
--
--   curl -s "https://gaavynmmysdhovpatzlp.supabase.co/rest/v1/rpc/create_regression_users" \
--        -H "apikey: <anon_key>" \
--        -H "Content-Type: application/json" \
--        -d '{}'
--
-- Returns:
--   {"reg_player_one_id": "<uuid>", "reg_player_two_id": "<uuid>", "status": "ok"}
-- ════════════════════════════════════════════════════════════════════════════
