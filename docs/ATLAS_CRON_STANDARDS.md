# Atlas Cron Standards — Cheat Sheet

**One page. Read before creating any new Atlas Passport cron, Perplexity Computer scheduled task, or Vercel cron.** For the full incident history and underlying spec, see [`CRON_NO_CREDENTIAL_PROMPT_GUARDRAIL.md`](./CRON_NO_CREDENTIAL_PROMPT_GUARDRAIL.md).

---

## 1. Hard rules (non-negotiable)

Every cron task body — Perplexity Computer or otherwise — MUST start with this block:

```
HARD RULES (do not violate):
- NEVER call request_credential or open a custom-credential / "Add credential" form.
  If a step would need a token not already provided via api_credentials or a
  connected connector, mark the step "skipped (no credential available)" in the
  report and continue. Do not pause for user input.
- Auth comes ONLY from: api_credentials=["github"] for gh, api_credentials=["vercel"]
  for vercel CLI, and the connected Supabase connector for Supabase work.
- Do NOT hit third-party REST APIs with a manual bearer token. Use the connector
  if one exists; otherwise skip and log under "Auth-blocked checks".
- On 401/403, log under "Auth-blocked checks" and continue. Never escalate mid-run.
```

And the notification body MUST include a final section:
```
N. Auth-blocked checks (list any step skipped due to a missing credential)
```

**Why:** see issue [#43](https://github.com/pilotspry-maker/Atlas-Passport/issues/43). One missing rule = the cron pauses on your phone at midnight.

---

## 2. GitHub-native authentication pattern

Use the GitHub connector for all GitHub work, never inline tokens. The same pattern applies to Vercel and Supabase.

| Service  | Right way                                              | Wrong way                            |
|----------|--------------------------------------------------------|--------------------------------------|
| GitHub   | `gh` CLI with `api_credentials=["github"]`             | Hand-pasted `GITHUB_TOKEN` in script |
| Vercel   | `vercel ls --scope ramon-spry` with `api_credentials=["vercel"]` | `vercel ls --token $VERCEL_TOKEN`    |
| Supabase | Supabase MCP tools (`list_tables`, `get_logs`, etc.)    | Direct `psql` with `SUPABASE_DB_URL` |
| Slack    | Comment on a GitHub issue — Slack bridge fans it in    | Direct Slack API call with a token   |
| Resend / other third-party | Check `list_external_tools` first; skip if not CONNECTED | Hardcode `RESEND_API_KEY` in the task |

**Fallback chain when Vercel CLI auth-fails:**
1. Retry `vercel ls atlas-passport --scope ramon-spry` (no `--token`)
2. Fall back to `gh api repos/pilotspry-maker/Atlas-Passport/deployments?per_page=3`
3. Log "Vercel CLI auth-blocked" under Auth-blocked checks and continue

---

## 3. Mandatory high-alert skip date integration

When the app enters high-alert mode (post-launch, post-incident, post-migration), monitoring crons MUST stand down — otherwise they false-alarm during a window where the underlying checks are intentionally suppressed.

**Every monitoring cron must include this line at the top of its task body:**
```
Skip the run if today's date is on or before YYYY-MM-DD (high-alert mode is still
active that day).
```

**Every watchdog/derivative cron that observes a monitoring cron** must regex-extract `YYYY-MM-DD` from the parent's task body and stand down on the same date. Don't hard-code it twice — read it from the source of truth.

Example regex (Python): `r"on or before (\d{4}-\d{2}-\d{2})"`

When high-alert mode ends, **delete the line** from the parent cron. Watchdogs auto-resume.

---

## 4. Staging-before-main procedure

Atlas Passport uses **Vercel Preview deployments per PR** as its staging environment. There is no separate `staging` branch. Every PR gets a unique preview URL with the `preview` Vercel target.

**For any new cron, workflow, or migration:**

1. **Branch off main:** `git checkout -b feat/<short-name>` or `ops/<short-name>`.
2. **For Perplexity Computer crons:** create the cron with `cross_session=false` and run it manually once from the owning thread before letting it auto-fire. Confirm `Auth-blocked checks` section is empty.
3. **For Vercel crons (`vercel.json`) or GitHub workflows:** open a PR. Vercel auto-builds a preview deploy targeting the `preview` env. The CI workflow (`ci.yml`) runs on `pull_request` to `main`.
4. **Verify against the preview URL,** not production:
   - Preview URL pattern: `https://atlas-passport-git-<branch>-ramon-spry.vercel.app`
   - Required env vars are mirrored in `preview` target per `.github/workflows/check-env-vars.yml`. If new vars are needed, add them to BOTH `production` and `preview` Vercel targets before merging.
5. **Required CI to pass before merge:**
   - `ci.yml` (lint + build + unit tests)
   - `check-env-vars.yml` (env parity)
   - `rls-regression.yml` (RLS still enforced)
   - `rls-exploit-tests.yml` (no new holes)
6. **Squash-merge to `main`.** Vercel auto-deploys production. The `Atlas Passport post-merge health check` cron (`9bbfdf96`) fires within 5 minutes and reports on the merged commit.
7. **Watch issue #43 the next morning at 9:30 AM ET.** The guardrail watchdog (`76006630`) silently confirms the run was clean — or posts a comment if anything tripped.

**Hot-fixing main without a PR is forbidden.** RLS or env changes can break the daily cron quietly.

---

## 5. Cron checklist (copy this into your PR description)

- [ ] HARD RULES block at the top of the task body
- [ ] No `--token $VERCEL_TOKEN` or hand-coded `Authorization: Bearer` headers
- [ ] `list_external_tools` called before assuming a third-party connector is available
- [ ] Notification body has a final "Auth-blocked checks" section
- [ ] `api_credentials=[...]` set on every shell call needing auth
- [ ] High-alert skip line included if cron is on a monitoring path
- [ ] Manual test run from the owning thread completed cleanly
- [ ] If Vercel/Supabase env vars added: confirmed in both `production` and `preview` targets
- [ ] Silent on green; only notifies on real failures or auth-blocks

---

## 6. Quick reference — known crons (as of 2026-06-29)

| ID         | Name                                | Cadence              | Owner thread |
|------------|-------------------------------------|----------------------|--------------|
| `95b287f1` | Daily Bug Cleanse                   | 9 AM ET daily        | `4d84762a`   |
| `cd7c6c7e` | Daily health check                  | 9 AM ET daily        | `2ff492c8`   |
| `9bbfdf96` | Post-merge health check             | Per main commit (5min poll) | `2ff492c8` |
| `092fd773` | RLS Security Monitor                | 9 AM ET weekdays     | `076bf69e`   |
| `f7217a76` | Morning Briefing                    | 9 AM ET weekdays     | `076bf69e`   |
| `76006630` | Guardrail watchdog                  | 9:30 AM ET weekdays  | this repo    |
| `5564cd09` | Weekly guardrail summary            | Fri 5 PM ET          | this repo    |

To list all crons across all threads: `pplx-tool schedule_cron` with `action=list, cross_session=true`.

---

*Maintainer: Ramon · Last updated 2026-06-29 · One-page rule: if this grows past two screens, split it.*
