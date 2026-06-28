/**
 * vitest.rls.config.ts
 *
 * Isolated Vitest config for RLS exploit tests.
 * These tests run against the live Supabase project via PostgREST HTTP.
 *
 * Run locally:
 *   SUPABASE_URL=https://gaavynmmysdhovpatzlp.supabase.co \
 *   SUPABASE_ANON_KEY=sb_publishable_... \
 *   SUPABASE_SERVICE_ROLE_KEY=sb_secret_... \
 *   npx vitest run --config vitest.rls.config.ts
 *
 * In CI: env vars come from GitHub Actions secrets.
 * Config intentionally kept separate from the Next.js app test config
 * so these network tests never run during a unit-test pass.
 */

import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Each test file gets its own isolated context
    globals: true,
    environment: "node",

    // Test file pattern — only the exploit suite
    include: ["tests/rls/exploits/**/*.test.ts"],

    // Sequential execution — tests share a live Supabase DB; parallel runs
    // produce race conditions on fixture rows. Vitest 4 defaults to
    // fileParallelism: true, so this must be set explicitly. poolOptions
    // was dropped from Vitest 4's InlineConfig types; fileParallelism:false
    // forces all test files into a single worker.
    pool: "forks",
    fileParallelism: false,

    // 30-second timeout per test (network calls to Supabase)
    testTimeout: 30_000,
    hookTimeout: 30_000,

    // Detailed reporters so CI logs show full failure context
    // Note: Vitest 2.x uses 'reporters' (plural) not 'reporter'
    reporters: ["verbose"],

    // globalSetup seeds the test fixtures once before all tests run
    globalSetup: ["tests/rls/exploits/setup.ts"],
  },
});
