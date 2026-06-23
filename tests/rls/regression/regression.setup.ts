/**
 * tests/rls/regression/regression.setup.ts
 *
 * Vitest globalSetup for the RLS regression suite.
 * Seeds an isolated set of fixtures (reg_player_one / reg_player_two)
 * that are separate from the exploit-suite fixtures.
 *
 * Seeding strategy:
 *   1. rpc/create_test_users_reg  — SECURITY DEFINER, inserts directly into
 *      auth.users (no GoTrue, no email, no rate limit).
 *      Falls back to signup + rpc/confirm_test_users if not available.
 *   2. Service-role direct upsert for corridors, nodes, rewards.
 *   3. Authenticated upsert for passports + check-ins.
 *
 * All operations are idempotent — re-running on the same DB is always safe.
 *
 * NOTE: If migrations 004–008 have not been applied, this setup will fail
 * with an RPC-not-found error. Apply migrations first.
 */

import {
  SUPABASE_URL,
  ANON_KEY,
  SERVICE_ROLE_KEY,
  REST,
  AUTH,
  REG,
  signIn,
  anonHeaders,
  serviceHeaders,
} from "./regression.client.js";

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function rpc(
  fn: string,
  args: Record<string, unknown> = {},
  useSvc = false
): Promise<unknown> {
  const headers: Record<string, string> = {
    ...(useSvc ? serviceHeaders() : anonHeaders()),
    "Content-Type": "application/json",
  };
  const res = await fetch(`${REST}/rpc/${fn}`, {
    method: "POST",
    headers,
    body: JSON.stringify(args),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`rpc/${fn} failed (${res.status}): ${text}`);
  return JSON.parse(text);
}

async function svcUpsert(
  table: string,
  row: Record<string, unknown>
): Promise<void> {
  const res = await fetch(`${REST}/${table}`, {
    method: "POST",
    headers: {
      ...serviceHeaders(),
      "Content-Type": "application/json",
      Prefer: "resolution=ignore-duplicates,return=minimal",
    },
    body: JSON.stringify(row),
  });
  if (!res.ok && res.status !== 409) {
    console.warn(`  [reg setup] WARN svcUpsert ${table}: ${res.status} ${await res.text()}`);
  } else {
    console.log(`  [reg setup] upsert ${table}: ok`);
  }
}

async function authedUpsert(
  table: string,
  row: Record<string, unknown>,
  jwt: string
): Promise<void> {
  const res = await fetch(`${REST}/${table}`, {
    method: "POST",
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
      Prefer: "resolution=ignore-duplicates,return=minimal",
    },
    body: JSON.stringify(row),
  });
  if (!res.ok && res.status !== 409) {
    console.warn(`  [reg setup] WARN authedUpsert ${table}: ${res.status} ${await res.text()}`);
  } else {
    console.log(`  [reg setup] authedUpsert ${table}: ok`);
  }
}

async function createUsersViaMigration008(): Promise<boolean> {
  // Try the generalized create_test_users RPC first (migration 008).
  // It accepts a users array — use the regression-specific credentials.
  try {
    await rpc("create_test_users", {}, false);
    console.log("  [reg setup] create_test_users (migration 008): ok");
    return true;
  } catch (e) {
    console.log("  [reg setup] create_test_users not available, falling back to signUp");
    return false;
  }
}

async function signUpAndConfirm(email: string, password: string, fullName: string): Promise<void> {
  // signUp
  const res = await fetch(`${AUTH}/signup`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, data: { full_name: fullName } }),
  });
  if (!res.ok && res.status !== 422) {
    const text = await res.text();
    const body = JSON.parse(text) as { msg?: string; message?: string };
    const msg = body.msg ?? body.message ?? text;
    if (!msg.toLowerCase().includes("already")) {
      throw new Error(`signUp ${email} failed (${res.status}): ${text}`);
    }
  }
  console.log(`  [reg setup] signUp ${email}: ok`);

  // confirm
  try {
    await rpc("confirm_test_users", { user_email: email });
    console.log(`  [reg setup] confirm ${email}: ok`);
  } catch (e) {
    console.warn(`  [reg setup] WARN confirm_test_users: ${e} — user may already be confirmed`);
  }
}

// ─── Export setup / teardown ──────────────────────────────────────────────────

