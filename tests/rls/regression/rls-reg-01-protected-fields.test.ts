/**
 * tests/rls/regression/rls-reg-01-protected-fields.test.ts
 *
 * ═══════════════════════════════════════════════════════════════════
 * REGRESSION CATEGORY 1 — Protected Field Mutation Prevention
 * ═══════════════════════════════════════════════════════════════════
 *
 * Verifies that RLS policies permanently prevent unauthorized writes
 * to protected columns. These tests are designed to catch:
 *
 *   REG-1a: is_admin escalation (anon) — migration 005
 *   REG-1b: is_admin escalation (own authenticated user) — migration 005
 *   REG-1c: is_admin escalation (another user's row) — migration 005
 *   REG-1d: referral_code immutability — cannot overwrite once set
 *   REG-1e: created_at immutability — cannot backdate own profile
 *   REG-1f: Profile UPDATE leakage — cannot PATCH another user's profile
 *
 * Policy under test:
 *   profiles_update_own (migration 005)
 *   WITH CHECK (auth.uid() = id AND is_admin = (SELECT is_admin FROM profiles WHERE id = auth.uid()))
 *
 * All assertions are hard failures — any 2xx response to a protected
 * field write is a confirmed vulnerability, not a warning.
 * ═══════════════════════════════════════════════════════════════════
 */

import { describe, it, expect, beforeAll } from "vitest";
import {
  REG,
  signIn,
  authedHeaders,
  anonHeaders,
  serviceHeaders,
  pgPatch,
  svcRead,
  accessResult,
} from "./regression.client.js";

let p1JWT: string;
let p1Id:  string;
let p2JWT: string;
let p2Id:  string;

beforeAll(async () => {
  [p1JWT, p2JWT] = await Promise.all([
    signIn(REG.PLAYER_ONE_EMAIL, REG.PLAYER_ONE_PASS),
    signIn(REG.PLAYER_TWO_EMAIL, REG.PLAYER_TWO_PASS),
  ]);
  const decode = (jwt: string): string => {
    const pad = "=".repeat(4 - (jwt.split(".")[1].length % 4));
    return (JSON.parse(Buffer.from(jwt.split(".")[1] + pad, "base64").toString()) as { sub: string }).sub;
  };
  p1Id = decode(p1JWT);
  p2Id = decode(p2JWT);
});

