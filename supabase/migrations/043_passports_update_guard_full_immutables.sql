-- ════════════════════════════════════════════════════════════════════════════
-- Migration 043 — passports_update_own: close the state-mutation gap
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   Migration 042 introduced an explicit `passports_update_own` UPDATE
--   policy for authenticated users. That policy pinned FOUR structural
--   fields as immutable:
--
--     user_id, corridor_id, activated_at, expires_at
--
--   But the `passports` table has additional player-mutable columns that
--   migration 042 left unguarded:
--
--     status              (text)     — 'active' | 'complete' | 'expired' | ...
--     completed_at        (timestamptz)
--     warning_sent_at     (timestamptz)
--     reward_claimed      (bool)
--
--   Before migration 042, PostgreSQL default-deny prevented all
--   authenticated PATCHes on passports, so these fields were implicitly
--   immutable. Migration 042 opened an authenticated UPDATE path without
--   re-locking them, which enabled a live exploit:
--
--     PATCH /rest/v1/passports?id=eq.<own_id>
--       { "status": "complete", "reward_claimed": true }
--
--   That flips the passport to complete and, via rewards_select_own
--   (gated on passport.status = 'complete'), unlocks the corridor
--   redemption_code — a business-logic bypass.
--
--   Migration 005's prevent_reward_unclaim trigger only blocks
--   reward_claimed TRUE→FALSE. It does NOT block FALSE→TRUE, because it
--   was written under the assumption that no UPDATE policy existed.
--
-- WHAT THIS DOES:
--   Extends the SECURITY DEFINER helper `committed_passport_immutables`
--   to return the four additional immutable-under-authenticated-PATCH
--   fields alongside the original four, then rewrites
--   `passports_update_own` WITH CHECK to pin all eight against the
--   committed row via one helper call.
--
--   All legitimate transitions (status → complete, warning_sent_at,
--   completed_at, reward_claimed → true) go through createAdminClient()
--   (service_role), which bypasses RLS entirely — see CLAUDE.md §8.
--
-- INVARIANT (checked by rls-drift-watch INV-4):
--   roles = '{authenticated}' AND qual contains 'user_id' AND 'auth.uid'
--   AND with_check contains 'user_id' AND 'auth.uid'
--
-- RECURSION-SAFETY (Pattern A):
--   The helper is `committed_`-prefixed and SECURITY DEFINER with a locked
--   search_path (Pattern D). The WITH CHECK never subqueries
--   public.passports directly — it only calls the helper — so no RLS
--   re-entry occurs during policy evaluation. This mirrors the migration
--   035 pattern.
--
-- FIELDS NOT PINNED HERE:
--   `id`            — primary key, PostgREST doesn't allow it in PATCH bodies
--                     with our schema, and even if attempted, RLS USING
--                     restricts the row.
--   `created_at`    — has a DEFAULT and no legitimate reason to be updated,
--                     but it's not security-critical. Left mutable for now
--                     to keep the diff scoped to the actual exploit surface.
-- ════════════════════════════════════════════════════════════════════════════

-- ── SECURITY DEFINER helper: committed_passport_immutables (v2) ─────────────
-- Extend the return signature to include status, completed_at,
-- warning_sent_at, reward_claimed. Use CREATE OR REPLACE where possible;
-- since we are widening the RETURNS TABLE signature, we must DROP first.
-- The old signature only returned four fields — no other callsite exists in
-- the repo (only the passports_update_own policy uses it), so this drop is
-- safe. We also drop the policy first to avoid dependency errors, and
-- recreate both in the correct order below.
DROP POLICY IF EXISTS "passports_update_own" ON public.passports;
DROP FUNCTION IF EXISTS public.committed_passport_immutables(uuid);

