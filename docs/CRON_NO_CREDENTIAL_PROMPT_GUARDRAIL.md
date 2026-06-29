# Atlas Passport Cron Guardrail — Never Prompt For Credentials

**Date added:** 2026-06-29
**Owner:** Ramon (pilotspry@gmail.com)
**Related incident:** Nightly "Atlas Passport — Daily Bug Cleanse (9 AM EDT)" run paused waiting for a custom Bearer token on the user's phone at 11:55 PM EDT on 2026-06-28. The agent had improvised an HTTP call that wanted a token, opened the in-app "Add credential" form, and blocked the whole run until manually dismissed.

## What went wrong

The Daily Bug Cleanse task body did not forbid the agent from opening a credential form. When step 6 (Vercel deployment check) or step 7 (Resend delivery check) hit an unauthenticated path, the agent decided the right next move was to ask the user for a token via `request_credential`. That paused the cron mid-run, which:

1. Made the morning report late / missing.
2. Required manual intervention from a phone at midnight.
3. Would repeat every 24h on the same cron schedule unless the task body itself was fixed.

The same `$VERCEL_TOKEN` reference pattern existed in two other Atlas Passport crons (`cd7c6c7e` daily health check, `9bbfdf96` post-merge health check), so those were patched preemptively.

## The guardrail

Every Atlas Passport monitoring/health-check cron MUST include this block at the top of its task body:

```
HARD RULES (do not violate):
- NEVER call request_credential or open a custom-credential / "Add credential" form. If any step would need a token/key that is not already provided via api_credentials or a connected connector, mark that step as "skipped (no credential available)" in the report and continue. Do not pause for user input.
- Only use these auth sources:
    * api_credentials=["github"] for the gh CLI
    * api_credentials=["vercel"] for the vercel CLI
    * the connected Supabase connector (supabase MCP tools) for all Supabase work
    * connected Pipedream connectors (e.g. resend__pipedream) ONLY if list_external_tools shows them as CONNECTED
- Do NOT hit third-party REST APIs with a manual bearer token. Use the connector if one exists; otherwise skip the step and log it under "Auth-blocked checks" in the report.
- If any step returns 401/403 or any auth error, log it under "Auth-blocked checks" and continue. Never escalate to the user mid-run.
```

And the notification body MUST include a final section:

```
12. Auth-blocked checks (list any step that was skipped due to a missing credential)
```

## Vercel-specific rule

Drop explicit `--token $VERCEL_TOKEN` arguments from `vercel ls` / `vercel inspect`. With `api_credentials=["vercel"]`, auth is injected by the runner. The explicit token reference was the foothold that let the agent improvise toward a credential prompt when the env var came up empty.

Fallback chain when Vercel CLI auth-fails:
1. Retry `vercel ls atlas-passport --scope ramon-spry` with `api_credentials=["vercel"]`, no `--token`.
2. If still auth-blocked, fall back to `gh api repos/pilotspry-maker/Atlas-Passport/deployments?per_page=3` (deployments mirror).
3. If both fail, log "Vercel CLI auth-blocked" under Auth-blocked checks and continue. Do NOT prompt.

## Crons covered by this guardrail (as of 2026-06-29)

| ID | Name | Status |
|---|---|---|
| `95b287f1` | Atlas Passport — Daily Bug Cleanse (9 AM EDT) | Patched 2026-06-29 |
| `cd7c6c7e` | Atlas Passport daily health check | Patched 2026-06-29 |
| `9bbfdf96` | Atlas Passport post-merge health check | Patched 2026-06-29 |
| `092fd773` | Atlas Passport RLS Security Monitor | Already clean (github-only) |
| `f7217a76` | Atlas Passport Morning Briefing | Already clean (github-only) |
| `a16d885e`, `c6796cfe`, `d6650dd0` | High-Alert Checks #2/#3/#4 | One-shot, window ends 2026-06-29; not patched |

## Future cron checklist

Before creating any new Atlas Passport cron:

- [ ] HARD RULES block is at the top of the task body
- [ ] No explicit `--token $VERCEL_TOKEN` or hand-coded `Authorization: Bearer` headers
- [ ] `list_external_tools` is called before assuming a third-party connector (Resend, etc.) is available
- [ ] Notification body has an "Auth-blocked checks" section
- [ ] `api_credentials=[...]` is set on every shell call that needs auth (github, vercel)
- [ ] Run silently on green; only notify on real failures or auth-blocks worth knowing about

## How to verify the guardrail works

Run any of the patched crons manually from its owning thread:

```
Run cron <id> now and show me the report.
```

The report should reach step 13 (or end silently) without ever opening a credential form. If a credential form appears, the HARD RULES block didn't take — re-paste it.
