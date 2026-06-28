# Atlas Passport Operations Runbook

Operational procedures for Atlas Passport. Per-topic runbooks live under
`docs/runbooks/`; this file holds launch-critical, cross-cutting procedures.

## Service Role Key Rotation

The `SUPABASE_SERVICE_ROLE_KEY` must be the legacy JWT format (a token that
begins with `eyJ`). The newer opaque format (a token that begins with
`sb_secret_`) is NOT resolved to the `service_role` Postgres role by PostgREST,
so every server-side call that bypasses RLS returns 401 with a `42501`
("permission denied for function") body. Symptoms: CI seed-fixture jobs fail,
the corridor worker cannot claim jobs, and admin API routes cannot write.

### When to rotate

- The current key is in `sb_secret_…` form and PostgREST rejects it.
- A key is suspected leaked.
- Routine rotation per security policy.

### Where to rotate (four locations)

Generate the legacy JWT `service_role` key in the Supabase Dashboard first:
Project `gaavynmmysdhovpatzlp` -> Project Settings -> API -> `service_role`
secret (JWT). Then set that same value in all four places below. The value is
identical everywhere; only the storage location differs.

1. Vercel project `atlas-passport` (org `ramon-spry`), Environment Variables,
   scope Production. Set `SUPABASE_SERVICE_ROLE_KEY`.
2. Vercel project `corridor-platform` (org `ramon-spry`), Environment
   Variables, scope Production. Set `SUPABASE_SERVICE_ROLE_KEY`.
3. GitHub repository secret on `pilotspry-maker/Atlas-Passport`:
   Settings -> Secrets and variables -> Actions -> `SUPABASE_SERVICE_ROLE_KEY`.
4. `pilotspry-maker/corridor-platform` has no GitHub Actions secrets. Skip.

### After rotating

1. Redeploy both Vercel projects so the new env value is picked up (a new
   deploy, or redeploy the latest, depending on project settings).
2. Re-run CI on the open PR by pushing a commit or re-running the workflow.
3. Verify the live REST surface with `scripts/verify-key-rotation.sh`
   (see that script for required env vars). Expected: 200 on `corridors`,
   `public.claim_jobs`, and `verify_service_role_permissions`.

### Notes

- The env var NAME is `SUPABASE_SERVICE_ROLE_KEY` everywhere. Do not introduce
  variants such as `SUPABASE_SECRET_KEY`.
- There is exactly one place in the Atlas-Passport code that constructs the
  service-role client: `src/lib/supabase/admin.ts`. The corridor-platform
  equivalent is `src/shared/db/server.ts` (`serviceClient()`).
- Never commit a key value to the repo. `.env.example` documents the variable
  with a placeholder only.
