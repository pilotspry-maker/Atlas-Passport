-- ============================================================================
-- Migration 027 - Align CI seed UUIDs to test contract + gate rewards reads
-- ============================================================================
--
-- WHY THIS EXISTS:
--   PR #40 RLS Security Tests run: 20/21 pass, last failure is
--   test_complete_passport_can_read_reward, plus the rls-regression and
--   rls-exploit jobs failing on the same UUID drift root cause.
--
--   Two coupled drifts to fix:
--
--   1. tests/rls/test_rls_policies.py expects deterministic fixtures at:
--        CORRIDOR_ID = aaaaaaaa-0000-0000-0000-000000000001
--        NODE_ID     = bbbbbbbb-0000-0000-0000-000000000001
--        REWARD_ID   = cccccccc-0000-0000-0000-000000000001
--                       (redemption_code = SECRET-CODE-XYZ)
--      But:
--        - seed_ci_fixtures() creates corridor/node/reward at 00000000-... and
--          never sets redemption_code.
--        - seed_ci_passports() (migration 022) inserts passports at the same
--          legacy 00000000-... corridor_id.
--      Net effect: every test that filters by CORRIDOR_ID or REWARD_ID misses.
--
--   2. rewards_select_auth policy was USING(true) FOR authenticated, so any
--      signed-in user could read every reward including redemption_code.
--      Once we create reward cccccccc-..., test_active_passport_cannot_read_reward
--      would FAIL because player_one (active passport, NOT complete) would see it.
--
-- FIX:
--   Part A - data migration: free up the slug ci-test-corridor, move existing
--            check_ins/passports off the legacy corridor onto the new
--            aaaaaaaa-... corridor, then delete the legacy rows.
--   Part B - replace seed_ci_fixtures() to upsert at the aaaaaaaa/bbbbbbbb/
--            cccccccc-... ids with SECRET-CODE-XYZ.
--   Part C - replace seed_ci_passports() to point at the aaaaaaaa-... corridor.
--   Part D - tighten rewards_select_auth to require a complete passport on
--            that corridor.
--
-- IDEMPOTENT: every step uses ON CONFLICT DO UPDATE / IF EXISTS / IS NULL guard.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Part A - Data migration: drain the legacy 00000000-... CI test corridor
-- ----------------------------------------------------------------------------

