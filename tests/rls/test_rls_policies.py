"""
Atlas Passport — RLS Integration Tests
File: tests/rls/test_rls_policies.py

Tests RLS policies against the live Supabase project by making direct
PostgREST HTTP requests with different authentication contexts:

  - No token (anon role)
  - Authenticated player with an active passport
  - Authenticated player with a complete passport
  - Cross-user write attempts

These tests run against the real database. They do NOT use a local
Supabase instance. Seeded fixture data uses deterministic UUIDs that
match supabase/seed.sql so tests are idempotent.

Usage:
  pip install pytest httpx
  SUPABASE_URL=https://xxx.supabase.co \\
  SUPABASE_ANON_KEY=sb_publishable_... \\
  SUPABASE_SERVICE_ROLE_KEY=sb_secret_... \\
  pytest tests/rls/test_rls_policies.py -v

In CI these values come from GitHub Actions secrets.
"""

import os
import json
import httpx
import pytest

# ─── Config ──────────────────────────────────────────────────────────────────

SUPABASE_URL       = os.environ["SUPABASE_URL"].rstrip("/")
ANON_KEY           = os.environ["SUPABASE_ANON_KEY"]
SERVICE_ROLE_KEY   = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

REST = f"{SUPABASE_URL}/rest/v1"
AUTH = f"{SUPABASE_URL}/auth/v1"

# ─── Fixture UUIDs (match seed.sql deterministic values) ─────────────────────

CORRIDOR_ID = "aaaaaaaa-0000-0000-0000-000000000001"
NODE_ID     = "bbbbbbbb-0000-0000-0000-000000000001"
REWARD_ID   = "cccccccc-0000-0000-0000-000000000001"
PASSPORT_ACTIVE_ID   = "dddddddd-0000-0000-0000-000000000001"
PASSPORT_COMPLETE_ID = "dddddddd-0000-0000-0000-000000000002"
CHECKIN_ID  = "eeeeeeee-0000-0000-0000-000000000001"

PLAYER_ONE_EMAIL = "player_one_rls@test.atlas"
PLAYER_ONE_PASS  = "TestPlayer1!RLS"
PLAYER_TWO_EMAIL = "player_two_rls@test.atlas"
PLAYER_TWO_PASS  = "TestPlayer2!RLS"


# ─── Helpers ─────────────────────────────────────────────────────────────────

def anon_headers() -> dict:
    """No JWT — hits as the anon role."""
    return {"apikey": ANON_KEY}


def authed_headers(access_token: str) -> dict:
    """Authenticated user JWT."""
    return {
        "apikey": ANON_KEY,
        "Authorization": f"Bearer {access_token}",
    }


def service_headers() -> dict:
    """Service role — bypasses all RLS (admin operations only)."""
    return {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
    }


def get_token(email: str, password: str) -> str:
    """Sign in and return access_token."""
    resp = httpx.post(
        f"{AUTH}/token?grant_type=password",
        headers={"apikey": ANON_KEY, "Content-Type": "application/json"},
        json={"email": email, "password": password},
        timeout=15,
    )
    assert resp.status_code == 200, f"Sign-in failed for {email}: {resp.text}"
    return resp.json()["access_token"]


def table_count(table: str, headers: dict, filters: str = "") -> int:
    """Return the count of rows returned for a table with given auth."""
    url = f"{REST}/{table}?select=id{('&' + filters) if filters else ''}"
    resp = httpx.get(url, headers=headers, timeout=15)
    if resp.status_code != 200:
        return -1
    data = resp.json()
    return len(data) if isinstance(data, list) else -1


# ─── Fixtures ────────────────────────────────────────────────────────────────

@pytest.fixture(scope="session")
def player_one_token():
    return get_token(PLAYER_ONE_EMAIL, PLAYER_ONE_PASS)


@pytest.fixture(scope="session")
def player_two_token():
    return get_token(PLAYER_TWO_EMAIL, PLAYER_TWO_PASS)


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 1 — Unauthenticated (anon role)
# ═════════════════════════════════════════════════════════════════════════════

