-- Migration 035: fix infinite recursion in profiles_update_own WITH CHECK
--
-- Background
-- ----------
-- Migration 005 introduced a column guard on profiles_update_own to block
-- is_admin self-escalation. The guard re-reads the committed is_admin value
-- via a sub-SELECT against public.profiles inside the WITH CHECK clause.
-- Under the current Supabase Postgres stack (PG 17.6 + PostgREST), that
-- inline sub-SELECT triggers RLS re-entry on the same table during WITH CHECK
-- evaluation, raising 42P17 "infinite recursion detected in policy for
-- relation 'profiles'". The PATCH still fails (HTTP 500), but the contract
-- the RLS exploit suite asserts (401/403) is broken, and the security
-- guarantee depends on a crash rather than a properly enforced policy.
--
-- Reproduction (before this migration):
--   PATCH /rest/v1/profiles?id=eq.<own_id>  body: {"is_admin": true}
--   → HTTP 500 {"code":"42P17", "message":"infinite recursion detected
--      in policy for relation \"profiles\""}
--
-- Expected (after this migration):
--   → HTTP 403 {"code":"42501", "message":"new row violates row-level
--      security policy for table \"profiles\""}
--   is_admin column unchanged in DB.
--
-- Fix
-- ---
-- Replace the inline sub-SELECT with a SECURITY DEFINER helper. The helper
-- bypasses RLS on its own read (which is safe — it reads only the caller's
-- own row, keyed by auth.uid()) and the policy expression becomes a flat
-- equality check with no re-entry.
--
-- Same security guarantee as migration 005:
--   - USING (auth.uid() = id)               → only caller's row is updatable
--   - WITH CHECK is_admin = (committed val) → is_admin remains frozen
--
-- Blast radius
-- ------------
-- - DDL only. No data writes. No data backfill.
-- - public.profiles RLS contract unchanged: only the caller's own row is
--   updatable, is_admin remains frozen at its committed value, no other
--   column restrictions are added or removed.
-- - Helper public.current_user_is_admin() is SECURITY DEFINER but reads
--   only public.profiles filtered by auth.uid(). It can never return
--   another user's data. EXECUTE is granted to anon, authenticated,
--   service_role; PUBLIC is revoked.
-- - search_path is locked to (public, pg_temp) to prevent search_path
--   attacks on a SECURITY DEFINER function (Supabase advisor best practice).
--
-- Verification post-apply:
--   1) RLS exploit test exploit-01-admin-escalation.test.ts must pass:
--      - 1a: PATCH {is_admin:true} → 403
--      - 1b: SELECT is_admin via service role → false
--      - 1c: SELECT rewards as non-admin → empty
--   2) RLS regression test REG-1b and REG-1c must pass for both own-PATCH
--      and cross-user PATCH attempts on profiles.

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select is_admin from public.profiles where id = auth.uid()
$$;

comment on function public.current_user_is_admin() is
  'Returns the committed is_admin value for the calling auth.uid(). SECURITY DEFINER to avoid RLS re-entry when used inside profiles_update_own WITH CHECK. Safe: filter is auth.uid()-keyed, cannot return another user''s row.';

revoke all on function public.current_user_is_admin() from public;
revoke execute on function public.current_user_is_admin() from anon;
grant execute on function public.current_user_is_admin() to authenticated, service_role;
-- The function is only meaningful when called with a real auth.uid().
-- Anon has no JWT and would always read null. Tighten exposure to avoid
-- Supabase advisor 0028 (anon can execute SECURITY DEFINER function).

drop policy if exists profiles_update_own on public.profiles;

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id and is_admin = public.current_user_is_admin());
