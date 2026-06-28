#!/usr/bin/env bash
#
# verify-key-rotation.sh
#
# Post-rotation smoke test for the SUPABASE_SERVICE_ROLE_KEY.
# Run this AFTER rotating the service-role key to the legacy JWT (eyJ...) form
# in all four locations (see docs/RUNBOOK.md). It exercises the live PostgREST
# surface with the new key and confirms each endpoint returns HTTP 200.
#
# It is read-only and idempotent: it claims zero jobs (p_limit = 0) and selects
# at most one row, so it is safe to run repeatedly against production.
#
# Required environment:
#   SUPABASE_URL                Project URL, e.g. https://gaavynmmysdhovpatzlp.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY   The rotated legacy JWT service_role key
#
# This script never prints the key value.
#
# Exit code 0 = all checks passed. Non-zero = at least one check failed.

set -euo pipefail

URL="${SUPABASE_URL:-${NEXT_PUBLIC_SUPABASE_URL:-}}"
KEY="${SUPABASE_SERVICE_ROLE_KEY:-}"

fail=0

if [ -z "$URL" ]; then
  echo "ERROR: SUPABASE_URL (or NEXT_PUBLIC_SUPABASE_URL) is not set." >&2
  exit 2
fi
if [ -z "$KEY" ]; then
  echo "ERROR: SUPABASE_SERVICE_ROLE_KEY is not set." >&2
  exit 2
fi

# Warn (do not fail) if the key is not in JWT shape. PostgREST will reject a
# non-JWT service key, so this is almost certainly a misconfiguration.
case "$KEY" in
  eyJ*) : ;;
  *) echo "WARN: SUPABASE_SERVICE_ROLE_KEY does not begin with 'eyJ' — PostgREST may reject it as opaque." >&2 ;;
esac

URL="${URL%/}"

# check NAME METHOD PATH [JSON_BODY]
# Emits one line with the HTTP status and a PASS/FAIL verdict.
check() {
  local name="$1" method="$2" path="$3" body="${4:-}"
  local code
  if [ "$method" = "POST" ]; then
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
      -X POST "${URL}${path}" \
      -H "apikey: ${KEY}" \
      -H "Authorization: Bearer ${KEY}" \
      -H "Content-Type: application/json" \
      --data "${body}" || echo "000")"
  else
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
      "${URL}${path}" \
      -H "apikey: ${KEY}" \
      -H "Authorization: Bearer ${KEY}" || echo "000")"
  fi

  if [ "$code" = "200" ]; then
    echo "PASS  ${name}  (HTTP ${code})"
  else
    echo "FAIL  ${name}  (HTTP ${code}, expected 200)"
    fail=1
  fi
}

echo "Verifying rotated service-role key against ${URL}"
echo "------------------------------------------------------------"

# 1. Public REST read on corridors. 200 (possibly empty array) means the key
#    authenticates and PostgREST resolves it to service_role.
check "corridors select"            GET  "/rest/v1/corridors?select=id&limit=1"

# 2. public.claim_jobs wrapper (migration 024). p_limit=0 claims nothing.
check "public.claim_jobs rpc"       POST "/rest/v1/rpc/claim_jobs" '{"p_limit": 0}'

# 3. verify_service_role_permissions diagnostic (migration 019). Requires 019
#    to be applied to prod; until then this is expected to 404.
check "verify_service_role_perms"   POST "/rest/v1/rpc/verify_service_role_permissions" '{}'

echo "------------------------------------------------------------"
if [ "$fail" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "ONE OR MORE CHECKS FAILED"
fi
exit "$fail"
