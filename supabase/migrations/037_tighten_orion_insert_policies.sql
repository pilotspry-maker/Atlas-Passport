-- ════════════════════════════════════════════════════════════════════════════
-- Migration 037 — Task 2: tighten Orion INSERT policies; baseline
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
--   Migration 034 subsequently tightened service policies and dropped the
--   open `corridor_covers_select_public` SELECT policy. It also rescoped
--   the waitlist_entries INSERT policy ("Public join waitlist") to
--   anon+authenticated with CHECK(true). This migration supersedes that
--   partial fix by adding an email-format CHECK constraint and re-issuing
--   the INSERT policy with regex validation. It also creates the
--   waitlist_entries table baseline (CREATE TABLE IF NOT EXISTS) in case
--   it is absent in CI-bootstrap environments.
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
--                         Also drops migration 034's "Public join waitlist"
--                         policy (CHECK true) and replaces with stricter
--                         "Anyone can join waitlist" (CHECK email regex).
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
--   For waitlist_entries: restore "Public join waitlist" with CHECK(true),
--   drop the email CHECK constraint (ALTER TABLE DROP CONSTRAINT).
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1+2. ap_events / referral_events — drop open INSERT policies ─────────────
DROP POLICY IF EXISTS "Service inserts ap events" ON public.ap_events;
DROP POLICY IF EXISTS "Service inserts referrals" ON public.referral_events;

-- ── 3. waitlist_entries — baseline table + email validation ──────────────────

CREATE TABLE IF NOT EXISTS public.waitlist_entries (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  email      text        NOT NULL UNIQUE,
  city       text,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT waitlist_entries_email_format
    CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

ALTER TABLE public.waitlist_entries ENABLE ROW LEVEL SECURITY;

-- Add email CHECK constraint idempotently (NOT VALID skips live-data scan)
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

-- Drop migration 034's permissive INSERT policy and replace with validated one
DROP POLICY IF EXISTS "Public join waitlist" ON public.waitlist_entries;
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
    RAISE EXCEPTION '[037] VERIFICATION FAILED: ap_events still has % INSERT policy/ies for public/anon/authenticated', policy_count;
  END IF;

  -- referral_events must have NO insert policy for public/authenticated
  SELECT COUNT(*) INTO policy_count
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename  = 'referral_events'
     AND cmd        = 'INSERT'
     AND roles && ARRAY['public'::name, 'anon'::name, 'authenticated'::name];
  IF policy_count > 0 THEN
    RAISE EXCEPTION '[037] VERIFICATION FAILED: referral_events still has % INSERT policy/ies for public/anon/authenticated', policy_count;
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
    RAISE EXCEPTION '[037] VERIFICATION FAILED: waitlist_entries does not have RLS enabled';
  END IF;

  -- waitlist_entries must have the email-gated INSERT policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename  = 'waitlist_entries'
       AND policyname = 'Anyone can join waitlist'
  ) THEN
    RAISE EXCEPTION '[037] VERIFICATION FAILED: "Anyone can join waitlist" policy not found';
  END IF;

  RAISE NOTICE '[037] OK: Orion INSERT policies tightened; waitlist_entries baselined with email validation';
END $$;

COMMIT;
