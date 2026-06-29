# Changelog

All notable changes to Atlas Passport.

## [Unreleased]

### Added — Orion schema baseline + Travelers policy rescope (branch `chore/orion-schema-baseline-and-rescope`)

- **032 `orion_schema_baseline`**: Baselines the 5 live-only "Orion" tables into repo migration history so CI's bootstrap-from-zero (`supabase db push --local`) matches live: `traveler_profiles` (PK FK → `auth.users(id) ON DELETE CASCADE`, per CLAUDE.md §12), `passport_activations`, `mission_progress` (composite PK), `ap_events`, `referral_events`. Enables RLS on each and recreates the 12 existing policies **exactly as live** — `TO public` with bare `auth.uid()`, including the 2 `Service inserts *` policies (`WITH CHECK (true)`). `CREATE TABLE IF NOT EXISTS` + `DROP POLICY IF EXISTS` make it a no-op when applied to live. Ends with a verification DO block asserting all 5 tables exist with `rowsecurity = true`.
- **033 `rescope_legacy_travelers_policies`**: Drops + recreates the 11 `Travelers *` policies `TO authenticated` with `(select auth.uid())` (fixes the `auth_rls_initplan` advisor and the overly-broad `public` role). The 2 `Service inserts *` policies are left untouched (separate advisor findings). The legacy `check_ins."Travelers read own checkins"` policy is **dropped with no replacement**: repo `check_ins` is keyed on `user_id` (001) with no `traveler_id` column, so recreating on `traveler_id` would break the fresh-DB bootstrap; current ownership is covered by `check_ins_select_own`/`check_ins_insert_own`. Ends with a verification DO block that raises if any `Travelers%` policy still has `public` in its roles.

### DOWN path (032–033)

```sql
-- 033: restore prior TO public policies (or re-run 032's policy block).
-- 032: DROP the 5 Orion tables only on a non-live DB; on live they pre-exist and must NOT be dropped.
-- No data is destroyed by either migration when applied to live (both are no-ops there).
```

### Fixed — Task 1: Idempotent seed RPCs (PR #40)

