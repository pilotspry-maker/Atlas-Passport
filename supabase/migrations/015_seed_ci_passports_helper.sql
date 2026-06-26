-- ════════════════════════════════════════════════════════════════════════════
-- Migration 015 — seed_ci_passports() + seed_regression_passports() helpers
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   The CI seeding workflows insert passports and check-ins using the
--   Supabase service role key via REST API. The service role bypasses RLS
--   for tables WITHOUT INSERT policies (corridors, nodes, rewards succeed).
--   But public.passports has:
--     CREATE POLICY "passports_insert_own" ... WITH CHECK (user_id = auth.uid())
--   When the service role makes a fresh INSERT (no existing row to conflict
--   against), PostgreSQL evaluates the WITH CHECK expression. On some Supabase
--   configurations the service_role role does not have the BYPASSRLS attribute
--   wired correctly for WITH CHECK, causing 401 "new row violates row-level
--   security policy for table passports".
--
--   Fix: seed passports and check-ins via SECURITY DEFINER RPCs (same
--   pattern as seed_ci_fixtures / seed_ci_fixtures_v2). SECURITY DEFINER
--   functions run as the function owner (postgres superuser) and bypass
--   RLS entirely, regardless of the calling role.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. seed_ci_passports — exploit suite ─────────────────────────────────────

DROP FUNCTION IF EXISTS public.seed_ci_passports();

CREATE OR REPLACE FUNCTION public.seed_ci_passports()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  -- Deterministic user UUIDs — must match create_exploit_test_users (migration 016)
  P1_ID UUID := 'aaaaaaaa-0011-0000-0000-000000000000';
  P2_ID UUID := 'aaaaaaaa-0022-0000-0000-000000000000';

  -- Fixture UUIDs — must match rls-exploit-tests.yml and exploit test client.ts FIXTURES
  CORRIDOR_ID          UUID := 'aaaaaaaa-0000-0000-0000-000000000001';
  NODE_ID              UUID := 'bbbbbbbb-0000-0000-0000-000000000001';
  PASSPORT_ACTIVE_ID   UUID := 'dddddddd-0000-0000-0000-000000000001';
  PASSPORT_COMPLETE_ID UUID := 'dddddddd-0000-0000-0000-000000000002';
  CHECKIN_ID           UUID := 'eeeeeeee-0000-0000-0000-000000000001';
BEGIN
  -- passports (idempotent)
  INSERT INTO public.passports (id, user_id, corridor_id, status)
  VALUES
    (PASSPORT_ACTIVE_ID,   P1_ID, CORRIDOR_ID, 'active'),
    (PASSPORT_COMPLETE_ID, P2_ID, CORRIDOR_ID, 'complete')
  ON CONFLICT (id) DO UPDATE SET
    user_id    = EXCLUDED.user_id,
    corridor_id = EXCLUDED.corridor_id,
    status     = EXCLUDED.status;

  -- check_ins (idempotent)
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
    'status',               'ok'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM anon;
REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.seed_ci_passports() TO service_role;

-- ── 2. seed_regression_passports — regression suite ──────────────────────────
--
-- Seeds ALL regression fixtures: corridors, node, reward, passports, check-in.
-- Uses SECURITY DEFINER to bypass RLS entirely — the service_role BYPASSRLS
-- attribute is not reliable on all Supabase configurations, so all inserts
-- go through this function rather than direct REST calls.

DROP FUNCTION IF EXISTS public.seed_regression_passports();

CREATE OR REPLACE FUNCTION public.seed_regression_passports()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  -- Deterministic user UUIDs — must match create_regression_users (migration 009+)
  P1_ID UUID := 'bbbbbbbb-0001-0000-0000-000000000000';
  P2_ID UUID := 'bbbbbbbb-0002-0000-0000-000000000000';

  -- Fixture UUIDs — must match rls-regression.yml and regression test files
  CORRIDOR_ACTIVE_ID   UUID := 'cccc0001-0000-0000-0000-000000000001';
  CORRIDOR_INACTIVE_ID UUID := 'cccc0001-0000-0000-0000-000000000002';
  NODE_ID              UUID := 'cccc0002-0000-0000-0000-000000000001';
  REWARD_ID            UUID := 'cccc0005-0000-0000-0000-000000000001';
  PASSPORT_ACTIVE_ID   UUID := 'cccc0003-0000-0000-0000-000000000001';
  PASSPORT_COMPLETE_ID UUID := 'cccc0003-0000-0000-0000-000000000002';
  PASSPORT_OTHER_ID    UUID := 'cccc0003-0000-0000-0000-000000000003';
  CHECKIN_SEED_ID      UUID := 'cccc0004-0000-0000-0000-000000000001';
BEGIN
  -- corridors (idempotent) — seeded here because svc_upsert via REST fails
  -- on some Supabase configs where service_role does not have BYPASSRLS.
  INSERT INTO public.corridors (id, name, city, country, is_active)
  VALUES
    (CORRIDOR_ACTIVE_ID,   'Regression Corridor Active',   'Test City', 'US', TRUE),
    (CORRIDOR_INACTIVE_ID, 'Regression Corridor Inactive', 'Test City', 'US', FALSE)
  ON CONFLICT (id) DO NOTHING;

  -- node (idempotent)
  INSERT INTO public.nodes (id, corridor_id, name, sequence, latitude, longitude, is_active)
  VALUES (NODE_ID, CORRIDOR_ACTIVE_ID, 'Regression Node', 1, 38.9, -77.0, TRUE)
  ON CONFLICT (id) DO NOTHING;

  -- reward (idempotent)
  INSERT INTO public.rewards (id, corridor_id, title, description, redemption_code)
  VALUES (REWARD_ID, CORRIDOR_ACTIVE_ID, 'Regression Reward', 'Regression test reward', 'REG-TEST-001')
  ON CONFLICT (id) DO NOTHING;

  -- passports (idempotent)
  INSERT INTO public.passports (id, user_id, corridor_id, status)
  VALUES
    (PASSPORT_ACTIVE_ID,   P1_ID, CORRIDOR_ACTIVE_ID, 'active'),
    (PASSPORT_COMPLETE_ID, P2_ID, CORRIDOR_ACTIVE_ID, 'complete'),
    (PASSPORT_OTHER_ID,    P2_ID, CORRIDOR_ACTIVE_ID, 'active')
  ON CONFLICT (id) DO UPDATE SET
    user_id     = EXCLUDED.user_id,
    corridor_id = EXCLUDED.corridor_id,
    status      = EXCLUDED.status;

  -- check_ins (idempotent)
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
    'status',               'ok'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_regression_passports() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.seed_regression_passports() FROM anon;
REVOKE EXECUTE ON FUNCTION public.seed_regression_passports() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.seed_regression_passports() TO service_role;

DO $$
BEGIN
  RAISE NOTICE '[015] seed_ci_passports + seed_regression_passports created. ✓';
  RAISE NOTICE '[015] Apply this migration, then CI seed steps will bypass RLS entirely.';
END;
$$;
