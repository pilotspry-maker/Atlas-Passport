#!/usr/bin/env bash
# =============================================================================
# scripts/test-rls-local.sh
#
# Local RLS regression runner for Atlas Passport.
# Run this before every commit that touches a migration or an RLS policy.
#
# Usage:
#   ./scripts/test-rls-local.sh              # test against local Supabase
#   ./scripts/test-rls-local.sh --live       # test against production (careful)
#   ./scripts/test-rls-local.sh --exploit    # run exploit suite too
#   ./scripts/test-rls-local.sh --all        # exploit + regression
#
# Prerequisites:
#   - Docker running
#   - supabase CLI installed (supabase --version)
#   - Node 18+ installed
#   - npm install --legacy-peer-deps already run
# =============================================================================

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Args ─────────────────────────────────────────────────────────────────────
LIVE=false
RUN_EXPLOIT=false
RUN_REGRESSION=true

for arg in "$@"; do
  case "$arg" in
    --live)      LIVE=true ;;
    --exploit)   RUN_EXPLOIT=true ;;
    --all)       RUN_EXPLOIT=true; RUN_REGRESSION=true ;;
    --help|-h)
      echo "Usage: $0 [--live] [--exploit] [--all]"
      echo ""
      echo "  (no flags)   Run regression suite against local Supabase (default)"
      echo "  --live       Run against production Supabase (use .env.local credentials)"
      echo "  --exploit    Run exploit suite only"
      echo "  --all        Run both exploit suite and regression suite"
      exit 0
      ;;
  esac
done

# ─── Header ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║      Atlas Passport — RLS Local Test Runner         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

# ─── Step 1: Set env vars ─────────────────────────────────────────────────────
if [ "$LIVE" = true ]; then
  echo -e "${YELLOW}⚠  Running against PRODUCTION Supabase${RESET}"
  echo -e "${YELLOW}   Loading credentials from .env.local${RESET}"
  echo ""

  if [ ! -f ".env.local" ]; then
    echo -e "${RED}✗ .env.local not found. Cannot run against production.${RESET}"
    exit 1
  fi

  # Load .env.local
  export $(grep -v '^#' .env.local | grep -E 'SUPABASE_URL|SUPABASE_ANON_KEY|SUPABASE_SERVICE_ROLE_KEY|NEXT_PUBLIC_SUPABASE' | xargs)

  # Normalize key names (Next.js uses NEXT_PUBLIC_ prefix)
  export SUPABASE_URL="${SUPABASE_URL:-${NEXT_PUBLIC_SUPABASE_URL:-}}"
  export SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-${NEXT_PUBLIC_SUPABASE_ANON_KEY:-}}"

  if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
    echo -e "${RED}✗ Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env.local${RESET}"
    exit 1
  fi

  read -r -p "$(echo -e "${YELLOW}Are you sure you want to run tests against PRODUCTION? [y/N] ${RESET}")" confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
else
  echo -e "${BLUE}▶  Targeting local Supabase (127.0.0.1:54321)${RESET}"
  echo ""

  # ── Check Docker ─────────────────────────────────────────────────────────────
  if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}✗ Docker is not running. Start Docker Desktop and retry.${RESET}"
    exit 1
  fi

  # ── Start local Supabase if not already running ───────────────────────────────
  if ! supabase status 2>/dev/null | grep -q "API URL"; then
    echo -e "${BLUE}  Starting local Supabase...${RESET}"
    supabase start
    echo ""
    echo -e "${BLUE}  Applying migrations...${RESET}"
    supabase db reset
    echo ""
  fi

  # ── Extract keys from supabase status ────────────────────────────────────────
  STATUS_OUTPUT=$(supabase status 2>/dev/null)
  export SUPABASE_URL="http://127.0.0.1:54321"
  export SUPABASE_ANON_KEY=$(echo "$STATUS_OUTPUT" | grep -E 'anon key' | awk '{print $NF}')
  export SUPABASE_SERVICE_ROLE_KEY=$(echo "$STATUS_OUTPUT" | grep -E 'service_role key' | awk '{print $NF}')

  if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
    echo -e "${YELLOW}⚠  Could not auto-detect keys from supabase status${RESET}"
    echo -e "${YELLOW}   Set SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY manually.${RESET}"
    exit 1
  fi
fi

echo -e "${GREEN}  SUPABASE_URL      = $SUPABASE_URL${RESET}"
echo -e "${GREEN}  SUPABASE_ANON_KEY = ${SUPABASE_ANON_KEY:0:20}...${RESET}"
echo ""

# ─── Step 2: Install deps ─────────────────────────────────────────────────────
echo -e "${BLUE}▶  Checking dependencies...${RESET}"
if [ ! -d "node_modules" ]; then
  echo -e "${BLUE}  Running npm install --legacy-peer-deps${RESET}"
  npm install --legacy-peer-deps
fi
echo ""

# ─── Step 3: Run suites ───────────────────────────────────────────────────────
EXIT_CODE=0

if [ "$RUN_EXPLOIT" = true ]; then
  echo -e "${BOLD}═══ Exploit Suite (24 assertions) ═══════════════════════${RESET}"
  if npm run test:rls-exploits; then
    echo -e "${GREEN}✓ Exploit suite passed${RESET}"
  else
    echo -e "${RED}✗ Exploit suite FAILED${RESET}"
    EXIT_CODE=1
  fi
  echo ""
fi

if [ "$RUN_REGRESSION" = true ]; then
  echo -e "${BOLD}═══ Regression Suite ════════════════════════════════════${RESET}"
  if npm run test:rls-regression; then
    echo -e "${GREEN}✓ Regression suite passed${RESET}"
  else
    echo -e "${RED}✗ Regression suite FAILED${RESET}"
    EXIT_CODE=1
  fi
  echo ""
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ Summary ═════════════════════════════════════════════${RESET}"
if [ $EXIT_CODE -eq 0 ]; then
  echo -e "${GREEN}✓ All RLS tests passed — safe to commit${RESET}"
else
  echo -e "${RED}✗ One or more RLS test suites failed${RESET}"
  echo -e "${RED}  Do not merge until all tests pass.${RESET}"
fi
echo ""

exit $EXIT_CODE