- **020 `idempotent_seed_helpers`**: Redeploys `create_exploit_test_users`, `seed_ci_passports`, and `seed_regression_passports` with Clean-slate DELETE blocks + `ON CONFLICT (id) DO UPDATE` on `public.profiles` so the `handle_new_user` trigger not firing can never break the seed. Fixes migration-registry drift between live DB and repo.
- **021 `fix_seed_phone_collision`**: Changes `phone=''` to `phone=NULL` in the exploit user INSERT. The `auth.users_phone_key` UNIQUE index ignores NULL values, eliminating the `23505 duplicate key` failure on second seed runs.
- **022 `align_seed_ci_passports_uuids`**: Aligns `seed_ci_passports()` corridor UUID to match what `seed_ci_fixtures()` actually creates (`00000000-…0001` not `aaaaaaaa-…0001`). Makes the function self-sufficient (upserts corridor + node internally).
- **023**: Extends `create_exploit_test_users` Clean slate to delete `check_ins` and `passports` child rows before deleting `auth.users`, preventing 23503 FK violation when prior runs left residual rows.
- **024–028**: Additional clean-slate, NULL-fix, and regression alignment patches applied to bring the repo migration files in sync with live DB state.
- **029 `fix_regression_users_clean_slate`**: Applies the same child-row pre-cleanup to `create_regression_users` (missed in 023 which only covered exploit users). Deletes `check_ins` and `passports` for regression UUIDs before the `auth.users` DELETE. Fixes CI 23503 `check_ins_user_id_fkey` violation on repeat runs.
- **026**: Drops legacy `USING(true) PUBLIC` read policies on `corridors` and `nodes`; replaces with `anon` + `authenticated`-scoped policies (tighter but functionally equivalent for the app).
- **ci (exploit tests setup.ts)**: `rpc()` helper now uses `SERVICE_ROLE_KEY` instead of `ANON_KEY`. `confirm_test_users` and `seed_ci_fixtures` are SECURITY DEFINER / service_role-only; calling them with the anon key produced 42501. Also imports `SERVICE_ROLE_KEY` from `client.ts`.
- **ci (rls-regression.yml)**: Seeder adds Step 0 pre-cleanup that deletes residual `check_ins` and `passports` for regression UUIDs before calling `create_regression_users`, eliminating the 23503 FK violation on repeat runs without requiring DB migration.
- **ci**: RLS Security Tests seed step uses `service_role` key for locked RPCs; CI preflight accepts Supabase opaque `sb_secret_` key format (PR #27 merged to main).

- **030 `rls_audit_helpers`**: Creates `get_public_rls_policies()` and `get_public_rls_status()` SECURITY DEFINER functions (service_role only) that expose `pg_catalog.pg_policies` and `pg_catalog.pg_class` data via PostgREST RPC. Required by REG-4 regression tests — PostgREST cannot serve `pg_catalog` tables directly (PGRST205). Tests degrade gracefully (skip with warning) when migration 030 is not yet applied.

### Fixed — test fixes for exploit + regression suites (same PR)

- **exploit-05 fallback UPSERT**: Added `slug: "ci-inactive-test-corridor"` to the service-role fallback UPSERT in `exploit-05-inactive-corridor-insert.test.ts`. Migration 024 added `slug NOT NULL` to corridors; the fallback was written before that column existed.
- **exploit-03 test 3a**: Changed PATCH payload from `{ reward_claimed: false }` (false→false no-op) to `{ reward_claimed: true }` so the ground-truth check is meaningful. Accepts 204 in addition to 401/403 — PostgREST returns 204 (0 rows affected) when no UPDATE policy exists and RLS silently filters the row, not 403. Ground-truth assertion confirms `reward_claimed` was NOT set to true by the PATCH.
- **regression.setup.ts**: Removed non-existent columns `start_date`, `end_date` from corridors upsert; removed `location_name`, `latitude`, `longitude` from nodes upsert; removed `name` (should be `title`) and `claimed` from rewards upsert. Added correct columns: `slug`, `city`, `country` for corridors; `sequence` for nodes; `title` for rewards.
- **REG-1a**: Accepts 204 (PostgREST no-rows-affected) in addition to 401/403. Adds ground-truth check that `is_admin` was not set to true.
- **REG-1c**: Accepts 204 in addition to 401/403/404. Adds ground-truth check that p2's `full_name` was not modified.
- **REG-2m**: Changed from `anonHeaders()` to `authedHeaders(p1JWT)` and updated test name. `corridors_select_active` is `TO authenticated` (not public/anon) — anon reads correctly return `[]`. Test now verifies authenticated players can read active corridors, which is the intended behavior.
- **REG-3a**: Fixed `select=id,name,redemption_code` → `select=id,title,redemption_code`. Rewards table uses `title` not `name` (migration 004, which adds `name`, is PENDING).
- **REG-3f**: Fixed reward INSERT body: `name` → `title`, removed `claimed` (both are migration 004 columns not yet in the live DB). With correct column names, PostgREST now correctly returns 403 (no INSERT policy for authenticated).
- **REG-4 setup/4a–4f**: Replaced direct `pg_policies`/`pg_class` PostgREST queries (which fail with PGRST205) with calls to the new `get_public_rls_policies()` and `get_public_rls_status()` SECURITY DEFINER RPCs. All six tests skip gracefully with a console warning when migration 030 is not yet applied to the live DB.

### DOWN path

Migrations 020–030 are function replacements (`CREATE OR REPLACE`), index additions, and policy recreations. DOWN path:
```sql
-- Restore prior function bodies from repo tags or backup; drop the new indexes.
-- DROP FUNCTION IF EXISTS public.get_public_rls_policies();
-- DROP FUNCTION IF EXISTS public.get_public_rls_status();
-- No data is destroyed by any of these migrations.
```
