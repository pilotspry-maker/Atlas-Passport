# Atlas Passport — RLS Regression Suite

Automated regression tests for Row-Level Security policies. These tests run
locally before every commit (via pre-commit hook) and in CI on every PR to `main`.

---

## What it tests

| File | Assertions | Category |
|---|---|---|
| `rls-reg-01-protected-fields.test.ts` | 7 | `profiles.is_admin` column guard, referral_code immutability, cross-user PATCH |
| `rls-reg-02-passport-data.test.ts` | 13 | Passport ownership, inactive corridor block, IDOR prevention, SELECT isolation |
| `rls-reg-03-reward-integrity.test.ts` | 6 | Reward claimed immutability, redemption_code access, player INSERT block |
| `rls-reg-04-policy-inventory.test.ts` | 8 | Policy existence by name, RLS enabled on all tables, WITH CHECK expression guards |
| **Total** | **34** | |

---

## Policies covered

| Policy | Migration | Tests |
|---|---|---|
| `profiles_select_own` | 004 | REG-1f |
| `profiles_update_own` | 005 | REG-1a, REG-1b, REG-1b (ground truth), REG-1c, REG-4c |
| `passports_select_own` | 004 | REG-2a, REG-2k |
| `passports_insert_own` | 007 | REG-2b, REG-2c, REG-2c (ground truth), REG-2d, REG-4e |
| `check_ins_select_own` | 004 | REG-2g, REG-2l |
| `check_ins_insert_own` | 005 | REG-2h, REG-2i, REG-2j, REG-4d |
| `rewards_select_own` | 004 | REG-3a, REG-3b |
| `corridors_select_active` | 004 | REG-2m |
| `prevent_reward_unclaim` trigger | 004 | REG-3c, REG-3d |
| Policy inventory (all) | 004–007 | REG-4a, REG-4b, REG-4f, REG-4g, REG-4h |

---

## Running locally

### Prerequisites

- Docker running
- `supabase` CLI ≥ 2.78.1 installed
- Migrations 004–008 applied (run `supabase db reset` to apply from scratch)
- Node 18+ and `npm install --legacy-peer-deps` completed

### Quick run (local Supabase)

```bash
# Starts Docker + Supabase, resets DB, runs regression suite
npm run test:rls-local
```

### Run both suites (exploit + regression)

```bash
npm run test:rls-local:all
# equivalent to: bash scripts/test-rls-local.sh --all
```

### Manual run against local Supabase

```bash
supabase start
supabase db reset   # applies all migrations from scratch

export SUPABASE_URL=http://127.0.0.1:54321
export SUPABASE_ANON_KEY=$(supabase status | grep "anon key" | awk '{print $NF}')
export SUPABASE_SERVICE_ROLE_KEY=$(supabase status | grep "service_role key" | awk '{print $NF}')

npm run test:rls-regression
```

### Watch mode (for active development)

```bash
npm run test:rls-regression:watch
```

### Run against production (read-only probes only — careful)

```bash
npm run test:rls-local -- --live
# You will be asked to confirm before proceeding
```

---

## Pre-commit hook

The pre-commit hook automatically runs the regression suite when any of these
files are staged:

- `supabase/migrations/*.sql`
- `tests/rls/**`
- `vitest.regression.config.ts`

### Install the hook

The `prepare` script in `package.json` installs it automatically when you run
`npm install`. To install manually:

```bash
cp scripts/pre-commit-rls.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### Skip for emergency commits

```bash
git commit --no-verify -m "hotfix: ..."
```

Use sparingly. CI will still enforce the tests on your PR.

---

## CI integration

The regression suite runs as a separate GitHub Actions workflow:
`.github/workflows/rls-regression.yml`

### Pipeline order

```
lint-build-size          (ci.yml)
       │
       ▼
rls-tests                (ci.yml — pytest integration tests)
       │
       ▼
rls-exploit-tests        (rls-exploit-tests.yml — 24 assertions, gates on exploit suite)
       │
       ▼
rls-regression-tests     (rls-regression.yml — 34 assertions, gates on regression suite)
```

Each step must pass before the next runs. If the exploit suite fails (indicating
migrations are not applied), the regression tests also fail at fixture seeding —
both point to the same root cause.

### Required GitHub secrets

All three secrets are already registered in the repo:

| Secret | Used for |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Anon key for authenticated player operations |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role for reg-04 policy inventory queries |

### Adding the regression job as a required status check

After the first successful CI run:

1. Go to [Branch protection settings](https://github.com/pilotspry-maker/Atlas-Passport/settings/branches)
2. Edit the `main` branch rule
3. Under **Require status checks to pass before merging**, add:
   - `RLS Regression Tests (reg-01 → reg-04)`
4. Save

---

## Extending the suite

### Adding a new regression test

1. Open the appropriate test file (reg-01 through reg-04) or create `rls-reg-05-*.test.ts`
2. Add your `it()` block following the existing REG-Nx naming convention
3. Update `MIN_TESTS` in `rls-regression.yml` (line: `MIN_TESTS: '28'`) to the new total
4. Run `npm run test:rls-regression` to verify locally before committing

### Fixture namespace rules

All regression fixtures use the `cccc` UUID prefix. Never use UUIDs from the
exploit suite (`aaaaaaaa`–`eeeeeeee`) in regression tests — they are separate
fixture namespaces to prevent cross-suite interference.

Note: the original `rrrrrrr` prefix was invalid hex (PostgreSQL UUID type requires
0-9 and a-f only). Replaced with `cccc` to match the CI workflow seeding and
avoid "invalid input syntax for type uuid" errors.

---

## Fixture reference

| Name | UUID |
|---|---|
| `CORRIDOR_ACTIVE_ID` | `cccc0001-0000-0000-0000-000000000001` |
| `CORRIDOR_INACTIVE_ID` | `cccc0001-0000-0000-0000-000000000002` |
| `NODE_ID` | `cccc0002-0000-0000-0000-000000000001` |
| `PASSPORT_ACTIVE_ID` | `cccc0003-0000-0000-0000-000000000001` (player_one) |
| `PASSPORT_COMPLETE_ID` | `cccc0003-0000-0000-0000-000000000002` (player_two) |
| `PASSPORT_OTHER_ID` | `cccc0003-0000-0000-0000-000000000003` (player_two, active — for IDOR tests) |
| `CHECKIN_SEED_ID` | `cccc0004-0000-0000-0000-000000000001` |
| `REWARD_ID` | `cccc0005-0000-0000-0000-000000000001` |
| `PLAYER_ONE_EMAIL` | `reg_player_one@test.atlasci.com` |
| `PLAYER_TWO_EMAIL` | `reg_player_two@test.atlasci.com` |
