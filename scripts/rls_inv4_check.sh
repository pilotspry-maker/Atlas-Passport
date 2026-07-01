#!/usr/bin/env bash
# scripts/rls_inv4_check.sh
# Standalone INV-4 check for public.passports UPDATE policies.
# Called by .github/workflows/rls-inv4-check.yml
#
# Required env: SUPABASE_DB_URL, SLACK_WEBHOOK_URL
# Optional env: GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID
#
# Exit codes:
#   0 — clean (no Slack post) OR HIGH-only deviation (Slack posted)
#   1 — CRITICAL deviation detected (Slack posted, job shows red)
#
# No set -x. No secrets printed to stdout/stderr.
set -euo pipefail

RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-pilotspry-maker/atlas-passport}/actions/runs/${GITHUB_RUN_ID:-0}"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

_redact() { printf '%s' "$1" | sed -E 's#(://[^:@]+:)[^@]+(@)#\1****\2#g'; }

_slack_post() {
  local color="$1"
  local title="$2"
  local body="$3"

  local payload
  payload=$(jq -n -c \
    --arg color  "$color" \
    --arg title  "$title" \
    --arg body   "$body" \
    --arg run    "$RUN_URL" \
    --arg footer "Atlas-Passport RLS INV-4 check · ${TIMESTAMP}" \
    '{
      text: $title,
      attachments: [{
        color: $color,
        title: $title,
        text: $body,
        actions: [{type:"button", text:"View run", url: $run}],
        footer: $footer
      }]
    }')

  local http_code
  http_code=$(curl -sS -o /tmp/slack_inv4.out -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    --data-binary "$payload" "$SLACK_WEBHOOK_URL")

  if [[ "$http_code" != "200" ]]; then
    echo "::warning::Slack post returned HTTP ${http_code}"
    cat /tmp/slack_inv4.out >&2 || true
  else
    echo "Slack post OK (HTTP ${http_code})"
  fi
}

# ── Query ──────────────────────────────────────────────────────────────────
echo "── RLS INV-4 check — ${TIMESTAMP} ──"
echo "DB: $(_redact "$SUPABASE_DB_URL")"

SQL='SELECT jsonb_build_object(
  '"'"'update_policy_count'"'"',
    (SELECT COUNT(*) FROM pg_policies
     WHERE schemaname='"'"'public'"'"' AND tablename='"'"'passports'"'"' AND cmd='"'"'UPDATE'"'"'),
  '"'"'update_policy_roles'"'"',
    (SELECT COALESCE(roles::text, '"'"'none'"'"')
     FROM pg_policies
     WHERE schemaname='"'"'public'"'"' AND tablename='"'"'passports'"'"' AND cmd='"'"'UPDATE'"'"'
     LIMIT 1),
  '"'"'qual_has_user_id'"'"',
    (SELECT COALESCE(qual LIKE '"'"'%user_id%'"'"', false)
     FROM pg_policies
     WHERE schemaname='"'"'public'"'"' AND tablename='"'"'passports'"'"' AND cmd='"'"'UPDATE'"'"'
     LIMIT 1),
  '"'"'qual_has_auth_uid'"'"',
    (SELECT COALESCE(qual LIKE '"'"'%auth.uid%'"'"', false)
     FROM pg_policies
     WHERE schemaname='"'"'public'"'"' AND tablename='"'"'passports'"'"' AND cmd='"'"'UPDATE'"'"'
     LIMIT 1),
  '"'"'with_check_has_user_id'"'"',
    (SELECT COALESCE(with_check LIKE '"'"'%user_id%'"'"', false)
     FROM pg_policies
     WHERE schemaname='"'"'public'"'"' AND tablename='"'"'passports'"'"' AND cmd='"'"'UPDATE'"'"'
     LIMIT 1),
  '"'"'with_check_has_auth_uid'"'"',
    (SELECT COALESCE(with_check LIKE '"'"'%auth.uid%'"'"', false)
     FROM pg_policies
     WHERE schemaname='"'"'public'"'"' AND tablename='"'"'passports'"'"' AND cmd='"'"'UPDATE'"'"'
     LIMIT 1),
  '"'"'anon_update_count'"'"',
    (SELECT COUNT(*) FROM pg_policies
     WHERE schemaname='"'"'public'"'"' AND tablename='"'"'passports'"'"' AND cmd='"'"'UPDATE'"'"'
     AND (roles::text LIKE '"'"'%anon%'"'"' OR roles::text LIKE '"'"'%public%'"'"')),
  '"'"'helper_exists'"'"',
    (SELECT COUNT(*) > 0 FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '"'"'public'"'"'
     AND p.proname = '"'"'committed_passport_immutables'"'"'
     AND p.prosecdef = true)
);'

