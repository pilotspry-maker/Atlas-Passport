-- Migration 022 — Align seed_ci_passports UUIDs and seed corridor/node
-- Recovered from production schema_migrations on 2026-06-27

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
  CORRIDOR_ID          UUID := '00000000-0000-0000-0000-000000000001';
  NODE_ID              UUID := '00000000-0000-0000-0000-000000000002';
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
    'migration',            '022'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM anon;
REVOKE EXECUTE ON FUNCTION public.seed_ci_passports() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.seed_ci_passports() TO service_role;
