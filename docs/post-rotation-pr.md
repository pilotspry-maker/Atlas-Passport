# Draft PR description: post-rotation verification

Use this as the body of the follow-up PR opened AFTER the
`SUPABASE_SERVICE_ROLE_KEY` is rotated to the legacy JWT form and PR #28 is
merged. It is a draft only; adjust SHAs and check results to reflect reality at
the time of opening.

---

## Summary

Follow-up to PR #28. The `SUPABASE_SERVICE_ROLE_KEY` has been rotated to the
legacy JWT (`eyJ…`) format in all four locations (see `docs/RUNBOOK.md`). This
PR re-runs CI on a green key and flips the remaining launch-readiness checklist
items that were blocked on the opaque-key 401.

## What changed

- No application code changes are required for the rotation itself; the key is
  an environment value, not source. This PR exists to (a) re-trigger CI against
  the rotated key and (b) record the verification evidence.
- If migration 019 (`verify_service_role_permissions`) was not yet applied to
  prod when PR #28 merged, apply it now so the diagnostic RPC is reachable.

## Verification

- [ ] CI green: Seed RLS Test Fixtures, Seed Regression Fixtures, RLS Security
      Tests all pass (these were red on PR #28 solely due to the opaque key).
- [ ] `scripts/verify-key-rotation.sh` run against prod returns ALL CHECKS
      PASSED:
      - [ ] `corridors select` -> 200
      - [ ] `public.claim_jobs rpc` -> 200
      - [ ] `verify_service_role_perms` -> 200 (requires migration 019 in prod)
- [ ] Migrations 019-024 confirmed applied to prod (project
      `gaavynmmysdhovpatzlp`). Confirm each via the Supabase SQL editor or the
      migration history.
- [ ] Corridor worker can claim jobs end to end (see open finding below).

## Open finding to resolve before relying on the worker

The corridor-platform worker constructs its Supabase client with
`db: { schema: "corridor" }` (`src/shared/db/server.ts`, `serviceClient()` and
`anonClient()`). As a result `sb.rpc("claim_jobs", ...)` is sent with a
`Content-Profile: corridor` header and resolves to `corridor.claim_jobs`, NOT
the `public.claim_jobs` wrapper that migration 024 added. For the worker to
function after rotation, one of the following must be true:

1. PostgREST is configured to expose the `corridor` schema (PGRST_DB_SCHEMAS /
   "Exposed schemas" includes `corridor`), in which case migration 024's public
   wrapper is not on the worker's path and the worker hits `corridor.claim_jobs`
   directly; or
2. The worker is changed so the `claim_jobs` call (and corridor-schema table
   access) goes through the `public` surface that migration 024 exposes.

Confirm which is intended and verify the exposed-schemas setting before launch.

## Post-merge action

- [ ] Tick the remaining launch checklist items in the tracker.
- [ ] Close PR #27 (superseded by #28 plus this follow-up).