create or replace function public.committed_passport_immutables(p_id uuid)
returns table (
  user_id          uuid,
  corridor_id      uuid,
  activated_at     timestamptz,
  expires_at       timestamptz,
  status           text,
  completed_at     timestamptz,
  warning_sent_at  timestamptz,
  reward_claimed   boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.user_id,
    p.corridor_id,
    p.activated_at,
    p.expires_at,
    p.status,
    p.completed_at,
    p.warning_sent_at,
    p.reward_claimed
  from public.passports p
  where p.id = p_id
$$;

comment on function public.committed_passport_immutables(uuid) is
  'Returns the committed immutable-under-authenticated-PATCH fields of a passport by id: (user_id, corridor_id, activated_at, expires_at, status, completed_at, warning_sent_at, reward_claimed). SECURITY DEFINER to avoid RLS re-entry when used inside passports_update_own WITH CHECK (same pattern as migration 035 / current_user_is_admin). Safe: the calling policy already gates by auth.uid() = user_id, so the caller can only reach this helper for a row they already own. Locked search_path prevents Pattern D escalation. Widened in migration 043 to close the state-mutation gap left by migration 042.';

-- Lock down EXECUTE (identical grants to the v1 helper).
revoke all      on function public.committed_passport_immutables(uuid) from public;
revoke execute  on function public.committed_passport_immutables(uuid) from anon;
grant  execute  on function public.committed_passport_immutables(uuid) to authenticated, service_role;

-- ── passports_update_own policy (v2 — full immutables) ──────────────────────
-- Authenticated users may UPDATE only their own passports, and only if
-- ALL EIGHT structural/state fields remain unchanged. In practice this
-- makes the authenticated UPDATE path a no-op — which is the intended
-- security posture: legitimate transitions run through service_role and
-- bypass RLS. The policy remains explicit and INV-4-compliant so the
-- drift watch can assert on it.
CREATE POLICY "passports_update_own" ON public.passports
  FOR UPDATE TO authenticated
  USING (
    (select auth.uid()) = user_id
  )
  WITH CHECK (
    -- Own row only (new values must still belong to the same user)
    (select auth.uid()) = user_id
    -- All eight fields must equal the committed values. One helper call,
    -- eight field comparisons, no RLS re-entry.
    AND (
      passports.user_id,
      passports.corridor_id,
      passports.activated_at,
      passports.expires_at,
      passports.status,
      passports.completed_at,
      passports.warning_sent_at,
      passports.reward_claimed
    ) = (
      select
        c.user_id,
        c.corridor_id,
        c.activated_at,
        c.expires_at,
        c.status,
        c.completed_at,
        c.warning_sent_at,
        c.reward_claimed
      from public.committed_passport_immutables(passports.id) c
    )
  );

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_helper_rettypes text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'passports'
      AND policyname = 'passports_update_own'
      AND cmd        = 'UPDATE'
  ) THEN
    RAISE EXCEPTION '[043] VERIFICATION FAILED: passports_update_own policy not found.';
  END IF;

  -- Confirm no anon/public UPDATE policy exists (the CRITICAL exploit class).
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'passports'
      AND cmd        = 'UPDATE'
      AND (roles::text LIKE '%anon%' OR roles::text LIKE '%public%')
  ) THEN
    RAISE EXCEPTION '[043] VERIFICATION FAILED: anon or public UPDATE policy found on passports — CRITICAL.';
  END IF;

  -- Confirm the recursion-safe helper exists with SECURITY DEFINER.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'committed_passport_immutables'
      AND p.prosecdef = true
  ) THEN
    RAISE EXCEPTION '[043] VERIFICATION FAILED: committed_passport_immutables SECURITY DEFINER helper not found.';
  END IF;

  -- Confirm the helper returns all EIGHT immutable fields (widened signature).
  SELECT pg_get_function_result(p.oid)
    INTO v_helper_rettypes
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'committed_passport_immutables';

  IF v_helper_rettypes IS NULL
     OR v_helper_rettypes NOT LIKE '%status%'
     OR v_helper_rettypes NOT LIKE '%completed_at%'
     OR v_helper_rettypes NOT LIKE '%warning_sent_at%'
     OR v_helper_rettypes NOT LIKE '%reward_claimed%' THEN
    RAISE EXCEPTION '[043] VERIFICATION FAILED: committed_passport_immutables helper missing widened fields. Got: %', v_helper_rettypes;
  END IF;

  RAISE NOTICE '[043] OK: passports_update_own now pins all 8 immutable fields (user_id, corridor_id, activated_at, expires_at, status, completed_at, warning_sent_at, reward_claimed). Recursion-safe helper widened. No anon/public UPDATE policies on passports.';
END;
$$;
