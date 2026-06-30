import { defineConfig } from 'vitest/config'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

/**
 * Fast, dependency-free unit tests for lib/* helpers.
 *
 * Distinct from the existing RLS suites:
 *   - vitest.rls.config.ts        — exploit harness, needs a live Supabase
 *   - vitest.regression.config.ts — RLS regression suite, needs a live Supabase
 *   - vitest.unit.config.ts       — pure unit tests, NO external services
 *
 * Run with: npm run test:unit
 */
export default defineConfig({
  test: {
    include: ['src/**/__tests__/**/*.test.ts'],
    environment: 'node',
    globals: false,
  },
  resolve: {
    alias: {
      '@': path.resolve(path.dirname(fileURLToPath(import.meta.url)), 'src'),
    },
  },
})
