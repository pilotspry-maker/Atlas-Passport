-- ════════════════════════════════════════════════════════════════════════════
-- Migration 019 — verify_service_role_permissions() introspection RPC
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   PostgREST 42501 ("permission denied for function") failures on seed RPCs
--   in CI were difficult to diagnose because:
--     a) PostgREST hides which role the JWT ultimately decoded to.
--     b) Direct pg_proc / pg_roles queries via PostgREST are gated by role
--        privileges and the service_role JWT can't run ad-hoc SQL.
--     c) Manually running `has_function_privilege()` locally tests the LOCAL
--        DB state, not the live project's state at the moment PostgREST
--        evaluates the call.
--
--   This RPC closes the loop. It's:
--     - SECURITY DEFINER so the caller doesn't need pg_catalog privileges
--     - granted ONLY to service_role (the legitimate CI caller)
--     - read-only — exposes grant metadata, never row data or secrets
--     - search_path-pinned to pg_catalog, public for injection safety
--     - idempotent — every CI run re-asserts the live state
--
--   CI calls this BEFORE seed RPCs as a pre-flight check. Local pgTAP tests
--   call it via supabase/tests/verify_service_role_permissions.test.sql.
--
-- SAFETY:
--   - SECURITY DEFINER runs as the function owner (postgres on Supabase),
--     which can read pg_catalog regardless of caller role.
--   - REVOKE from PUBLIC/anon/authenticated; GRANT EXECUTE to service_role
--     only. The same role that legitimately calls seed RPCs.
--   - Returns NO row data from app tables, NO column data, NO secrets — only
--     pg_catalog metadata that any DB superuser could read.
-- ════════════════════════════════════════════════════════════════════════════

-- Drop first to allow signature changes on re-apply
DROP FUNCTION IF EXISTS public.verify_service_role_permissions();

