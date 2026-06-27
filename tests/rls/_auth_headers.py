"""
tests/rls/_auth_headers.py

Mirror of src/lib/supabase/auth-headers.ts for Python test runners and inline
CI scripts in .github/workflows/*.yml. Same prefix-dispatch rules — see the
TypeScript file for full rationale and the Supabase docs reference.
"""

from __future__ import annotations

from typing import Dict


class KeyFormatError(ValueError):
    pass


def detect_key_format(key: str) -> str:
    """Return 'legacy_jwt' | 'sb_secret' | 'sb_publishable'. Raise on unknown."""
    if not key:
        raise KeyFormatError("empty key")
    if key.startswith("sb_secret_"):
        return "sb_secret"
    if key.startswith("sb_publishable_"):
        return "sb_publishable"
    parts = key.split(".")
    if key.startswith("eyJ") and len(parts) == 3:
        return "legacy_jwt"
    raise KeyFormatError(
        f'key starts with "{key[:8]}…", segments={len(parts)}'
    )


def anon_auth(anon_key: str) -> Dict[str, str]:
    """Anonymous request — works for both legacy anon JWT and sb_publishable_*."""
    return {"apikey": anon_key}


def user_auth(anon_key: str, user_jwt: str) -> Dict[str, str]:
    """Authenticated user request — pairs anon/publishable + user GoTrue JWT."""
    return {"apikey": anon_key, "Authorization": f"Bearer {user_jwt}"}


def service_auth(service_key: str) -> Dict[str, str]:
    """
    Service-role request — accepts EITHER legacy service_role JWT or sb_secret_*.
    Sends Authorization: Bearer only when the key is a JWT; otherwise apikey-only.
    """
    fmt = detect_key_format(service_key)
    headers: Dict[str, str] = {"apikey": service_key}
    if fmt == "legacy_jwt":
        headers["Authorization"] = f"Bearer {service_key}"
    return headers


def mgmt_auth(pat: str) -> Dict[str, str]:
    """Management API request — always a JWT-format PAT in Bearer."""
    if len(pat.split(".")) != 3:
        raise KeyFormatError("management token is not a JWT")
    return {"Authorization": f"Bearer {pat}"}
