-- ════════════════════════════════════════════════════════════════════════════
-- Migration 030 — RLS audit helpers for the regression test suite
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   tests/rls/regression/rls-reg-04-policy-inventory.test.ts (REG-4) validates
--   that required RLS policies exist by name and that RLS is enabled on all
--   private tables. To do this it needs to query pg_catalog.pg_policies and
--   pg_catalog.pg_class.
--
--   PostgREST only exposes the 'public' schema by default. Querying
--   GET /rest/v1/pg_policies returns PGRST205 (table not found) because
--   pg_policies lives in pg_catalog, not public.
--
--   These two SECURITY DEFINER functions expose the required catalog data
--   via the standard /rest/v1/rpc/* path so REG-4 tests can call them
--   with the service role key.
--
-- FUNCTIONS:
--   get_public_rls_policies()   → rows from pg_policies WHERE schemaname='public'
--   get_public_rls_status()     → relname + relrowsecurity for public tables
--
-- IDEMPOTENT: CREATE OR REPLACE.
-- ════════════════════════════════════════════════════════════════════════════

-- ── get_public_rls_policies ──────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_public_rls_policies();

CREATE OR REPLACE FUNCTION public.get_public_rls_policies()
RETURNS TABLE (
  tablename  name,
  policyname name,
  cmd        text,
  permissive text,
  roles      name[],
  qual       text,
  with_check text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    tablename,
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public';
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_rls_policies() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_public_rls_policies() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_public_rls_policies() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.get_public_rls_policies() TO service_role;

-- ── get_public_rls_status ────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_public_rls_status();

CREATE OR REPLACE FUNCTION public.get_public_rls_status()
RETURNS TABLE (
  relname        name,
  relrowsecurity boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    c.relname,
    c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
  ORDER BY c.relname;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_rls_status() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_public_rls_status() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_public_rls_status() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.get_public_rls_status() TO service_role;

DO $$
BEGIN
  RAISE NOTICE '[030] RLS audit helpers get_public_rls_policies + get_public_rls_status created ✓';
END;
$$;