CREATE OR REPLACE FUNCTION public.verify_service_role_permissions()
RETURNS TABLE (
  function_name                       TEXT,
  function_args                       TEXT,
  function_oid                        OID,
  owner_role                          TEXT,
  overload_count                      INT,
  acl                                 TEXT,
  service_role_execute                BOOLEAN,
  authenticator_execute               BOOLEAN,
  authenticated_execute               BOOLEAN,
  anon_execute                        BOOLEAN,
  public_execute                      BOOLEAN,
  authenticator_usage_on_public       BOOLEAN,
  service_role_usage_on_public        BOOLEAN,
  service_role_bypassrls              BOOLEAN,
  verdict                             TEXT,   -- 'OK' | 'FAIL' | 'WARN' | 'MISSING'
  detail                              TEXT    -- human-readable explanation
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  -- Canonical list of seed / CI helper functions to verify. Update this
  -- whenever a new helper is added — co-locate with the migration that
  -- introduces it.
  target_names CONSTANT TEXT[] := ARRAY[
    'create_test_users',
    'create_regression_users',
    'create_exploit_test_users',
    'seed_ci_fixtures',
    'seed_ci_fixtures_v2',
    'seed_ci_passports',
    'seed_regression_passports',
    'confirm_test_users',
    'cleanup_ci_fixtures'
  ];
  v_authn_usage BOOLEAN;
  v_svc_usage   BOOLEAN;
  v_bypassrls   BOOLEAN;
BEGIN
  -- Schema- and role-level state is constant across rows — compute once.
  v_authn_usage := pg_catalog.has_schema_privilege('authenticator', 'public', 'USAGE');
  v_svc_usage   := pg_catalog.has_schema_privilege('service_role',  'public', 'USAGE');
  SELECT r.rolbypassrls INTO v_bypassrls
  FROM pg_catalog.pg_roles r
  WHERE r.rolname = 'service_role';

  RETURN QUERY
  WITH found AS (
    SELECT
      p.proname::TEXT                                                     AS f_name,
      pg_catalog.pg_get_function_identity_arguments(p.oid)::TEXT          AS f_args,
      p.oid                                                               AS f_oid,
      pg_catalog.pg_get_userbyid(p.proowner)::TEXT                        AS f_owner,
      (SELECT COUNT(*)::INT
         FROM pg_catalog.pg_proc p2
         JOIN pg_catalog.pg_namespace n2 ON n2.oid = p2.pronamespace
         WHERE n2.nspname = 'public' AND p2.proname = p.proname)          AS f_overloads,
      COALESCE(p.proacl::TEXT, '<default>')                               AS f_acl,
      pg_catalog.has_function_privilege('service_role',   p.oid, 'EXECUTE') AS f_svc,
      pg_catalog.has_function_privilege('authenticator',  p.oid, 'EXECUTE') AS f_authn,
      pg_catalog.has_function_privilege('authenticated',  p.oid, 'EXECUTE') AS f_authd,
      pg_catalog.has_function_privilege('anon',           p.oid, 'EXECUTE') AS f_anon,
      pg_catalog.has_function_privilege('public',         p.oid, 'EXECUTE') AS f_pub
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(target_names)
  ),
  -- Per-function verdict + detail
  judged AS (
    SELECT
      f_name, f_args, f_oid, f_owner, f_overloads, f_acl,
      f_svc, f_authn, f_authd, f_anon, f_pub,
      CASE
        WHEN NOT v_authn_usage THEN 'FAIL'
        WHEN NOT f_svc          THEN 'FAIL'
        WHEN f_overloads > 1    THEN 'WARN'
        ELSE                         'OK'
      END AS j_verdict,
      CASE
        WHEN NOT v_authn_usage
          THEN 'authenticator lacks USAGE on schema public — PostgREST cannot reach this function (or any function in public).'
        WHEN NOT f_svc
          THEN 'service_role lacks EXECUTE — GRANT EXECUTE ON FUNCTION public.' || f_name || '(' || f_args || ') TO service_role;'
        WHEN f_overloads > 1
          THEN 'Multiple overloads exist (' || f_overloads::TEXT || ') — verify GRANT covers the signature PostgREST actually calls.'
        ELSE 'OK'
      END AS j_detail
    FROM found
  ),
  -- Synthesise MISSING rows for target functions that don't exist
  missing AS (
    SELECT
      t::TEXT                AS f_name,
      ''::TEXT               AS f_args,
      NULL::OID              AS f_oid,
      NULL::TEXT             AS f_owner,
      0::INT                 AS f_overloads,
      '<not found>'::TEXT    AS f_acl,
      NULL::BOOLEAN          AS f_svc,
      NULL::BOOLEAN          AS f_authn,
      NULL::BOOLEAN          AS f_authd,
      NULL::BOOLEAN          AS f_anon,
      NULL::BOOLEAN          AS f_pub,
      'MISSING'::TEXT        AS j_verdict,
      ('Function public.' || t || ' does not exist — its migration has not been applied to this project.')::TEXT AS j_detail
    FROM unnest(target_names) AS t
    WHERE NOT EXISTS (
      SELECT 1 FROM found f WHERE f.f_name = t
    )
  )
  SELECT
    f_name      AS function_name,
    f_args      AS function_args,
    f_oid       AS function_oid,
    f_owner     AS owner_role,
    f_overloads AS overload_count,
    f_acl       AS acl,
    f_svc       AS service_role_execute,
    f_authn     AS authenticator_execute,
    f_authd     AS authenticated_execute,
    f_anon      AS anon_execute,
    f_pub       AS public_execute,
    v_authn_usage,
    v_svc_usage,
    v_bypassrls,
    j_verdict   AS verdict,
    j_detail    AS detail
  FROM judged
  UNION ALL
  SELECT
    f_name, f_args, f_oid, f_owner, f_overloads, f_acl,
    f_svc, f_authn, f_authd, f_anon, f_pub,
    v_authn_usage, v_svc_usage, v_bypassrls,
    j_verdict, j_detail
  FROM missing
  ORDER BY 1, 3;
END;
$$;

-- Lock callers to service_role only. This RPC is a CI diagnostic — there is
-- no legitimate reason for anon or authenticated to call it.
REVOKE ALL ON FUNCTION public.verify_service_role_permissions() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_service_role_permissions() FROM anon;
REVOKE ALL ON FUNCTION public.verify_service_role_permissions() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.verify_service_role_permissions() TO service_role;

COMMENT ON FUNCTION public.verify_service_role_permissions() IS
  'CI diagnostic RPC. Returns one row per seed/CI helper function in the '
  'public schema with grant/ownership/overload state and a verdict '
  '(OK/FAIL/WARN/MISSING) explaining any issue. SECURITY DEFINER; reads '
  'pg_catalog only. Called as a pre-seed validation step from '
  '.github/workflows/rls-exploit-tests.yml and rls-regression.yml, and as '
  'a pgTAP assertion source from supabase/tests/verify_service_role_permissions.test.sql.';

DO $$
BEGIN
  RAISE NOTICE '[019] verify_service_role_permissions() created and granted to service_role.';
END $$;
