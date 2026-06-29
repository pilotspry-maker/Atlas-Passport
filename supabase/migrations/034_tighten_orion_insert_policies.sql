-- ════════════════════════════════════════════════════════════════════════════
-- Migration 034 — Task 2: tighten Orion INSERT policies; baseline
--                         waitlist_entries with email validation
-- ════════════════════════════════════════════════════════════════════════════
--
-- CONTEXT (from migration 032 comments, deliberately deferred):
--   Migration 032 created ap_events and referral_events with:
--     FOR INSERT TO public WITH CHECK (true)
--   This allows ANY authenticated user to directly inject game-engine events,
--   bypassing the application layer entirely. Migration 033 rescoped the 11
--   "Travelers *" policies but left these two "Service inserts *" policies
--   in place, noting them as "separate advisor findings". This migration
--   closes that gap.
--
-- CHANGES:
--   1. ap_events     — drop "Service inserts ap events" (WITH CHECK true).
--                      service_role is BYPASSRLS; no insert policy needed.
--                      Authenticated users must go through the app worker.
--   2. referral_events — same: drop "Service inserts referrals".
--   3. waitlist_entries — CREATE TABLE IF NOT EXISTS (out-of-band in live);
--                         email CHECK constraint; INSERT policy for anon +
--                         authenticated with email-format guard; no SELECT
--                         policy for public (service_role reads via BYPASSRLS).
--
-- IDEMPOTENCY:
--   DROP POLICY IF EXISTS; CREATE TABLE IF NOT EXISTS; DO $$ block adds the
--   email CHECK constraint only when absent (NOT VALID skips live-data scan).
--
-- DOWN:
--   To revert, re-add the dropped INSERT policies:
--     CREATE POLICY "Service inserts ap events" ON public.ap_events
--       FOR INSERT TO public WITH CHECK (true);
--     CREATE POLICY "Service inserts referrals" ON public.referral_events
--       FOR INSERT TO public WITH CHECK (true);
--   And DROP TABLE public.waitlist_entries (only if it was new in this migration).
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. ap_events: remove unrestricted INSERT ──────────────────────────────────
--
-- The old policy granted any public (anon + authenticated) role the right to
-- inject arbitrary ap_events rows, including spoofed points for other travelers.
-- After this DROP there is no INSERT policy for public or authenticated; only
-- service_role (which bypasses RLS entirely) may insert.

DROP POLICY IF EXISTS "Service inserts ap events" ON public.ap_events;


-- ── 2. referral_events: remove unrestricted INSERT ───────────────────────────

DROP POLICY IF EXISTS "Service inserts referrals" ON public.referral_events;


-- ── 3. waitlist_entries: baseline + email validation ─────────────────────────
--
-- This table exists out-of-band in the live project (listed in CLAUDE.md §12
-- baseline) but was never committed to migrations. CREATE TABLE IF NOT EXISTS
-- makes the CI bootstrap-from-zero schema match live.

CREATE TABLE IF NOT EXISTS public.waitlist_entries (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  email      text        NOT NULL UNIQUE,
  city       text,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT waitlist_entries_email_format
    CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

ALTER TABLE public.waitlist_entries ENABLE ROW LEVEL SECURITY;

-- For the live DB (table already exists), add the CHECK constraint idempotently.
-- NOT VALID skips scanning existing rows; new rows are always validated.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM information_schema.table_constraints
     WHERE table_schema    = 'public'
       AND table_name      = 'waitlist_entries'
       AND constraint_name = 'waitlist_entries_email_format'
  ) THEN
    ALTER TABLE public.waitlist_entries
      ADD CONSTRAINT waitlist_entries_email_format
      CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$') NOT VALID;
  END IF;
END $$;

-- Public waitlist signup — anyone may submit; email must match RFC-5322-lite.
-- No SELECT policy: only service_role (BYPASSRLS) reads the list.
DROP POLICY IF EXISTS "Anyone can join waitlist" ON public.waitlist_entries;
CREATE POLICY "Anyone can join waitlist" ON public.waitlist_entries
  FOR INSERT TO anon, authenticated
  WITH CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');


-- ── Verification ─────────────────────────────────────────────────────────────

DO $$
DECLARE
  policy_count integer;
BEGIN
  -- ap_events must have NO insert policy for public/authenticated after this migration
  SELECT COUNT(*) INTO policy_count
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename  = 'ap_events'
     AND cmd        = 'INSERT'
     AND roles && ARRAY['public'::name, 'anon'::name, 'authenticated'::name];

  IF policy_count > 0 THEN
    RAISE EXCEPTION '[034] VERIFICATION FAILED: ap_events still has % INSERT policy/ies for public/anon/authenticated', policy_count;
  END IF;

  -- referral_events must have NO insert policy for public/authenticated
  SELECT COUNT(*) INTO policy_count
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename  = 'referral_events'
     AND cmd        = 'INSERT'
     AND roles && ARRAY['public'::name, 'anon'::name, 'authenticated'::name];

  IF policy_count > 0 THEN
    RAISE EXCEPTION '[034] VERIFICATION FAILED: referral_events still has % INSERT policy/ies for public/anon/authenticated', policy_count;
  END IF;

  -- waitlist_entries must have RLS enabled
  IF NOT EXISTS (
    SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname = 'waitlist_entries'
       AND c.relrowsecurity = true
  ) THEN
    RAISE EXCEPTION '[034] VERIFICATION FAILED: waitlist_entries does not have RLS enabled';
  END IF;

  RAISE NOTICE '[034] OK: ap_events and referral_events INSERT policies for public roles removed; waitlist_entries baselined with RLS';
END $$;

COMMIT;
