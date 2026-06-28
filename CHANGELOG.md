# Changelog

All notable changes to Atlas Passport.

## [Unreleased]

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

### DOWN path

Migrations 020–029 are function replacements (`CREATE OR REPLACE`), index additions, and policy recreations. DOWN path:
```sql
-- Restore prior function bodies from repo tags or backup; drop the new indexes.
-- No data is destroyed by any of these migrations.
```
