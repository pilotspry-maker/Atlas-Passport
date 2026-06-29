-- ════════════════════════════════════════════════════════════════════════════
-- Migration 032 — Orion schema baseline (out-of-band tables → in-repo)
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   Five "Orion" tables (traveler_profiles, passport_activations,
--   mission_progress, ap_events, referral_events) were created directly in the
--   live Supabase project (ref gaavynmmysdhovpatzlp) and never landed in the
--   repo's migration history. See CLAUDE.md §12 ("Orion — The State of Record").
--
--   CI bootstraps a fresh database from migrations (ci.yml:
--   `supabase db push --local` + `supabase test db --local`). Because these
--   tables were absent from the repo, any future migration that references them
--   would fail the bootstrap with "relation does not exist". This migration
--   makes the repo a faithful baseline of live so the bootstrap-from-zero
--   schema matches production.
--
-- IDEMPOTENCY / NO-OP-ON-LIVE:
--   Every object uses CREATE TABLE IF NOT EXISTS / DROP POLICY IF EXISTS so that
--   applying this to the live DB (which already has these objects) is a no-op,
--   while applying it to a fresh CI DB recreates them exactly.
--
-- POLICY SCOPE:
--   The 12 policies below are recreated EXACTLY as they exist in live — scoped
--   TO public with bare auth.uid(). This is a true baseline. Migration 033
--   rescopes the 11 "Travelers *" policies TO authenticated with
--   (select auth.uid()); the 2 "Service inserts *" policies are intentionally
--   left TO public here and untouched by 033 (tracked as separate advisor
--   findings).
--
-- FK NOTE (traveler_profiles.id):
--   CLAUDE.md §12 documents this as a hidden FK to auth.users(id) ON DELETE
--   CASCADE ("not visible in information_schema ... must provision an auth.users
--   row before creating a traveler_profile"). The baseline encodes that
--   relationship explicitly.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Tables (dependency order: traveler_profiles first) ───────────────────────

CREATE TABLE IF NOT EXISTS public.traveler_profiles (
  id             uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  passport_id    text NOT NULL UNIQUE,
  display_name   text,
  email          text,
  atlas_points   integer DEFAULT 0,
  current_tier   text DEFAULT 'wayfarer',
  referral_code  text UNIQUE,
  created_at     timestamptz DEFAULT now()
);
ALTER TABLE public.traveler_profiles ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.passport_activations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  traveler_id   uuid REFERENCES public.traveler_profiles(id),
  corridor_id   uuid REFERENCES public.corridors(id),
  status        text DEFAULT 'active',
  activated_at  timestamptz DEFAULT now(),
  expires_at    timestamptz DEFAULT (now() + interval '72 hours'),
  completed_at  timestamptz
);
ALTER TABLE public.passport_activations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.mission_progress (
  traveler_id      uuid NOT NULL REFERENCES public.traveler_profiles(id),
  activation_id    uuid NOT NULL REFERENCES public.passport_activations(id),
  nodes_completed  integer DEFAULT 0,
  total_nodes      integer DEFAULT 0,
  status           text DEFAULT 'in_progress',
  updated_at       timestamptz DEFAULT now(),
  PRIMARY KEY (traveler_id, activation_id)
);
ALTER TABLE public.mission_progress ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.ap_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  traveler_id   uuid REFERENCES public.traveler_profiles(id),
  source_type   text,
  points        integer NOT NULL,
  reference_id  uuid,
  created_at    timestamptz DEFAULT now()
);
ALTER TABLE public.ap_events ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.referral_events (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id    uuid REFERENCES public.traveler_profiles(id),
  referred_id    uuid REFERENCES public.traveler_profiles(id),
  referral_code  text NOT NULL,
  activated_at   timestamptz,
  ap_awarded     boolean DEFAULT false,
  created_at     timestamptz DEFAULT now()
);
ALTER TABLE public.referral_events ENABLE ROW LEVEL SECURITY;

-- ── Policies (baseline — TO public, bare auth.uid(), exactly as live) ─────────

-- traveler_profiles
DROP POLICY IF EXISTS "Travelers insert own profile" ON public.traveler_profiles;
CREATE POLICY "Travelers insert own profile" ON public.traveler_profiles
  FOR INSERT TO public WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Travelers read own profile" ON public.traveler_profiles;
CREATE POLICY "Travelers read own profile" ON public.traveler_profiles
  FOR SELECT TO public USING (auth.uid() = id);

DROP POLICY IF EXISTS "Travelers update own profile" ON public.traveler_profiles;
CREATE POLICY "Travelers update own profile" ON public.traveler_profiles
  FOR UPDATE TO public USING (auth.uid() = id);

-- passport_activations
DROP POLICY IF EXISTS "Travelers insert own activations" ON public.passport_activations;
CREATE POLICY "Travelers insert own activations" ON public.passport_activations
  FOR INSERT TO public WITH CHECK (auth.uid() = traveler_id);

DROP POLICY IF EXISTS "Travelers read own activations" ON public.passport_activations;
CREATE POLICY "Travelers read own activations" ON public.passport_activations
  FOR SELECT TO public USING (auth.uid() = traveler_id);

-- mission_progress
DROP POLICY IF EXISTS "Travelers insert own progress" ON public.mission_progress;
CREATE POLICY "Travelers insert own progress" ON public.mission_progress
  FOR INSERT TO public WITH CHECK (auth.uid() = traveler_id);

DROP POLICY IF EXISTS "Travelers read own progress" ON public.mission_progress;
CREATE POLICY "Travelers read own progress" ON public.mission_progress
  FOR SELECT TO public USING (auth.uid() = traveler_id);

DROP POLICY IF EXISTS "Travelers update own progress" ON public.mission_progress;
CREATE POLICY "Travelers update own progress" ON public.mission_progress
  FOR UPDATE TO public USING (auth.uid() = traveler_id);

-- ap_events
DROP POLICY IF EXISTS "Service inserts ap events" ON public.ap_events;
CREATE POLICY "Service inserts ap events" ON public.ap_events
  FOR INSERT TO public WITH CHECK (true);

DROP POLICY IF EXISTS "Travelers read own ap events" ON public.ap_events;
CREATE POLICY "Travelers read own ap events" ON public.ap_events
  FOR SELECT TO public USING (auth.uid() = traveler_id);

-- referral_events
DROP POLICY IF EXISTS "Service inserts referrals" ON public.referral_events;
CREATE POLICY "Service inserts referrals" ON public.referral_events
  FOR INSERT TO public WITH CHECK (true);

DROP POLICY IF EXISTS "Travelers read own referrals" ON public.referral_events;
CREATE POLICY "Travelers read own referrals" ON public.referral_events
  FOR SELECT TO public USING (auth.uid() = referrer_id);

-- ── Verification: all 5 tables exist and have RLS enabled ─────────────────────
DO $$
DECLARE
  t            text;
  orion_tables text[] := ARRAY[
    'traveler_profiles',
    'passport_activations',
    'mission_progress',
    'ap_events',
    'referral_events'
  ];
  rls_on       boolean;
BEGIN
  FOREACH t IN ARRAY orion_tables LOOP
    SELECT c.relrowsecurity
      INTO rls_on
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = t;

    IF rls_on IS NULL THEN
      RAISE EXCEPTION '[032] VERIFICATION FAILED: table public.% does not exist', t;
    END IF;
    IF rls_on IS FALSE THEN
      RAISE EXCEPTION '[032] VERIFICATION FAILED: RLS not enabled on public.%', t;
    END IF;
  END LOOP;
END $$;

COMMIT;
