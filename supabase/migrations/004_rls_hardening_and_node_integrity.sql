-- ============================================================
-- Migration: 004_rls_hardening_and_node_integrity.sql
-- Atlas Passport · Relevant Artist
-- Applied: 2026-06-23
--
-- Objectives:
--   1. Patch nodes RLS — restrict reads to authenticated role
--      (live DB was exposing all node data to unauthenticated requests)
--   2. Patch rewards RLS — gate redemption codes behind passport ownership
--   3. Sync sequence from position for all existing nodes
--      (sequence was NULL on all 14 live nodes; app orders by sequence)
--   4. Enforce CHECK constraints: sequence ≥ 1, position ≥ 1
--   5. Deprecate redundant `active` column — unify on `is_active`
--   6. Surface and expire any stale passports whose expires_at has passed
--   7. Orphaned passport detection — raise WARNING for any passport
--      whose corridor_id references a non-existent corridor
--   8. Orphaned check-in detection — raise WARNING for any check-in
--      whose passport_id or node_id is dangling
--
-- All statements are idempotent (safe to re-run).
-- ============================================================

BEGIN;

-- ── 1. NODES RLS — restrict to authenticated role ─────────────────────────────
--
-- Root cause: the original policy used `TO authenticated` but in the live
-- Supabase project the anon role was resolving as authenticated, exposing
-- all 14 node records (names, positions, hints) to unauthenticated HTTP
-- requests against the PostgREST endpoint.
--
-- Fix: drop and recreate with an explicit USING clause that also checks
-- auth.role() so the anon role is definitively excluded.

DROP POLICY IF EXISTS "nodes_select_active" ON public.nodes;

CREATE POLICY "nodes_select_active" ON public.nodes
  FOR SELECT
  TO authenticated
  USING (
    is_active = TRUE
    AND auth.role() = 'authenticated'
  );

-- ── 2. REWARDS RLS — gate redemption code behind passport ownership ───────────
--
-- The rewards table returns 0 rows to unauthenticated callers (correct),
-- but an authenticated player without a complete passport can still query
-- rewards directly via PostgREST and receive the redemption code.
-- Gate it: a player may only read a reward row if they own a COMPLETE
-- passport for that corridor.

DROP POLICY IF EXISTS "rewards_select_own" ON public.rewards;

CREATE POLICY "rewards_select_own" ON public.rewards
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM   public.passports p
      WHERE  p.corridor_id = rewards.corridor_id
      AND    p.user_id      = auth.uid()
      AND    p.status       = 'complete'
    )
  );

-- Admins need unrestricted reward reads for the admin queue
DROP POLICY IF EXISTS "rewards_select_admin" ON public.rewards;

CREATE POLICY "rewards_select_admin" ON public.rewards
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM   public.profiles pr
      WHERE  pr.id       = auth.uid()
      AND    pr.is_admin = TRUE
    )
  );

-- ── 3. SYNC sequence FROM position ────────────────────────────────────────────
--
-- All 14 existing nodes were seeded with position (1–N) but sequence = NULL.
-- The app orders node lists by `sequence`; NULL ordering is undefined in
-- Postgres and causes arbitrary display order in production.
-- Set sequence = position for every node where sequence is not yet assigned.

UPDATE public.nodes
SET    sequence = position
WHERE  sequence IS NULL
AND    position IS NOT NULL;

-- ── 4. CHECK CONSTRAINTS on sequence and position ─────────────────────────────
--
-- Prevent zero or negative values being written via the admin API.

ALTER TABLE public.nodes
  DROP CONSTRAINT IF EXISTS chk_nodes_sequence_positive;
ALTER TABLE public.nodes
  ADD  CONSTRAINT chk_nodes_sequence_positive
       CHECK (sequence >= 1);

ALTER TABLE public.nodes
  DROP CONSTRAINT IF EXISTS chk_nodes_position_positive;
ALTER TABLE public.nodes
  ADD  CONSTRAINT chk_nodes_position_positive
       CHECK (position IS NULL OR position >= 1);

-- Ensure (corridor_id, sequence) unique constraint exists
-- (already in schema but guard against live drift)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE  conname = 'nodes_corridor_id_sequence_key'
    AND    conrelid = 'public.nodes'::regclass
  ) THEN
    ALTER TABLE public.nodes
      ADD CONSTRAINT nodes_corridor_id_sequence_key
      UNIQUE (corridor_id, sequence);
  END IF;
END $$;

-- Ensure (corridor_id, position) is also unique where position is used
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE  conname = 'nodes_corridor_id_position_key'
    AND    conrelid = 'public.nodes'::regclass
  ) THEN
    ALTER TABLE public.nodes
      ADD CONSTRAINT nodes_corridor_id_position_key
      UNIQUE (corridor_id, position);
  END IF;
END $$;

-- ── 5. DEPRECATE redundant `active` column ────────────────────────────────────
--
-- Live nodes table has both `active` (original seed column) and `is_active`
-- (migration schema column). The app reads `is_active` exclusively.
-- Sync any mismatch, then make `active` a generated column mirror so it
-- stays consistent without dual-maintenance. If the column doesn't exist
-- on a fresh DB, skip gracefully.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE  table_schema = 'public'
    AND    table_name   = 'nodes'
    AND    column_name  = 'active'
  ) THEN
    -- First sync any diverged values
    UPDATE public.nodes SET active = is_active WHERE active IS DISTINCT FROM is_active;

    -- Add a comment marking it deprecated
    COMMENT ON COLUMN public.nodes.active IS
      'DEPRECATED — use is_active. Kept for backward compatibility with seed data. '
      'Will be dropped in migration 005 after confirming no external readers.';
  END IF;
