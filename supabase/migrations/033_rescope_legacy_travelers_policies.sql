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
-- SCOPE — 15 policies rescoped TO authenticated (was 11):
--   • 11 "Travelers *" policies on the Orion tables (baselined in 032), INCLUDING
--     check_ins."Travelers read own checkins" which gates on check_ins.traveler_id.
--     Live verification confirmed traveler_id DOES exist on live's check_ins
--     (real drift); 032 now baselines that column, so this policy is rescoped
--     (NOT dropped, as in the first revision of this PR).
--   • 4 repo-owned SELECT policies that were defined TO public in migration 001
--     and never rescoped: check_ins_select_own (user_id = auth.uid()),
--     passports_select_own (user_id = auth.uid()), profiles_select_own
--     (auth.uid() = id). Their USING clauses are preserved byte-for-byte with
--     auth.uid() wrapped as (select auth.uid()).
--
--   The 2 "Service inserts *" policies (ap_events, referral_events) are NOT
--   touched (separate advisor track). check_ins."Travelers insert own checkins"
--   is NOT touched — migration 031 already rescoped it TO authenticated.
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

-- ── check_ins legacy SELECT — rescope on baselined traveler_id ────────────────
-- traveler_id IS present on live (real drift, baselined in 032). Rescope rather
-- than drop (reverses the first revision of this PR).
DROP POLICY IF EXISTS "Travelers read own checkins" ON public.check_ins;
CREATE POLICY "Travelers read own checkins" ON public.check_ins
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = traveler_id);

-- ── repo-owned SELECT policies missed in 001/002 (still TO public) ────────────
DROP POLICY IF EXISTS "check_ins_select_own" ON public.check_ins;
CREATE POLICY "check_ins_select_own" ON public.check_ins
  FOR SELECT TO authenticated
  USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "passports_select_own" ON public.passports;
CREATE POLICY "passports_select_own" ON public.passports
  FOR SELECT TO authenticated
  USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT TO authenticated
  USING ((select auth.uid()) = id);

-- ── Verification: none of the 15 rescoped policies remain scoped TO public ────
DO $$
DECLARE
  bad_count integer;
BEGIN
  SELECT count(*) INTO bad_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND policyname IN (
      'Travelers read own ap events',
      'Travelers insert own progress','Travelers read own progress','Travelers update own progress',
      'Travelers insert own activations','Travelers read own activations',
      'Travelers read own referrals',
      'Travelers insert own profile','Travelers read own profile','Travelers update own profile',
      'Travelers read own checkins',
      'check_ins_select_own','passports_select_own','profiles_select_own'
    )
    AND 'public' = ANY(roles);
  IF bad_count > 0 THEN
    RAISE EXCEPTION '[033] VERIFICATION FAILED: % policies still scoped TO public', bad_count;
  END IF;
END $$;

COMMIT;
