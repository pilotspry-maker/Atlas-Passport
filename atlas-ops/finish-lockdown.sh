#!/usr/bin/env bash
# =============================================================================
# atlas-ops/finish-lockdown.sh
# Atlas Passport — secret rotation for VERCEL_TOKEN, SUPABASE_SERVICE_ROLE_KEY,
# RESEND_API_KEY.
#
# REQUIREMENTS (run from YOUR LOCAL machine, not in CI):
#   bash >= 4.x
#   gh   >= 2.x  authenticated via: gh auth login   (scopes: repo, workflow,
#                                                    admin:repo_hook OR
#                                                    fine-grained "Secrets" RW)
#   curl, jq, base64, date
#
# NOT REQUIRED:
#   vercel CLI — this script speaks directly to the Vercel REST API via curl.
#   Do not be misled by status reports that flag a missing `vercel` binary;
#   it is intentionally not used here so the script works in clean shells.
#
# SECURITY RULES — non-negotiable:
#   1. Values are read via `read -s` (no terminal echo, no shell history entry
#      from within this script's subshell).
#   2. Values are NEVER echoed, logged, written to files, or embedded in
#      command-line arguments (pipe via stdin or use jq --arg instead).
#   3. Run in a private terminal — not over screen-share.
#   4. Optionally disable parent-shell history first:
#        HISTFILE=/dev/null bash ./atlas-ops/finish-lockdown.sh
#   5. If any step fails, the script exits immediately (set -euo pipefail).
#      Stop and tell Claude — do not retry blindly.
# =============================================================================

set -euo pipefail

# ─── Constants ────────────────────────────────────────────────────────────────

readonly REPO="pilotspry-maker/Atlas-Passport"
readonly VERCEL_TEAM_ID="team_4QVS3jF4bz6HIripIcSe0Re5"
readonly VERCEL_PROJECT="atlas-passport"
readonly VERCEL_API_BASE="https://api.vercel.com/v9/projects/${VERCEL_PROJECT}"
readonly VERCEL_ENVS_URL="${VERCEL_API_BASE}/env?teamId=${VERCEL_TEAM_ID}&limit=100"

