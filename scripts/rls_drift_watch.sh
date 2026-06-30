#!/usr/bin/env bash
# scripts/rls_drift_watch.sh — weekday RLS-drift watch
# Called by .github/workflows/rls-drift-watch.yml
# Required env: SUPABASE_DB_URL, SLACK_WEBHOOK_URL, GH_TOKEN
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-pilotspry-maker/atlas-passport}"
SOURCE_THREAD="https://www.perplexity.ai/computer/tasks/ce8f2629-9d75-42fa-ba38-1a652ecc6c6b"

redacted_url() { printf '%s' "$1" | sed -E 's#(://[^:]+:)[^@]+@#\1****@#'; }

echo "── RLS drift watch — $(date -u +%FT%TZ) ──"
echo "DB target: $(redacted_url "$SUPABASE_DB_URL")"

findings=()
has_critical=false

# ── CHECK 1: Main-branch RLS workflow run status ────────────────────────────
echo ""
echo "CHECK 1: Main-branch RLS workflow run status"

runs_json=$(gh run list \
  -R "$REPO" \
  --branch main \
  -L 20 \
  --json databaseId,name,event,status,conclusion,headSha,url 2>&1) || {
  findings+=("CHECK1 ERROR: gh run list failed — ${runs_json:-unknown error}")
  runs_json='[]'
}

declare -A seen_workflow

while IFS= read -r run; do
  name=$(printf '%s' "$run"    | jq -r '.name')
  conclusion=$(printf '%s' "$run" | jq -r '.conclusion // ""')
  url=$(printf '%s' "$run"     | jq -r '.url')
  event=$(printf '%s' "$run"   | jq -r '.event')

  # Only check push/schedule/workflow_dispatch events
  case "$event" in push|schedule|workflow_dispatch) ;; *) continue ;; esac

  # Only the most recent run per workflow name
  [[ -n "${seen_workflow[$name]+set}" ]] && continue
  seen_workflow["$name"]=1

  case "$conclusion" in
    failure|timed_out|cancelled)
      run_id=$(printf '%s' "$run" | jq -r '.databaseId')
      log_excerpt=""
      failing_job_id=$(gh run view "$run_id" -R "$REPO" --json jobs \
        --jq '[.jobs[] | select(.conclusion == "failure")] | .[0].databaseId // ""' \
        2>/dev/null || true)
      if [[ -n "$failing_job_id" ]]; then
        log_excerpt=$(gh run view --log --job "$failing_job_id" -R "$REPO" 2>/dev/null \
          | grep -Em1 'EXPLOIT LIVE|##\[error\]|^Error:|^FAIL' \
          | cut -c1-400 || true)
      fi
      if [[ -n "$log_excerpt" ]]; then
        findings+=("CHECK1 *${name}*: last run \`${conclusion}\` — <${url}|view run> — \`${log_excerpt}\`")
      else
        findings+=("CHECK1 *${name}*: last run \`${conclusion}\` — <${url}|view run>")
      fi
      ;;
  esac
done < <(printf '%s' "$runs_json" \
  | jq -c '.[] | select(.name | test("RLS|Verify RLS"; "i"))')

echo "CHECK 1 done (${#findings[@]} finding(s) so far)"

# ── CHECK 2: Policy-definition drift via psql ──────────────────────────────
echo ""
echo "CHECK 2: Policy-definition drift"

psql_out=$(psql "$SUPABASE_DB_URL" -At -F'|' -c "
  select schemaname, tablename, policyname, cmd, roles::text,
         coalesce(qual,''), coalesce(with_check,'')
  from pg_policies
  where (schemaname='public' and tablename in
          ('ap_events','referral_events','waitlist_entries','passports'))
     or (schemaname='corridor' and tablename in ('audit_log','jobs'))
     or (schemaname='storage' and tablename='objects'
         and policyname ilike '%corridor_covers%')
  order by schemaname, tablename, cmd, policyname;" 2>&1) || {
  findings+=("CHECK2 ERROR: psql query failed — $(printf '%s' "$psql_out" | head -c 300)")
  psql_out=""
}

declare -A inv5_service_seen  # key=tablename → 1 when service_role ALL policy seen

