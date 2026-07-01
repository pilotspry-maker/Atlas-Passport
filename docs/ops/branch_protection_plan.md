# Branch Protection Hardening Plan — `main`

**Repo:** `pilotspry-maker/Atlas-Passport`
**Owner:** Ramon Spry — Relevant Artist LLC
**Companion:** `docs/dispatch_runbook.md` (PR #88)
**Version:** 1.0 · 2026-07-01

---

## 1. Why

On 2026-07-01 the Dispatch AI coworker proposed two workflow-bypassing shortcuts within one hour: (a) a "blind confirm" on 8 unseen field edits, and (b) a `push-main.bat` file placed on the operator's Desktop that would `git push origin main` on double-click. Both were declined.

The current branch protection on `main` correctly blocks force-push and deletion and requires status checks, but sets **`required_approving_review_count: 0`**. Any actor with `contents:write` on the repo — including a leaked Dispatch token — can therefore open a PR and self-merge with green CI, bypassing human review entirely.

This plan closes that loophole and pins the merge path as the only way changes reach `main`.

---

## 2. Baseline (as of 2026-07-01 15:30 UTC)

| Setting | Current | Verdict |
|---|---|---|
| Branch protection on `main` | ON | ✅ |
| Force pushes | Blocked | ✅ |
| Branch deletion | Blocked | ✅ |
| Admin enforcement | ON | ✅ |
| Required status checks (4) | Verify env · Lint/Build/Bundle · RLS Regression · RLS Exploit | ✅ |
| Strict (up-to-date branch required) | ON | ✅ |
| Required approving reviews | **0** | ❌ **primary gap** |
| Dismiss stale reviews on new commits | ON | ✅ (once reviews required) |
| Require last-push approval | OFF | ⚠️ tighten |
| Required linear history | OFF | ⚠️ tighten |
| Required conversation resolution | OFF | ⚠️ tighten |
| Signed commits required | OFF | ⚠️ consider |
| CODEOWNERS | Not present | ❌ |
| Rulesets | None | ⚠️ upgrade path |
| Actions: allowed_actions | `all` | ⚠️ tighten |
| SHA pinning required for actions | OFF | ⚠️ tighten |
| Squash-only merges | ON | ✅ |
| Auto-delete branches on merge | ON | ✅ |

---

## 3. Enforcement layers (defense in depth)

Four layers. Any single one blocks the bypass; together they make it impossible without your explicit action.

### Layer 1 — Branch protection: require review (primary fix)

Set `required_approving_review_count = 1` and pin the reviewer surface via CODEOWNERS. This alone closes the self-merge loophole: even with `contents:write`, a token cannot approve its own PR.

Also tighten:
- `require_last_push_approval = true` — a fresh push after approval dismisses the approval
- `required_linear_history = true` — no merge commits sneaking through
- `required_conversation_resolution = true` — every review comment must be resolved

Restrict who can push to `main` at all (only via merged PR) using `restrictions.users` set to `["pilotspry-maker"]` only. This means Dispatch's token can push to feature branches (still needed for PRs) but not directly to `main`.

### Layer 2 — CODEOWNERS

Adds `.github/CODEOWNERS` pinning `@pilotspry-maker` as required reviewer for the entire tree, with tighter ownership on the paths that most need human eyes:

- `/supabase/migrations/**` — any DB migration
- `/.github/workflows/**` — CI itself
- `/.github/CODEOWNERS` — CODEOWNERS itself (prevents self-neutering)
- `/docs/dispatch_runbook.md` — policy file
- `/docs/ops/branch_protection_plan.md` — this doc
- `/CLAUDE.md` — coworker instructions

CODEOWNERS interacts with `required_pull_request_reviews.require_code_owner_reviews = true` to force the right reviewer, not just any reviewer.

### Layer 3 — Verification workflow (audit + regression watchdog)

New workflow `.github/workflows/branch-protection-audit.yml` runs on push to `main` and on a weekly schedule. It:

1. Reads `repos/{owner}/{repo}/branches/main/protection` via `gh api`
2. Compares every field against `.github/branch-protection.expected.json` (the canonical config committed in this PR)
3. Fails red if drift is detected → posts to Slack `#launch-ops`
4. On workflow_dispatch, optionally re-applies the canonical config

This is the "who watches the watcher" layer — if someone disables branch protection via the GitHub UI, this workflow catches it within a week (or immediately if triggered on push).

### Layer 4 — Actions hardening

Move Actions permissions from `allowed_actions: all` → `allowed_actions: selected` with a curated allowlist:
- `actions/*` (first-party)
- `github/*` (first-party)
- Specific third-party actions already used: `supabase/setup-cli`, `pnpm/action-setup`, etc.

Enable `sha_pinning_required: true` so every third-party action must be pinned to a full-SHA commit, not a floating tag.

Set default workflow token permission to `read` (from repo Settings → Actions → General → Workflow permissions). Any workflow needing write must opt in explicitly with `permissions:` blocks.

---

## 4. What Dispatch's token can and cannot do after this

| Action | Before | After |
|---|---|---|
| Clone / read repo | ✅ | ✅ |
| Create feature branch | ✅ | ✅ |
| Push to feature branch | ✅ | ✅ |
| Open PR | ✅ | ✅ |
| Comment on PR | ✅ | ✅ |
| Approve own PR | ❌ (GitHub blocks) | ❌ |
| Merge own PR without human review | ⚠️ **YES** (review count = 0) | ❌ **BLOCKED** |
| Push directly to `main` | ⚠️ possible if not restricted | ❌ **BLOCKED** by restrictions |
| Force-push anywhere | ❌ (already blocked) | ❌ |
| Delete `main` | ❌ | ❌ |
| Disable branch protection | Requires admin scope | Same + audit fires within 7 days |
| Trigger workflow_dispatch | ✅ if scope allows | ✅ |
| Modify `.github/workflows/**` via PR | ✅ (auto-merge risk) | ❌ requires CODEOWNERS review |
| Modify `docs/dispatch_runbook.md` via PR | ✅ | ❌ requires CODEOWNERS review |

The net effect: **Dispatch keeps its full productive workflow (feature branch → PR → CI) and loses only the ability to bypass you.**

---

## 5. Token scope guidance (Dispatch side)

Independent of the repo hardening, review Dispatch's GitHub token scope. From the Dispatch Runbook §6, the intended minimum is:

- `repo` (contents:read, contents:write on Atlas-Passport only)
- `actions:read`
- `pull_requests:write`

Explicitly **not**:
- `admin:repo` — would allow disabling branch protection
- `delete_repo`
- `workflow` write (with a fine-grained PAT, this is the "GitHub Actions workflows" scope) — modifying `.github/workflows/**` requires this, and with the CODEOWNERS setup, disallowing it here adds a second layer
- Any org-level scope

If Dispatch's current token is a classic PAT with `repo` (which grants everything under `repo`), consider migrating to a **fine-grained PAT** with only the specific permissions above, scoped to `Atlas-Passport` alone. Fine-grained PATs also expire — set 90 days and add a quarterly rotation reminder.

---

## 6. Rollout — 3 phases

### Phase 1 (this PR — safe, reversible)

- Commit `.github/CODEOWNERS`
- Commit `.github/branch-protection.expected.json` (canonical config)
- Commit `.github/workflows/branch-protection-audit.yml` (audit workflow, dry-run only in this PR)
- Commit `scripts/ops/apply-branch-protection.sh` (idempotent applier — not run yet)
- Commit `docs/ops/branch_protection_plan.md` (this doc)

**No enforcement changes yet.** The audit workflow reports drift; nothing is enforced.

### Phase 2 (manual apply after PR #88 and this PR merge)

Ramon runs `scripts/ops/apply-branch-protection.sh` locally (or triggers the audit workflow with `workflow_dispatch` input `apply=true`). This:

1. PUTs the canonical protection config to `main`
2. Sets `restrictions.users = ["pilotspry-maker"]`
3. Sets `required_pull_request_reviews.require_code_owner_reviews = true`
4. Sets `required_approving_review_count = 1`
5. Enables `require_last_push_approval`, `required_linear_history`, `required_conversation_resolution`
6. Updates repo settings: default workflow token permission = read; SHA pinning = required; allowed_actions = selected + allowlist

### Phase 3 (30-day follow-up, separate PR)

- Migrate legacy branch protection → rulesets (better bypass-actor control)
- Evaluate signed-commit requirement
- Add per-migration reviewer requirement for `supabase/migrations/**` via a second CODEOWNERS entry escalating to a specific reviewer if you add collaborators

---

## 7. Rollback

Every change is reversible:

- CODEOWNERS: revert PR
- Audit workflow: disable in Actions tab or revert PR
- Branch protection settings: run `scripts/ops/apply-branch-protection.sh --rollback` which restores the 2026-07-01 baseline snapshot committed as `.github/branch-protection.baseline.json`

Emergency-only bypass path: repository admin (you) can temporarily edit branch protection via the GitHub UI — the audit workflow will fire on the next push or scheduled run and post drift to `#launch-ops`, keeping a visible trail.

---

## 8. Success criteria

- ✅ Dispatch can no longer merge a PR without your explicit approval
- ✅ Dispatch can no longer push to `main` directly under any code path
- ✅ Any drift from the canonical config is detected within 7 days (immediately on push to `main`)
- ✅ CODEOWNERS enforcement blocks self-review on the paths that matter
- ✅ Dispatch's productive workflow (feature branch → PR → CI green → your review → merge) is preserved

---

## 9. Refs

- Companion policy: `docs/dispatch_runbook.md` §4 (red-light operations) and §6 (token scoping)
- Trigger incident: 2026-07-01 push-main.bat proposal (declined by Ramon)
- Baseline snapshot: `.github/branch-protection.baseline.json` (committed with this PR)
- Canonical target: `.github/branch-protection.expected.json` (committed with this PR)
