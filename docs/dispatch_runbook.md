# Dispatch Runbook

**Owner:** Ramon Spry — Relevant Artist LLC
**Coworker:** Claude (via Dispatch)
**Scope:** `pilotspry-maker/Atlas-Passport`
**Last updated:** 2026-06-30
**Version:** 1.0

---

## 1. Purpose

Dispatch is an AI coworker (Claude) that attaches to the local Atlas-Passport
repo and executes engineering directives on Ramon's behalf — primarily from
mobile. This runbook defines what Dispatch is allowed to do, what it must never
do, how secrets are handled, and how work is logged and reviewed.

The goal: Dispatch operates as a fast, trustworthy execution layer while Ramon
retains all policy, deploy, and destructive-action authority.

---

## 2. Attach & environment

- **Host machine:** the machine running Dispatch must have Atlas-Passport
  cloned locally. Preferred path: `~/Projects/atlas-passport` (macOS/Linux).
- **Persistence:** Dispatch should attach to a persistent host (dedicated Mac
  mini, small VPS, or always-on dev box). Laptops that sleep are discouraged.
- **Branch discipline:** Dispatch works on feature branches by default. Direct
  work on `main` is forbidden (see §4).
- **Node / package manager:** use whatever is pinned in the repo
  (`.nvmrc`, `package.json` engines). Do not upgrade runtimes without approval.

---

## 3. Allowed operations (green light)

Dispatch may perform these without asking, provided it logs the action
(see §7):

**Code & repo**
- Read any file in the repo.
- Create, edit, or delete files on a feature branch.
- Create branches, commit, and push to feature branches.
- Open pull requests targeting `main` (never auto-merge).
- Add PR descriptions, checklists, and linked issues.
- Run linters, formatters, type checks, and unit tests locally.

**CI / build**
- Trigger CI on feature branches.
- Inspect CI logs, GitHub Actions runs, and Vercel preview builds.
- Re-run failed jobs on feature branches.

**Supabase (non-destructive)**
- Read schema via `list_tables`, `list_migrations`, `list_extensions`.
- Read logs and advisors.
- Draft new migration files (as text in the repo) — do not apply.

**Diagnostics**
- Read env var *names* (never values).
- Read `.env.example`, config files, and public keys.
- Query security advisors and dependency audits.

---

## 4. Forbidden operations (red light — require explicit Ramon approval per action)

Dispatch must stop and request approval before any of the following:

**Repo**
- Push directly to `main` or any protected branch.
- Force-push (`--force` / `--force-with-lease`) anywhere.
- Rewrite history on shared branches (rebase, squash, amend on pushed commits).
- Merge, squash-merge, or rebase-merge a PR.
- Delete branches other than its own working feature branches.
- Change repo settings, branch protection, collaborators, or webhooks.

**Secrets & credentials**
- Read, print, echo, or transmit any secret value (env vars, tokens, API keys).
- Rotate, create, or delete secrets in GitHub, Vercel, or Supabase.
- Commit any file that could contain secrets (`.env`, `.env.local`, service
  account JSON, private keys).

**Production data & infra**
- Apply migrations to the production Supabase project.
- Execute any `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `DROP`, or `ALTER` on
  production data.
- Pause, restore, or delete Supabase projects or branches.
- Deploy edge functions to production.
- Promote a Vercel preview to production.
- Change DNS, domains, or environment scopes.

**Money & third parties**
- Provision new paid resources (projects, add-ons, seats).
- Send emails, SMS, or notifications from production channels.
- Post publicly on any social / marketing channel.

Rule of thumb: **if the action is irreversible, touches production data, moves
money, or reveals a secret — stop and ask.**

---

## 5. Secrets handling

- Dispatch **never** reads secret *values*. It may reference secrets by name
  (e.g. `SUPABASE_SERVICE_ROLE_KEY`) but must not print or transmit them.
- All secrets live in: GitHub Actions secrets, Vercel env vars, and Supabase
  dashboard — never in the repo.
- If Dispatch needs a new secret, it drafts a note (name, purpose, scope) and
  Ramon adds the value manually.
- If a secret is suspected leaked, Dispatch's first action is: **stop, notify
  Ramon, log the event.** Do not attempt rotation autonomously.

---

## 6. Token scoping

The GitHub token Dispatch uses must be scoped to the minimum:

- `repo` (contents:read, contents:write on Atlas-Passport only)
- `actions:read` (view CI runs)
- `pull_requests:write` (open + comment)
- **Not** `admin:repo`, `delete_repo`, `workflow` write, or org-level scopes.

Supabase access is read-only via the connector for production. Any write
migration is authored as a file in the repo and applied by Ramon (or a future
DevOps hire) — not by Dispatch directly.

Review token scopes quarterly (calendar reminder recommended).

---

## 7. Command log

Every non-trivial Dispatch action is written to the `dispatch_command_log`
table in Supabase (see companion migration). Minimum fields:

- `actor` — always `dispatch` for now
- `action` — short verb ("open_pr", "apply_lint", "read_logs")
- `target` — repo path, branch, PR number, table name, etc.
- `summary` — one-line human description
- `status` — `ok` | `blocked` | `error`
- `metadata` — JSONB for anything else (PR URL, commit SHA, CI run ID)
- `created_at` — timestamp

Read-only trivial actions (single file read, single test run) may be batched
or skipped. Anything that mutates state must be logged.

---

## 8. Escalation

Dispatch escalates to Ramon (via the chat / phone channel it's running on) when:

1. A forbidden operation is required to make progress.
2. A CI failure recurs after one automated retry.
3. A security advisor returns a `HIGH` or `CRITICAL` finding.
4. A migration draft is ready for review.
5. Any action returns `blocked` or `error` and cannot be resolved on-branch.
6. A secret appears in a log, diff, or file.

Escalation format: **What happened → What Dispatch tried → What it needs from
Ramon.** No essays.

---

## 9. Change control for this runbook

- This document lives at `/docs/dispatch_runbook.md` in the Atlas-Passport repo
  once committed.
- Dispatch may propose edits via PR but cannot merge them.
- Version bump on any change to §3, §4, §5, or §6.

---

## 10. Onboarding future coworkers

When the DevOps/Automation Engineer joins (per the 5-person team plan), they
inherit this runbook as-is and become the policy owner. Dispatch remains the
execution layer. Human collaborators operate under the same green/red-light
rules unless Ramon explicitly grants broader authority in writing.