while IFS='|' read -r schema tbl policy cmd roles qual with_check; do
  [[ -z "$schema" ]] && continue

  case "${schema}.${tbl}" in

    # INV-1: ap_events INSERT must be service_role + with_check='true'; no UPDATE/DELETE
    public.ap_events)
      if [[ "$cmd" == "INSERT" ]]; then
        if [[ "$roles" != "{service_role}" || "$with_check" != "true" ]]; then
          findings+=("INV-1 *ap_events* INSERT \`${policy}\`: want roles={service_role} with_check=true, got roles=${roles} with_check=${with_check:0:80}")
        fi
      elif [[ "$cmd" == "UPDATE" || "$cmd" == "DELETE" ]]; then
        findings+=("INV-1 *ap_events* unexpected ${cmd} policy \`${policy}\`")
      fi
      ;;

    # INV-2: referral_events same contract as INV-1
    public.referral_events)
      if [[ "$cmd" == "INSERT" ]]; then
        if [[ "$roles" != "{service_role}" || "$with_check" != "true" ]]; then
          findings+=("INV-2 *referral_events* INSERT \`${policy}\`: want roles={service_role} with_check=true, got roles=${roles} with_check=${with_check:0:80}")
        fi
      elif [[ "$cmd" == "UPDATE" || "$cmd" == "DELETE" ]]; then
        findings+=("INV-2 *referral_events* unexpected ${cmd} policy \`${policy}\`")
      fi
      ;;

    # INV-3: waitlist_entries INSERT — roles={anon}, with_check must not be bare 'true'
    public.waitlist_entries)
      if [[ "$cmd" == "INSERT" ]]; then
        if [[ "$roles" != "{anon}" || "$with_check" == "true" ]]; then
          findings+=("INV-3 *waitlist_entries* INSERT \`${policy}\`: unexpected shape — roles=${roles} with_check=${with_check:0:80}")
        fi
      elif [[ "$cmd" == "UPDATE" || "$cmd" == "DELETE" ]]; then
        findings+=("INV-3 *waitlist_entries* unexpected ${cmd} policy \`${policy}\`")
      fi
      ;;

    # INV-4 (CRITICAL CLASS): passports UPDATE
    public.passports)
      if [[ "$cmd" == "UPDATE" ]]; then
        if [[ "$roles" != "{authenticated}" && "$roles" != "{service_role}" ]]; then
          findings+=("CRITICAL INV-4 *passports* UPDATE \`${policy}\`: anon/public UPDATE — roles=${roles}")
          has_critical=true
        elif [[ "$roles" == "{authenticated}" ]]; then
          # qual + with_check must both reference user_id and auth.uid
          q_ok=true; w_ok=true
          if ! printf '%s' "$qual" | grep -q 'user_id' || ! printf '%s' "$qual" | grep -q 'auth\.uid'; then
            q_ok=false
          fi
          if ! printf '%s' "$with_check" | grep -q 'user_id' || ! printf '%s' "$with_check" | grep -q 'auth\.uid'; then
            w_ok=false
          fi
          if [[ "$q_ok" == "false" || "$w_ok" == "false" ]]; then
            findings+=("INV-4 *passports* UPDATE \`${policy}\`: missing user_id/auth.uid in qual(${q_ok}) or with_check(${w_ok})")
          fi
        fi
      fi
      ;;

    # INV-5: corridor.audit_log + corridor.jobs need ≥1 service_role ALL; non-service_role = deviation
    corridor.audit_log|corridor.jobs)
      if [[ "$cmd" == "ALL" && "$roles" == "{service_role}" ]]; then
        inv5_service_seen["$tbl"]=1
      elif [[ "$roles" != "{service_role}" ]]; then
        findings+=("INV-5 *${schema}.${tbl}* non-service_role policy \`${policy}\`: roles=${roles} cmd=${cmd}")
      fi
      ;;

    # INV-6: storage.objects corridor-covers — no list policy
    storage.objects)
      if printf '%s' "$policy" | grep -qi 'list'; then
        findings+=("INV-6 *corridor-covers* bucket listing policy detected: \`${policy}\`")
      fi
      ;;
  esac
done <<< "$psql_out"

# INV-5 coverage check — both corridor tables must have a service_role ALL policy
for tbl in audit_log jobs; do
  if [[ -z "${inv5_service_seen[$tbl]+set}" ]]; then
    findings+=("INV-5 *corridor.${tbl}*: no service_role ALL policy found — deny coverage missing")
  fi
done

echo "CHECK 2 done (${#findings[@]} finding(s) so far)"

# ── CHECK 3: Unknown new policynames on monitored tables ────────────────────
echo ""
echo "CHECK 3: Unknown policyname patterns"

# Known-good patterns for monitored tables (case-insensitive)
known_pattern='^(service_role_inserts_|passports_update_own$|passports_.*_service$|passports_select_|passports_insert_|waitlist_|corridor_.*_service$|corridor_covers_|Service inserts )'

while IFS='|' read -r schema tbl policy cmd roles qual with_check; do
  [[ -z "$schema" || -z "$policy" ]] && continue
  if ! printf '%s' "$policy" | grep -qiE "$known_pattern"; then
    findings+=("CHECK3 *${schema}.${tbl}*: unknown policy \`${policy}\` (cmd=${cmd} roles=${roles}) — operator review needed")
  fi
done <<< "$psql_out"

echo "CHECK 3 done — ${#findings[@]} total finding(s)"

# ── Silent exit if clean ─────────────────────────────────────────────────────
if [[ ${#findings[@]} -eq 0 ]]; then
  echo ""
  echo "No deviations detected. Exiting silently."
  exit 0
fi

echo ""
echo "Deviations detected: ${#findings[@]}"
printf '  - %s\n' "${findings[@]}"

# ── Build Slack payload ──────────────────────────────────────────────────────
date_str=$(date -u +%F)
header_text="Atlas Passport RLS drift — ${date_str}"
[[ "$has_critical" == "true" ]] && header_text=":rotating_light: CRITICAL — ${header_text}"

body=$(printf '• %s\n' "${findings[@]}")

payload=$(jq -n -c \
  --arg fallback "Atlas Passport RLS drift — ${date_str}: ${#findings[@]} deviation(s)" \
  --arg header "$header_text" \
  --arg body "$body" \
  --arg sop "$SOURCE_THREAD" \
  '{
    text: $fallback,
    blocks: [
      {type: "header", text: {type: "plain_text", text: $header, emoji: true}},
      {type: "section", text: {type: "mrkdwn", text: $body}},
      {type: "context", elements: [
        {type: "mrkdwn",
         text: ("Standing SOP: `docs/LAUNCH_STABILITY.md` §1 · <" + $sop + "|Source thread>")}
      ]}
    ]
  }')

http_code=$(curl -sS -o /tmp/slack.out -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  --data-binary "$payload" "$SLACK_WEBHOOK_URL")

if [[ "$http_code" != "200" ]]; then
  echo "::error::Slack post failed: HTTP ${http_code}"
  cat /tmp/slack.out
  exit 1
fi

echo "Slack post OK (HTTP ${http_code})"

if [[ "$has_critical" == "true" ]]; then
  echo "::error::Critical RLS deviation detected — INV-4 anon/public UPDATE on passports"
  exit 1
fi
