-- ════════════════════════════════════════════════════════════════════════════
-- Migration 042 — passports_update_own: explicit authenticated UPDATE guard
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   The passports table has SELECT + INSERT policies but no UPDATE policy.
--   PostgreSQL's default-deny means authenticated users cannot currently UPDATE
--   passports directly — but the denial is implicit. This migration makes it
--   explicit and auditable, adding the correct policy shape expected by the
--   weekday RLS drift watch (INV-4).
--
--   All legitimate passport state transitions in the app use createAdminClient()
--   (service_role), which bypasses RLS. This policy only governs direct
--   PostgREST UPDATE calls by authenticated users.
--
--   Fields locked as immutable (WITH CHECK against the committed row, read
--   via a SECURITY DEFINER helper to avoid RLS recursion — see Pattern A
--   in docs/rls_security_patterns.md and model migration 035):
--     user_id      — cannot transfer ownership
--     corridor_id  — cannot switch corridors
--     activated_at — immutable timestamp
--     expires_at   — cannot self-extend the 72-hour window
--
--   reward_claimed is protected separately by the prevent_reward_unclaim
--   BEFORE-UPDATE trigger installed in migration 005.
--
-- INVARIANT (checked by rls-drift-watch INV-4):
--   roles = '{authenticated}' AND qual contains 'user_id' AND 'auth.uid'
--   AND with_check contains 'user_id' AND 'auth.uid'
--
-- RECURSION-SAFE PATTERN:
--   The original draft of this migration used inline subqueries against
--   public.passports inside WITH CHECK to compare new vs committed values:
--     corridor_id = (SELECT p2.corridor_id FROM public.passports p2 WHERE p2.id = passports.id)
--   That triggers RLS re-entry on public.passports during WITH CHECK
--   evaluation and raises 42P17 "infinite recursion detected in policy"
--   (same class of bug fixed for profiles_update_own in migration 035).
--   We follow the migration 035 fix: move the lookup into a SECURITY DEFINER
--   helper named with the `committed_` prefix that bypasses RLS on its own
--   read. The read is safe — the helper returns only the immutable structural
--   fields of a row the caller already passes the id for, and the USING clause
--   already restricts the caller to rows they own (auth.uid() = user_id).
-- ════════════════════════════════════════════════════════════════════════════

-- ── SECURITY DEFINER helper: committed_passport_immutables ──────────────────
-- Returns the committed immutable fields of public.passports for a given id.
-- SECURITY DEFINER + locked search_path so the helper bypasses RLS on its
-- own read without exposing a search_path attack surface (Pattern D).
create or replace function public.committed_passport_immutables(p_id uuid)
returns table (
  user_id      uuid,
  corridor_id  uuid,
  activated_at timestamptz,
  expires_at   timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.user_id, p.corridor_id, p.activated_at, p.expires_at
  from public.passports p
  where p.id = p_id
$$;

comment on function public.committed_passport_immutables(uuid) is
  'Returns the committed (user_id, corridor_id, activated_at, expires_at) for a passport by id. SECURITY DEFINER to avoid RLS re-entry when used inside passports_update_own WITH CHECK (same pattern as migration 035 / current_user_is_admin). Safe: the calling policy already gates by auth.uid() = user_id, so the caller can only reach this helper for a row they already own. Locked search_path prevents Pattern D escalation.';

-- Lock down EXECUTE: only authenticated callers (PostgREST UPDATE path) and
-- service_role (admin path) ever need this. anon has no auth.uid(), so the
-- helper is meaningless there and exposing it would trip Supabase advisor
-- 0028 (anon-executable SECURITY DEFINER function).
revoke all      on function public.committed_passport_immutables(uuid) from public;
revoke execute  on function public.committed_passport_immutables(uuid) from anon;
grant  execute  on function public.committed_passport_immutables(uuid) to authenticated, service_role;

-- ── passports_update_own policy ─────────────────────────────────────────────
-- Idempotent: drop before recreate.
DROP POLICY IF EXISTS "passports_update_own" ON public.passports;

-- Authenticated users may UPDATE only their own passports, and only if the
-- immutable structural fields remain unchanged. The four immutable-field
-- comparisons read the committed row via the SECURITY DEFINER helper above,
-- so this policy contains no inline subquery against public.passports and
-- cannot trigger 42P17 recursion.
CREATE POLICY "passports_update_own" ON public.passports
  FOR UPDATE TO authenticated
  USING (
    (select auth.uid()) = user_id
  )
  WITH CHECK (
    -- Own row only (new values must still belong to the same user)
    (select auth.uid()) = user_id
    -- All four structural fields must equal the committed values. One helper
    -- call, four field comparisons, no RLS re-entry.
    AND (passports.user_id, passports.corridor_id, passports.activated_at, passports.expires_at)
        = (
          select c.user_id, c.corridor_id, c.activated_at, c.expires_at
          from public.committed_passport_immutables(passports.id) c
        )
  );

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'passports'
      AND policyname = 'passports_update_own'
      AND cmd        = 'UPDATE'
  ) THEN
    RAISE EXCEPTION '[042] VERIFICATION FAILED: passports_update_own policy not found.';
  END IF;
  -- Confirm no anon/public UPDATE policy exists (the CRITICAL exploit class).
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'passports'
      AND cmd        = 'UPDATE'
      AND (roles::text LIKE '%anon%' OR roles::text LIKE '%public%')
  ) THEN
    RAISE EXCEPTION '[042] VERIFICATION FAILED: anon or public UPDATE policy found on passports — CRITICAL.';
  END IF;
  -- Confirm the recursion-safe helper exists and has the expected security
  -- properties.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'committed_passport_immutables'
      AND p.prosecdef = true
  ) THEN
    RAISE EXCEPTION '[042] VERIFICATION FAILED: committed_passport_immutables SECURITY DEFINER helper not found.';
  END IF;
  RAISE NOTICE '[042] OK: passports_update_own verified. Recursion-safe helper installed. No anon/public UPDATE policies on passports.';
END;
$$;
