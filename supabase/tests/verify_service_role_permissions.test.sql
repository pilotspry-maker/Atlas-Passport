-- ============================================================
-- Atlas Passport — service_role permission verification (pgTAP)
-- File: supabase/tests/verify_service_role_permissions.test.sql
--
-- WHAT THIS TESTS:
--   That every seed / CI helper function in the public schema has the
--   grants PostgREST needs in order to execute it under the service_role
--   JWT. Catches the failure modes that produced 42501 in CI:
--     - missing EXECUTE grant on service_role
--     - missing USAGE grant on schema public for authenticator
--     - silent function overloads that the GRANT did not cover
--     - missing functions (migration not applied)
--
-- HOW IT WORKS:
--   Calls public.verify_service_role_permissions() (defined by
--   migration 019). That RPC returns one row per target function with
--   a verdict column ('OK' | 'FAIL' | 'WARN' | 'MISSING'). We assert
--   every row's verdict is 'OK'. Any FAIL row's detail column is
--   printed by pgTAP's diag() so the test output names the offending
--   function and the exact GRANT to add.
--
-- RUN LOCALLY:
--   supabase db reset      # applies all migrations including 019
--   supabase test db       # runs every *.test.sql in supabase/tests/
--
-- RUN IN CI:
--   The same RPC is called over PostgREST as a pre-seed validation
--   step in .github/workflows/rls-exploit-tests.yml and
--   .github/workflows/rls-regression.yml. If migration 019 is not yet
--   applied to the live project, the CI step prints a clear message
--   directing you to apply migrations 005-019 via
--   apply-migrations-oneshot.yml.
--
-- pgTAP docs:               https://pgtap.org/
-- Supabase test runner:     https://supabase.com/docs/guides/database/testing
-- ============================================================

BEGIN;

-- ── Plan ──────────────────────────────────────────────────────
-- 1: RPC exists
-- 2: RPC is granted to service_role
-- 3: RPC is NOT granted to anon
-- 4: RPC is NOT granted to authenticated
-- 5: RPC returns at least one row (target list is non-empty)
-- 6: No row has verdict='FAIL'
-- 7: No row has verdict='MISSING'
-- 8: authenticator has USAGE on schema public
-- 9: service_role has EXECUTE on create_test_users()
-- 10: service_role has EXECUTE on create_regression_users()
SELECT plan(10);

-- ── 1. RPC exists ─────────────────────────────────────────────
SELECT has_function(
  'public',
  'verify_service_role_permissions',
  ARRAY[]::TEXT[],
  'verify_service_role_permissions() exists in the public schema'
);

-- ── 2-4. RPC grant surface is locked to service_role only ─────
SELECT function_privs_are(
  'public',
  'verify_service_role_permissions',
  ARRAY[]::TEXT[],
  'service_role',
  ARRAY['EXECUTE'],
  'service_role has EXECUTE on verify_service_role_permissions()'
);

SELECT function_privs_are(
  'public',
  'verify_service_role_permissions',
  ARRAY[]::TEXT[],
  'anon',
  ARRAY[]::TEXT[],
  'anon has NO grants on verify_service_role_permissions()'
);

SELECT function_privs_are(
  'public',
  'verify_service_role_permissions',
  ARRAY[]::TEXT[],
  'authenticated',
  ARRAY[]::TEXT[],
  'authenticated has NO grants on verify_service_role_permissions()'
);

-- ── 5. RPC returns rows ───────────────────────────────────────
SELECT cmp_ok(
  (SELECT COUNT(*)::INT FROM public.verify_service_role_permissions()),
  '>=',
  1,
  'verify_service_role_permissions() returns at least one row'
);

-- Surface offending rows in pgTAP diagnostic output BEFORE assertion fails
-- so the test log names the exact functions that need fixing.
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT function_name, function_args, verdict, detail
    FROM public.verify_service_role_permissions()
    WHERE verdict IN ('FAIL', 'MISSING')
  LOOP
    RAISE NOTICE '[verify_service_role_permissions] % public.%(%): %',
      rec.verdict, rec.function_name, rec.function_args, rec.detail;
  END LOOP;
END $$;

-- ── 6. No FAIL rows ───────────────────────────────────────────
SELECT is(
  (SELECT COUNT(*)::INT FROM public.verify_service_role_permissions()
     WHERE verdict = 'FAIL'),
  0,
  'No seed/CI function has verdict=FAIL — all required grants are present'
);

-- ── 7. No MISSING rows (every migration applied) ──────────────
SELECT is(
  (SELECT COUNT(*)::INT FROM public.verify_service_role_permissions()
     WHERE verdict = 'MISSING'),
  0,
  'No seed/CI function has verdict=MISSING — all migrations 006-016 applied'
);

-- ── 8. authenticator USAGE on public ──────────────────────────
SELECT ok(
  (SELECT bool_and(authenticator_usage_on_public)
     FROM public.verify_service_role_permissions()
     WHERE verdict <> 'MISSING'),
  'authenticator has USAGE on schema public'
);

-- ── 9, 10. Explicit assertions for the two functions called out
--    by the failing CI jobs (create_test_users, create_regression_users)
SELECT ok(
  (SELECT service_role_execute
     FROM public.verify_service_role_permissions()
     WHERE function_name = 'create_test_users'
     LIMIT 1),
  'service_role has EXECUTE on create_test_users()'
);

SELECT ok(
  (SELECT service_role_execute
     FROM public.verify_service_role_permissions()
     WHERE function_name = 'create_regression_users'
     LIMIT 1),
  'service_role has EXECUTE on create_regression_users()'
);

SELECT * FROM finish();

ROLLBACK;
