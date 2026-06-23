-- ============================================================
-- Migration: 006_test_helpers.sql
-- Atlas Passport · Relevant Artist
-- Applied: 2026-06-23
--
-- Purpose:
--   Provide a SECURITY DEFINER helper that the Vitest exploit test
--   suite and the CI fixture seeder can call via the PostgREST RPC
--   endpoint (/rest/v1/rpc/confirm_test_users) to confirm test user
--   accounts without requiring a JWT-format service-role key.
--
--   Background:
--     The project uses Supabase's new opaque sb_secret_ key format.
--     The Auth Admin API (/auth/v1/admin/users) validates JWTs directly
--     in GoTrue and does not accept the opaque key format — only the
--     PostgREST/REST gateway translates opaque keys.  The SECURITY
--     DEFINER approach sidesteps this by running the confirmation UPDATE
--     inside Postgres with elevated privileges, reachable via /rest/v1/rpc.
--
--   Security model:
--     • The function is callable by the 'anon' role (public) ONLY when
--       the calling email matches the hardcoded CI test user allow-list.
--     • It confirms ONLY the two designated CI test accounts:
--         player_one_rls@test.atlas
--         player_two_rls@test.atlas
--     • Attempting to confirm any other email raises an exception.
--     • The function has no effect in production if those emails never
--       sign up (they exist only in the CI fixture seeder).
--
--   All statements are idempotent.
-- ============================================================

