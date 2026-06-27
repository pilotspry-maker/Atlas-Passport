-- ════════════════════════════════════════════════════════════════════════════
-- Migration 023 — Fix two ERROR-level Supabase security advisors
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   Two ERROR-level findings on the Supabase Security Advisors panel as of
--   2026-06-27 against project gaavynmmysdhovpatzlp:
--
--   1. public.check_ins_player_view — SECURITY DEFINER. The view filters by
--      auth.uid() but executes with the definer's privileges, so it
--      effectively bypasses any caller-side RLS on check_ins. Recreate as
--      security_invoker=true + security_barrier=true so the caller's role
--      and RLS apply (and so the WHERE clause is not pushed past RLS).
--
--   2. public.dev_env_status — RLS not enabled. The table holds dev/ops
--      diagnostic state and must never be readable by anon or authenticated
--      callers. Enable + FORCE RLS, revoke from anon/authenticated, and add
--      a service_role-only policy.
--
-- SAFETY:
--   - View is dropped + recreated identically; no schema change to consumers.
--   - dev_env_status policies revoke from end-user roles only — service_role
--     keeps full access via the new policy.
--   - Idempotent: DROP IF EXISTS / DROP POLICY IF EXISTS guards.
--
-- VERIFICATION (run on 2026-06-27 in prod, expected after apply):
--   SELECT relname, reloptions, relrowsecurity, relforcerowsecurity
--   FROM pg_class WHERE relname IN ('check_ins_player_view','dev_env_status');
--     → check_ins_player_view  reloptions: {security_invoker=true, security_barrier=true}
--     → dev_env_status         rls_enabled=true, rls_forced=true
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. check_ins_player_view → SECURITY INVOKER ──────────────────────────────
DROP VIEW IF EXISTS public.check_ins_player_view;

CREATE VIEW public.check_ins_player_view
WITH (security_invoker = true, security_barrier = true) AS
SELECT
  id,
  user_id,
  passport_id,
  node_id,
  status,
  submitted_at,
  reviewed_at,
  created_at
FROM public.check_ins
WHERE user_id = auth.uid();

REVOKE ALL ON public.check_ins_player_view FROM PUBLIC;
GRANT  SELECT ON public.check_ins_player_view TO authenticated;
GRANT  SELECT ON public.check_ins_player_view TO service_role;


-- ── 2. dev_env_status → RLS enabled + forced, service_role-only ──────────────
ALTER TABLE public.dev_env_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dev_env_status FORCE  ROW LEVEL SECURITY;

REVOKE ALL ON public.dev_env_status FROM PUBLIC;
REVOKE ALL ON public.dev_env_status FROM anon;
REVOKE ALL ON public.dev_env_status FROM authenticated;
GRANT  ALL ON public.dev_env_status TO service_role;

DROP POLICY IF EXISTS "dev_env_status_service_role_all" ON public.dev_env_status;
CREATE POLICY "dev_env_status_service_role_all"
  ON public.dev_env_status
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);


DO $$
BEGIN
  RAISE NOTICE '[023] Security advisors fixed: check_ins_player_view (invoker), dev_env_status (RLS forced) ✓';
END;
$$;
