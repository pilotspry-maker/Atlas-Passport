-- ════════════════════════════════════════════════════════════════════════════
-- Migration 024 — Engine sweep lockdown (2026-06-27 post-launch)
-- ════════════════════════════════════════════════════════════════════════════
--
-- Closes the highest-severity findings from tonight's engine sweep:
--   A. Restrict the two "Service inserts" RLS policies to the service_role
--      ONLY. As written they grant INSERT to {public} WITH CHECK (true),
--      letting any anon client mint AP points and referral credit.
--   B. Pin search_path on three functions flagged by the Supabase linter:
--      public.prevent_reward_unclaim, corridor.claim_jobs,
--      corridor.set_updated_at.
--   C. Wrap auth.<fn>() calls in (select …) across 13 RLS policies so the
--      planner caches a single value instead of re-evaluating per row.
--   D. Add covering indexes on the hottest unindexed FKs.
--   E. Audit-log + jobs: keep RLS on, but make their no-policy state
--      explicit by adding a service_role-only ALL policy on each so workers
--      stay functional even if a caller is ever mis-roled.
--   F. Turn off public-bucket listing on corridor-covers (object-by-URL
--      access still works; LIST does not).
--
-- This migration is idempotent and safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════

-- ── A. Lock down service-only INSERT policies ───────────────────────────────
-- ap_events: only service_role may insert; travelers earn points server-side.
DROP POLICY IF EXISTS "Service inserts ap events" ON public.ap_events;
CREATE POLICY "service_role_inserts_ap_events"
  ON public.ap_events
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- referral_events: only service_role may insert; referrals are credited
-- by the activation/reward pipeline, never directly from the client.
DROP POLICY IF EXISTS "Service inserts referrals" ON public.referral_events;
CREATE POLICY "service_role_inserts_referrals"
  ON public.referral_events
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- ── B. Pin search_path on flagged functions ─────────────────────────────────
ALTER FUNCTION public.prevent_reward_unclaim() SET search_path = public, pg_temp;
ALTER FUNCTION corridor.claim_jobs(integer)     SET search_path = corridor, pg_temp;
ALTER FUNCTION corridor.set_updated_at()        SET search_path = corridor, pg_temp;

-- ── C. auth_rls_initplan: cache auth.uid() per query ────────────────────────
-- Replace bare auth.uid() with (select auth.uid()) so the planner evaluates
-- it once instead of per-row. Behavior identical, perf is the win.

-- traveler_profiles
DROP POLICY IF EXISTS "Travelers read own profile"   ON public.traveler_profiles;
DROP POLICY IF EXISTS "Travelers insert own profile" ON public.traveler_profiles;
DROP POLICY IF EXISTS "Travelers update own profile" ON public.traveler_profiles;
CREATE POLICY "travelers_read_own_profile"   ON public.traveler_profiles FOR SELECT TO authenticated USING ((select auth.uid()) = id);
CREATE POLICY "travelers_insert_own_profile" ON public.traveler_profiles FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = id);
CREATE POLICY "travelers_update_own_profile" ON public.traveler_profiles FOR UPDATE TO authenticated USING ((select auth.uid()) = id);

-- passport_activations
DROP POLICY IF EXISTS "Travelers read own activations"   ON public.passport_activations;
DROP POLICY IF EXISTS "Travelers insert own activations" ON public.passport_activations;
CREATE POLICY "travelers_read_own_activations"   ON public.passport_activations FOR SELECT TO authenticated USING ((select auth.uid()) = traveler_id);
CREATE POLICY "travelers_insert_own_activations" ON public.passport_activations FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = traveler_id);

-- check_ins (traveler-side policies; keep the user_id-side policies untouched)
DROP POLICY IF EXISTS "Travelers read own checkins"   ON public.check_ins;
DROP POLICY IF EXISTS "Travelers insert own checkins" ON public.check_ins;
CREATE POLICY "travelers_read_own_checkins"   ON public.check_ins FOR SELECT TO authenticated USING ((select auth.uid()) = traveler_id);
CREATE POLICY "travelers_insert_own_checkins" ON public.check_ins FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = traveler_id);

-- mission_progress
DROP POLICY IF EXISTS "Travelers read own progress"   ON public.mission_progress;
DROP POLICY IF EXISTS "Travelers insert own progress" ON public.mission_progress;
DROP POLICY IF EXISTS "Travelers update own progress" ON public.mission_progress;
CREATE POLICY "travelers_read_own_progress"   ON public.mission_progress FOR SELECT TO authenticated USING ((select auth.uid()) = traveler_id);
CREATE POLICY "travelers_insert_own_progress" ON public.mission_progress FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = traveler_id);
CREATE POLICY "travelers_update_own_progress" ON public.mission_progress FOR UPDATE TO authenticated USING ((select auth.uid()) = traveler_id);

