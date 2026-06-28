/**
 * tests/rls/regression/rls-reg-04-policy-inventory.test.ts
 *
 * ═══════════════════════════════════════════════════════════════════
 * REGRESSION CATEGORY 4 — Policy Inventory & Structure Validation
 * ═══════════════════════════════════════════════════════════════════
 *
 * Validates the policy inventory via service role reads on pg_policies
 * and pg_class. These tests catch silent deletions and structural
 * regressions that behavioral tests would miss:
 *
 *   REG-4a: All required policies exist by name
 *   REG-4b: RLS is enabled on all private tables
 *   REG-4c: profiles_update_own WITH CHECK contains is_admin guard
 *   REG-4d: check_ins_insert_own WITH CHECK contains passport ownership EXISTS
 *   REG-4e: passports_insert_own WITH CHECK contains is_active corridor guard
 *   REG-4f: No unexpected public-access policies on private tables
 *   REG-4g: check_ins_player_view exists (migration 007 sentinel)
 *   REG-4h: create_test_users RPC exists (migration 008 sentinel)
 *
 * These tests run entirely via service role — no auth flow required.
 * They supplement the behavioral tests by catching structural gaps
 * before they can be exercised by real traffic.
 * ═══════════════════════════════════════════════════════════════════
 */

import { describe, it, expect } from "vitest";
import {
  SUPABASE_URL,
  serviceHeaders,
  REST,
} from "./regression.client.js";

// ─── Policy query helpers ─────────────────────────────────────────────────────
//
// pg_policies and pg_class live in pg_catalog, not the public schema, so
// PostgREST cannot serve them directly (GET /rest/v1/pg_policies → PGRST205).
// Migration 030 creates two SECURITY DEFINER functions that expose this data
// via the standard /rest/v1/rpc/* path (service-role only).
//
// Both helpers return null when the RPC is not yet available (migration 030
// not applied). Tests that depend on them skip gracefully in that case.

interface PolicyRow {
  tablename: string;
  policyname: string;
  cmd: string;
  permissive: string;
  roles: string[];
  qual: string | null;
  with_check: string | null;
}

async function fetchPolicies(): Promise<PolicyRow[] | null> {
  const res = await fetch(`${REST}/rpc/get_public_rls_policies`, {
    method: "POST",
    headers: { ...serviceHeaders(), "Content-Type": "application/json" },
    body: "{}",
  });
  if (res.status === 404) {
    console.warn("  [REG-4] get_public_rls_policies not available — migration 030 not applied; skipping");
    return null;
  }
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`get_public_rls_policies failed (${res.status}): ${text}`);
  }
  return res.json() as Promise<PolicyRow[]>;
}

interface TableRLS {
  relname: string;
  relrowsecurity: boolean;
}

async function fetchRLSStatus(): Promise<TableRLS[] | null> {
  const res = await fetch(`${REST}/rpc/get_public_rls_status`, {
    method: "POST",
    headers: { ...serviceHeaders(), "Content-Type": "application/json" },
    body: "{}",
  });
  if (res.status === 404) {
    console.warn("  [REG-4b] get_public_rls_status not available — migration 030 not applied; skipping");
    return null;
  }
  if (!res.ok) throw new Error(`get_public_rls_status failed (${res.status})`);
  return res.json() as Promise<TableRLS[]>;
}

