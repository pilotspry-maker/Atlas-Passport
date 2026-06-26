-- ════════════════════════════════════════════════════════════════════════════
-- Migration 017 — Grant service_role EXECUTE on CI seed functions
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   On 2026-06-26 all 8 CI seed functions were locked to service_role-only
--   callers (REVOKE from PUBLIC/anon/authenticated). However no explicit
--   GRANT to service_role was added, so the functions became callable by
--   nobody — including service_role itself.
--
--   CI now uses the service_role key (apikey + Authorization: Bearer) for
--   all seed RPC calls. This migration adds the missing GRANT so those calls
--   succeed.
--
--   Scope: seed/utility functions only.  Test assertion flows (exploit tests,
--   regression tests) use anon/authenticated keys intentionally to verify
--   RLS from a player perspective — those are NOT modified here.
-- ════════════════════════════════════════════════════════════════════════════

-- ── create_test_users() — migration 008/011 ──────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_test_users'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.create_test_users() TO service_role';
    RAISE NOTICE '[017] GRANT EXECUTE create_test_users → service_role ✓';
  ELSE
    RAISE NOTICE '[017] create_test_users not found — skipping';
  END IF;
END $$;

-- ── create_regression_users() — migration 009 ────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_regression_users'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.create_regression_users() TO service_role';
    RAISE NOTICE '[017] GRANT EXECUTE create_regression_users → service_role ✓';
  ELSE
    RAISE NOTICE '[017] create_regression_users not found — skipping';
  END IF;
END $$;

-- ── create_exploit_test_users() — migration 016 ──────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_exploit_test_users'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.create_exploit_test_users() TO service_role';
    RAISE NOTICE '[017] GRANT EXECUTE create_exploit_test_users → service_role ✓';
  ELSE
    RAISE NOTICE '[017] create_exploit_test_users not found — skipping (apply migration 016 first)';
  END IF;
END $$;

-- ── seed_ci_fixtures() ────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'seed_ci_fixtures'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.seed_ci_fixtures() TO service_role';
    RAISE NOTICE '[017] GRANT EXECUTE seed_ci_fixtures → service_role ✓';
  ELSE
    RAISE NOTICE '[017] seed_ci_fixtures not found — skipping';
  END IF;
END $$;

-- ── seed_ci_fixtures_v2() ─────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'seed_ci_fixtures_v2'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.seed_ci_fixtures_v2() TO service_role';
    RAISE NOTICE '[017] GRANT EXECUTE seed_ci_fixtures_v2 → service_role ✓';
  ELSE
    RAISE NOTICE '[017] seed_ci_fixtures_v2 not found — skipping';
  END IF;
END $$;

-- ── seed_ci_passports() — migration 015 ──────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'seed_ci_passports'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.seed_ci_passports() TO service_role';
    RAISE NOTICE '[017] GRANT EXECUTE seed_ci_passports → service_role ✓';
  ELSE
    RAISE NOTICE '[017] seed_ci_passports not found — skipping (apply migration 015 first)';
  END IF;
END $$;

-- ── seed_regression_passports() — migration 015 ──────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'seed_regression_passports'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.seed_regression_passports() TO service_role';
    RAISE NOTICE '[017] GRANT EXECUTE seed_regression_passports → service_role ✓';
  ELSE
    RAISE NOTICE '[017] seed_regression_passports not found — skipping (apply migration 015 first)';
  END IF;
END $$;

-- ── confirm_test_users(TEXT) — migration 006 ─────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'confirm_test_users'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.confirm_test_users(TEXT) TO service_role';
    RAISE NOTICE '[017] GRANT EXECUTE confirm_test_users(TEXT) → service_role ✓';
  ELSE
    RAISE NOTICE '[017] confirm_test_users not found — skipping';
  END IF;
END $$;

-- ── cleanup_ci_fixtures() — if present ───────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'cleanup_ci_fixtures'
  ) THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.cleanup_ci_fixtures() TO service_role';
    RAISE NOTICE '[017] GRANT EXECUTE cleanup_ci_fixtures → service_role ✓';
  ELSE
    RAISE NOTICE '[017] cleanup_ci_fixtures not found — skipping';
  END IF;
END $$;

DO $$
BEGIN
  RAISE NOTICE '[017] service_role EXECUTE grants complete.';
  RAISE NOTICE '[017] If any function showed "not found", apply its migration first then re-run this script.';
END $$;