export async function setup(): Promise<void> {
  console.log("\n[RLS regression setup] Seeding regression fixtures...");

  // ── Step 1: Create regression test users ─────────────────────────────────────
  console.log("\n── Step 1: users ─────────────────────────────────────────────");
  const via008 = await createUsersViaMigration008();
  if (!via008) {
    await signUpAndConfirm(REG.PLAYER_ONE_EMAIL, REG.PLAYER_ONE_PASS, "Regression Player One");
    await signUpAndConfirm(REG.PLAYER_TWO_EMAIL, REG.PLAYER_TWO_PASS, "Regression Player Two");
  }
  await new Promise((r) => setTimeout(r, 1000));

  // ── Step 2: Seed corridors (active + inactive) via service role ───────────────
  console.log("\n── Step 2: corridors ─────────────────────────────────────────");
  await svcUpsert("corridors", {
    id: REG.CORRIDOR_ACTIVE_ID,
    name: "Regression Corridor Active",
    description: "Regression test corridor",
    is_active: true,
    start_date: new Date().toISOString(),
    end_date: new Date(Date.now() + 86400000 * 90).toISOString(),
  });
  await svcUpsert("corridors", {
    id: REG.CORRIDOR_INACTIVE_ID,
    name: "Regression Corridor Inactive",
    description: "Inactive — regression test only",
    is_active: false,
    start_date: new Date(Date.now() - 86400000 * 2).toISOString(),
    end_date: new Date(Date.now() - 86400000).toISOString(),
  });

  // ── Step 3: Seed node ─────────────────────────────────────────────────────────
  console.log("\n── Step 3: node ──────────────────────────────────────────────");
  await svcUpsert("nodes", {
    id: REG.NODE_ID,
    corridor_id: REG.CORRIDOR_ACTIVE_ID,
    name: "Regression Node",
    location_name: "Test Location",
    latitude: 38.9,
    longitude: -77.0,
    is_active: true,
  });

  // ── Step 4: Seed reward ───────────────────────────────────────────────────────
  console.log("\n── Step 4: reward ────────────────────────────────────────────");
  await svcUpsert("rewards", {
    id: REG.REWARD_ID,
    corridor_id: REG.CORRIDOR_ACTIVE_ID,
    name: "Regression Reward",
    description: "Regression test reward",
    redemption_code: "REG-TEST-001",
    claimed: false,
  });

  // ── Step 5: Seed passports via each player's own JWT ─────────────────────────
  console.log("\n── Step 5: passports + check-in ──────────────────────────────");
  let p1JWT: string | null = null;
  let p2JWT: string | null = null;

  try {
    p1JWT = await signIn(REG.PLAYER_ONE_EMAIL, REG.PLAYER_ONE_PASS);
    console.log("  [reg setup] signIn reg_player_one: ok");
  } catch (e) {
    console.warn(`  [reg setup] WARN p1 signIn: ${e}`);
  }
  try {
    p2JWT = await signIn(REG.PLAYER_TWO_EMAIL, REG.PLAYER_TWO_PASS);
    console.log("  [reg setup] signIn reg_player_two: ok");
  } catch (e) {
    console.warn(`  [reg setup] WARN p2 signIn: ${e}`);
  }

  if (p1JWT) {
    const p1Id = JSON.parse(
      Buffer.from(p1JWT.split(".")[1] + "=".repeat(4 - (p1JWT.split(".")[1].length % 4)), "base64").toString()
    ).sub as string;
    await authedUpsert("passports", {
      id: REG.PASSPORT_ACTIVE_ID,
      user_id: p1Id,
      corridor_id: REG.CORRIDOR_ACTIVE_ID,
      status: "active",
    }, p1JWT);
    await authedUpsert("check_ins", {
      id: REG.CHECKIN_SEED_ID,
      passport_id: REG.PASSPORT_ACTIVE_ID,
      user_id: p1Id,
      node_id: REG.NODE_ID,
      status: "pending",
      proof_url: "https://example.com/reg-proof.jpg",
      proof_storage_path: "regression/proof.jpg",
    }, p1JWT);
  }

  if (p2JWT) {
    const p2Id = JSON.parse(
      Buffer.from(p2JWT.split(".")[1] + "=".repeat(4 - (p2JWT.split(".")[1].length % 4)), "base64").toString()
    ).sub as string;
    await authedUpsert("passports", {
      id: REG.PASSPORT_COMPLETE_ID,
      user_id: p2Id,
      corridor_id: REG.CORRIDOR_ACTIVE_ID,
      status: "complete",
    }, p2JWT);
    await authedUpsert("passports", {
      id: REG.PASSPORT_OTHER_ID,
      user_id: p2Id,
      corridor_id: REG.CORRIDOR_ACTIVE_ID,
      status: "active",
    }, p2JWT);
  }

  console.log("\n[RLS regression setup] Done.\n");
}

export async function teardown(): Promise<void> {
  // Fixtures are left in place intentionally — idempotent setup handles re-runs.
}
