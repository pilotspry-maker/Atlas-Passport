# Approved Resend API Keys

This file is the **authoritative allowlist** of Resend API keys approved for use
in the Atlas-Passport project. The weekly audit workflow
(`.github/workflows/resend-key-audit.yml`) reads this file every Monday and
pings Slack if Resend's account contains any key not listed here.

## How this file is used

Every Monday at 13:00 UTC the audit workflow:

1. Calls `GET https://api.resend.com/api-keys` with the `RESEND_AUDIT_KEY` secret
2. Parses the YAML block below for the approved key `id`s
3. Sends a paired test email through `RESEND_API_KEY` (the production sender)
   to `AUDIT_TEST_RECIPIENT` to prove the keeper still works
4. Posts to Slack via `SLACK_WEBHOOK_URL` only if:
   - The keeper's `id` is missing from Resend's response
   - The test send returns non-2xx (the production key no longer works)
   - Resend's response contains an `id` that is **not** present in the
     `approved_keys` list below

## Editing this file

When you legitimately add or rotate a Resend API key:

1. Create the key in [Resend → API Keys](https://resend.com/api-keys)
2. Add a new entry under `approved_keys` below — include `id` (from Resend
   list response), `name`, `purpose`, `added_by`, `added_on`, and `fingerprint`
   (first 8 chars + last 4 chars of the secret, separated by `...`)
3. Open a PR with this change
4. Once merged to `main`, the next Monday audit will treat it as approved

When you revoke a key, remove its entry. The audit will flag it as missing
only if it was the keeper — extra keys disappearing is silently fine.

## Allowlist

The block below is parsed as YAML. Do not change the `BEGIN`/`END` markers —
the workflow uses them to extract the YAML.

<!-- BEGIN_APPROVED_KEYS -->
```yaml
keeper_id: REPLACE_WITH_KEEPER_ID
keeper_fingerprint: "re_WLoeg...Qed1"
approved_keys:
  - id: REPLACE_WITH_KEEPER_ID
    name: "production-sender"
    purpose: "Production magic-link send via Supabase custom SMTP"
    fingerprint: "re_WLoeg...Qed1"
    added_by: "pilotspry-maker"
    added_on: "2026-06-04"
  - id: REPLACE_WITH_AUDIT_KEY_ID
    name: "audit-monday-cron"
    purpose: "Read-only list calls from the weekly audit workflow"
    fingerprint: "re_xxxxxxxx...xxxx"
    added_by: "pilotspry-maker"
    added_on: "2026-06-30"
```
<!-- END_APPROVED_KEYS -->

## Bootstrapping

When this file first lands on `main`, the `REPLACE_WITH_*` placeholders need
real `id` values from Resend. The repo owner should:

1. Locally run `curl -sS https://api.resend.com/api-keys -H "Authorization: Bearer $RESEND_AUDIT_KEY" | jq '.data[]'`
2. Copy the `id` for the production key (fingerprint `re_WLoeg...Qed1`) into both
   `keeper_id` and the first `approved_keys[].id`
3. Copy the `id` for the audit key into the second `approved_keys[].id`
4. Update each `fingerprint` field
5. Open a follow-up PR

Until the placeholders are replaced, the audit workflow will skip the diff
check and only run the keeper send-test (which is the most critical signal).
This avoids spurious Slack pings during the bootstrap window.
