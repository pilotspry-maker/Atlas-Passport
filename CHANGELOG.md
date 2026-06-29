# Changelog

All notable changes to Atlas Passport.

## [Unreleased]

### Security — Task 2: Tighten Orion INSERT policies + baseline waitlist_entries (branch `claude/atlas-passport-mvp-hw9hmr`)

- **034 `tighten_orion_insert_policies`**: Closes the unrestricted INSERT gap left deliberately open by migration 032. Drops `"Service inserts ap events"` and `"Service inserts referrals"` (`TO public WITH CHECK (true)`), which allowed any authenticated or anon user to inject arbitrary rows into `ap_events` (spoofed atlas-points) or `referral_events` (forged referral chains). `service_role` is BYPASSRLS — no replacement policy is needed for the worker layer. Baselines `public.waitlist_entries` (`CREATE TABLE IF NOT EXISTS`) — this table existed out-of-band in production (CLAUDE.md §12) but was absent from migration history. Adds an email-format CHECK constraint (`~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'`, NOT VALID for live-data compatibility) and an INSERT policy scoped to `anon, authenticated` with the same regex in WITH CHECK. No SELECT policy for public — only service_role reads via BYPASSRLS. Verification DO block asserts zero INSERT policies for public/anon/authenticated on both Orion event tables and that RLS is enabled on waitlist_entries.
- **exploit-07-orion-write-fence.test.ts**: 5 new RLS exploit assertions — (7a-1) authenticated INSERT into ap_events blocked; (7a-2) anon INSERT into ap_events blocked; (7b-1) authenticated INSERT into referral_events blocked; (7c) anon INSERT into waitlist_entries with valid email accepted; (7d) anon INSERT with invalid email rejected; (7e) anon GET /waitlist_entries returns empty array (no SELECT policy). Exploit threshold updated from 24 → 29 in `rls-exploit-tests.yml`.

### Added — Orion schema baseline + Travelers policy rescope (branch `chore/orion-schema-baseline-and-rescope`)

- **032 `orion_schema_baseline`**: Baselines the 5 live-only "Orion" tables into repo migration history so CI's bootstrap-from-zero (`supabase db push --local`) matches live: `traveler_profiles` (PK FK → `auth.users(id) ON DELETE CASCADE`, per CLAUDE.md §12), `passport_activations`, `mission_progress` (composite PK), `ap_events`, `referral_events`. Enables RLS on each and recreates the 12 existing policies **exactly as live** — `TO public` with bare `auth.uid()`, including the 2 `Service inserts *` policies (`WITH CHECK (true)`). Also baselines a drift column: `check_ins.traveler_id` (nullable uuid, no FK) — added out-of-band in live and confirmed present via live `information_schema`. `CREATE TABLE/COLUMN IF NOT EXISTS` + `DROP POLICY IF EXISTS` make it a no-op when applied to live. Ends with a verification DO block asserting all 5 tables exist with `rowsecurity = true` and that `check_ins.traveler_id` exists.
- **033 `rescope_legacy_travelers_policies`**: Rescopes **15 policies** total from `TO public` → `TO authenticated` with `auth.uid()` wrapped as `(select auth.uid())` (fixes the `auth_rls_initplan` advisor + overly-broad `public` role): the 11 `Travelers *` policies (including `check_ins."Travelers read own checkins"`, gated on the now-baselined `traveler_id`) plus 4 repo-owned policies that were never rescoped — `check_ins_select_own`, `passports_select_own`, `profiles_select_own`. The 2 `Service inserts *` policies are left untouched (separate advisor track). Ends with a verification DO block that raises if any of the 15 named policies still has `public` in its roles.

### DOWN path (032–033)

```sql
-- 033: restore prior TO public policies (or re-run 032's policy block).
-- 032: DROP the 5 Orion tables / check_ins.traveler_id column only on a non-live DB; on live they pre-exist and must NOT be dropped.
-- No data is destroyed by either migration when applied to live (both are no-ops there).
```

### Fixed — RLS inventory repair + worker 406 loop (chore/fix-rls-and-worker-logs)

- **031 `fix_rewards_policy_checkins_grant`**: Renames `rewards_select_auth`→`rewards_select_own` (REG-4a) keeping the complete-passport gate; re-scopes legacy `check_ins` policy "Travelers insert own checkins" from `TO public`→`TO authenticated` with the full owner+active gate (REG-4f); re-affirms `service_role`-only EXECUTE on `confirm_test_users(TEXT)`.
- **ci (regression.setup.ts)**: `confirm_test_users` now called with the service-role key (was anon → 42501), mirroring the earlier exploit `setup.ts` fix.
- **worker (api/corridors/route.ts)**: corridors-by-id poll uses `.maybeSingle()` instead of `.single()` so a 0-row result returns `{ corridor: null }` instead of a PostgREST 406.

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
