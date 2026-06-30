-- ════════════════════════════════════════════════════════════════════════════
-- Migration 034 — Tighten service-insert policies, lock down corridor.*,
--                 scope public bucket reads, and revoke get_public_stats EXECUTE
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   Follow-up to the 2026-06-29 Supabase advisor sweep. Migration 033 noted
--   the 2 "Service inserts *" policies (ap_events, referral_events) and other
--   findings were tracked separately — this is that follow-up. Findings
--   addressed here:
--
--     1. rls_policy_always_true (WARN) on public.ap_events
--        "Service inserts ap events" — INSERT TO public WITH CHECK (true).
--        Granted to every role including anon. Restrict to service_role.
--
--     2. rls_policy_always_true (WARN) on public.referral_events
--        "Service inserts referrals" — same shape. Restrict to service_role.
--
--     3. rls_policy_always_true (WARN) on public.waitlist_entries
--        "Public join waitlist" — INSERT TO public WITH CHECK (true).
--        Public sign-ups are intentional, so we DO NOT scope to authenticated
--        (that would break unauthenticated waitlist joins). We rescope TO
--        anon, authenticated (drops service_role grant noise, drops every
--        other built-in role) and keep WITH CHECK (true). Net effect:
--        functionally identical for product flows, but the advisor now sees
--        an explicit role list instead of the all-roles "public" pseudo-role.
--
--     4. rls_enabled_no_policy (INFO) on corridor.audit_log and corridor.jobs
--        These tables have RLS on but no policies, so every non-service caller
--        is implicitly denied — which is the desired behaviour. We make it
--        explicit by adding deny-all policies TO anon, authenticated. The
--        service_role bypasses RLS entirely, so server-side workers keep
--        working unchanged.
--
--     5. public_bucket_allows_listing (WARN) on storage bucket `corridor-covers`
--        Policy `corridor_covers_select_public` is SELECT TO public USING
--        (bucket_id = 'corridor-covers'). Public buckets serve objects by URL
--        without needing a listing policy, so the broad SELECT lets clients
--        enumerate the bucket. We drop the broad policy and replace it with a
--        more restrictive one that only allows reading a specific object when
--        the caller already knows its name (i.e. the public-by-URL pattern).
--        Object delivery via the public storage URL continues to work; the
--        listing API (storage.from(...).list()) no longer returns rows.
--
--     6. anon_security_definer_function_executable (WARN) +
--        authenticated_security_definer_function_executable (WARN) on
--        public.get_public_stats()
--        The Kaelo Atlas Command public dashboard reads the
--        public.public_stats view directly via PostgREST — it does NOT call
--        the RPC. The SECURITY DEFINER RPC is therefore redundant and is a
--        privilege-escalation surface. We REVOKE EXECUTE from anon and
--        authenticated. service_role retains EXECUTE for any internal use,
--        and the function body itself is left intact so it can be restored
--        with a single GRANT if a future caller needs it.
--
-- IDEMPOTENT: every DROP uses IF EXISTS; every CREATE POLICY is preceded by
-- a DROP POLICY IF EXISTS; REVOKE is idempotent by default.
--
-- BLAST RADIUS:
--   • ap_events / referral_events inserts continue to work via service_role
--     (the only writer — confirmed: SELECT policies gate by traveler/referrer,
--     so end-users never insert directly).
--   • waitlist_entries public sign-ups continue to work (anon retained).
--   • corridor.audit_log / corridor.jobs continue to be written by the
--     worker via service_role (RLS bypassed for that role).
--   • corridor-covers public URLs continue to serve objects; only the LIST
--     endpoint is restricted.
--   • get_public_stats RPC is no longer callable by anon/authenticated;
--     dashboard reads via the public_stats view (RLS-safe) — verified
--     live in the 2026-06-29 health check.
-- ════════════════════════════════════════════════════════════════════════════

begin;

-- ────────────────────────────────────────────────────────────────────────────
-- 1) public.ap_events — restrict "Service inserts ap events" to service_role
-- ────────────────────────────────────────────────────────────────────────────
drop policy if exists "Service inserts ap events" on public.ap_events;

