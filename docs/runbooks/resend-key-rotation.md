# Atlas Passport — Resend API Key Rotation Runbook

**Scope:** Rotation of `RESEND_API_KEY` across Vercel (Production, Preview, Development) and GitHub Actions secrets
**Target rotation time:** ≤ 15 minutes
**Vercel project:** `atlas-passport` (scope: `ramon-spry`)
**GitHub repo:** `pilotspry-maker/Atlas-Passport`
**Resend dashboard:** https://resend.com/api-keys
**Last updated:** 2026-06-29

---

## When to use this runbook

Run this procedure whenever any of the following is true:

- Scheduled rotation (recommended: every 90 days)
- Key suspected leaked (commit, log, screenshot, third-party share)
- A teammate with `re_...` access has offboarded
- Resend reports anomalous send volume
- `RESEND_API_KEY` in Vercel is older than 90 days (see Section 1)

`RESEND_API_KEY` is referenced from:

- `src/lib/resend.ts` → `new Resend(process.env.RESEND_API_KEY)`
- `src/lib/email.ts` → all 6 transactional send paths
- `.github/workflows/ci.yml` → build-time env for CI
- `.github/workflows/check-env-vars.yml` → asserts presence in Vercel Production + Preview

Any rotation that updates Vercel but not the GitHub Actions secret will turn `ci.yml` red on the next push.

---

## Quick-Reference Decision Tree

```
Need to rotate RESEND_API_KEY?
│
├─ Routine scheduled rotation?
│   └─ GO TO → Section 1 → 2 → 3 → 4 → 5 → 6
│
├─ Key confirmed leaked (treat as incident)?
│   └─ GO TO → Section 0 (Emergency revoke) → Section 2 → 3 → 4 → 5 → 6
│
└─ Vercel updated but CI is red on RESEND?
    └─ GO TO → Section 4 (GitHub Actions secret sync)
```

---

## Section 0 — Emergency Revoke (incident path only)

Use this **only** when the current key is known compromised. It accepts ~30–120 seconds of email send failures in production in exchange for cutting off the leaked key immediately.

1. Open https://resend.com/api-keys
2. Find the active key (label should match what's in `RESEND_API_KEY`'s Vercel entry — confirm by last-used timestamp).
3. Click **Revoke**. Confirm.
4. Immediately proceed to Section 2 to create a replacement; do not wait.

Email sends from `src/lib/email.ts` will throw `403` from Resend during the gap. The `/api/cron/*` routes will log failures but will not crash the deployment.

---

## Section 1 — Verify Current Key Age & State (2 min)

Confirm what's actually in Vercel before you change anything. Run locally with the operator's Vercel token.

```bash
# Link the local checkout to the Vercel project (idempotent — safe to re-run)
cd ~/code/Atlas-Passport
npx vercel link --yes --project atlas-passport --scope ramon-spry

# Inspect current RESEND_* entries across all targets
npx vercel env ls | grep -i resend
```

Expected shape (key names only — values are encrypted and never printed):

```
 RESEND_API_KEY      Encrypted    Development            <age>
 RESEND_API_KEY      Encrypted    Production, Preview    <age>
 RESEND_FROM_NAME    Encrypted    Development            <age>
 RESEND_FROM_NAME    Encrypted    Production, Preview    <age>
 RESEND_FROM_EMAIL   Encrypted    Development            <age>
 RESEND_FROM_EMAIL   Encrypted    Production, Preview    <age>
```

**Decision points:**

