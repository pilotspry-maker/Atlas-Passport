/**
 * src/lib/supabase/auth-headers.ts
 *
 * Single source of truth for every Authorization / apikey header pair we send
 * to Supabase. Dispatches on key prefix at call time so rotating
 * SUPABASE_SERVICE_ROLE_KEY from a legacy JWT (eyJ…) to a new-format secret
 * key (sb_secret_…) requires NO further code changes anywhere else.
 *
 * Reference: https://supabase.com/docs/guides/api/api-keys
 *
 *   "You cannot send a publishable or secret key in the Authorization: Bearer
 *    header, except if the value exactly equals the apikey header. In this
 *    case, your request will be forwarded down to your project's database,
 *    but will be rejected as the value is not a JWT."
 *
 * Therefore:
 *   - legacy JWT keys (eyJ…)          → send BOTH apikey and Authorization: Bearer
 *   - new sb_secret_ / sb_publishable → send apikey ONLY (Bearer would be rejected)
 *   - user access tokens (GoTrue JWT) → unaffected; still go in Authorization: Bearer
 *   - personal access tokens (Mgmt)   → unaffected; still JWT in Bearer to api.supabase.com
 */

export class KeyFormatError extends Error {
  constructor(public reason: string) {
    super(`Unrecognized Supabase key format: ${reason}`);
    this.name = "KeyFormatError";
  }
}

export type KeyFormat = "legacy_jwt" | "sb_secret" | "sb_publishable";

export function detectKeyFormat(key: string): KeyFormat {
  if (!key) throw new KeyFormatError("empty key");
  if (key.startsWith("sb_secret_")) return "sb_secret";
  if (key.startsWith("sb_publishable_")) return "sb_publishable";
  if (key.startsWith("eyJ") && key.split(".").length === 3) return "legacy_jwt";
  throw new KeyFormatError(
    `key starts with "${key.slice(0, 8)}…", segments=${key.split(".").length}`,
  );
}

export type AuthHeaders = Record<string, string>;

/** Anonymous request — works for both legacy anon JWT and sb_publishable_*. */
export function anonAuth(anonKey: string): AuthHeaders {
  return { apikey: anonKey };
}

/** Authenticated user request — pairs anon/publishable + user GoTrue JWT. */
export function userAuth(anonKey: string, userJwt: string): AuthHeaders {
  return {
    apikey: anonKey,
    Authorization: `Bearer ${userJwt}`,
  };
}

/**
 * Service-role request — accepts EITHER legacy service_role JWT or sb_secret_*.
 *
 * For legacy JWTs we send both `apikey` and `Authorization: Bearer` (current
 * production behavior). For sb_secret_* we send `apikey` ONLY — PostgREST
 * rejects non-JWT values in the Authorization header.
 */
export function serviceAuth(serviceKey: string): AuthHeaders {
  const fmt = detectKeyFormat(serviceKey);
  const headers: AuthHeaders = { apikey: serviceKey };
  if (fmt === "legacy_jwt") {
    headers.Authorization = `Bearer ${serviceKey}`;
  }
  return headers;
}

/** Management API request — always a JWT-format PAT in Authorization: Bearer. */
export function mgmtAuth(pat: string): AuthHeaders {
  if (pat.split(".").length !== 3) {
    throw new KeyFormatError("management token is not a JWT");
  }
  return { Authorization: `Bearer ${pat}` };
}
