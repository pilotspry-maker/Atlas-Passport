#!/usr/bin/env bash
# =============================================================================
# scripts/pre-commit-rls.sh
#
# Git pre-commit hook that runs the RLS regression suite when any
# migration file or RLS-related source file is staged for commit.
#
# Install:
#   cp scripts/pre-commit-rls.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Or use the npm postinstall script (see package.json):
#   "postinstall": "cp scripts/pre-commit-rls.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit"
#
# Skip for emergency hotfixes (use sparingly):
#   git commit --no-verify
# =============================================================================

set -euo pipefail

# ─── Detect relevant changes ──────────────────────────────────────────────────
STAGED=$(git diff --cached --name-only 2>/dev/null || true)

MIGRATION_CHANGED=false
RLS_TEST_CHANGED=false

while IFS= read -r file; do
  case "$file" in
    supabase/migrations/*.sql)           MIGRATION_CHANGED=true ;;
    tests/rls/*)                         RLS_TEST_CHANGED=true ;;
    vitest.rls.config.ts)                RLS_TEST_CHANGED=true ;;
    vitest.regression.config.ts)        RLS_TEST_CHANGED=true ;;
  esac
done <<< "$STAGED"

# ─── Early exit if nothing relevant is staged ─────────────────────────────────
if [ "$MIGRATION_CHANGED" = false ] && [ "$RLS_TEST_CHANGED" = false ]; then
  exit 0
fi

# ─── Run the regression suite ─────────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│ pre-commit: RLS-sensitive files staged — running    │"
echo "│ regression suite before allowing commit             │"
echo "└─────────────────────────────────────────────────────┘"
echo ""

if [ "$MIGRATION_CHANGED" = true ]; then
  echo "  Migration files staged:"
  echo "$STAGED" | grep 'supabase/migrations' | sed 's/^/    /'
fi
if [ "$RLS_TEST_CHANGED" = true ]; then
  echo "  RLS test files staged:"
  echo "$STAGED" | grep -E 'tests/rls|vitest.*config' | sed 's/^/    /'
fi
echo ""

# Check if local Supabase is running — if not, skip with warning
if ! supabase status 2>/dev/null | grep -q "API URL"; then
  echo "⚠  Local Supabase is not running."
  echo "   Skipping pre-commit RLS check (Docker/Supabase not available)."
  echo "   The CI pipeline will enforce this check on your PR."
  echo ""
  exit 0
fi

# Run regression suite against local Supabase
if ! ./scripts/test-rls-local.sh 2>&1; then
  echo ""
  echo "✗ RLS regression suite failed — commit blocked."
  echo "  Fix the failing tests before committing."
  echo "  To skip (emergency only): git commit --no-verify"
  echo ""
  exit 1
fi

echo ""
echo "✓ RLS regression suite passed — proceeding with commit"
echo ""
exit 0
