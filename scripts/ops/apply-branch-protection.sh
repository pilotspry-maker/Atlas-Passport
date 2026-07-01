#!/usr/bin/env bash
# scripts/ops/apply-branch-protection.sh
#
# Idempotent applier for the canonical branch-protection config on main.
# Reads .github/branch-protection.expected.json (canonical) or
# .github/branch-protection.baseline.json (--rollback).
#
# Requires: gh CLI, jq, admin scope on the repo. Refuses to run under
# any GitHub Actions token unless BRANCH_PROTECTION_ALLOW_CI=1 (guard
# against Dispatch triggering this via workflow_dispatch).
#
# Usage:
#   scripts/ops/apply-branch-protection.sh              # apply expected
#   scripts/ops/apply-branch-protection.sh --dry-run    # print PUT body, do not send
#   scripts/ops/apply-branch-protection.sh --rollback   # apply baseline
#
# See docs/ops/branch_protection_plan.md.

set -euo pipefail

REPO="${REPO:-pilotspry-maker/Atlas-Passport}"
BRANCH="${BRANCH:-main}"
MODE="apply"
CONFIG=".github/branch-protection.expected.json"

for arg in "$@"; do
  case "$arg" in
    --dry-run)  MODE="dry-run" ;;
    --rollback) CONFIG=".github/branch-protection.baseline.json" ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

# Guard: refuse to run inside GitHub Actions unless explicitly allowed.
# This prevents a Dispatch-triggered workflow_dispatch from silently
# re-applying / rolling back protection.
if [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ "${BRANCH_PROTECTION_ALLOW_CI:-0}" != "1" ]]; then
  echo "Refusing to run in GitHub Actions without BRANCH_PROTECTION_ALLOW_CI=1." >&2
  echo "This is intentional — see docs/ops/branch_protection_plan.md §5." >&2
  exit 3
fi

command -v gh >/dev/null || { echo "gh CLI required" >&2; exit 4; }
command -v jq >/dev/null || { echo "jq required"    >&2; exit 4; }

[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; exit 5; }

echo "Repo:   $REPO"
echo "Branch: $BRANCH"
echo "Mode:   $MODE"
echo "Config: $CONFIG"
echo ""

# Build the PUT body from the .protection block of the config file.
BODY=$(jq '.protection' "$CONFIG")

if [[ "$MODE" == "dry-run" ]]; then
  echo "=== PUT body (dry-run) ==="
  echo "$BODY" | jq .
  exit 0
fi

echo "Applying to $REPO branch $BRANCH …"
echo "$BODY" | gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/$REPO/branches/$BRANCH/protection" \
  --input - > /tmp/apply-result.json

echo ""
echo "=== Result ==="
jq '{required_approving_review_count: .required_pull_request_reviews.required_approving_review_count,
     require_code_owner_reviews:      .required_pull_request_reviews.require_code_owner_reviews,
     require_last_push_approval:      .required_pull_request_reviews.require_last_push_approval,
     required_linear_history:         .required_linear_history.enabled,
     required_conversation_resolution:.required_conversation_resolution.enabled,
     restrictions:                    (.restrictions | if . == null then null else {users:[.users[].login]} end),
     enforce_admins:                  .enforce_admins.enabled}' /tmp/apply-result.json

echo ""
echo "Done. Trigger .github/workflows/branch-protection-audit.yml (workflow_dispatch) to confirm no drift."
