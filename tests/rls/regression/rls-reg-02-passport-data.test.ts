/**
 * tests/rls/regression/rls-reg-02-passport-data.test.ts
 *
 * ═══════════════════════════════════════════════════════════════════
 * REGRESSION CATEGORY 2 — Core Passport Data Integrity
 * ═══════════════════════════════════════════════════════════════════
 *
 * Verifies that passport rows and check-in rows are correctly owned
 * and immutable after transition. Catches:
 *
 *   REG-2a: Anon cannot read any passport — SELECT isolation
 *   REG-2b: Anon cannot INSERT a passport row — write blocked
 *   REG-2c: Player cannot INSERT a passport into an inactive corridor
 *   REG-2d: Player cannot INSERT a passport for another user (user_id spoofing)
 *   REG-2e: Authenticated player cannot write to another player's passport
 *   REG-2f: passport.status cannot be set directly to 'complete' by the player
 *   REG-2g: Anon cannot read check_ins
 *   REG-2h: Player cannot INSERT a check-in against another player's passport (IDOR)
 *   REG-2i: Player cannot INSERT a check-in against a complete passport
 *   REG-2j: Player cannot INSERT a check-in for another user's user_id
 *
 * Policies under test:
 *   passports_select_own (migration 004)
 *   passports_insert_own (migration 007) — active corridor EXISTS guard
 *   check_ins_select_own (migration 004)
 *   check_ins_insert_own (migration 005) — passport ownership + status='active'
 * ═══════════════════════════════════════════════════════════════════
 */

