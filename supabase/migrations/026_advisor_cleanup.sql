-- ════════════════════════════════════════════════════════════════════════════
-- Migration 026 — Advisor cleanup (residual findings after lockdown sweep 024)
-- ════════════════════════════════════════════════════════════════════════════
--
-- Closes the remaining Supabase database-linter advisory after migrations
-- 023–025 (PR #29 lockdown sweep) land. Reviewed against the 2026-06-28
-- security audit; the only finding not already handled by 024 is:
--
--   • public.waitlist_entries — RLS policy "Public join waitlist" grants
--     INSERT to {public} WITH CHECK (true). Waitlist join must remain
--     publicly callable (signed-out users opt in via the marketing page),
--     but the policy currently lets an attacker mint waitlist rows that
--     forge `invited=true` or impersonate a `position_tier` value the
--     server would never grant. Tighten the WITH CHECK while keeping the
--     route open to the `anon` role only.
--
-- Findings intentionally NOT modified here (already correct):
--   • public.get_public_stats — anon-executable SECURITY DEFINER is the
--     documented contract for the Kaelo Atlas Command public dashboard
--     (see 025_public_stats_view.sql header). search_path is locked.
--   • public.ap_events / public.referral_events INSERT — restricted to
--     service_role in 024 (the residual advisor entry in the 2026-06-28
--     report will clear once #29 merges to main).
--   • corridor.audit_log / corridor.jobs — explicit service_role-only
--     ALL policies added in 024 (Block E).
--   • prevent_reward_unclaim / corridor.claim_jobs / corridor.set_updated_at
--     — search_path pinned in 024 (Block B).
--   • storage corridor-covers — broad SELECT replaced with by-name lookup
--     in 024 (Block F).
--
-- This migration is idempotent and safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Preflight: bail loudly if 024 has not landed yet ────────────────────────
-- 024 is a hard dependency. If it hasn't been applied, the policies this
-- migration assumes (e.g. service_role_inserts_ap_events) won't exist and
-- the advisor reconciliation block below would mislead.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'ap_events'
      AND policyname = 'service_role_inserts_ap_events'
  ) THEN
    RAISE EXCEPTION
      '[026] migration 024 (engine sweep lockdown) must be applied first';
  END IF;
END
$$;

-- ── 1. Harden public.waitlist_entries INSERT policy ─────────────────────────
-- Replace the {public} + WITH CHECK (true) policy with an anon-only policy
-- that constrains the row shape:
--   - email must be present, non-empty, and look like an email
--   - invited must be false (only admin path may set true)
--   - position_tier must be the public-allowed value(s); 'general' is the
--     default and the only tier a self-serve client may request
--   - id, joined_at left to defaults
DROP POLICY IF EXISTS "Public join waitlist" ON public.waitlist_entries;
DROP POLICY IF EXISTS "anon_join_waitlist"   ON public.waitlist_entries;

CREATE POLICY "anon_join_waitlist"
  ON public.waitlist_entries
  FOR INSERT
  TO anon
  WITH CHECK (
        email IS NOT NULL
    AND length(btrim(email)) BETWEEN 3 AND 320
    AND email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    AND coalesce(invited, false) = false
    AND coalesce(position_tier, 'general') = 'general'
  );

-- Service role retains full access via its existing grant; no policy needed
-- because service_role bypasses RLS by default. Confirm explicit grant.
GRANT INSERT, SELECT, UPDATE, DELETE ON public.waitlist_entries TO service_role;

-- Authenticated users do not need to join the waitlist (they already have
-- accounts); leave them with no policy → RLS denies by default.
REVOKE INSERT ON public.waitlist_entries FROM authenticated;

-- ── 2. Belt-and-suspenders: column-level guard against invited escalation ──
-- Even with the WITH CHECK above, defense-in-depth: revoke direct UPDATE on
-- the `invited` column from anon/authenticated so only service_role (admin
-- pipeline) can flip it.
REVOKE UPDATE (invited, position_tier) ON public.waitlist_entries FROM anon, authenticated;

-- ── 3. Reconciliation NOTICE for the operator ───────────────────────────────
DO $$
DECLARE
  v_remaining int;
BEGIN
  SELECT count(*) INTO v_remaining
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename  = 'waitlist_entries'
    AND policyname = 'Public join waitlist';

  IF v_remaining > 0 THEN
    RAISE EXCEPTION '[026] old "Public join waitlist" policy still present';
  END IF;

  RAISE NOTICE
    '[026] Advisor cleanup complete: waitlist_entries INSERT policy hardened (anon-only, shape-checked).';
END
$$;
