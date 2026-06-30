# Runbook: Atlas Command dashboard returns 401 / OFFLINE

**Symptom:** [atlas-passport.pplx.app](https://atlas-passport.pplx.app) header shows 🔴 **OFFLINE**, all six KPI tiles render as `—`, and the Corridors panel shows "Network unreachable. Retrying soon." The shell loads fine; only the data layer is broken.

**Telltale log line** (Supabase → API logs):

```
GET | 401 | https://<project-ref>.supabase.co/rest/v1/public_stats?select=*
```

Sibling endpoints (e.g. `/rest/v1/corridors?...&is_active=eq.true`) return 200 with the same key.

---

## Root cause (June 2026 incident)

`public.public_stats` is defined as `SELECT ... FROM get_public_stats() AS get_public_stats(...)`. The view is `SECURITY INVOKER`, so reading it executes `public.get_public_stats()` as the caller (`anon` / `authenticated`).

Migration **`034_tighten_service_policies_and_public_bucket.sql`** (section 6) revoked `EXECUTE` on `get_public_stats()` from `anon` and `authenticated` on the incorrect premise that the dashboard did not invoke the function. The next time the dashboard hit the view, PostgREST returned 401.

## Permanent fix

Migration **`041_restore_public_stats_anon_execute.sql`** re-grants `EXECUTE` to `anon` and `authenticated` and adds a `COMMENT ON FUNCTION` documenting that the grant is intentional. The function is `SECURITY DEFINER` and returns only aggregate counts (no PII, no row-level data), so the public-by-URL posture is preserved.

## Verify

```sql
-- 1) Both roles have EXECUTE
select rolname,
       has_function_privilege(rolname, 'public.get_public_stats()', 'EXECUTE') as can_exec
from pg_roles
where rolname in ('anon','authenticated','service_role')
order by rolname;
-- expect anon=true, authenticated=true, service_role=true

-- 2) View returns rows to anon
set role anon;
select * from public.public_stats limit 1;
reset role;
```

End-to-end:

```bash
ANON="<publishable_or_anon_key>"
curl -sS -w "\nHTTP %{http_code}\n" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  "https://<project-ref>.supabase.co/rest/v1/public_stats?select=*"
# expect HTTP 200 with a JSON array containing total_users, total_passports, ...
```

## Fast-path remediation if it regresses

Run, as a Supabase migration or via the SQL editor:

```sql
grant execute on function public.get_public_stats() to anon, authenticated;
```

Then hard-refresh the dashboard. The "↻ REFRESH" button alone will not clear cached `401` state in some browsers.

## Future hardening (deferred)

If we want to satisfy the original `*_security_definer_function_executable` advisor warnings without breaking the dashboard, switch the dashboard client from the view to an explicit RPC call (`/rest/v1/rpc/get_public_stats`) and keep the EXECUTE grant as the intentional, documented public surface — already justified inline via the `COMMENT ON FUNCTION` set in migration 041.

## References

- Migration that broke it: [`supabase/migrations/034_tighten_service_policies_and_public_bucket.sql`](../../supabase/migrations/034_tighten_service_policies_and_public_bucket.sql)
- Migration that fixed it: [`supabase/migrations/041_restore_public_stats_anon_execute.sql`](../../supabase/migrations/041_restore_public_stats_anon_execute.sql)
- PR #65: fix(rls): restore anon/authenticated EXECUTE on get_public_stats
