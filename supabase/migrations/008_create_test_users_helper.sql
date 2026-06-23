-- ════════════════════════════════════════════════════════════════════════════
-- Migration 008 — create_test_users helper
-- ════════════════════════════════════════════════════════════════════════════
--
-- PURPOSE:
--   Add a SECURITY DEFINER function that inserts CI test users directly into
--   auth.users, bypassing GoTrue completely. This avoids:
--     • GoTrue email TLD validation  (rejects fake TLDs like .atlas)
--     • GoTrue email rate limits     (429 over_email_send_rate_limit)
--     • GoTrue confirmation emails   (not needed for headless CI)
--
-- Called by the CI seeder via:
--   POST /rest/v1/rpc/create_test_users  (anon key — SECURITY DEFINER runs as owner)
--
-- SAFE TO RUN MULTIPLE TIMES — uses ON CONFLICT DO NOTHING.
-- ════════════════════════════════════════════════════════════════════════════

-- ── create_test_users ────────────────────────────────────────────────────────
--
-- Inserts both CI test users into auth.users with:
--   • A hashed password (bcrypt via pgcrypto)
--   • email_confirmed_at / confirmed_at set to NOW() (pre-confirmed)
--   • user_metadata with full_name
--
-- Returns JSONB with the two user IDs so the seeder can use them for
-- passport/check-in upserts without a sign-in round trip.
-- However the seeder still signs in via GoTrue to get a real JWT for RLS
-- authenticated inserts — this function just ensures the users exist.

CREATE OR REPLACE FUNCTION public.create_test_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  p1_id  UUID;
  p2_id  UUID;
  now_ts TIMESTAMPTZ := NOW();
BEGIN
  -- ── Player One ─────────────────────────────────────────────────────────────
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
    'player_one_rls@test.atlasci.com',
    crypt('TestPlayer1!RLS', gen_salt('bf')),
    now_ts,
    now_ts,
    '{"full_name": "CI Player One"}'::JSONB,
    '{"provider": "email", "providers": ["email"]}'::JSONB,
    now_ts,
    now_ts,
    'authenticated',
    'authenticated'
  )
  ON CONFLICT (email) DO NOTHING;

  -- ── Player Two ─────────────────────────────────────────────────────────────
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
    'player_two_rls@test.atlasci.com',
    crypt('TestPlayer2!RLS', gen_salt('bf')),
    now_ts,
    now_ts,
    '{"full_name": "CI Player Two"}'::JSONB,
    '{"provider": "email", "providers": ["email"]}'::JSONB,
    now_ts,
    now_ts,
    'authenticated',
    'authenticated'
  )
  ON CONFLICT (email) DO NOTHING;

  -- Fetch the IDs (works whether they were just created or already existed)
  SELECT id INTO p1_id FROM auth.users WHERE email = 'player_one_rls@test.atlasci.com';
  SELECT id INTO p2_id FROM auth.users WHERE email = 'player_two_rls@test.atlasci.com';

  RETURN jsonb_build_object(
    'player_one_id', p1_id,
    'player_two_id', p2_id,
    'status', 'ok'
  );
END;
$$;

-- Grant execute to the anon role so the CI seeder can call it without a JWT.
-- The function is safe to call publicly — it only creates the two known
-- allow-listed test users with deterministic passwords.
GRANT EXECUTE ON FUNCTION public.create_test_users() TO anon;
GRANT EXECUTE ON FUNCTION public.create_test_users() TO authenticated;

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_test_users'
  ) THEN
    RAISE EXCEPTION '[008] VERIFICATION FAILED: create_test_users function not found.';
  END IF;
  RAISE NOTICE '[008] create_test_users: present. ✓';
END;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- USAGE (from CI seeder, replacing GoTrue signUp calls):
--
--   curl -s "https://gaavynmmysdhovpatzlp.supabase.co/rest/v1/rpc/create_test_users" \
--        -H "apikey: <anon_key>" \
--        -H "Content-Type: application/json" \
--        -d '{}'
--
-- Returns:
--   {"player_one_id": "<uuid>", "player_two_id": "<uuid>", "status": "ok"}
-- ════════════════════════════════════════════════════════════════════════════
