-- ════════════════════════════════════════════════════════════════════════════
-- Migration 022 — Align seed_ci_passports() UUIDs with deployed seed_ci_fixtures
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   The repo's migration 015 (and my 020) defines seed_ci_passports() with
--   corridor_id = aaaaaaaa-0000-...0001, but the function deployed in prod as
--   seed_ci_fixtures() actually creates corridor 00000000-0000-...0001 and
--   node 00000000-0000-...0002. Result: even with the right service_role
--   key in CI, seed_ci_passports() fails with:
--
--     ERROR 23503: insert or update on table "passports" violates foreign
--                  key constraint "passports_corridor_id_fkey"
--     DETAIL: Key (corridor_id)=(aaaaaaaa-0000-0000-0000-000000000001) is
--             not present in table "corridors".
--
--   Verified live on 2026-06-27 in project gaavynmmysdhovpatzlp.
--
--   Root cause is migration registry drift: seed_ci_fixtures was applied
--   manually with different UUIDs than seed_ci_passports references. The
--   repo never had a definition of seed_ci_fixtures, so the two helpers
--   diverged.
--
-- FIX:
--   1. Align seed_ci_passports() corridor_id/node_id to the actual deployed
--      values (00000000-... family).
--   2. Make seed_ci_passports() self-sufficient — upsert the corridor and
--      node it needs BEFORE inserting passports. This removes the ordering
--      dependency on seed_ci_fixtures() and makes the function robust to
--      any future re-deploys of seed_ci_fixtures.
--   3. Fill the NOT NULL columns passports.activated_at and
--      passports.expires_at (omitted in repo migration 015 — would have
--      failed if anyone ever rebuilt the schema from scratch).
--
-- SAFETY:
--   - CREATE OR REPLACE — re-applicable.
--   - corridor/node upserts use ON CONFLICT DO NOTHING so they never clobber
--     real data.
-- ════════════════════════════════════════════════════════════════════════════

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
  -- Aligned with deployed seed_ci_fixtures() — 00000000-... family.
  CORRIDOR_ID          UUID := '00000000-0000-0000-0000-000000000001';
  NODE_ID              UUID := '00000000-0000-0000-0000-000000000002';
  PASSPORT_ACTIVE_ID   UUID := 'dddddddd-0000-0000-0000-000000000001';
  PASSPORT_COMPLETE_ID UUID := 'dddddddd-0000-0000-0000-000000000002';
  CHECKIN_ID           UUID := 'eeeeeeee-0000-0000-0000-000000000001';
  v_now                TIMESTAMPTZ := now();
BEGIN
  -- ── Defensive profiles backfill ────────────────────────────────────────
  INSERT INTO public.profiles (id, email, full_name, is_admin)
  VALUES
    (P1_ID, 'player_one_rls@test.atlasci.com', 'RLS Exploit Player One', false),
    (P2_ID, 'player_two_rls@test.atlasci.com', 'RLS Exploit Player Two', false)
  ON CONFLICT (id) DO NOTHING;

  -- ── Defensive corridor + node upsert ───────────────────────────────────
  -- Removes ordering dependency on seed_ci_fixtures().
  INSERT INTO public.corridors (id, name, slug, city, country, is_active)
  VALUES (CORRIDOR_ID, 'CI Test Corridor', 'ci-test-corridor', 'Test City', 'US', TRUE)
  ON CONFLICT (id) DO UPDATE SET is_active = TRUE;

  INSERT INTO public.nodes (id, corridor_id, name, sequence, is_active)
  VALUES (NODE_ID, CORRIDOR_ID, 'CI Test Node', 1, TRUE)
  ON CONFLICT (id) DO UPDATE SET is_active = TRUE;

  -- ── Passports — supply activated_at + expires_at (both NOT NULL) ───────
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

  -- ── Check-in ──────────────────────────────────────────────────────────
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

DO $$
BEGIN
  RAISE NOTICE '[022] seed_ci_passports aligned to deployed corridor UUIDs + self-seeds corridor/node ✓';
END;
$$;