result=""
if ! result=$(psql "$SUPABASE_DB_URL" -tA -c "$SQL" 2>/tmp/psql_inv4_err.txt); then
  err=$(cat /tmp/psql_inv4_err.txt | head -c 400 || true)
  echo "::error::psql failed — cannot verify invariants"
  _slack_post '#dc2626' \
    '🚨 CRITICAL — Atlas-Passport RLS INV-4 check failed' \
    "psql could not connect to the database or query failed.\n\nError (redacted):\n\`$(printf '%s' "$err" | sed -E 's#(://[^:@]+:)[^@]+(@)#\1****\2#g' | head -c 300)\`\n\nRun: ${RUN_URL}"
  exit 1
fi

if [[ -z "$result" ]] || ! printf '%s' "$result" | jq -e . >/dev/null 2>&1; then
  echo "::error::psql returned non-JSON output: $(printf '%s' "$result" | head -c 100)"
  _slack_post '#dc2626' \
    '🚨 CRITICAL — Atlas-Passport RLS INV-4 check: unexpected psql output' \
    "psql returned empty or non-JSON output — cannot verify invariants.\n\nOutput: \`$(printf '%s' "$result" | head -c 200)\`\n\nRun: ${RUN_URL}"
  exit 1
fi

echo "psql OK. Parsing assertions..."

# ── Parse assertions ────────────────────────────────────────────────────────
count=$(printf '%s' "$result"      | jq -r '.update_policy_count')
roles=$(printf '%s' "$result"      | jq -r '.update_policy_roles // "none"')
qual_uid=$(printf '%s' "$result"   | jq -r '.qual_has_user_id')
qual_auth=$(printf '%s' "$result"  | jq -r '.qual_has_auth_uid')
wc_uid=$(printf '%s' "$result"     | jq -r '.with_check_has_user_id')
wc_auth=$(printf '%s' "$result"    | jq -r '.with_check_has_auth_uid')
anon_count=$(printf '%s' "$result" | jq -r '.anon_update_count')
helper=$(printf '%s' "$result"     | jq -r '.helper_exists')

critical_findings=()
high_findings=()

# INV-4 assertions 1-5 (CRITICAL class)

# 1. Exactly one UPDATE policy
if [[ "$count" != "1" ]]; then
  critical_findings+=("*INV-4 #1* Expected exactly 1 UPDATE policy on passports, found \`${count}\`")
fi

# 2. That policy has roles = {authenticated}
if [[ "$count" == "1" && "$roles" != "{authenticated}" ]]; then
  critical_findings+=("*INV-4 #2* UPDATE policy roles = \`${roles}\`, expected \`{authenticated}\`")
fi

# 3. qual contains user_id AND auth.uid
if [[ "$qual_uid" != "true" ]]; then
  critical_findings+=("*INV-4 #3* UPDATE policy USING does not contain \`user_id\`")
fi
if [[ "$qual_auth" != "true" ]]; then
  critical_findings+=("*INV-4 #3* UPDATE policy USING does not contain \`auth.uid\`")
fi

# 4. with_check contains user_id AND auth.uid
if [[ "$wc_uid" != "true" ]]; then
  critical_findings+=("*INV-4 #4* UPDATE policy WITH CHECK does not contain \`user_id\`")
fi
if [[ "$wc_auth" != "true" ]]; then
  critical_findings+=("*INV-4 #4* UPDATE policy WITH CHECK does not contain \`auth.uid\`")
fi

# 5. No anon/public UPDATE policy
if [[ "$anon_count" != "0" ]]; then
  critical_findings+=("*INV-4 #5 EXPLOIT CLASS* anon/public UPDATE policy found on passports (count=${anon_count})")
fi

# 6. Helper function exists (HIGH only)
if [[ "$helper" != "true" ]]; then
  high_findings+=("*INV-4 #6* SECURITY DEFINER helper \`public.committed_passport_immutables(uuid)\` not found — migration 043 may not be applied")
fi

# ── Silent exit if clean ────────────────────────────────────────────────────
total=$(( ${#critical_findings[@]} + ${#high_findings[@]} ))
if [[ "$total" -eq 0 ]]; then
  echo "All INV-4 assertions passed. Exiting silently."
  exit 0
fi

echo "Deviations: ${#critical_findings[@]} CRITICAL, ${#high_findings[@]} HIGH"

# ── Post to Slack ────────────────────────────────────────────────────────────
if [[ ${#critical_findings[@]} -gt 0 ]]; then
  color='#dc2626'
  header='🚨 CRITICAL — Atlas-Passport RLS INV-4 deviation'
else
  color='#f59e0b'
  header='⚠️ HIGH — Atlas-Passport RLS INV-4 deviation'
fi

body_lines=()
for f in "${critical_findings[@]}"; do body_lines+=("$f"); done
for f in "${high_findings[@]}";     do body_lines+=("$f"); done

body=$(printf '• %s\n' "${body_lines[@]}")
body+="$(printf '\n\nRun: %s' "$RUN_URL")"

_slack_post "$color" "$header" "$body"

# ── Exit code ────────────────────────────────────────────────────────────────
if [[ ${#critical_findings[@]} -gt 0 ]]; then
  echo "::error::${header}"
  exit 1
fi
# HIGH only → exit 0 (Slack posted above)
exit 0
