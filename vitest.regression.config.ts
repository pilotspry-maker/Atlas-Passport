/**
 * vitest.regression.config.ts
 *
 * Isolated Vitest config for the RLS regression suite.
 * Runs independently of the Next.js app config and the exploit suite config.
 *
 * Usage — local:
 *   SUPABASE_URL=https://gaavynmmysdhovpatzlp.supabase.co \
 *   SUPABASE_ANON_KEY=<anon_key> \
 *   SUPABASE_SERVICE_ROLE_KEY=<service_role_key> \
 *   npm run test:rls-regression
 *
 * Usage — against local Supabase:
 *   supabase start
 *   SUPABASE_URL=http://127.0.0.1:54321 \
 *   SUPABASE_ANON_KEY=$(supabase status | grep anon | awk '{print $2}') \
 *   SUPABASE_SERVICE_ROLE_KEY=$(supabase status | grep service_role | awk '{print $2}') \
 *   npm run test:rls-regression
 *
 * In CI: env vars are injected via GitHub Actions secrets.
 *
 * The regression suite deliberately targets 4 test files covering:
 *   reg-01: protected field mutation (profiles.is_admin, etc.)
 *   reg-02: passport and check-in data integrity
 *   reg-03: reward immutability and access control
 *   reg-04: policy inventory and structural validation (service role)
 */

import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",

    // Only the regression suite — not the exploit suite
    include: ["tests/rls/regression/**/*.test.ts"],

    // Sequential execution — tests share live DB state; parallel creates
    // race conditions on fixture rows. Vitest 4 defaults to
    // fileParallelism: true, so this must be set explicitly. poolOptions
    // was dropped from Vitest 4's InlineConfig types; fileParallelism:false
    // forces all test files into a single worker.
    pool: "forks",
    fileParallelism: false,

    // Network timeout (Supabase PostgREST round-trip)
    testTimeout: 30_000,
    hookTimeout: 30_000,

    // Verbose so every it() pass/fail is visible in CI logs
    reporters: ["verbose"],

    // Seeds regression-specific fixture namespace before all tests
    globalSetup: ["tests/rls/regression/regression.setup.ts"],

    // Retry network-flaky tests once before marking as failed
    retry: 1,
  },
});
