-- ════════════════════════════════════════════════════════════════════════════
-- Migration 041 — Restore anon/authenticated EXECUTE on public.get_public_stats()
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   Migration 034 ("Tighten service-insert policies, lock down corridor.*,
--   scope public bucket reads, and revoke get_public_stats EXECUTE") revoked
--   EXECUTE on public.get_public_stats() from anon and authenticated. The
--   stated rationale (lines 45-54 of 034) was that the Kaelo Atlas Command
--   public dashboard reads public.public_stats "directly via PostgREST — it
--   does NOT call the RPC", so revoking EXECUTE was deemed safe.
--
--   That premise was incorrect. public.public_stats is defined as:
--
--       SELECT total_users, total_passports, ...
--       FROM get_public_stats() AS get_public_stats(...);
--
--   The view is SECURITY INVOKER, so a SELECT from public.public_stats
--   executes get_public_stats() as the caller. After 034 shipped, anon and
--   authenticated lost EXECUTE, and the dashboard at
--   https://atlas-passport.pplx.app went OFFLINE — every KPI dashed out and
--   the PostgREST /rest/v1/public_stats endpoint returned 401.
--
-- WHAT THIS DOES:
--   Restore EXECUTE on public.get_public_stats() to anon and authenticated.
--
-- WHY THIS IS STILL RLS-SAFE:
--   public.get_public_stats() is SECURITY DEFINER and returns only aggregate
--   counts (total users, passports, check-ins, etc.) — no row-level traveler
--   data, no PII. It is the intended public-stats surface for the dashboard.
--   The security advisor warnings 034 was trying to address
--   (anon_security_definer_function_executable /
--    authenticated_security_definer_function_executable) flag the SHAPE of
--   the surface (SECURITY DEFINER + EXECUTE to anon) but the function's
--   body is purpose-built to be public-safe, so the correct response is to
--   document the exception rather than break the dashboard.
--
-- ALTERNATIVE WE CONSIDERED:
--   Refactor the dashboard to call public.rpc.get_public_stats directly and
--   leave the view ungranted. Deferred — restoring EXECUTE is the minimal
--   change that re-greens the dashboard without touching the deployed
--   client.
--
-- IDEMPOTENT: GRANT is idempotent (re-running has no effect once granted).
-- ════════════════════════════════════════════════════════════════════════════

begin;

grant execute on function public.get_public_stats() to anon, authenticated;

comment on function public.get_public_stats() is
  'Public aggregate stats for the Kaelo Atlas Command dashboard. SECURITY '
  'DEFINER by design — returns only aggregate counts (users, passports, '
  'check-ins, corridors, nodes, etc.), no row-level traveler data. EXECUTE '
  'is intentionally granted to anon and authenticated; the public.public_stats '
  'view (SECURITY INVOKER) wraps this function and is the surface used by '
  'PostgREST clients. See migrations 034 and 041 for the full history.';

commit;

-- ════════════════════════════════════════════════════════════════════════════
-- VERIFY (run after apply):
--
--   -- anon + authenticated regain EXECUTE; service_role keeps it
--   select rolname,
--          has_function_privilege(rolname, 'public.get_public_stats()', 'EXECUTE') as can_exec
--   from pg_roles
--   where rolname in ('anon','authenticated','service_role')
--   order by rolname;
--   -- expect anon=true, authenticated=true, service_role=true
--
--   -- View now returns rows to anon
--   set role anon;
--   select * from public.public_stats limit 1;
--   reset role;
-- ════════════════════════════════════════════════════════════════════════════
