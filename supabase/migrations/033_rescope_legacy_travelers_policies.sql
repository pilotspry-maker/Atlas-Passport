-- ════════════════════════════════════════════════════════════════════════════
-- Migration 033 — Rescope legacy "Travelers *" policies TO authenticated
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   The 11 legacy "Travelers *" RLS policies created with the Orion tables (see
--   migration 032) were scoped TO public with a bare auth.uid() call. Two
--   Supabase advisor findings apply:
--     1. multiple_permissive_policies / overly-broad role  — policies that gate
--        on auth.uid() should target the `authenticated` role, not `public`
--        (which also includes `anon`). Behaviourally equivalent here because
--        auth.uid() is NULL for anon, but the explicit role is the correct,
--        advisor-clean form.
--     2. auth_rls_initplan — a bare auth.uid() is re-evaluated per row. Wrapping
--        it as (select auth.uid()) lets Postgres cache it as an initplan,
--        avoiding the per-row re-evaluation.
--
--   This migration drops + recreates ONLY the 11 "Travelers *" policies with
--   `TO authenticated` and `(select auth.uid())`. The 2 "Service inserts *"
--   policies (ap_events, referral_events) are deliberately left untouched —
--   they are tracked as separate advisor findings.
--
-- IDEMPOTENT: DROP POLICY IF EXISTS before each CREATE.
--
-- check_ins NOTE (see PR description "Open question resolution"):
--   The live "Travelers read own checkins" SELECT policy gates on
--   check_ins.traveler_id. The repo's check_ins (001_initial_schema.sql) is
--   keyed on user_id and NO migration adds a traveler_id column; CLAUDE.md §13
--   forbids restructuring check_ins. Recreating this policy on a non-existent
--   traveler_id column would fail the fresh-DB CI bootstrap. The current,
--   advisor-clean check_ins ownership policies are check_ins_select_own /
--   check_ins_insert_own (migrations 004/005, on user_id). The legacy
--   "Travelers read own checkins" policy is therefore DROPPED with no
--   replacement: a no-op on the fresh CI DB, and on live it removes a stale
--   TO public policy with no loss of coverage.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── traveler_profiles (3) ────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Travelers insert own profile" ON public.traveler_profiles;
CREATE POLICY "Travelers insert own profile" ON public.traveler_profiles
  FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Travelers read own profile" ON public.traveler_profiles;
CREATE POLICY "Travelers read own profile" ON public.traveler_profiles
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Travelers update own profile" ON public.traveler_profiles;
CREATE POLICY "Travelers update own profile" ON public.traveler_profiles
  FOR UPDATE TO authenticated
  USING ((select auth.uid()) = id);

-- ── passport_activations (2) ─────────────────────────────────────────────────
DROP POLICY IF EXISTS "Travelers insert own activations" ON public.passport_activations;
CREATE POLICY "Travelers insert own activations" ON public.passport_activations
  FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = traveler_id);

DROP POLICY IF EXISTS "Travelers read own activations" ON public.passport_activations;
CREATE POLICY "Travelers read own activations" ON public.passport_activations
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = traveler_id);

-- ── mission_progress (3) ─────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Travelers insert own progress" ON public.mission_progress;
CREATE POLICY "Travelers insert own progress" ON public.mission_progress
  FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = traveler_id);

DROP POLICY IF EXISTS "Travelers read own progress" ON public.mission_progress;
CREATE POLICY "Travelers read own progress" ON public.mission_progress
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = traveler_id);

DROP POLICY IF EXISTS "Travelers update own progress" ON public.mission_progress;
CREATE POLICY "Travelers update own progress" ON public.mission_progress
  FOR UPDATE TO authenticated
  USING ((select auth.uid()) = traveler_id);

-- ── ap_events (1 Travelers policy; "Service inserts ap events" left alone) ────
DROP POLICY IF EXISTS "Travelers read own ap events" ON public.ap_events;
CREATE POLICY "Travelers read own ap events" ON public.ap_events
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = traveler_id);

-- ── referral_events (1 Travelers policy; "Service inserts referrals" left alone)
DROP POLICY IF EXISTS "Travelers read own referrals" ON public.referral_events;
CREATE POLICY "Travelers read own referrals" ON public.referral_events
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = referrer_id);

-- ── check_ins legacy SELECT — DROP only (see header note) ─────────────────────
DROP POLICY IF EXISTS "Travelers read own checkins" ON public.check_ins;

-- ── Verification: no "Travelers%" policy remains scoped TO public ─────────────
DO $$
DECLARE
  bad_count integer;
BEGIN
  SELECT count(*) INTO bad_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND policyname LIKE 'Travelers%'
    AND 'public' = ANY(roles);
  IF bad_count > 0 THEN
    RAISE EXCEPTION '[033] VERIFICATION FAILED: % Travelers policies still scoped TO public', bad_count;
  END IF;
END $$;

COMMIT;
