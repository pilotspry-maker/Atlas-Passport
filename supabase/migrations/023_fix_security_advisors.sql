-- ════════════════════════════════════════════════════════════════════════════
-- Migration 023 — Fix two ERROR-level Supabase security advisors
-- Recovered from production schema_migrations on 2026-06-27
-- ════════════════════════════════════════════════════════════════════════════
--
-- 1. public.check_ins_player_view — currently SECURITY DEFINER. Recreate as
--    security_invoker=true + security_barrier=true so caller's RLS applies.
--
-- 2. public.dev_env_status — currently has no RLS. Enable + force RLS,
--    revoke anon/authenticated, add service_role-only policy.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. check_ins_player_view → SECURITY INVOKER ─────────────────────────────
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

-- ── 2. dev_env_status → RLS enabled + forced, service_role-only ─────────────
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