// ─────────────────────────────────────────────────────────────────────────────
describe("REG-4 Policy inventory and structural validation", () => {

  let allPolicies: PolicyRow[] | null = null;

  // Fetch policies once, shared across all tests in this suite
  it("REG-4 setup: can query pg_policies via service role", async () => {
    allPolicies = await fetchPolicies();
    if (allPolicies === null) {
      console.warn("  [REG-4 setup] SKIP — migration 030 (get_public_rls_policies) not applied");
      return;
    }
    expect(
      allPolicies,
      "get_public_rls_policies returned no rows. Ensure service role key is correct and migrations 004–007 are applied."
    ).toBeDefined();
    // Cache for downstream tests
    (globalThis as Record<string, unknown>).__reg4_policies__ = allPolicies;
  });

  // ── REG-4a: All required policies exist ──────────────────────────────────────
  it("REG-4a: all required RLS policies are present by name", async () => {
    const cached = (globalThis as Record<string, unknown>).__reg4_policies__ as PolicyRow[] | undefined;
    const policies = cached ?? await fetchPolicies();
    if (policies === null) {
      console.warn("  [REG-4a] SKIP — migration 030 not applied");
      return;
    }

    const REQUIRED: Array<{ table: string; name: string; migration: string }> = [
      { table: "profiles",   name: "profiles_select_own",       migration: "004" },
      { table: "profiles",   name: "profiles_update_own",       migration: "005" },
      { table: "passports",  name: "passports_select_own",      migration: "004" },
      { table: "passports",  name: "passports_insert_own",      migration: "007" },
      { table: "check_ins",  name: "check_ins_select_own",      migration: "004" },
      { table: "check_ins",  name: "check_ins_insert_own",      migration: "005" },
      { table: "rewards",    name: "rewards_select_own",        migration: "004" },
      { table: "corridors",  name: "corridors_select_active",   migration: "004" },
      { table: "nodes",      name: "nodes_select_active",       migration: "004" },
    ];

    const policyNames = new Set(policies.map((p) => p.policyname));
    const missing = REQUIRED.filter((r) => !policyNames.has(r.name));

    expect(
      missing,
      `Missing ${missing.length} required RLS polic${missing.length === 1 ? "y" : "ies"}:\n` +
      missing.map((m) => `  • ${m.name} (table: ${m.table}, migration: ${m.migration})`).join("\n") +
      "\nRun: SELECT policyname FROM pg_policies WHERE schemaname='public' ORDER BY policyname;"
    ).toHaveLength(0);
  });

  // ── REG-4b: RLS is enabled on all private tables ─────────────────────────────
  it("REG-4b: row-level security is enabled on all private tables", async () => {
    const PRIVATE_TABLES = ["profiles", "passports", "check_ins", "rewards", "corridors", "nodes"];
    const tableStatus = await fetchRLSStatus();
    if (tableStatus === null) {
      console.warn("  [REG-4b] SKIP — migration 030 not applied");
      return;
    }
    const statusMap = new Map(tableStatus.map((t) => [t.relname, t.relrowsecurity]));

    const rlsDisabled = PRIVATE_TABLES.filter((t) => {
      const status = statusMap.get(t);
      return status !== undefined && status === false;
    });

    expect(
      rlsDisabled,
      `RLS is DISABLED on ${rlsDisabled.length} table(s): [${rlsDisabled.join(", ")}]. ` +
      `This means ALL policies on these tables are bypassed — every row is visible to every user. ` +
      `Fix: ${rlsDisabled.map((t) => `ALTER TABLE public.${t} ENABLE ROW LEVEL SECURITY;`).join(" ")}`
    ).toHaveLength(0);
  });

  // ── REG-4c: profiles_update_own WITH CHECK contains is_admin guard ────────────
  it("REG-4c: profiles_update_own WITH CHECK contains is_admin column freeze", async () => {
    const cached = (globalThis as Record<string, unknown>).__reg4_policies__ as PolicyRow[] | undefined;
    const policies = cached ?? await fetchPolicies();
    if (policies === null) { console.warn("  [REG-4c] SKIP — migration 030 not applied"); return; }
    const policy = policies.find((p) => p.policyname === "profiles_update_own");

    if (!policy) {
      throw new Error(
        "profiles_update_own policy not found. Migration 005 may not be applied. " +
        "This test cannot proceed — REG-4a should have caught this first."
      );
    }

    const withCheck = policy.with_check ?? "";
    expect(
      withCheck.toLowerCase(),
      `profiles_update_own WITH CHECK does not contain an is_admin guard.\n` +
      `Current WITH CHECK: ${withCheck || "(empty)"}\n` +
      `Expected to contain: is_admin = (SELECT is_admin FROM profiles WHERE id = auth.uid())\n` +
      `Without this guard, any authenticated user can escalate themselves to admin.`
    ).toContain("is_admin");
  });

  // ── REG-4d: check_ins_insert_own WITH CHECK contains passport ownership EXISTS ─
  it("REG-4d: check_ins_insert_own WITH CHECK contains passport ownership EXISTS clause", async () => {
    const cached = (globalThis as Record<string, unknown>).__reg4_policies__ as PolicyRow[] | undefined;
    const policies = cached ?? await fetchPolicies();
    if (policies === null) { console.warn("  [REG-4d] SKIP — migration 030 not applied"); return; }
    const policy = policies.find((p) => p.policyname === "check_ins_insert_own");

    if (!policy) {
      throw new Error("check_ins_insert_own policy not found — migration 005 may not be applied.");
    }

    const withCheck = policy.with_check ?? "";
    // Must contain both passport ownership check and status guard
    expect(
      withCheck.toLowerCase(),
      `check_ins_insert_own WITH CHECK is missing the passport ownership EXISTS clause.\n` +
      `Current WITH CHECK: ${withCheck || "(empty)"}\n` +
      `Expected to contain: EXISTS(...passports...user_id = auth.uid())\n` +
      `Without this, a player can INSERT check-ins against any passport (IDOR).`
    ).toContain("exists");

    expect(
      withCheck.toLowerCase(),
      `check_ins_insert_own WITH CHECK is missing the status='active' guard.\n` +
      `Current WITH CHECK: ${withCheck || "(empty)"}\n` +
      `Expected to contain: p.status = 'active'\n` +
      `Without this, players can add check-ins to completed passports.`
    ).toContain("active");
  });

  // ── REG-4e: passports_insert_own WITH CHECK contains is_active corridor guard ──
  it("REG-4e: passports_insert_own WITH CHECK contains active corridor EXISTS guard", async () => {
    const cached = (globalThis as Record<string, unknown>).__reg4_policies__ as PolicyRow[] | undefined;
    const policies = cached ?? await fetchPolicies();
    if (policies === null) { console.warn("  [REG-4e] SKIP — migration 030 not applied"); return; }
    const policy = policies.find((p) => p.policyname === "passports_insert_own");

    if (!policy) {
      throw new Error("passports_insert_own policy not found — migration 007 may not be applied.");
    }

    const withCheck = policy.with_check ?? "";
    expect(
      withCheck.toLowerCase(),
      `passports_insert_own WITH CHECK is missing the is_active corridor guard.\n` +
      `Current WITH CHECK: ${withCheck || "(empty)"}\n` +
      `Expected to contain: corridors...is_active = TRUE\n` +
      `Without this, players can create passports in deactivated corridors.`
    ).toContain("is_active");
  });

  // ── REG-4f: No permissive policies grant full table access to anon ────────────
  it("REG-4f: no permissive policies on private tables expose all rows to anon/public", async () => {
    const cached = (globalThis as Record<string, unknown>).__reg4_policies__ as PolicyRow[] | undefined;
    const policies = cached ?? await fetchPolicies();
    if (policies === null) { console.warn("  [REG-4f] SKIP — migration 030 not applied"); return; }
    const PRIVATE_TABLES = new Set(["profiles", "passports", "check_ins", "rewards"]);

    // A dangerous policy: permissive, targets public/anon role, and has no USING clause (or trivial TRUE)
    const dangerous = policies.filter((p) => {
      if (!PRIVATE_TABLES.has(p.tablename)) return false;
      if (p.permissive !== "PERMISSIVE") return false;
      const roles = p.roles ?? [];
      const isPublic = roles.includes("public") || roles.includes("anon") || roles.length === 0;
      const hasNoFilter = !p.qual || p.qual.trim() === "true";
      return isPublic && hasNoFilter;
    });

    expect(
      dangerous,
      `Found ${dangerous.length} dangerous polic${dangerous.length === 1 ? "y" : "ies"} ` +
      `granting unrestricted access to private tables:\n` +
      dangerous.map((p) => `  • ${p.tablename}.${p.policyname} (${p.cmd}, roles: ${JSON.stringify(p.roles)})`).join("\n")
    ).toHaveLength(0);
  });

  // ── REG-4g: check_ins_player_view exists (migration 007 sentinel) ────────────
  it("REG-4g: check_ins_player_view view exists (migration 007 SECURITY BARRIER sentinel)", async () => {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/check_ins_player_view?limit=1`,
      { headers: serviceHeaders() }
    );
    expect(
      res.status,
      `check_ins_player_view returned ${res.status}. ` +
      `Expected 200 — the view is created by migration 007. ` +
      `If 404, migration 007 (007_rls_column_guards.sql) has not been applied.`
    ).toBe(200);
  });

  // ── REG-4h: create_test_users RPC exists (migration 008 sentinel) ─────────────
  it("REG-4h: create_test_users RPC function exists (migration 008 sentinel)", async () => {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/create_test_users`,
      {
        method: "POST",
        headers: { ...serviceHeaders(), "Content-Type": "application/json" },
        body: "{}",
      }
    );
    // 200 = function exists and ran; 400 = function exists but args wrong — both OK
    // 404 = function does not exist — migration 008 not applied
    expect(
      res.status,
      `create_test_users RPC returned ${res.status}. ` +
      `Expected 200 or 400 — 404 means migration 008 (008_create_test_users_helper.sql) has not been applied. ` +
      `Apply migrations and re-run.`
    ).toSatisfy((s: number) => s !== 404);
  });
});
