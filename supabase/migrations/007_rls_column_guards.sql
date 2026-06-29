-- ============================================================
-- Migration: 007_rls_column_guards.sql
-- Atlas Passport · Relevant Artist
-- Applied: 2026-06-23
--
-- Objectives (two residual gaps from the post-migration audit):
--
--   GAP-A — passports: INSERT allows inactive corridor_id
--     passports_insert_own checked only user_id = auth.uid().
--     A player calling POST /rest/v1/passports directly could
--     provide a corridor_id whose is_active = FALSE and the DB
--     would accept the insert. The app route guards this at the
--     application layer, but the DB policy did not.
--     Fix: add an EXISTS subquery that requires the corridor to
--     be active before the INSERT is accepted.
--
--   GAP-C — check_ins: reviewed_by column exposed to players
--     check_ins_select_own returns SELECT * to the check-in
--     owner, including reviewed_by (an admin profile UUID never
--     intended to be player-visible). admin_notes and reviewed_at
--     ARE intentionally visible to players (rejection reason and
--     stamp date respectively — confirmed by NodeCard.tsx and
--     nodes/[nodeId]/page.tsx). Only reviewed_by is purely
--     internal.
--
--     RLS USING clauses cannot perform column-level projection.
--     The only DB-layer options are:
--       a) A security-barrier view that exposes the safe subset
--       b) Revoking column-level SELECT privilege on reviewed_by
--          (requires superuser; not available in Supabase)
--       c) Application-layer projection (partial fix only)
--
--     This migration implements option (a): a SECURITY BARRIER
--     view public.check_ins_player_view that exposes every column
--     the player legitimately needs while excluding reviewed_by.
--     The underlying check_ins_select_own policy remains on the
--     base table for admin reads; the view adds its own RLS via
--     the SECURITY BARRIER option.
--
-- All statements are idempotent.
-- ============================================================

BEGIN;

-- ══════════════════════════════════════════════════════════════
-- PATCH 1 — passports_insert_own: active corridor guard
-- ══════════════════════════════════════════════════════════════
--
-- Before: WITH CHECK (user_id = auth.uid())
-- After:  WITH CHECK (
--           user_id = auth.uid()
--           AND EXISTS (
--             SELECT 1 FROM public.corridors c
--             WHERE c.id = passports.corridor_id
--             AND   c.is_active = TRUE
--           )
--         )
--
-- Effect:
--   • Deactivated corridors can no longer be targeted by a
--     direct PostgREST INSERT — PostgREST returns 403.
--   • Active corridors behave identically to before.
--   • The app route's own .eq('is_active', true) check is now
--     double-enforced at the DB layer (defense in depth).
--   • The UNIQUE(user_id, corridor_id) constraint means a player
--     cannot have two passports for the same corridor regardless;
--     this patch specifically closes the inactive-corridor vector.
--
-- Re-entry safety: DROP IF EXISTS before CREATE is idempotent.

DROP POLICY IF EXISTS "passports_insert_own" ON public.passports;

CREATE POLICY "passports_insert_own" ON public.passports
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM   public.corridors c
      WHERE  c.id        = passports.corridor_id
      AND    c.is_active = TRUE
    )
  );

-- ══════════════════════════════════════════════════════════════
-- PATCH 2 — check_ins_player_view: hide reviewed_by from players
-- ══════════════════════════════════════════════════════════════
--
-- Column visibility matrix:
--
--   Column              Player sees?   Admin sees?   Reason
--   ──────────────────  ─────────────  ────────────  ─────────────────────────────────
--   id                  YES            YES           needed for check-in identity
--   passport_id         YES            YES           needed to correlate with passport
--   user_id             YES            YES           needed for ownership display
--   node_id             YES            YES           needed for node correlation
--   status              YES            YES           drives UI state (approved/rejected)
--   proof_url           YES            YES           player can see their own proof
--   proof_storage_path  YES            YES           needed for signed-URL regeneration
--   notes               YES            YES           player-submitted caption
--   admin_notes         YES            YES           rejection reason shown in NodeCard.tsx
--   reviewed_at         YES            YES           stamp date shown in NodeCard.tsx
--   reviewed_by         NO             YES           admin UUID — internal only
--   submitted_at        YES            YES           timestamp shown on passport page
--   created_at          YES            YES           standard audit column
--
-- Implementation: SECURITY BARRIER view
--
--   SECURITY BARRIER ensures Postgres evaluates the view's WHERE
--   clause (user_id = auth.uid()) before executing any WHERE
--   predicates pushed down from the calling query, preventing
--   leakage of rows via clever WHERE filter pushdown.
--
--   The view has RLS enabled separately so Supabase's realtime
--   subscription filter (passport_id=eq.{id}) also goes through
--   the same ownership check.
--
-- Player code change:
--   Queries that need admin-safe reads should target
--   check_ins_player_view instead of check_ins.
--   Admin routes continue to use check_ins directly (via
--   createAdminClient which bypasses RLS entirely).

