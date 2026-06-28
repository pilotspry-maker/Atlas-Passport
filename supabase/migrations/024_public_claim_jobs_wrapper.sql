-- Migration 024
-- Purpose:
--   Add public.claim_jobs(int) wrapper that delegates to corridor.claim_jobs
--   so workers calling /rest/v1/rpc/claim_jobs reach the actual function.
--   PostgREST only exposes the `public` schema by default; without this
--   wrapper the workers hit 404 (and currently 401 from the broken service
--   role key — once the key rotates, this wrapper is what unblocks them).
--
--   Note: public.verify_service_role_permissions() is owned by migration 019
--   which lands once PR #28 CI passes after the key rotation.
-- Idempotent: CREATE OR REPLACE FUNCTION; revoke/grant statements are no-ops on repeat.

create or replace function public.claim_jobs(p_limit integer default 10)
returns setof corridor.jobs
language sql
security definer
set search_path = 'corridor', 'public', 'pg_temp'
as $$
  select * from corridor.claim_jobs(p_limit);
$$;

revoke all on function public.claim_jobs(integer) from public;
revoke all on function public.claim_jobs(integer) from anon, authenticated;
grant execute on function public.claim_jobs(integer) to service_role;

comment on function public.claim_jobs(integer) is
  'Service-role-only PostgREST wrapper around corridor.claim_jobs. Workers must call /rest/v1/rpc/claim_jobs with a valid service_role key.';