-- ── 1. confirm_test_users ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.confirm_test_users(user_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
DECLARE
  allowed_emails TEXT[] := ARRAY[
    'player_one_rls@test.atlas',
    'player_two_rls@test.atlas'
  ];
  affected_count INTEGER;
BEGIN
  -- Guard: only allow the two CI test accounts
  IF NOT (user_email = ANY(allowed_emails)) THEN
    RAISE EXCEPTION
      'confirm_test_users: email % is not in the CI test allow-list', user_email
      USING ERRCODE = '42501';  -- insufficient_privilege
  END IF;

  -- Confirm the user by setting email_confirmed_at and confirmed_at.
  -- Works regardless of whether the user was created via signUp (unconfirmed)
  -- or already exists. Idempotent — updating an already-confirmed user is safe.
  UPDATE auth.users
  SET
    email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
    confirmed_at       = COALESCE(confirmed_at,       NOW()),
    updated_at         = NOW()
  WHERE email = user_email;

  GET DIAGNOSTICS affected_count = ROW_COUNT;

  -- Return a status object the caller can inspect
  RETURN jsonb_build_object(
    'email',    user_email,
    'updated',  affected_count,
    'status',   CASE WHEN affected_count > 0 THEN 'confirmed' ELSE 'not_found' END
  );
END;
$$;

-- Grant execute to the anon role so the test seeder can call it via RPC
-- without needing any JWT (the function itself validates the allow-list)
GRANT EXECUTE ON FUNCTION public.confirm_test_users(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.confirm_test_users(TEXT) TO authenticated;

-- ── 2. seed_ci_fixtures ────────────────────────────────────────────────────────
--
-- Optional companion: upserts the deterministic corridor/node/reward fixture
-- rows used by the Vitest exploit suite. Callable by the anon role via RPC.
-- The rows are not sensitive — they carry only CI test labels and no
-- production data.
--
-- Note: passport/check-in rows require profile UUIDs so they are seeded
-- by setup.ts after sign-in, not here.

CREATE OR REPLACE FUNCTION public.seed_ci_fixtures()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Corridor (active)
  INSERT INTO public.corridors (id, name, city, country, is_active)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001',
    'CI Exploit Test Corridor', 'Test City', 'US', TRUE
  )
  ON CONFLICT (id) DO NOTHING;

  -- Node
  INSERT INTO public.nodes (id, corridor_id, name, sequence, is_active)
  VALUES (
    'bbbbbbbb-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'CI Exploit Test Node', 1, TRUE
  )
  ON CONFLICT (id) DO NOTHING;

  -- Reward
  INSERT INTO public.rewards (id, corridor_id, title, redemption_code)
  VALUES (
    'cccccccc-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'CI Exploit Test Reward', 'SECRET-CODE-XYZ'
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN jsonb_build_object('status', 'ok', 'seeded', ARRAY['corridor', 'node', 'reward']);
END;
$$;

GRANT EXECUTE ON FUNCTION public.seed_ci_fixtures() TO anon;
GRANT EXECUTE ON FUNCTION public.seed_ci_fixtures() TO authenticated;

-- ── 2b. seed_ci_fixtures_v2 ───────────────────────────────────────────────────
--
-- Extension of seed_ci_fixtures that adds the inactive corridor required by
-- exploit-05-inactive-corridor-insert.test.ts.
--
-- What's new vs v1:
--   • 'aaaaaaaa-0000-0000-0000-000000000002' — CI Inactive Test Corridor
--     is_active = FALSE. Used to verify that passports_insert_own (migration 007)
--     correctly rejects INSERT attempts targeting deactivated corridors.
--
-- All rows use ON CONFLICT (id) DO NOTHING — idempotent, safe to re-run.
-- Calling v2 does NOT re-seed the v1 rows (separate function to avoid
-- replacing a potentially edited active corridor in long-lived environments).

CREATE OR REPLACE FUNCTION public.seed_ci_fixtures_v2()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Active corridor (same UUID as v1 — idempotent)
  INSERT INTO public.corridors (id, name, city, country, is_active)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001',
    'CI Exploit Test Corridor', 'Test City', 'US', TRUE
  )
  ON CONFLICT (id) DO NOTHING;

  -- INACTIVE corridor — new in v2, required by exploit-05
  -- UUID: aaaaaaaa-0000-0000-0000-000000000002
  -- is_active = FALSE intentionally — this corridor must stay inactive
  --             for the corridor INSERT guard test to be meaningful.
  INSERT INTO public.corridors (id, name, city, country, is_active)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000002',
    'CI Inactive Test Corridor', 'Test City', 'US', FALSE
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN jsonb_build_object(
    'status', 'ok',
    'seeded', ARRAY['corridor_active', 'corridor_inactive']
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.seed_ci_fixtures_v2() TO anon;
GRANT EXECUTE ON FUNCTION public.seed_ci_fixtures_v2() TO authenticated;

-- ── 3. VERIFY ─────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'confirm_test_users'
  ) THEN
    RAISE EXCEPTION '[006] VERIFICATION FAILED: confirm_test_users function not found.';
  END IF;
  RAISE NOTICE '[006] confirm_test_users: present. ✓';

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'seed_ci_fixtures'
  ) THEN
    RAISE EXCEPTION '[006] VERIFICATION FAILED: seed_ci_fixtures function not found.';
  END IF;
  RAISE NOTICE '[006] seed_ci_fixtures: present. ✓';

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'seed_ci_fixtures_v2'
  ) THEN
    RAISE EXCEPTION '[006] VERIFICATION FAILED: seed_ci_fixtures_v2 function not found.';
  END IF;
  RAISE NOTICE '[006] seed_ci_fixtures_v2: present. ✓';
END $$;

-- ── POST-MIGRATION NOTES ──────────────────────────────────────────────────────
--
-- Usage from shell (idempotent — safe to call multiple times):
--
--   curl -s "https://gaavynmmysdhovpatzlp.supabase.co/rest/v1/rpc/confirm_test_users" \
--        -H "apikey: sb_publishable_1BPrFxSYIb__I7JZUbgimQ_RZcVR_oU" \
--        -H "Content-Type: application/json" \
--        -d '{"user_email":"player_one_rls@test.atlas"}'
--
--   curl -s "https://gaavynmmysdhovpatzlp.supabase.co/rest/v1/rpc/seed_ci_fixtures" \
--        -H "apikey: sb_publishable_1BPrFxSYIb__I7JZUbgimQ_RZcVR_oU" \
--        -H "Content-Type: application/json" \
--        -d '{}'
--
-- The confirm_test_users function rejects any email not in the allow-list
-- with SQLSTATE 42501 (insufficient_privilege), surfaced as HTTP 403 by PostgREST.