- If `<age>` for `RESEND_API_KEY` is `> 90d`, rotate now.
- If only one target row is present (e.g. Production missing), STOP. Investigate before rotating — the gap is itself a bug.
- If `RESEND_FROM_EMAIL` / `RESEND_FROM_NAME` are missing from any target, fix those in the same change window (they're required by `check-env-vars.yml`).

Cross-check against Resend's last-used data:

```
Resend dashboard → API Keys → (active key) → "Last used"
```

If "Last used" is older than 7 days but production is sending email, you may have a phantom key still configured somewhere — investigate before adding a new one.

---

## Section 2 — Create the New Key in Resend (2 min)

1. Open https://resend.com/api-keys
2. Click **Create API Key**.
3. Name: `atlas-passport-prod-YYYYMMDD` (e.g. `atlas-passport-prod-20260629`). The dated suffix makes future audits trivial.
4. Permission: **Full access** (matches the current key — `src/lib/email.ts` uses both `emails.send` and reads delivery state).
5. Domain: `atlaspassport.com` (the verified sender domain — must match `RESEND_FROM_EMAIL`).
6. Copy the `re_...` value **once** to your password manager. Resend will not show it again.
7. Do not paste the key into chat, the terminal scrollback, or any file. Section 3 reads it from an interactive prompt.

**Do not revoke the old key yet.** Old and new must coexist until Section 6 verifies the new key in production.

---

## Section 3 — Update Vercel Environment Variables (5 min)

The Vercel CLI accepts the secret value from an interactive prompt — the key never appears in shell history, command output, or process listings.

```bash
cd ~/code/Atlas-Passport

# 1. Remove the existing Production value
npx vercel env rm RESEND_API_KEY production --yes

# 2. Add the new value (CLI will prompt: "What's the value of RESEND_API_KEY?")
#    Paste the re_... value from your password manager. Input is hidden.
npx vercel env add RESEND_API_KEY production

# 3. Repeat for Preview
npx vercel env rm RESEND_API_KEY preview --yes
npx vercel env add RESEND_API_KEY preview

# 4. Repeat for Development
npx vercel env rm RESEND_API_KEY development --yes
npx vercel env add RESEND_API_KEY development
```

Confirm the new ages:

```bash
npx vercel env ls | grep -i resend
```

All three `RESEND_API_KEY` rows should now show age `0s` to a few minutes; the `RESEND_FROM_*` rows should be untouched.

**Anti-patterns — do not do any of these:**

- ❌ `echo "$NEW_KEY" | vercel env add ...` (writes to history)
- ❌ `vercel env add RESEND_API_KEY production <<< "$NEW_KEY"` (same)
- ❌ Setting via Vercel dashboard while CLI is mid-rotation (race on the rm/add)
- ❌ Skipping Preview or Development to "save time" — `check-env-vars.yml` fails on the next PR if Preview is missing the key

---

## Section 4 — Update GitHub Actions Secret (operator-local, 3 min)

> ⚠️ **Proxy restriction.** The remote agent environment cannot reach `POST /repos/{owner}/{repo}/actions/secrets` through `git-agent-proxy.perplexity.ai` (returns `403 Forbidden`). This section **must** be run from the operator's local machine against `api.github.com` directly. There is no remote-agent fallback.

From the operator's workstation (authenticated `gh` CLI with `repo` + `admin:repo_hook` scopes):

```bash
# Verify auth is to api.github.com, not the proxy
gh auth status

# Confirm the secret exists today (lists names + last-updated, never values)
gh secret list -R pilotspry-maker/Atlas-Passport | grep -i resend

# Update the secret. gh will prompt for the value (hidden input).
gh secret set RESEND_API_KEY -R pilotspry-maker/Atlas-Passport

# Verify the updated timestamp
gh secret list -R pilotspry-maker/Atlas-Passport | grep RESEND_API_KEY
```

`Updated at` should be within the last minute.

`RESEND_FROM_EMAIL` and `RESEND_FROM_NAME` are also referenced in `ci.yml` but are not secrets being rotated — leave them alone unless you are also changing the sender identity.

---

## Section 5 — Redeploy Production (2 min)

Vercel does not auto-redeploy on env var changes. The currently-running production deployment still holds the old key in its serverless function bundle until a new deploy ships.

Option A — CLI redeploy (preferred, no code change needed):

```bash
cd ~/code/Atlas-Passport
npx vercel --prod --token "$VERCEL_TOKEN"
```

Option B — Empty commit (useful if you also want a CI run on `main`):

```bash
git checkout main && git pull
git commit --allow-empty -m "chore: rotate RESEND_API_KEY (no code change)"
git push origin main
```

Wait for the deployment to reach `READY`:

```bash
npx vercel ls atlas-passport --token "$VERCEL_TOKEN" | head -5
```

---

## Section 6 — Verify the New Key in Production (3 min)

Run **all three** checks. The key is not considered rotated until all pass.

### 6.1 Resend dashboard — last-used

1. https://resend.com/api-keys
2. The new `atlas-passport-prod-YYYYMMDD` key should show `Last used` within 1–2 minutes of the production redeploy completing (the post-deploy health ping or first real send will populate it).
3. The old key's `Last used` should stop advancing. If it keeps advancing >5 minutes after redeploy, an old deployment is still serving — check Section 7.

### 6.2 End-to-end send through production

Trigger any transactional path that hits `src/lib/email.ts`. Pick whichever is fastest for the current launch state:

```bash
# Example: rehearsal welcome path (adjust to a real test account you control)
curl -X POST https://atlas-passport.vercel.app/api/auth/test-email \
  -H "Content-Type: application/json" \
  -d '{"to":"<your-test-inbox>"}'
```

Expected: `200` from the route, email arrives in the test inbox within ~30s, `From:` header reads `Kaelo <kaelo@atlaspassport.com>` (per `src/lib/resend.ts`).

If the production app has no exposed test endpoint, send through the cron path manually:

```bash
curl -X POST https://atlas-passport.vercel.app/api/cron/hourly-launch-monitor \
  -H "Authorization: Bearer $CRON_SECRET"
```

### 6.3 CI green on a fresh push

The `check-env-vars.yml` workflow runs on every push to `main` and on PRs. Confirm:

```bash
gh run list -R pilotspry-maker/Atlas-Passport \
  --workflow=check-env-vars.yml --limit 3
gh run list -R pilotspry-maker/Atlas-Passport \
  --workflow=ci.yml --limit 3
```

Both most-recent runs against the post-rotation commit must be `completed / success`. A failure on `check-env-vars.yml` after rotation means a Vercel target is missing the key — go back to Section 3. A failure on `ci.yml` build step means the GitHub Actions secret in Section 4 wasn't updated.

---

## Section 7 — Revoke the Old Key (1 min)

**Only after all three checks in Section 6 pass.**

1. https://resend.com/api-keys
2. Find the previous key (the one whose `Last used` stopped advancing).
3. Click **Revoke**. Confirm.
4. Immediately re-run check 6.2 — production must still send. If it fails, you revoked the wrong key; create a replacement (Section 2) and restart from Section 3.

---

## Section 8 — Record the Rotation

Append a one-line entry to the rotation log so the next operator knows the history:

```bash
# In docs/runbooks/resend-key-rotation.md, append to the table below
```

| Date (UTC)       | Operator         | Old key label                | New key label                | Reason     | Verified by |
|------------------|------------------|------------------------------|------------------------------|------------|-------------|
| _YYYY-MM-DD_     | _name / handle_  | atlas-passport-prod-YYYYMMDD | atlas-passport-prod-YYYYMMDD | scheduled  | _name_      |

Then commit:

```bash
git checkout -b chore/resend-rotation-$(date +%Y%m%d)
git add docs/runbooks/resend-key-rotation.md
git commit -m "chore(docs): log RESEND_API_KEY rotation $(date +%Y-%m-%d)"
git push -u origin HEAD
gh pr create --fill --base main
```

The PR itself is the audit trail. Do not include any `re_...` substring in the commit, PR title, or body.

---

## Failure Modes & Recovery

| Symptom                                                          | Likely cause                                                  | Fix                                                       |
|------------------------------------------------------------------|---------------------------------------------------------------|-----------------------------------------------------------|
| `check-env-vars.yml` red, "MISSING from PREVIEW: RESEND_API_KEY" | Forgot Preview in Section 3                                   | Re-run Section 3 step 3                                   |
| `ci.yml` red on build step, Vercel fine                          | GitHub Actions secret not synced                              | Section 4                                                 |
| Resend `401 Unauthorized` in production logs                     | Production env not redeployed after env var change            | Section 5                                                 |
| Resend `401 Unauthorized` immediately after Section 7            | Revoked the key still in use; new key not actually live       | Re-create key (Section 2), re-run Sections 3, 5, 6        |
| Old key's `Last used` still advances >5 min after redeploy       | Stale deployment alias, or another project shares the key     | `vercel ls atlas-passport` → re-alias latest to `prod`    |
| `vercel env rm` says "not found"                                 | Target already missing the var                                | Skip the `rm`, proceed to `vercel env add` for that target |
| `gh secret set` fails with 403 from operator's workstation       | `gh` is routed through the agent proxy                        | Run `gh auth status`, re-auth against `github.com` directly |

---

## References

- Code: `src/lib/resend.ts`, `src/lib/email.ts`
- CI: `.github/workflows/ci.yml`, `.github/workflows/check-env-vars.yml`
- CLAUDE.md §5 (Environment Variables), §13 (Safety Constraints — Secrets & env)
- Resend docs: https://resend.com/docs/dashboard/api-keys/introduction
- Vercel CLI env reference: https://vercel.com/docs/cli/env
- GitHub Actions secrets: https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions
