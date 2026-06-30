-- Migration 036: make seed_ci_passports idempotent for reward_claimed
--
-- Background
-- ----------
-- The RLS exploit test exploit-03 ("reward_claimed state reversal") sets
-- passports.reward_claimed = true on PASSPORT_COMPLETE_ID via service role
-- to set up its trigger-firing assertion. The prevent_reward_unclaim trigger
-- (migration 005) intentionally blocks any subsequent UPDATE that flips
-- reward_claimed true → false, even via service role.
--
-- The seed_ci_passports RPC (migration 015/027) is used between test runs to
-- reset fixture state, but its ON CONFLICT DO UPDATE list omits reward_claimed:
--
--     ON CONFLICT (id) DO UPDATE SET
--       user_id     = EXCLUDED.user_id,
--       corridor_id = EXCLUDED.corridor_id,
--       status      = EXCLUDED.status;
--
-- Adding `reward_claimed = EXCLUDED.reward_claimed` is not sufficient on its
-- own — the prevent_reward_unclaim trigger will reject the UPDATE for any
-- row whose committed reward_claimed is already true (which it always is
-- after the first exploit-03 run). This causes the seed step to succeed
-- (it raises only on the prior assignment) — but the row state stays true,
-- and the next exploit-03 run sees the residue and 1a's ground-truth check
-- fails.
--
-- Fix
-- ---
-- Bracket the upsert with `SET LOCAL session_replication_role = replica`,
-- which skips user-defined triggers for the duration of the function call.
-- This is the canonical Postgres pattern for a privileged, scoped trigger
-- bypass and is safe here because:
--   - The function is SECURITY DEFINER, owned by postgres, callable only
--     from service_role.
--   - SET LOCAL is transaction-scoped and reverts on commit/rollback.
--   - The trigger is restored for all subsequent UPDATE traffic the moment
--     the seed call returns.
--   - Application paths (anon, authenticated) never call this RPC.
--
-- This makes the seed truly idempotent: each run rewrites the complete
-- passport with reward_claimed = false regardless of prior test pollution.
--
-- Blast radius
-- ------------
-- - No schema change. No data change for production paths.
-- - Function signature unchanged.
-- - Trigger prevent_reward_unclaim remains active for all non-RPC traffic.
-- - search_path is unchanged (public, extensions) per the migration 027 baseline.

create or replace function public.seed_ci_passports()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
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
  -- Profiles and corridor/node setup — unchanged from migration 027.
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

  -- ── Bypass user-defined triggers for the passports upsert only ────────
  -- This skips prevent_reward_unclaim so we can reset reward_claimed=false
  -- between test runs. SET LOCAL is transaction-scoped; the trigger is
  -- restored for all other paths the instant this function returns.
  SET LOCAL session_replication_role = replica;

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
    user_id        = EXCLUDED.user_id,
    corridor_id    = EXCLUDED.corridor_id,
    status         = EXCLUDED.status,
    reward_claimed = EXCLUDED.reward_claimed;

  -- Restore default trigger behaviour for the rest of the function.
  SET LOCAL session_replication_role = origin;

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
    'migration',            '036'
  );
END;
$function$;