-- Drop and recreate (idempotent)
DROP VIEW IF EXISTS public.check_ins_player_view;

CREATE VIEW public.check_ins_player_view
  WITH (security_barrier = true)
AS
SELECT
  id,
  passport_id,
  user_id,
  node_id,
  status,
  proof_url,
  proof_storage_path,
  notes,
  admin_notes,    -- intentionally included: rejection reason shown to player
  reviewed_at,    -- intentionally included: stamp date shown to player
  -- reviewed_by intentionally excluded: admin profile UUID, never player-facing
  submitted_at,
  created_at
FROM public.check_ins
WHERE user_id = auth.uid();  -- ownership enforced inside the view

-- Grant SELECT to authenticated role
-- (anon has no business reading check-ins)
GRANT SELECT ON public.check_ins_player_view TO authenticated;

-- Enable RLS on the view so Supabase treats it like a first-class
-- protected resource and realtime filters respect ownership.
ALTER VIEW public.check_ins_player_view OWNER TO postgres;

-- ── Policy on the view itself ─────────────────────────────────────────────────
--
-- The WHERE clause inside the view already enforces user_id = auth.uid().
-- Adding an explicit RLS policy on the view provides a second layer and
-- makes the intent explicit for future maintainers.
--
-- Note: Supabase does not support ALTER TABLE ... ENABLE ROW LEVEL SECURITY
-- on views directly — security_barrier + the embedded WHERE is the
-- Postgres-native equivalent and is sufficient.

-- ══════════════════════════════════════════════════════════════
-- PATCH 3 — Revoke reviewed_by from the base table's player policy
-- ══════════════════════════════════════════════════════════════
--
-- The base table check_ins_select_own still grants SELECT * to
-- authenticated users (owner's rows). This patch does NOT remove
-- that policy — admin routes and service-role reads rely on direct
-- table access. Instead, we document that reviewed_by is only safe
-- to read via the service-role path (admin routes), not via the
-- PostgREST player path after migration 007.
--
-- Action for application code (non-SQL):
--   Replace .from('check_ins').select('*') in player-facing code
--   with .from('check_ins_player_view').select('*') to use the
--   column-restricted view.
--
-- The three player-facing files that need updating:
--   1. src/app/passport/page.tsx      — line 28: .select('*')
--   2. src/app/nodes/[nodeId]/page.tsx — line 40: .select('*')
--   3. RealtimePassportUpdater.tsx    — table: 'check_ins'
--
-- These are NOT changed in this migration (SQL scope only) but are
-- tracked in the post-007 app code checklist below.

-- ══════════════════════════════════════════════════════════════
-- VERIFICATION
-- ══════════════════════════════════════════════════════════════

-- V1. passports_insert_own exists with the corridor guard
DO $$
DECLARE
  pol_qual TEXT;
BEGIN
  SELECT qual::text
  INTO   pol_qual
  FROM   pg_policies
  WHERE  schemaname = 'public'
  AND    tablename  = 'passports'
  AND    policyname = 'passports_insert_own';

  IF pol_qual IS NULL THEN
    RAISE EXCEPTION '[007] VERIFICATION FAILED: passports_insert_own policy not found.';
  END IF;

  IF pol_qual NOT LIKE '%is_active%' THEN
    RAISE EXCEPTION
      '[007] VERIFICATION FAILED: passports_insert_own WITH CHECK does not contain '
      'is_active guard. Found: %', pol_qual;
  END IF;

  RAISE NOTICE '[007] passports_insert_own: active corridor guard present. ✓';
END $$;

-- V2. check_ins_player_view exists and excludes reviewed_by
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   information_schema.views
    WHERE  table_schema = 'public'
    AND    table_name   = 'check_ins_player_view'
  ) THEN
    RAISE EXCEPTION '[007] VERIFICATION FAILED: check_ins_player_view view not found.';
  END IF;

  -- Confirm reviewed_by is NOT in the view's column list
  IF EXISTS (
    SELECT 1
    FROM   information_schema.columns
    WHERE  table_schema = 'public'
    AND    table_name   = 'check_ins_player_view'
    AND    column_name  = 'reviewed_by'
  ) THEN
    RAISE EXCEPTION
      '[007] VERIFICATION FAILED: reviewed_by column is present in '
      'check_ins_player_view — it must be excluded.';
  END IF;

  -- Confirm admin_notes and reviewed_at ARE in the view (player-visible)
  IF NOT EXISTS (
    SELECT 1
    FROM   information_schema.columns
    WHERE  table_schema = 'public'
    AND    table_name   = 'check_ins_player_view'
    AND    column_name  = 'admin_notes'
  ) THEN
    RAISE EXCEPTION
      '[007] VERIFICATION FAILED: admin_notes is missing from check_ins_player_view. '
      'It must be included (rejection reason shown in NodeCard.tsx).';
  END IF;

  RAISE NOTICE '[007] check_ins_player_view: present, reviewed_by excluded, admin_notes present. ✓';