class TestAnonAccess:
    """No JWT token. All reads must return 0 rows. All writes must return 403."""

    def test_anon_cannot_read_nodes(self):
        count = table_count("nodes", anon_headers())
        assert count == 0, f"Expected 0 nodes for anon, got {count}"

    def test_anon_cannot_read_corridors(self):
        count = table_count("corridors", anon_headers())
        assert count == 0, f"Expected 0 corridors for anon, got {count}"

    def test_anon_cannot_read_passports(self):
        count = table_count("passports", anon_headers())
        assert count == 0, f"Expected 0 passports for anon, got {count}"

    def test_anon_cannot_read_check_ins(self):
        count = table_count("check_ins", anon_headers())
        assert count == 0, f"Expected 0 check_ins for anon, got {count}"

    def test_anon_cannot_read_rewards(self):
        count = table_count("rewards", anon_headers())
        assert count == 0, f"Expected 0 rewards for anon, got {count}"

    def test_anon_cannot_read_profiles(self):
        count = table_count("profiles", anon_headers())
        assert count == 0, f"Expected 0 profiles for anon, got {count}"

    def test_anon_cannot_insert_passport(self):
        resp = httpx.post(
            f"{REST}/passports",
            headers={**anon_headers(), "Content-Type": "application/json"},
            json={
                "user_id": "00000000-0000-0000-0000-000000000000",
                "corridor_id": CORRIDOR_ID,
            },
            timeout=15,
        )
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 for anon passport INSERT, got {resp.status_code}: {resp.text}"
        )

    def test_anon_cannot_insert_checkin(self):
        resp = httpx.post(
            f"{REST}/check_ins",
            headers={**anon_headers(), "Content-Type": "application/json"},
            json={
                "passport_id":         PASSPORT_ACTIVE_ID,
                "user_id":             "00000000-0000-0000-0000-000000000000",
                "node_id":             NODE_ID,
                "proof_url":           "https://evil.com/fake.jpg",
                "proof_storage_path":  "fake/path",
            },
            timeout=15,
        )
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 for anon check_in INSERT, got {resp.status_code}: {resp.text}"
        )


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 2 — player_one (active passport)
# ═════════════════════════════════════════════════════════════════════════════