import { describe, it, expect, beforeAll } from "vitest";
import {
  REG,
  SUPABASE_URL,
  signIn,
  authedHeaders,
  anonHeaders,
  pgInsert,
  pgPatch,
  pgGet,
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
describe("REG-2 Passport data integrity", () => {

  // ── REG-2a: Anon SELECT passports → [] ───────────────────────────────────────
  it("REG-2a: anon SELECT on passports returns [] — no data leakage", async () => {
    const res = await pgGet("passports", "select=id,user_id,status&limit=5", anonHeaders());
    expect(res.status).toBe(200);
    const rows = await res.json() as unknown[];
    expect(
      rows,
      `Anon read ${rows.length} passport row(s). ` +
      `passports_select_own USING(auth.uid()=user_id) must block anon reads. ` +
      `Check: SELECT relrowsecurity FROM pg_class WHERE relname='passports';`
    ).toHaveLength(0);
  });

  // ── REG-2b: Anon INSERT a passport → 401 ─────────────────────────────────────
  it("REG-2b: anon INSERT on passports → 401 Unauthorized", async () => {
    const res = await pgInsert(
      "passports",
      {
        id: "rrrrrrr3-0000-0000-0000-000000000099",
        user_id: "00000000-0000-0000-0000-000000000099",
        corridor_id: REG.CORRIDOR_ACTIVE_ID,
        status: "active",
      },
      anonHeaders()
    );
    expect(
      res.status,
      `${accessResult(res.status)}: anon was able to INSERT a passport row. ` +
      `passports_insert_own must require auth.uid()=user_id in its WITH CHECK. ` +
      `Unauthenticated callers have no auth.uid(), so the check must evaluate false.`
    ).toSatisfy((s: number) => s === 401 || s === 403);
  });

  // ── REG-2c: Player cannot INSERT passport into inactive corridor ──────────────
  it("REG-2c: authenticated player INSERT passport into inactive corridor → 401/403", async () => {
    const res = await pgInsert(
      "passports",
      {
        id: "rrrrrrr3-0000-0000-0000-000000000098",
        user_id: p1Id,
        corridor_id: REG.CORRIDOR_INACTIVE_ID,  // is_active = FALSE
        status: "active",
      },
      authedHeaders(p1JWT)
    );
    expect(
      res.status,
      `${accessResult(res.status)}: p1 inserted a passport into corridor ${REG.CORRIDOR_INACTIVE_ID} which has is_active=FALSE. ` +
      `passports_insert_own (migration 007) must include: ` +
      `EXISTS(SELECT 1 FROM corridors c WHERE c.id=passports.corridor_id AND c.is_active=TRUE). ` +
      `Run: SELECT with_check FROM pg_policies WHERE policyname='passports_insert_own';`
    ).toSatisfy((s: number) => s === 401 || s === 403);
  });

  // ── REG-2c ground truth: no row written for inactive corridor attempt ─────────
  it("REG-2c (ground truth): no passport row created in inactive corridor", async () => {
    const badId = "rrrrrrr3-0000-0000-0000-000000000098";
    await pgInsert(
      "passports",
      { id: badId, user_id: p1Id, corridor_id: REG.CORRIDOR_INACTIVE_ID, status: "active" },
      authedHeaders(p1JWT)
    );
    const row = await svcRead<string>("passports", `id=eq.${badId}`, "id");
    expect(
      row,
      `CRITICAL: passport ${badId} was written to the DB despite targeting inactive corridor. ` +
      `The policy blocked the HTTP response but the DB accepted the write. ` +
      `Cleanup: DELETE FROM passports WHERE id='${badId}';`
    ).toBeNull();
  });

  // ── REG-2d: Player cannot spoof user_id on INSERT ────────────────────────────
  it("REG-2d: player cannot INSERT a passport with another user's user_id (user_id spoofing)", async () => {
    const res = await pgInsert(
      "passports",
      {
        id: "rrrrrrr3-0000-0000-0000-000000000097",
        user_id: p2Id,   // p1 is trying to own a passport on behalf of p2
        corridor_id: REG.CORRIDOR_ACTIVE_ID,
        status: "active",
      },
      authedHeaders(p1JWT)  // authenticated as p1
    );
    expect(
      res.status,
      `${accessResult(res.status)}: p1 created a passport with user_id=${p2Id} (p2's ID). ` +
      `passports_insert_own WITH CHECK must be user_id=auth.uid(). ` +
      `A player should only be able to create passports for themselves.`
    ).toSatisfy((s: number) => s === 401 || s === 403);
  });

  // ── REG-2e: Player cannot PATCH another player's passport ────────────────────
  it("REG-2e: player cannot PATCH another player's passport row", async () => {
    const res = await pgPatch(
      "passports",
      `id=eq.${REG.PASSPORT_COMPLETE_ID}`,  // owned by p2
      { status: "abandoned" },
      authedHeaders(p1JWT)  // authenticated as p1
    );
    // PostgREST will return 200/204 with 0 rows affected (USING filters it out)
    // or 401/403 if an INSERT-level policy also covers UPDATE.
    // We verify the DB value didn't change.
    const actualStatus = await svcRead<string>("passports", `id=eq.${REG.PASSPORT_COMPLETE_ID}`, "status");
    expect(
      actualStatus,
      `p1 successfully changed p2's passport status to 'abandoned'. ` +
      `passports_update_own policy must have USING(user_id=auth.uid()). ` +
      `If no UPDATE policy exists, PostgREST defaults to deny — check if one was accidentally removed.`
    ).toBe("complete");
  });

  // ── REG-2f: Player cannot self-complete a passport ───────────────────────────
  it("REG-2f: player cannot set own passport.status='complete' directly via PATCH", async () => {
    const res = await pgPatch(
      "passports",
      `id=eq.${REG.PASSPORT_ACTIVE_ID}`,
      { status: "complete" },
      authedHeaders(p1JWT)
    );
    const actualStatus = await svcRead<string>("passports", `id=eq.${REG.PASSPORT_ACTIVE_ID}`, "status");
    // Status must still be 'active' — completion should only happen via server-side logic
    if (res.status === 200 || res.status === 204) {
      expect(
        actualStatus,
        `p1 set their own passport status to 'complete' via direct PATCH. ` +
        `Passport completion must be gated by a server function or trigger, ` +
        `not allowed via direct PostgREST PATCH from an authenticated client. ` +
        `Add passports_update_own WITH CHECK that prevents status escalation, ` +
        `or remove UPDATE permissions entirely and route through an API endpoint.`
      ).toBe("active");
    }
  });

  // ── REG-2g: Anon SELECT check_ins → [] ───────────────────────────────────────
  it("REG-2g: anon SELECT on check_ins returns [] — no data leakage", async () => {
    const res = await pgGet("check_ins", "select=id,user_id,passport_id&limit=5", anonHeaders());
    expect(res.status).toBe(200);
    const rows = await res.json() as unknown[];
    expect(
      rows,
      `Anon read ${rows.length} check_in row(s). ` +
      `check_ins_select_own USING(auth.uid()=user_id) must block anon reads.`
    ).toHaveLength(0);
  });

  // ── REG-2h: Player cannot INSERT check-in against another player's passport ───
  it("REG-2h: player cannot INSERT check-in referencing another player's passport (IDOR)", async () => {
    const res = await pgInsert(
      "check_ins",
      {
        id: "rrrrrrr4-0000-0000-0000-000000000098",
        passport_id: REG.PASSPORT_OTHER_ID,   // owned by p2
        user_id: p1Id,
        node_id: REG.NODE_ID,
        status: "pending",
        proof_url: "https://example.com/idor-proof.jpg",
        proof_storage_path: "regression/idor.jpg",
      },
      authedHeaders(p1JWT)  // p1 authenticating but using p2's passport
    );
    expect(
      res.status,
      `${accessResult(res.status)}: p1 inserted a check-in against p2's passport ${REG.PASSPORT_OTHER_ID}. ` +
      `check_ins_insert_own WITH CHECK must include: ` +
      `EXISTS(SELECT 1 FROM passports p WHERE p.id=check_ins.passport_id AND p.user_id=auth.uid()). ` +
      `The passport ownership EXISTS clause is absent or using the wrong column.`
    ).toSatisfy((s: number) => s === 401 || s === 403);
  });

  // ── REG-2i: Player cannot INSERT check-in against a complete/inactive passport ─
  it("REG-2i: player cannot INSERT check-in against a complete passport (status gate)", async () => {
    const res = await pgInsert(
      "check_ins",
      {
        id: "rrrrrrr4-0000-0000-0000-000000000097",
        passport_id: REG.PASSPORT_COMPLETE_ID,  // status = 'complete', owned by p2
        user_id: p2Id,
        node_id: REG.NODE_ID,
        status: "pending",
        proof_url: "https://example.com/complete-proof.jpg",
        proof_storage_path: "regression/complete.jpg",
      },
      authedHeaders(p2JWT)  // authenticated as p2 (owns the passport)
    );
    expect(
      res.status,
      `${accessResult(res.status)}: p2 inserted a check-in against a 'complete' passport. ` +
      `check_ins_insert_own WITH CHECK must include p.status='active'. ` +
      `Players should not accumulate check-ins after their game session has ended.`
    ).toSatisfy((s: number) => s === 401 || s === 403);
  });

  // ── REG-2j: Player cannot spoof user_id on check-in INSERT ───────────────────
  it("REG-2j: player cannot INSERT check-in with another user's user_id", async () => {
    const res = await pgInsert(
      "check_ins",
      {
        id: "rrrrrrr4-0000-0000-0000-000000000096",
        passport_id: REG.PASSPORT_ACTIVE_ID,  // owned by p1
        user_id: p2Id,   // spoofed to p2's ID
        node_id: REG.NODE_ID,
        status: "pending",
        proof_url: "https://example.com/spoof-proof.jpg",
        proof_storage_path: "regression/spoof.jpg",
      },
      authedHeaders(p1JWT)  // authenticated as p1
    );
    expect(
      res.status,
      `${accessResult(res.status)}: p1 inserted a check-in with user_id=${p2Id} (p2's ID). ` +
      `check_ins_insert_own WITH CHECK must include user_id=auth.uid(). ` +
      `A check-in's user_id must always match the caller's JWT sub claim.`
    ).toSatisfy((s: number) => s === 401 || s === 403);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe("REG-2 Cross-user SELECT isolation", () => {

  // ── REG-2k: Player can only read own passports ───────────────────────────────
  it("REG-2k: authenticated player SELECT on passports returns only own rows", async () => {
    const res = await pgGet(
      "passports",
      `select=id,user_id&limit=50`,
      authedHeaders(p1JWT)
    );
    expect(res.status).toBe(200);
    const rows = await res.json() as { id: string; user_id: string }[];

    const leaked = rows.filter((r) => r.user_id !== p1Id);
    expect(
      leaked,
      `p1 can read ${leaked.length} passport row(s) belonging to other users: ` +
      JSON.stringify(leaked.map((r) => r.id)) + `. ` +
      `passports_select_own USING(auth.uid()=user_id) is not filtering correctly.`
    ).toHaveLength(0);
  });

  // ── REG-2l: Player can only read own check_ins ───────────────────────────────
  it("REG-2l: authenticated player SELECT on check_ins returns only own rows", async () => {
    const res = await pgGet(
      "check_ins",
      `select=id,user_id&limit=50`,
      authedHeaders(p1JWT)
    );
    expect(res.status).toBe(200);
    const rows = await res.json() as { id: string; user_id: string }[];

    const leaked = rows.filter((r) => r.user_id !== p1Id);
    expect(
      leaked,
      `p1 can read ${leaked.length} check_in row(s) belonging to other users. ` +
      `check_ins_select_own USING(auth.uid()=user_id) is not filtering correctly.`
    ).toHaveLength(0);
  });

  // ── REG-2m: Public tables are readable by anon (corridors, nodes) ────────────
  it("REG-2m: anon can read active corridors — public read policy is intact", async () => {
    const res = await pgGet("corridors", "select=id,is_active&is_active=eq.true&limit=10", anonHeaders());
    expect(res.status).toBe(200);
    const rows = await res.json() as { is_active: boolean }[];
    // Must return at least one active corridor (the regression fixture)
    expect(rows.length).toBeGreaterThanOrEqual(1);
    // Every returned row must have is_active=true
    expect(rows.every((r) => r.is_active === true)).toBe(true);
  });
});
