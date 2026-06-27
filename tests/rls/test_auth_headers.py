"""
Unit tests for tests/rls/_auth_headers.py — pure, no network.
Run: pytest tests/rls/test_auth_headers.py
"""

import pytest

from tests.rls._auth_headers import (
    KeyFormatError,
    anon_auth,
    detect_key_format,
    mgmt_auth,
    service_auth,
    user_auth,
)

LEGACY_JWT = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig"
SB_SECRET = "sb_secret_abcDEF1234567890"
SB_PUBLISHABLE = "sb_publishable_abcDEF1234567890"


class TestDetectKeyFormat:
    def test_legacy_jwt(self):
        assert detect_key_format(LEGACY_JWT) == "legacy_jwt"

    def test_sb_secret(self):
        assert detect_key_format(SB_SECRET) == "sb_secret"

    def test_sb_publishable(self):
        assert detect_key_format(SB_PUBLISHABLE) == "sb_publishable"

    def test_empty_raises(self):
        with pytest.raises(KeyFormatError):
            detect_key_format("")

    def test_garbage_raises(self):
        with pytest.raises(KeyFormatError):
            detect_key_format("not-a-real-key")

    def test_pr_18_case_single_segment_raises(self):
        # The exact failure mode that triggered this whole effort
        with pytest.raises(KeyFormatError):
            detect_key_format("randomstring1segment")

    def test_two_segment_almost_jwt_raises(self):
        with pytest.raises(KeyFormatError):
            detect_key_format("eyJabc.eyJdef")


class TestAnonAuth:
    def test_apikey_only(self):
        assert anon_auth(SB_PUBLISHABLE) == {"apikey": SB_PUBLISHABLE}


class TestUserAuth:
    def test_pairs_apikey_with_bearer(self):
        assert user_auth(SB_PUBLISHABLE, LEGACY_JWT) == {
            "apikey": SB_PUBLISHABLE,
            "Authorization": f"Bearer {LEGACY_JWT}",
        }


class TestServiceAuth:
    def test_legacy_jwt_sends_both(self):
        assert service_auth(LEGACY_JWT) == {
            "apikey": LEGACY_JWT,
            "Authorization": f"Bearer {LEGACY_JWT}",
        }

    def test_sb_secret_sends_apikey_only(self):
        h = service_auth(SB_SECRET)
        assert h == {"apikey": SB_SECRET}
        assert "Authorization" not in h

    def test_malformed_raises(self):
        with pytest.raises(KeyFormatError):
            service_auth("nodotsorprefixhere")


class TestMgmtAuth:
    def test_jwt_pat_returns_bearer(self):
        assert mgmt_auth(LEGACY_JWT) == {"Authorization": f"Bearer {LEGACY_JWT}"}

    def test_non_jwt_pat_raises(self):
        with pytest.raises(KeyFormatError):
            mgmt_auth("sbp_pat_not_a_jwt")