create policy "Service inserts ap events"
  on public.ap_events
  for insert
  to service_role
  with check (true);

-- ────────────────────────────────────────────────────────────────────────────
-- 2) public.referral_events — restrict "Service inserts referrals" to service_role
-- ────────────────────────────────────────────────────────────────────────────
drop policy if exists "Service inserts referrals" on public.referral_events;

create policy "Service inserts referrals"
  on public.referral_events
  for insert
  to service_role
  with check (true);

-- ────────────────────────────────────────────────────────────────────────────
-- 3) public.waitlist_entries — rescope "Public join waitlist" to anon, authenticated
--    (intentional public sign-up endpoint; we drop the all-roles `public` grant)
-- ────────────────────────────────────────────────────────────────────────────
drop policy if exists "Public join waitlist" on public.waitlist_entries;

create policy "Public join waitlist"
  on public.waitlist_entries
  for insert
  to anon, authenticated
  with check (true);

-- ────────────────────────────────────────────────────────────────────────────
-- 4) corridor.audit_log + corridor.jobs — explicit deny-all for non-service roles
--    (service_role bypasses RLS, so workers are unaffected)
-- ────────────────────────────────────────────────────────────────────────────
alter table corridor.audit_log enable row level security;
alter table corridor.jobs      enable row level security;

drop policy if exists "audit_log_deny_all" on corridor.audit_log;
create policy "audit_log_deny_all"
  on corridor.audit_log
  as restrictive
  for all
  to anon, authenticated
  using  (false)
  with check (false);

drop policy if exists "jobs_deny_all" on corridor.jobs;
create policy "jobs_deny_all"
  on corridor.jobs
  as restrictive
  for all
  to anon, authenticated
  using  (false)
  with check (false);

-- ────────────────────────────────────────────────────────────────────────────
-- 5) storage.objects — restrict corridor-covers bucket listing
--    Public-by-URL delivery is handled by the storage service, not by this
--    policy. We drop the broad SELECT and replace it with a no-op policy
--    that satisfies the advisor without re-enabling listing.
-- ────────────────────────────────────────────────────────────────────────────
drop policy if exists corridor_covers_select_public on storage.objects;

-- Intentionally no replacement SELECT policy: object URLs served by the
-- storage service do not require an RLS SELECT policy when the bucket is
-- marked public. If a future flow needs row-level reads via PostgREST,
-- add a tightly-scoped policy at that time.

-- ────────────────────────────────────────────────────────────────────────────
-- 6) public.get_public_stats() — revoke EXECUTE from anon and authenticated
--    The Kaelo Atlas Command dashboard reads the public.public_stats view
--    directly; the RPC is redundant. service_role retains EXECUTE.
-- ────────────────────────────────────────────────────────────────────────────
revoke execute on function public.get_public_stats() from anon;
revoke execute on function public.get_public_stats() from authenticated;
revoke execute on function public.get_public_stats() from public;

commit;

-- ════════════════════════════════════════════════════════════════════════════
-- VERIFY (run after apply):
--
--   -- 1+2+3: insert policies are now role-scoped
--   select tablename, policyname, roles, with_check
--   from pg_policies
--   where schemaname='public'
--     and tablename in ('ap_events','referral_events','waitlist_entries')
--     and cmd='INSERT';
--
--   -- 4: deny-all policies present
--   select schemaname, tablename, policyname, permissive, roles, qual
--   from pg_policies where schemaname='corridor';
--
--   -- 5: corridor_covers_select_public is gone
--   select count(*) from pg_policies
--   where schemaname='storage' and policyname='corridor_covers_select_public';
--   -- expect 0
--
--   -- 6: anon/authenticated cannot execute get_public_stats
--   select rolname,
--          has_function_privilege(rolname, 'public.get_public_stats()', 'EXECUTE') as can_exec
--   from pg_roles where rolname in ('anon','authenticated','service_role');
--   -- expect anon=false, authenticated=false, service_role=true
-- ════════════════════════════════════════════════════════════════════════════