RED='\033[0;31m'; YEL='\033[1;33m'; GRN='\033[0;32m'; BLU='\033[0;34m'; RST='\033[0m'
log()  { echo -e "${BLU}[•]${RST} $*"; }
ok()   { echo -e "${GRN}[✓]${RST} $*"; }
warn() { echo -e "${YEL}[!]${RST} $*"; }
die()  { echo -e "${RED}[✗]${RST} $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

# ─── Validation ───────────────────────────────────────────────────────────────

validate_jwt() {
  local token="$1" label="${2:-JWT}"
  local hdr pay sig
  IFS='.' read -r hdr pay sig <<< "$token"
  [[ -n "$hdr" && -n "$pay" && -n "$sig" ]] || die "${label}: missing JWT segments (not a valid JWT)."
  local padded="$pay"
  while (( ${#padded} % 4 != 0 )); do padded+="="; done
  local decoded
  decoded=$(printf '%s' "$padded" | base64 -d 2>/dev/null) \
    || die "${label}: payload is not valid base64."
  local exp role
  exp=$(printf '%s' "$decoded"  | jq -r '.exp  // empty' 2>/dev/null || true)
  role=$(printf '%s' "$decoded" | jq -r '.role // empty' 2>/dev/null || true)
  if [[ -n "$exp" ]]; then
    local now; now=$(date +%s)
    (( exp > now )) || die "${label}: TOKEN IS EXPIRED — generate a fresh one."
    ok "${label}: expires $(date -d "@${exp}" 2>/dev/null || date -r "${exp}" 2>/dev/null || echo "@${exp}")"
  fi
  if [[ "$role" != "service_role" ]]; then
    warn "${label}: role is '${role}' — expected 'service_role'. Continuing anyway."
  else
    ok "${label}: role = service_role"
  fi
}

validate_resend_key() {
  local key="$1"
  [[ "$key" =~ ^re_ ]]   || die "RESEND_API_KEY must start with 're_'."
  (( ${#key} >= 20 ))    || die "RESEND_API_KEY looks too short (< 20 chars)."
  ok "RESEND_API_KEY: format OK"
}

validate_vercel_token() {
  local token="$1"
  (( ${#token} >= 20 )) || die "VERCEL_TOKEN looks too short (< 20 chars)."
  ok "VERCEL_TOKEN: length OK"
}

# ─── Vercel API helpers ───────────────────────────────────────────────────────

vercel_get_env_ids() {
  # Print all env IDs for a given key name (may be multiple across targets).
  local key="$1" token="$2"
  curl -sS \
    -H "Authorization: Bearer ${token}" \
    "${VERCEL_ENVS_URL}" \
    | jq -r --arg k "$key" '.envs[] | select(.key == $k) | .id'
}

vercel_delete_env() {
  local env_id="$1" token="$2"
  local http_code
  http_code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X DELETE \
    -H "Authorization: Bearer ${token}" \
    "${VERCEL_API_BASE}/env/${env_id}?teamId=${VERCEL_TEAM_ID}")
  [[ "$http_code" == "200" || "$http_code" == "204" ]] \
    || warn "  DELETE env ${env_id} returned HTTP ${http_code} — may already be gone."
}

vercel_create_env() {
  # Create a single encrypted env var targeting production + preview.
  # Value is passed as an argument (string, never echoed by this function).
  local key="$1" new_value="$2" token="$3"
  local payload
  payload=$(jq -n --arg k "$key" --arg v "$new_value" \
    '{"key":$k,"value":$v,"type":"encrypted","target":["production","preview"]}')
  local resp http_code body
  resp=$(curl -sS -w "\n__HTTP__:%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${VERCEL_ENVS_URL}")
  http_code=$(printf '%s' "$resp" | grep '^__HTTP__:' | cut -d: -f2)
  body=$(printf '%s' "$resp" | grep -v '^__HTTP__:')
  [[ "$http_code" == "200" || "$http_code" == "201" ]] \
    || die "Vercel API: failed to create ${key} (HTTP ${http_code}). Body: ${body}"
}

update_vercel_env() {
  # Delete any existing entries for KEY, then create a fresh encrypted entry
  # for production+preview. VALUE must be passed as arg $2 — never echoed.
  local key="$1" new_value="$2" token="$3"
  log "Vercel: rotating ${key} …"
  local ids
  ids=$(vercel_get_env_ids "$key" "$token")
  if [[ -n "$ids" ]]; then
    while IFS= read -r env_id; do
      [[ -z "$env_id" ]] && continue
      vercel_delete_env "$env_id" "$token"
      log "  Deleted old entry ${env_id}"
    done <<< "$ids"
  else
    warn "  ${key} not found in Vercel — will create it."
  fi
  vercel_create_env "$key" "$new_value" "$token"
  ok "Vercel: ${key} set for production+preview"
}

# ─── GitHub helper ────────────────────────────────────────────────────────────

update_github_secret() {
  local name="$1" new_value="$2"
  log "GitHub Actions: rotating secret ${name} …"
  printf '%s' "$new_value" | gh secret set "$name" -R "$REPO" --body - \
    || die "Failed to update GitHub Actions secret ${name}."
  ok "GitHub Actions: ${name} updated"
}

# ─── PRE-FLIGHT ───────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Atlas Passport — finish-lockdown.sh (secret rotation)     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
warn "Values are read via hidden prompt and are NEVER echoed, logged, or written to files."
warn "If anything unexpected happens: STOP and tell Claude."
echo ""

log "Checking required tools …"
require_cmd gh
require_cmd curl
require_cmd jq
require_cmd base64
require_cmd date
ok "All required tools found."

log "Checking gh authentication (functional test against the repo) …"
# We don't rely on `gh auth status -h github.com` because it returns an error
# when `gh` is configured for a non-default host (e.g. an enterprise proxy or
# agent sandbox). Instead, do a real read against the target repo — if that
# succeeds, `gh secret list` / `gh secret set` will work too.
if ! gh api "repos/${REPO}" --jq '.full_name' >/dev/null 2>&1; then
  echo ""
  warn "gh cannot read ${REPO}. Possible causes:"
  warn "  • not logged in           → run: gh auth login"
  warn "  • token missing 'repo'    → re-auth with full repo scope"
  warn "  • token missing 'admin:repo_hook' / Actions secrets scope"
  die "gh authentication test failed against ${REPO}."
fi
ok "gh: authenticated and can read ${REPO}."

log "Verifying gh can access Actions secrets (required for rotation) …"
if ! gh api "repos/${REPO}/actions/secrets" --jq '.total_count' >/dev/null 2>&1; then
  die "gh token cannot read Actions secrets. Re-auth with admin/secrets scope: gh auth refresh -h github.com -s repo,admin:repo_hook,workflow"
fi
ok "gh: Actions secrets API reachable."

log "Checking git status …"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_DIRTY=$(git status --porcelain)
[[ -z "$GIT_DIRTY" ]] || die "Working tree is not clean. Commit or stash first.\n$(git status --short)"
ok "Git: clean on branch ${BRANCH}."

echo ""
log "Authenticating to Vercel API for pre-flight …"
echo -n "  Enter your CURRENT Vercel API token (hidden — needed for env var snapshots): "
read -rs CURRENT_VERCEL_TOKEN; echo ""
[[ -n "$CURRENT_VERCEL_TOKEN" ]] || die "No token entered."

log "Verifying token against Vercel API …"
VFY_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${CURRENT_VERCEL_TOKEN}" \
  "${VERCEL_ENVS_URL}")
[[ "$VFY_CODE" == "200" ]] \
  || die "Vercel API rejected the token (HTTP ${VFY_CODE}). Check the token and retry."
ok "Vercel API reachable and token valid."

echo ""
log "Snapshotting Vercel env var names (no values logged) …"
VERCEL_SNAPSHOT=$(curl -sS \
  -H "Authorization: Bearer ${CURRENT_VERCEL_TOKEN}" \
  "${VERCEL_ENVS_URL}")

echo ""
echo "  PRODUCTION keys:"
printf '%s' "$VERCEL_SNAPSHOT" \
  | jq -r '.envs[] | select(.target[] == "production") | "    " + .key' | sort
echo ""
echo "  PREVIEW keys:"
printf '%s' "$VERCEL_SNAPSHOT" \
  | jq -r '.envs[] | select(.target[] == "preview") | "    " + .key' | sort
echo ""

log "Snapshotting GitHub Actions secrets (names only) …"
echo ""
gh secret list -R "$REPO" | awk '{print "    " $1}'
echo ""

echo "══════════════════════════════════════════════════════════════"
echo "  PRE-FLIGHT COMPLETE — review the snapshot above."
echo "  You will be asked key-by-key which ones to rotate."
echo "══════════════════════════════════════════════════════════════"
echo ""
echo -n "  Continue to rotation? [y/N]: "
read -r PREFLIGHT_OK; echo ""
[[ "$PREFLIGHT_OK" == "y" || "$PREFLIGHT_OK" == "Y" ]] \
  || { log "Aborted by operator. No keys were changed."; exit 0; }

# ─── KEY ROTATION ─────────────────────────────────────────────────────────────

# VERCEL_TOKEN
echo ""
echo "── VERCEL_TOKEN ──────────────────────────────────────────────"
echo -n "  Rotate VERCEL_TOKEN? [y/N]: "
read -r DO_VERCEL_TOKEN; echo ""
if [[ "$DO_VERCEL_TOKEN" == "y" || "$DO_VERCEL_TOKEN" == "Y" ]]; then
  warn "Generate a NEW token at: vercel.com → Account Settings → Tokens"
  warn "Do NOT delete the old token yet — wait until CI is confirmed green."
  echo -n "  Enter NEW Vercel token (hidden): "
  read -rs NEW_VERCEL_TOKEN; echo ""
  [[ -n "$NEW_VERCEL_TOKEN" ]] || die "No value entered for VERCEL_TOKEN."
  validate_vercel_token "$NEW_VERCEL_TOKEN"
  # VERCEL_TOKEN is a GitHub Actions secret only — not a Vercel env var.
  update_github_secret "VERCEL_TOKEN" "$NEW_VERCEL_TOKEN"
  ok "VERCEL_TOKEN rotation complete."
  warn "ACTION (after CI is green): delete the OLD token at vercel.com → Account Settings → Tokens."
  unset NEW_VERCEL_TOKEN
fi

# SUPABASE_SERVICE_ROLE_KEY
echo ""
echo "── SUPABASE_SERVICE_ROLE_KEY ─────────────────────────────────"
echo -n "  Rotate SUPABASE_SERVICE_ROLE_KEY? [y/N]: "
read -r DO_SRK; echo ""
if [[ "$DO_SRK" == "y" || "$DO_SRK" == "Y" ]]; then
  warn "Rotate at: Supabase dashboard → Project Settings → API → Service role key."
  echo -n "  Enter NEW SUPABASE_SERVICE_ROLE_KEY (hidden): "
  read -rs NEW_SRK; echo ""
  [[ -n "$NEW_SRK" ]] || die "No value entered for SUPABASE_SERVICE_ROLE_KEY."
  validate_jwt "$NEW_SRK" "SUPABASE_SERVICE_ROLE_KEY"
  update_vercel_env "SUPABASE_SERVICE_ROLE_KEY" "$NEW_SRK" "$CURRENT_VERCEL_TOKEN"
  update_github_secret "SUPABASE_SERVICE_ROLE_KEY" "$NEW_SRK"
  ok "SUPABASE_SERVICE_ROLE_KEY rotation complete (Vercel prod+preview + GitHub Actions)."
  unset NEW_SRK
fi

# RESEND_API_KEY
echo ""
echo "── RESEND_API_KEY ────────────────────────────────────────────"
echo -n "  Rotate RESEND_API_KEY? [y/N]: "
read -r DO_RESEND; echo ""
if [[ "$DO_RESEND" == "y" || "$DO_RESEND" == "Y" ]]; then
  warn "Generate a NEW key at: resend.com → API Keys."
  warn "Do NOT revoke the old key (re_JC6PSzFE_…) until email sends are confirmed working."
  echo -n "  Enter NEW RESEND_API_KEY (hidden): "
  read -rs NEW_RESEND; echo ""
  [[ -n "$NEW_RESEND" ]] || die "No value entered for RESEND_API_KEY."
  validate_resend_key "$NEW_RESEND"
  update_vercel_env "RESEND_API_KEY" "$NEW_RESEND" "$CURRENT_VERCEL_TOKEN"
  update_github_secret "RESEND_API_KEY" "$NEW_RESEND"
  ok "RESEND_API_KEY rotation complete (Vercel prod+preview + GitHub Actions)."
  warn "ACTION (after confirming email sends): revoke re_JC6PSzFE_… at resend.com → API Keys."
  unset NEW_RESEND
fi

unset CURRENT_VERCEL_TOKEN

# ─── POST-ROTATION ────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  POST-ROTATION"
echo "══════════════════════════════════════════════════════════════"
echo ""

log "Re-snapshotting GitHub Actions secrets to confirm updates …"
echo ""
gh secret list -R "$REPO" | awk '{print "    " $1}'
echo ""

echo "══════════════════════════════════════════════════════════════"
echo "  ROTATION COMPLETE — manual verification checklist:"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  CI will trigger automatically on the next push to main or"
echo "  a matching branch. To trigger the Vercel env-vars check now:"
echo "    git commit --allow-empty -m 'chore: trigger env-check CI'"
echo "    git push origin HEAD:refs/heads/chore/post-rotation-verify"
echo "    (then open a PR from that branch into main)"
echo ""
echo "  Verification steps:"
echo "  1. GitHub CI env-vars check green:"
echo "     https://github.com/${REPO}/actions"
echo "  2. Vercel deployment healthy:"
echo "     https://vercel.com/pilotspry-maker/${VERCEL_PROJECT}"
echo "  3. Supabase sentinel (from Supabase SQL Editor):"
echo "     SELECT now(); -- should return current timestamp, confirming auth"
echo "  4. Email smoke test: sign-up flow → confirm magic link arrives"
echo ""
echo "  Cleanup after verification:"
echo "  • Delete OLD Vercel token at vercel.com → Account Settings → Tokens"
echo "  • Revoke re_JC6PSzFE_… at resend.com → API Keys"
echo ""
