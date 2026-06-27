/**
 * vitest.unit.config.ts
 *
 * Vitest config for pure unit tests that don't need network or a live Supabase.
 * Currently scoped to src/lib/**\/*.test.ts.
 *
 * Run:
 *   npx vitest run --config vitest.unit.config.ts
 */

import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    include: ["src/lib/**/*.test.ts"],
  },
});