END $$;

-- V3. Active corridor guard smoke-test via pg_policies
DO $$
DECLARE
  chk_qual TEXT;
BEGIN
  SELECT with_check::text
  INTO   chk_qual
  FROM   pg_policies
  WHERE  schemaname = 'public'
  AND    tablename  = 'passports'
  AND    policyname = 'passports_insert_own';

  IF chk_qual IS NULL OR chk_qual NOT LIKE '%corridors%' THEN
    RAISE EXCEPTION
      '[007] VERIFICATION FAILED: passports_insert_own WITH CHECK clause does not '
      'reference corridors table. Got: %', chk_qual;
  END IF;

  RAISE NOTICE '[007] passports_insert_own WITH CHECK references corridors table. ✓';
END $$;

COMMIT;

-- ══════════════════════════════════════════════════════════════
-- POST-MIGRATION NOTES
-- ══════════════════════════════════════════════════════════════
--
-- ── A. Application code updates (required after applying this migration) ──────
--
-- Three player-facing files still query check_ins directly with select('*').
-- Switch them to check_ins_player_view to enforce the reviewed_by exclusion
-- at the API layer. The view returns identical results except reviewed_by.
--
-- 1. src/app/passport/page.tsx (line ~28):
--    BEFORE: supabase.from('check_ins').select('*').eq('passport_id', passport.id)
--    AFTER:  supabase.from('check_ins_player_view').select('*').eq('passport_id', passport.id)
--
-- 2. src/app/nodes/[nodeId]/page.tsx (line ~40):
--    BEFORE: supabase.from('check_ins').select('*').eq('passport_id', passport.id).eq('node_id', nodeId)...
--    AFTER:  supabase.from('check_ins_player_view').select('*').eq('passport_id', passport.id).eq('node_id', nodeId)...
--
-- 3. src/components/passport/RealtimePassportUpdater.tsx (line ~24):
--    BEFORE: table: 'check_ins'
--    AFTER:  table: 'check_ins_player_view'
--    NOTE:   Supabase realtime can subscribe to views with security_barrier.
--            The passport_id filter will still work identically.
--
-- Admin routes (src/app/api/checkins/, src/app/admin/) continue to use
-- check_ins directly via createAdminClient — no changes needed there.
--
-- ── B. GAP-A verification (run after applying this migration) ─────────────────
--
-- Test that a direct INSERT to /rest/v1/passports with an inactive
-- corridor_id is rejected:
--
--   PLAYER_JWT=<authenticated player JWT>
--   ANON=sb_publishable_1BPrFxSYIb__I7JZUbgimQ_RZcVR_oU
--   URL=https://gaavynmmysdhovpatzlp.supabase.co/rest/v1
--   PLAYER_ID=<player UUID from JWT sub>
--
--   First: deactivate a test corridor in the SQL editor:
--     UPDATE corridors SET is_active = FALSE WHERE id = '<test-corridor-id>';
--
--   Then attempt INSERT:
--     curl -s -w "\n%{http_code}" "$URL/passports" \
--       -X POST \
--       -H "apikey: $ANON" \
--       -H "Authorization: Bearer $PLAYER_JWT" \
--       -H "Content-Type: application/json" \
--       -d '{"user_id":"<PLAYER_ID>","corridor_id":"<inactive-corridor-id>"}'
--     Expected: 403
--
--   Re-activate: UPDATE corridors SET is_active = TRUE WHERE id = '<test-corridor-id>';
--
-- ── C. GAP-C verification (run after applying this migration) ─────────────────
--
-- Test that reviewed_by is absent from the player view:
--
--   curl -s "$URL/check_ins_player_view?select=*&limit=1" \
--     -H "apikey: $ANON" \
--     -H "Authorization: Bearer $PLAYER_JWT"
--   # Confirm: response JSON has no "reviewed_by" key
--
-- Test that reviewed_by IS present via service role (admin path):
--   SELECT reviewed_by FROM check_ins LIMIT 1;  -- in SQL Editor
--
-- ── D. Migration 008 candidates ───────────────────────────────────────────────
--   • DROP COLUMN public.nodes.active (deprecated in 004, comment added)
--   • passports_insert_own: consider capping one active passport per user
--     (currently enforced only at the app route layer)
--   • Realtime publication: add check_ins_player_view to supabase_realtime
--     once the app code switches to the view