class TestPlayerOneAccess:
    """Authenticated player with an ACTIVE (not complete) passport."""

    def test_can_read_active_nodes(self, player_one_token):
        count = table_count("nodes", authed_headers(player_one_token), "is_active=eq.true")
        assert count > 0, "player_one should be able to read active nodes"

    def test_can_read_active_corridors(self, player_one_token):
        count = table_count("corridors", authed_headers(player_one_token), "is_active=eq.true")
        assert count > 0, "player_one should be able to read active corridors"

    def test_sees_only_own_passport(self, player_one_token):
        resp = httpx.get(
            f"{REST}/passports?select=id,user_id",
            headers=authed_headers(player_one_token),
            timeout=15,
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert all(r["id"] != PASSPORT_COMPLETE_ID for r in rows), (
            "player_one should NOT see player_two's complete passport"
        )

    def test_sees_only_own_checkins(self, player_one_token):
        resp = httpx.get(
            f"{REST}/check_ins?select=id",
            headers=authed_headers(player_one_token),
            timeout=15,
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert all(r["id"] != "eeeeeeee-0000-0000-0000-000000000002" for r in rows), (
            "player_one should not see other players check-ins"
        )

    def test_active_passport_cannot_read_reward(self, player_one_token):
        """Redemption code must not be visible until passport is complete."""
        resp = httpx.get(
            f"{REST}/rewards?id=eq.{REWARD_ID}&select=redemption_code",
            headers=authed_headers(player_one_token),
            timeout=15,
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 0, (
            f"player_one with ACTIVE passport should NOT see reward, got: {rows}"
        )

    def test_cannot_read_other_player_profile(self, player_one_token):
        resp = httpx.get(
            f"{REST}/profiles?email=eq.{PLAYER_TWO_EMAIL}&select=id",
            headers=authed_headers(player_one_token),
            timeout=15,
        )
        assert resp.status_code == 200
        assert len(resp.json()) == 0, "player_one should not see player_two's profile"

    def test_cannot_create_passport_for_other_user(self, player_one_token, player_two_token):
        """Attempt to create a passport where user_id != auth.uid()."""
        # Get player_two's user ID via service role
        resp = httpx.get(
            f"{REST}/profiles?email=eq.{PLAYER_TWO_EMAIL}&select=id",
            headers=service_headers(),
            timeout=15,
        )
        if resp.status_code != 200 or not resp.json():
            pytest.skip("Could not retrieve player_two ID for cross-user write test")

        player_two_id = resp.json()[0]["id"]

        insert_resp = httpx.post(
            f"{REST}/passports",
            headers={**authed_headers(player_one_token), "Content-Type": "application/json"},
            json={"user_id": player_two_id, "corridor_id": CORRIDOR_ID},
            timeout=15,
        )
        assert insert_resp.status_code in (401, 403), (
            f"player_one should not create passport for player_two, got {insert_resp.status_code}"
        )


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 3 — player_two (complete passport)
# ═════════════════════════════════════════════════════════════════════════════

class TestPlayerTwoCompletedAccess:
    """Authenticated player with a COMPLETE passport — should see reward."""

    def test_complete_passport_can_read_reward(self, player_two_token):
        resp = httpx.get(
            f"{REST}/rewards?corridor_id=eq.{CORRIDOR_ID}&select=title,redemption_code",
            headers=authed_headers(player_two_token),
            timeout=15,
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 1, (
            f"player_two with COMPLETE passport should see the reward, got: {rows}"
        )
        assert rows[0].get("redemption_code") == "SECRET-CODE-XYZ", (
            f"Wrong redemption code returned: {rows[0]}"
        )

    def test_complete_passport_player_cannot_read_other_checkins(self, player_two_token):
        resp = httpx.get(
            f"{REST}/check_ins?id=eq.{CHECKIN_ID}&select=id",
            headers=authed_headers(player_two_token),
            timeout=15,
        )
        assert resp.status_code == 200
        assert len(resp.json()) == 0, (
            "player_two should not see player_one's check-in even with a complete passport"
        )

    def test_complete_passport_player_cannot_read_other_passport(self, player_two_token):
        resp = httpx.get(
            f"{REST}/passports?id=eq.{PASSPORT_ACTIVE_ID}&select=id",
            headers=authed_headers(player_two_token),
            timeout=15,
        )
        assert resp.status_code == 200
        assert len(resp.json()) == 0, (
            "player_two should not see player_one's passport"
        )


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 4 — Node brute-force enumeration resistance
# ═════════════════════════════════════════════════════════════════════════════

class TestNodeEnumeration:
    """Verifies that a player cannot brute-force node sequences via the API."""

    def test_authenticated_player_can_read_node_names(self, player_one_token):
        """Nodes are visible to players — but only via the app, which controls field selection."""
        resp = httpx.get(
            f"{REST}/nodes?select=id,name,sequence&is_active=eq.true",
            headers=authed_headers(player_one_token),
            timeout=15,
        )
        assert resp.status_code == 200
        rows = resp.json()
        # Nodes ARE readable by authenticated users — this is expected.
        # The security guarantee is: anon cannot read, and hints/addresses
        # are only surfaced in the app UI after passport activation.
        assert isinstance(rows, list), "Nodes endpoint should return a list"

    def test_anon_cannot_enumerate_node_sequences(self):
        """Critical: anon must get 0 rows, preventing pre-auth corridor mapping."""
        resp = httpx.get(
            f"{REST}/nodes?select=id,name,sequence,hint",
            headers=anon_headers(),
            timeout=15,
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 0, (
            f"CRITICAL: anon can enumerate {len(rows)} nodes including sequences/hints. "
            "Migration 004 nodes_select_active policy is not enforced."
        )

    def test_anon_cannot_enumerate_via_corridor_join(self):
        """Verify anon cannot bypass node policy via a nested select join."""
        resp = httpx.get(
            f"{REST}/corridors?select=id,name,nodes(id,name,sequence)",
            headers=anon_headers(),
            timeout=15,
        )
        assert resp.status_code == 200
        data = resp.json()
        # Either corridors returns 0 rows (correct) or nodes is empty in any row
        for corridor in (data if isinstance(data, list) else []):
            nodes = corridor.get("nodes", [])
            assert len(nodes) == 0, (
                f"Anon bypassed node RLS via corridor join. Got nodes: {nodes}"
            )