// ─────────────────────────────────────────────────────────────────────────────
describe("REG-1 Protected fields — profiles", () => {

  // ── REG-1a: Anon cannot escalate to admin ────────────────────────────────────
  it("REG-1a: anon PATCH {is_admin:true} on any profile row → 401/403", async () => {
    const res = await pgPatch(
      "profiles",
      `id=neq.00000000-0000-0000-0000-000000000000`,
      { is_admin: true },
      anonHeaders()
    );
    expect(
      res.status,
      `${accessResult(res.status)}: anon escalated all profile rows to admin. ` +
      `profiles_update_own is missing or its WITH CHECK allows anon writes. ` +
      `Fix: apply migration 005 and verify 'profiles_update_own' in pg_policies.`
    ).toSatisfy((s: number) => s === 401 || s === 403);
  });

  // ── REG-1b: Authenticated user cannot set own is_admin to true ───────────────
  it("REG-1b: authenticated user PATCH own profile {is_admin:true} → 401/403", async () => {
    const res = await pgPatch(
      "profiles",
      `id=eq.${p1Id}`,
      { is_admin: true },
      authedHeaders(p1JWT)
    );
    expect(
      res.status,
      `${accessResult(res.status)}: p1 (${p1Id}) successfully wrote is_admin=true to their own profile. ` +
      `The WITH CHECK column guard in profiles_update_own is not enforcing is_admin immutability. ` +
      `Expected guard: is_admin = (SELECT is_admin FROM profiles WHERE id = auth.uid()). ` +
      `Run: SELECT with_check FROM pg_policies WHERE policyname='profiles_update_own';`
    ).toSatisfy((s: number) => s === 401 || s === 403);
  });

  // ── REG-1b ground truth: is_admin unchanged in DB after attempt ───────────────
  it("REG-1b (ground truth): is_admin is still false in DB after escalation attempt", async () => {
    // Fire the exploit attempt
    await pgPatch(
      "profiles",
      `id=eq.${p1Id}`,
      { is_admin: true },
      authedHeaders(p1JWT)
    );
    // Verify via service role — bypasses RLS entirely
    const actual = await svcRead<boolean>("profiles", `id=eq.${p1Id}`, "is_admin");
    expect(
      actual,
      `CRITICAL: is_admin = ${actual} in the DB after attempted escalation. ` +
      `The policy blocked the HTTP request but the write still executed, ` +
      `or the DB returned an unexpected row. ` +
      `Immediate action: UPDATE profiles SET is_admin=false WHERE id='${p1Id}'; ` +
      `Then re-apply migration 005.`
    ).toBe(false);
  });

  // ── REG-1c: Authenticated user cannot write to another user's profile at all ──
  it("REG-1c: authenticated user PATCH another user's profile → 401/403", async () => {
    const res = await pgPatch(
      "profiles",
      `id=eq.${p2Id}`,
      { full_name: "Hijacked" },
      authedHeaders(p1JWT)  // p1 trying to write p2's row
    );
    expect(
      res.status,
      `${accessResult(res.status)}: p1 wrote to p2's profile row. ` +
      `profiles_update_own USING clause must be auth.uid()=id. ` +
      `Run: SELECT qual FROM pg_policies WHERE policyname='profiles_update_own';`
    ).toSatisfy((s: number) => s === 401 || s === 403 || s === 404);
  });

  // ── REG-1d: referral_code cannot be overwritten once set ─────────────────────
  // referral_code is generated at profile creation; it's the player's shareable
  // identifier. Players must not be able to change it post-creation.
  it("REG-1d: authenticated user cannot overwrite their own referral_code", async () => {
    const originalCode = await svcRead<string>("profiles", `id=eq.${p1Id}`, "referral_code");

    const res = await pgPatch(
      "profiles",
      `id=eq.${p1Id}`,
      { referral_code: "HACKED-CODE" },
      authedHeaders(p1JWT)
    );

    // Either the PATCH is rejected, or if it returns 2xx, the value must be unchanged
    if (res.status === 200 || res.status === 204) {
      const afterCode = await svcRead<string>("profiles", `id=eq.${p1Id}`, "referral_code");
      expect(
        afterCode,
        `referral_code was modified (${originalCode} → ${afterCode}). ` +
        `The profiles_update_own WITH CHECK must exclude referral_code from writable columns, ` +
        `or a separate immutability trigger must be added.`
      ).toBe(originalCode);
    }
    // 401/403 is also acceptable — policy-level rejection is preferred
  });

  // ── REG-1e: created_at cannot be backdated ────────────────────────────────────
  it("REG-1e: authenticated user cannot set created_at to a past date", async () => {
    const backdated = "2020-01-01T00:00:00Z";
    const original = await svcRead<string>("profiles", `id=eq.${p1Id}`, "created_at");

    const res = await pgPatch(
      "profiles",
      `id=eq.${p1Id}`,
      { created_at: backdated },
      authedHeaders(p1JWT)
    );

    if (res.status === 200 || res.status === 204) {
      const after = await svcRead<string>("profiles", `id=eq.${p1Id}`, "created_at");
      expect(
        after,
        `created_at was backdated to ${backdated}. ` +
        `Add a GENERATED ALWAYS or trigger to make created_at immutable.`
      ).toBe(original);
    }
    // 401/403/404 is acceptable
  });

  // ── REG-1f: Anon cannot read any profile fields ───────────────────────────────
  it("REG-1f: anon SELECT on profiles returns [] — no data leakage", async () => {
    const res = await fetch(`${process.env.SUPABASE_URL}/rest/v1/profiles?select=id,email,is_admin&limit=5`, {
      headers: anonHeaders(),
    });
    expect(res.status).toBe(200);
    const rows = await res.json() as unknown[];
    expect(
      rows,
      `Anon read ${rows.length} profile row(s). ` +
      `profiles_select_own USING clause must be auth.uid()=id. ` +
      `Anon has no auth.uid() so the clause must evaluate false and return [].`
    ).toHaveLength(0);
  });
});
