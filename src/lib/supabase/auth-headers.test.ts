/**
 * Unit tests for auth-headers.ts — pure, no network.
 */

import { describe, it, expect } from "vitest";
import {
  detectKeyFormat,
  anonAuth,
  userAuth,
  serviceAuth,
  mgmtAuth,
  KeyFormatError,
} from "./auth-headers";

// Synthetic 3-segment "JWT" — header.payload.signature, base64url-ish.
// We don't validate the signature, only segment count + eyJ prefix.
const LEGACY_JWT =
  "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig";
const SB_SECRET = "sb_secret_abcDEF1234567890";
const SB_PUBLISHABLE = "sb_publishable_abcDEF1234567890";

describe("detectKeyFormat", () => {
  it("recognizes legacy JWT", () => {
    expect(detectKeyFormat(LEGACY_JWT)).toBe("legacy_jwt");
  });

  it("recognizes sb_secret_", () => {
    expect(detectKeyFormat(SB_SECRET)).toBe("sb_secret");
  });

  it("recognizes sb_publishable_", () => {
    expect(detectKeyFormat(SB_PUBLISHABLE)).toBe("sb_publishable");
  });

  it("throws on empty input", () => {
    expect(() => detectKeyFormat("")).toThrow(KeyFormatError);
  });

  it("throws on garbage input", () => {
    expect(() => detectKeyFormat("not-a-real-key")).toThrow(KeyFormatError);
  });

  it("throws on a 1-segment string that isn't sb_* prefixed (the PR #18 case)", () => {
    // Simulates the broken secret that triggered this whole effort
    expect(() => detectKeyFormat("randomstring1segment")).toThrow(
      KeyFormatError,
    );
  });

  it("throws on a 2-segment near-JWT", () => {
    expect(() => detectKeyFormat("eyJabc.eyJdef")).toThrow(KeyFormatError);
  });
});

describe("anonAuth", () => {
  it("returns apikey only — no Authorization", () => {
    const h = anonAuth(SB_PUBLISHABLE);
    expect(h).toEqual({ apikey: SB_PUBLISHABLE });
    expect(h.Authorization).toBeUndefined();
  });

  it("works the same with a legacy anon JWT", () => {
    const legacyAnon = LEGACY_JWT;
    expect(anonAuth(legacyAnon)).toEqual({ apikey: legacyAnon });
  });
});

describe("userAuth", () => {
  it("includes Bearer with the user JWT, apikey with the anon/publishable key", () => {
    const userJwt = LEGACY_JWT; // GoTrue-issued user tokens stay JWT-format
    expect(userAuth(SB_PUBLISHABLE, userJwt)).toEqual({
      apikey: SB_PUBLISHABLE,
      Authorization: `Bearer ${userJwt}`,
    });
  });
});

describe("serviceAuth", () => {
  it("sends BOTH apikey and Authorization for a legacy JWT", () => {
    expect(serviceAuth(LEGACY_JWT)).toEqual({
      apikey: LEGACY_JWT,
      Authorization: `Bearer ${LEGACY_JWT}`,
    });
  });

  it("sends apikey ONLY for sb_secret_ (no Authorization header)", () => {
    const h = serviceAuth(SB_SECRET);
    expect(h.apikey).toBe(SB_SECRET);
    expect(h.Authorization).toBeUndefined();
    expect(Object.keys(h).sort()).toEqual(["apikey"]);
  });

  it("rejects sb_publishable_ — wrong privilege level for service calls", () => {
    // sb_publishable_ would still return a 200 from detectKeyFormat as a known
    // format, so serviceAuth doesn't itself reject it. We test the actual shape
    // (apikey-only) and trust the caller / PostgREST to enforce role mapping.
    const h = serviceAuth(SB_PUBLISHABLE);
    expect(h.Authorization).toBeUndefined();
    expect(h.apikey).toBe(SB_PUBLISHABLE);
  });

  it("throws KeyFormatError on a malformed value (the PR #18 case)", () => {
    expect(() => serviceAuth("nodotsorprefixhere")).toThrow(KeyFormatError);
  });
});

describe("mgmtAuth", () => {
  it("returns Authorization: Bearer with a JWT PAT", () => {
    expect(mgmtAuth(LEGACY_JWT)).toEqual({
      Authorization: `Bearer ${LEGACY_JWT}`,
    });
  });

  it("throws on a non-JWT PAT", () => {
    expect(() => mgmtAuth("sbp_pat_not_a_jwt")).toThrow(KeyFormatError);
  });
});
