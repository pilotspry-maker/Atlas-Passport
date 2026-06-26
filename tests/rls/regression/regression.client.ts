/**
 * tests/rls/regression/regression.client.ts
 *
 * Shared helpers for the RLS regression suite.
 *
 * Distinct from tests/rls/exploits/client.ts so the regression suite can
 * run independently with its own fixture namespace and env vars without
 * importing from the exploit path.
 *
 * Fixture namespace:
 *   All regression fixture UUIDs use the 0xRR prefix to avoid collisions
 *   with exploit-suite fixtures (0xAA–0xEE prefix).
 */

// ─── Env ──────────────────────────────────────────────────────────────────────

function requireEnv(key: string): string {
  const val = process.env[key];
  if (!val) throw new Error(`[regression] Missing required env var: ${key}`);
  return val.replace(/\/$/, "");
}

export const SUPABASE_URL     = requireEnv("SUPABASE_URL");
export const ANON_KEY         = requireEnv("SUPABASE_ANON_KEY");
export const SERVICE_ROLE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

export const REST = `${SUPABASE_URL}/rest/v1`;
export const AUTH = `${SUPABASE_URL}/auth/v1`;

// ─── Regression fixture UUIDs ─────────────────────────────────────────────────
// Deterministic, isolated from the exploit suite.

export const REG = {
  // Corridors — cccc0001 prefix, matching rls-regression.yml seed step
  CORRIDOR_ACTIVE_ID:   "cccc0001-0000-0000-0000-000000000001",
  CORRIDOR_INACTIVE_ID: "cccc0001-0000-0000-0000-000000000002",

  // Nodes
  NODE_ID:              "cccc0002-0000-0000-0000-000000000001",

  // Passports
  PASSPORT_ACTIVE_ID:   "cccc0003-0000-0000-0000-000000000001",  // owned by reg_player_one
  PASSPORT_COMPLETE_ID: "cccc0003-0000-0000-0000-000000000002",  // owned by reg_player_two
  PASSPORT_OTHER_ID:    "cccc0003-0000-0000-0000-000000000003",  // owned by reg_player_two (for IDOR tests)

  // Check-ins
  CHECKIN_SEED_ID:      "cccc0004-0000-0000-0000-000000000001",

  // Rewards
  REWARD_ID:            "cccc0005-0000-0000-0000-000000000001",

  // Test users — isolated from exploit suite
  PLAYER_ONE_EMAIL: "reg_player_one@test.atlasci.com",
  PLAYER_ONE_PASS:  "RegPlayer1!RLS",
  PLAYER_TWO_EMAIL: "reg_player_two@test.atlasci.com",
  PLAYER_TWO_PASS:  "RegPlayer2!RLS",
} as const;

// ─── Header factories ─────────────────────────────────────────────────────────

export function anonHeaders(): Record<string, string> {
  return { apikey: ANON_KEY };
}

export function authedHeaders(jwt: string): Record<string, string> {
  return { apikey: ANON_KEY, Authorization: `Bearer ${jwt}` };
}

export function serviceHeaders(): Record<string, string> {
  return {
    apikey: SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
  };
}

// ─── Auth helpers ─────────────────────────────────────────────────────────────

export async function signIn(email: string, password: string): Promise<string> {
  const res = await fetch(`${AUTH}/token?grant_type=password`, {
    method: "POST",
    headers: { ...anonHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`[regression] signIn ${email} failed (${res.status}): ${text}`);
  }
  return ((await res.json()) as { access_token: string }).access_token;
}

/** Extract user UUID from JWT sub claim. */
export function jwtSub(jwt: string): string {
  const pad = "=".repeat(4 - (jwt.split(".")[1].length % 4));
  return (JSON.parse(Buffer.from(jwt.split(".")[1] + pad, "base64").toString()) as { sub: string }).sub;
}

// ─── PostgREST helpers ────────────────────────────────────────────────────────

export async function pgGet(
  table: string,
  query: string,
  headers: Record<string, string>
): Promise<Response> {
  return fetch(`${REST}/${table}?${query}`, { headers });
}

export async function pgInsert(
  table: string,
  body: Record<string, unknown>,
  headers: Record<string, string>,
  prefer = "return=minimal"
): Promise<Response> {
  return fetch(`${REST}/${table}`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "application/json", Prefer: prefer },
    body: JSON.stringify(body),
  });
}

export async function pgPatch(
  table: string,
  filter: string,
  body: Record<string, unknown>,
  headers: Record<string, string>
): Promise<Response> {
  return fetch(`${REST}/${table}?${filter}`, {
    method: "PATCH",
    headers: { ...headers, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(body),
  });
}

export async function pgDelete(
  table: string,
  filter: string,
  headers: Record<string, string>
): Promise<Response> {
  return fetch(`${REST}/${table}?${filter}`, { method: "DELETE", headers });
}

/** Read a single column from a single row via service role. Returns null if not found. */
export async function svcRead<T>(
  table: string,
  filter: string,
  column: string
): Promise<T | null> {
  const res = await pgGet(table, `${filter}&select=${column}`, serviceHeaders());
  if (!res.ok) return null;
  const rows = (await res.json()) as Record<string, T>[];
  return rows.length > 0 ? rows[0][column] : null;
}

/** Classify an HTTP response status into a human-readable access result. */
export function accessResult(status: number): string {
  if (status === 200 || status === 201 || status === 204) return "ALLOWED";
  if (status === 401) return "BLOCKED (401 Unauthorized)";
  if (status === 403) return "BLOCKED (403 Forbidden)";
  return `UNKNOWN (${status})`;
}
