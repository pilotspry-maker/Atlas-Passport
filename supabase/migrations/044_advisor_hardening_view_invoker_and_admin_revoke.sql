-- Migration 044 — Advisor hardening: security_invoker view + revoke anon admin RPC
--
-- Closes two Supabase advisor findings that surfaced on 2026-06-30:
--
--   1. ERROR — `security_definer_view`
--      View `public.check_ins_player_view` was created without
--      `security_invoker=true`, so it enforces the view creator's
--      permissions instead of the querying user's. It already has
--      `security_barrier=true` (from migration 023) but the invoker
--      flag was never applied. This migration adds it.
--      Ref: https://supabase.com/docs/guides/database/database-linter?lint=0010_security_definer_view
--
--   2. WARN — `anon_security_definer_function_executable`
--      Function `public.committed_is_admin(uuid)` is a SECURITY DEFINER
--      admin-gate helper. Migration 039 correctly granted EXECUTE only
--      to `authenticated` and revoked from PUBLIC, but the `anon` role
--      still appears in the grantees list (grant drift). This migration
--      explicitly revokes EXECUTE from `anon`. Signed-in users
--      (`authenticated`) retain access — the function is called by the
--      `profiles_update_own` policy WITH CHECK clause (see migration 039).
--      Ref: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
--
-- Non-goals (intentionally not touched):
--   - `public.get_public_stats()` anon EXECUTE — the Kaelo Atlas Command
--     dashboard depends on this. Confirmed intentional per issue #68 and
--     migration 041.
--   - Auth "Leaked Password Protection" — that is a Supabase Auth
--     dashboard toggle, not a SQL change. See PR description for the
--     manual step.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. check_ins_player_view — enforce security_invoker=true
-- ─────────────────────────────────────────────────────────────────────
ALTER VIEW public.check_ins_player_view
  SET (security_invoker = true, security_barrier = true);

COMMENT ON VIEW public.check_ins_player_view IS
  'Player-scoped check-ins projection. security_invoker=true so RLS on '
  'check_ins is enforced as the caller, not the view owner. '
  'security_barrier=true prevents leaky predicates. See migration 044.';

-- ─────────────────────────────────────────────────────────────────────
-- 2. committed_is_admin(uuid) — revoke anon EXECUTE
-- ─────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.committed_is_admin(uuid) FROM anon;

-- Idempotent re-assert of the intended grant surface.
REVOKE ALL    ON FUNCTION public.committed_is_admin(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.committed_is_admin(uuid) TO authenticated;

COMMENT ON FUNCTION public.committed_is_admin(uuid) IS
  'Admin-gate helper used by profiles_update_own RLS policy. '
  'SECURITY DEFINER, STABLE, search_path=''''. EXECUTE granted to '
  '`authenticated` only — never `anon` or PUBLIC. See migration 044.';

-- ─────────────────────────────────────────────────────────────────────
-- 3. Verification (fail migration if state is wrong after apply)
-- ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_opts text[];
  v_has_anon boolean;
BEGIN
  -- 3a. view options include security_invoker=true
  SELECT c.reloptions
    INTO v_opts
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relname = 'check_ins_player_view';

  IF v_opts IS NULL OR NOT ('security_invoker=true' = ANY(v_opts)) THEN
    RAISE EXCEPTION
      '[044] VERIFICATION FAILED: check_ins_player_view missing security_invoker=true. reloptions=%',
      v_opts;
  END IF;

  -- 3b. anon must NOT have EXECUTE on committed_is_admin
  SELECT EXISTS (
    SELECT 1
      FROM information_schema.role_routine_grants
     WHERE routine_schema = 'public'
       AND routine_name   = 'committed_is_admin'
       AND grantee        = 'anon'
       AND privilege_type = 'EXECUTE'
  ) INTO v_has_anon;

  IF v_has_anon THEN
    RAISE EXCEPTION
      '[044] VERIFICATION FAILED: anon still has EXECUTE on committed_is_admin(uuid)';
  END IF;

  RAISE NOTICE '[044] OK: check_ins_player_view security_invoker=true; anon EXECUTE revoked on committed_is_admin(uuid)';
END $$;

COMMIT;
