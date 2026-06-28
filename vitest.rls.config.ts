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