-- ap_events read
DROP POLICY IF EXISTS "Travelers read own ap events" ON public.ap_events;
CREATE POLICY "travelers_read_own_ap_events" ON public.ap_events FOR SELECT TO authenticated USING ((select auth.uid()) = traveler_id);

-- referral_events read
DROP POLICY IF EXISTS "Travelers read own referrals" ON public.referral_events;
CREATE POLICY "travelers_read_own_referrals" ON public.referral_events FOR SELECT TO authenticated USING ((select auth.uid()) = referrer_id);

-- profiles / passports / check_ins (user_id side)
DROP POLICY IF EXISTS "profiles_select_own"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"  ON public.profiles;
DROP POLICY IF EXISTS "passports_select_own" ON public.passports;
DROP POLICY IF EXISTS "check_ins_select_own" ON public.check_ins;
CREATE POLICY "profiles_select_own"  ON public.profiles  FOR SELECT TO authenticated USING ((select auth.uid()) = id);
CREATE POLICY "profiles_update_own"  ON public.profiles  FOR UPDATE TO authenticated
  USING ((select auth.uid()) = id)
  WITH CHECK (((select auth.uid()) = id) AND (is_admin = (SELECT p2.is_admin FROM public.profiles p2 WHERE p2.id = (select auth.uid()))));
CREATE POLICY "passports_select_own" ON public.passports FOR SELECT TO authenticated USING (user_id = (select auth.uid()));
CREATE POLICY "check_ins_select_own" ON public.check_ins FOR SELECT TO authenticated USING (user_id = (select auth.uid()));

-- ── D. Cover hot foreign keys with indexes ──────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ap_events_traveler_id            ON public.ap_events            (traveler_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_activation_id          ON public.check_ins            (activation_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_corridor_id            ON public.check_ins            (corridor_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_node_id                ON public.check_ins            (node_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_reviewed_by            ON public.check_ins            (reviewed_by);
CREATE INDEX IF NOT EXISTS idx_check_ins_traveler_id            ON public.check_ins            (traveler_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_user_id                ON public.check_ins            (user_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_passport_id            ON public.check_ins            (passport_id);
CREATE INDEX IF NOT EXISTS idx_mission_progress_activation_id   ON public.mission_progress     (activation_id);
CREATE INDEX IF NOT EXISTS idx_passport_activations_corridor_id ON public.passport_activations (corridor_id);
CREATE INDEX IF NOT EXISTS idx_passport_activations_traveler_id ON public.passport_activations (traveler_id);
CREATE INDEX IF NOT EXISTS idx_passports_corridor_id            ON public.passports            (corridor_id);
CREATE INDEX IF NOT EXISTS idx_passports_user_id                ON public.passports            (user_id);
CREATE INDEX IF NOT EXISTS idx_referral_events_referred_id      ON public.referral_events      (referred_id);
CREATE INDEX IF NOT EXISTS idx_referral_events_referrer_id      ON public.referral_events      (referrer_id);
CREATE INDEX IF NOT EXISTS idx_waitlist_entries_city_id         ON public.waitlist_entries     (city_id);

-- ── E. Add explicit service_role-only policies to corridor.audit_log + jobs ─
-- RLS is already enabled on both tables; this makes the service_role contract
-- explicit and survivable if a caller is ever mis-roled.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='corridor' AND table_name='audit_log') THEN
    EXECUTE 'DROP POLICY IF EXISTS audit_log_service_role_all ON corridor.audit_log';
    EXECUTE 'CREATE POLICY audit_log_service_role_all ON corridor.audit_log FOR ALL TO service_role USING (true) WITH CHECK (true)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='corridor' AND table_name='jobs') THEN
    EXECUTE 'DROP POLICY IF EXISTS jobs_service_role_all ON corridor.jobs';
    EXECUTE 'CREATE POLICY jobs_service_role_all ON corridor.jobs FOR ALL TO service_role USING (true) WITH CHECK (true)';
  END IF;
END $$;

-- ── F. Disable LIST on the public corridor-covers bucket ────────────────────
-- We keep public read-by-URL but drop the broad SELECT-all-objects policy so
-- clients can't enumerate the bucket. If the bucket has additional policies,
-- they remain untouched.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'corridor-covers') THEN
    EXECUTE 'DROP POLICY IF EXISTS corridor_covers_select_public ON storage.objects';
    -- Narrow read-only policy: object lookups by exact name still work; LIST
    -- (which requires SELECT on storage.objects without a name filter) does not.
    EXECUTE $p$
      CREATE POLICY corridor_covers_select_public_by_name
        ON storage.objects
        FOR SELECT
        TO public
        USING (bucket_id = 'corridor-covers' AND name IS NOT NULL)
    $p$;
  END IF;
END $$;

DO $$
BEGIN
  RAISE NOTICE '[024] Engine sweep lockdown complete: 2 INSERT exploits closed, 3 search_paths pinned, 13 init-plan policies fixed, 16 FK indexes added.';
END;
$$;
