# Changelog

All notable changes to Atlas Passport.

## [Unreleased]

### Fixed — Task 1: Idempotent seed RPCs (PR #40)

- **020 `idempotent_seed_helpers`**: Redeploys `create_exploit_test_users`, `seed_ci_passports`, and `seed_regression_passports` with Clean-slate DELETE blocks + `ON CONFLICT (id) DO UPDATE` on `public.profiles` so the `handle_new_user` trigger not firing can never break the seed. Fixes migration-registry drift between live DB and repo.
- **021 `fix_seed_phone_collision`**: Changes `phone=''` to `phone=NULL` in the exploit user INSERT. The `auth.users_phone_key` UNIQUE index ignores NULL values, eliminating the `23505 duplicate key` failure on second seed runs.
- **022 `align_seed_ci_passports_uuids`**: Aligns `seed_ci_passports()` corridor UUID to match what `seed_ci_fixtures()` actually creates (`00000000-…0001` not `aaaaaaaa-…0001`). Makes the function self-sufficient (upserts corridor + node internally).
- **023–028**: Additional clean-slate, NULL-fix, and regression alignment patches applied to bring the repo migration files in sync with live DB state.
- **026**: Drops legacy `USING(true) PUBLIC` read policies on `corridors` and `nodes`; replaces with `anon` + `authenticated`-scoped policies (tighter but functionally equivalent for the app).
- **ci**: RLS Security Tests seed step now uses `service_role` key for locked RPCs; CI preflight accepts Supabase opaque `sb_secret_` key format (PR #27 merged to main).

### DOWN path

Migrations 020–028 are function replacements (`CREATE OR REPLACE`), index additions, and policy recreations. DOWN path:
```sql
-- Restore prior function bodies from repo tags or backup; drop the new indexes.
-- No data is destroyed by any of these migrations.
```