-- A1. Create the new corridor + node ahead of repointing, with a TEMP slug
--     so it doesn't collide with the legacy row's "ci-test-corridor" slug.
INSERT INTO public.corridors (id, name, slug, city, country, description, is_active)
VALUES (
  'aaaaaaaa-0000-0000-0000-000000000001',
  'CI Test Corridor',
  'ci-test-corridor-pending-027',
  'Test City', 'US',
  'Seeded by CI for RLS tests',
  TRUE
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.nodes (id, corridor_id, name, is_active, sequence)
VALUES (
  'bbbbbbbb-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'CI Test Node', TRUE, 1
)
ON CONFLICT (id) DO NOTHING;

-- A2. Repoint check_ins from the legacy node to the new node.
UPDATE public.check_ins
SET node_id = 'bbbbbbbb-0000-0000-0000-000000000001'
WHERE node_id = '00000000-0000-0000-0000-000000000002';

-- A3. Repoint passports from the legacy corridor to the new corridor.
--     passports has UNIQUE (user_id, corridor_id) - clean up any duplicate
--     pairing defensively before the UPDATE.
DELETE FROM public.passports p
USING public.passports q
WHERE p.user_id     = q.user_id
  AND p.corridor_id = '00000000-0000-0000-0000-000000000001'
  AND q.corridor_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  AND p.id <> q.id;

UPDATE public.passports
SET corridor_id = 'aaaaaaaa-0000-0000-0000-000000000001'
WHERE corridor_id = '00000000-0000-0000-0000-000000000001';

-- A4. Drop the legacy reward, node, corridor.
DELETE FROM public.rewards   WHERE id = '00000000-0000-0000-0000-000000000003';
DELETE FROM public.nodes     WHERE id = '00000000-0000-0000-0000-000000000002';
DELETE FROM public.corridors WHERE id = '00000000-0000-0000-0000-000000000001';

-- A5. Promote the new corridor's slug to the canonical value.
UPDATE public.corridors
SET slug = 'ci-test-corridor'
WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- ----------------------------------------------------------------------------
-- Part B - Realign seed_ci_fixtures() to the test UUID contract
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.seed_ci_fixtures();

CREATE OR REPLACE FUNCTION public.seed_ci_fixtures()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  CORRIDOR_ID UUID := 'aaaaaaaa-0000-0000-0000-000000000001';
  NODE_ID     UUID := 'bbbbbbbb-0000-0000-0000-000000000001';
  REWARD_ID   UUID := 'cccccccc-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO public.corridors (id, name, slug, city, country, description, is_active)
  VALUES (
    CORRIDOR_ID, 'CI Test Corridor', 'ci-test-corridor', 'Test City', 'US',
    'Seeded by CI for RLS tests', TRUE
  )
  ON CONFLICT (id) DO UPDATE
    SET is_active = TRUE,
        slug      = EXCLUDED.slug,
        name      = EXCLUDED.name;

  INSERT INTO public.nodes (id, corridor_id, name, is_active, sequence)
  VALUES (NODE_ID, CORRIDOR_ID, 'CI Test Node', TRUE, 1)
  ON CONFLICT (id) DO UPDATE
    SET is_active   = TRUE,
        corridor_id = EXCLUDED.corridor_id,
        sequence    = EXCLUDED.sequence;

  INSERT INTO public.rewards (id, corridor_id, title, description, redemption_code)
  VALUES (
    REWARD_ID, CORRIDOR_ID, 'CI Test Reward', 'Seeded by CI', 'SECRET-CODE-XYZ'
  )
  ON CONFLICT (id) DO UPDATE
    SET corridor_id     = EXCLUDED.corridor_id,
        title           = EXCLUDED.title,
        redemption_code = EXCLUDED.redemption_code;

  RETURN json_build_object(
    'corridor_id', CORRIDOR_ID,
    'node_id',     NODE_ID,
    'reward_id',   REWARD_ID,
    'migration',   '027'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_ci_fixtures() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.seed_ci_fixtures() FROM anon;
REVOKE EXECUTE ON FUNCTION public.seed_ci_fixtures() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.seed_ci_fixtures() TO service_role;

-- ----------------------------------------------------------------------------
-- Part C - Realign seed_ci_passports() to the test UUID contract
-- ----------------------------------------------------------------------------

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
  v_now                TIMESTAMPTZ := now();
BEGIN
  INSERT INTO public.profiles (id, email, full_name, is_admin)
  VALUES
    (P1_ID, 'player_one_rls@test.atlasci.com', 'RLS Exploit Player One', false),
    (P2_ID, 'player_two_rls@test.atlasci.com', 'RLS Exploit Player Two', false)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.corridors (id, name, slug, city, country, is_active)
  VALUES (CORRIDOR_ID, 'CI Test Corridor', 'ci-test-corridor', 'Test City', 'US', TRUE)
  ON CONFLICT (id) DO UPDATE SET is_active = TRUE;

  INSERT INTO public.nodes (id, corridor_id, name, sequence, is_active)
  VALUES (NODE_ID, CORRIDOR_ID, 'CI Test Node', 1, TRUE)
  ON CONFLICT (id) DO UPDATE SET is_active = TRUE;

  INSERT INTO public.passports (
    id, user_id, corridor_id, status,
    activated_at, expires_at, reward_claimed
  )
  VALUES
    (PASSPORT_ACTIVE_ID,   P1_ID, CORRIDOR_ID, 'active',
     v_now, v_now + INTERVAL '30 days', FALSE),
    (PASSPORT_COMPLETE_ID, P2_ID, CORRIDOR_ID, 'complete',
     v_now, v_now + INTERVAL '30 days', FALSE)
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
    'corridor_id',          CORRIDOR_ID,
    'node_id',              NODE_ID,
    'status',               'ok',
    'migration',            '027'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM anon;
REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.seed_ci_passports() TO service_role;

-- ----------------------------------------------------------------------------
-- Part D - Gate rewards SELECT behind a completed passport on that corridor
-- ----------------------------------------------------------------------------
-- Old policy: rewards_select_auth USING (true) FOR authenticated leaked the
-- redemption_code to any signed-in user. Replace it with a per-corridor
-- completion check. Service role bypasses RLS so admin paths still work.
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS rewards_select_auth ON public.rewards;

CREATE POLICY rewards_select_auth ON public.rewards
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.passports p
      WHERE p.user_id     = auth.uid()
        AND p.corridor_id = rewards.corridor_id
        AND p.status      = 'complete'
    )
  );

DO $$
BEGIN
  RAISE NOTICE '[027] CI seed UUIDs aligned + rewards gated on complete passport';
END;
$$;