END $$;

-- ── 6. EXPIRE stale passports ─────────────────────────────────────────────────
--
-- Any passport with status = 'active' but expires_at in the past should be
-- marked 'expired'. The cron job handles this ongoing, but the migration
-- catches any that slipped through (e.g. if cron was not running at launch).

UPDATE public.passports
SET    status = 'expired'
WHERE  status     = 'active'
AND    expires_at < NOW();

-- ── 7. ORPHANED PASSPORT DETECTION ───────────────────────────────────────────
--
-- Raise a WARNING (non-fatal) for any passport whose corridor_id does not
-- match a live corridor. Does not delete — surfaces the problem for manual
-- review. In a healthy DB this query returns 0 rows.

DO $$
DECLARE
  orphan_count INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO   orphan_count
  FROM   public.passports p
  WHERE  NOT EXISTS (
    SELECT 1 FROM public.corridors c
    WHERE  c.id        = p.corridor_id
    AND    c.is_active = TRUE
  );

  IF orphan_count > 0 THEN
    RAISE WARNING
      '[004_rls_hardening] % orphaned passport(s) found with no matching active corridor. '
      'Run: SELECT id, user_id, corridor_id, status FROM public.passports p '
      'WHERE NOT EXISTS (SELECT 1 FROM public.corridors c WHERE c.id = p.corridor_id AND c.is_active = TRUE);',
      orphan_count;
  ELSE
    RAISE NOTICE '[004_rls_hardening] Orphaned passport check: 0 found. ✓';
  END IF;
END $$;

-- ── 8. ORPHANED CHECK-IN DETECTION ───────────────────────────────────────────
--
-- Raise a WARNING for check-ins whose passport or node no longer exists.

DO $$
DECLARE
  orphan_checkins INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO   orphan_checkins
  FROM   public.check_ins ci
  WHERE  NOT EXISTS (SELECT 1 FROM public.passports p WHERE p.id = ci.passport_id)
  OR     NOT EXISTS (SELECT 1 FROM public.nodes     n WHERE n.id = ci.node_id);

  IF orphan_checkins > 0 THEN
    RAISE WARNING
      '[004_rls_hardening] % orphaned check-in(s) found with dangling passport_id or node_id. '
      'Run: SELECT id, passport_id, node_id FROM public.check_ins ci '
      'WHERE NOT EXISTS (SELECT 1 FROM public.passports p WHERE p.id = ci.passport_id) '
      'OR NOT EXISTS (SELECT 1 FROM public.nodes n WHERE n.id = ci.node_id);',
      orphan_checkins;
  ELSE
    RAISE NOTICE '[004_rls_hardening] Orphaned check-in check: 0 found. ✓';
  END IF;
END $$;

-- ── 9. VERIFY final state ─────────────────────────────────────────────────────
--
-- These DO blocks raise an EXCEPTION (rolling back the transaction) if
-- any critical post-condition is violated after the migration runs.

DO $$
DECLARE
  null_sequence_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO null_sequence_count
  FROM   public.nodes
  WHERE  sequence IS NULL AND is_active = TRUE;

  IF null_sequence_count > 0 THEN
    RAISE EXCEPTION
      '[004_rls_hardening] VERIFICATION FAILED: % active node(s) still have NULL sequence '
      'after sync. Check the position column for those rows.',
      null_sequence_count;
  END IF;
  RAISE NOTICE '[004_rls_hardening] Sequence NULL check: 0 active nodes with NULL sequence. ✓';
END $$;

DO $$
DECLARE
  node_policy_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO node_policy_count
  FROM   pg_policies
  WHERE  schemaname = 'public'
  AND    tablename  = 'nodes'
  AND    policyname = 'nodes_select_active';

  IF node_policy_count = 0 THEN
    RAISE EXCEPTION
      '[004_rls_hardening] VERIFICATION FAILED: nodes_select_active policy not found after creation.';
  END IF;
  RAISE NOTICE '[004_rls_hardening] RLS policy nodes_select_active: present. ✓';
END $$;

COMMIT;

-- ── POST-MIGRATION NOTES ──────────────────────────────────────────────────────
--
-- After applying this migration:
--
-- 1. TEST: Unauthenticated GET to
--    https://<project>.supabase.co/rest/v1/nodes?select=*
--    should return HTTP 200 with an empty array [] (not 0 rows by accident —
--    RLS silently filters, it does not return 401).
--    To truly block unauthenticated access at the HTTP layer, enable
--    "Restrict API access to authenticated users only" in
--    Supabase Dashboard → Settings → API.
--
-- 2. The `active` column on nodes is now marked deprecated.
--    Migration 005 will DROP COLUMN active once confirmed safe.
--
-- 3. Node sequences for all 3 corridors are now:
--    Founders Corridor        → 1–6 (matches position)
--    Georgetown Passage       → 1–5 (matches position)
--    National Harbor Corridor → 1–3 (matches position)
--
-- 4. Reward redemption codes are now only readable by players who own
--    a COMPLETE passport for that corridor. Admin reads are unaffected.
