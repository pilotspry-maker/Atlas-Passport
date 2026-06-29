# Atlas Passport — Resend API Key Rotation Runbook

**Scope:** Rotating `RESEND_API_KEY` (transactional email send key) across all three storage locations: Resend dashboard, GitHub Actions secrets, Vercel production environment.
**Target completion time:** ≤ 15 minutes (including DNS / send-test verification)
**Resend dashboard:** https://resend.com/api-keys
**GitHub secrets:** https://github.com/pilotspry-maker/Atlas-Passport/settings/secrets/actions
**Vercel project:** `prj_iGrq8qqC6xvRzRgROjt1VX7epXH1` (scope `ramon-spry`)
**Last updated:** 2026-06-29

---

## When to use this runbook

- The current Resend key is suspected compromised (leaked in logs, screenshots, force-pushed branch, etc.)
- Scheduled rotation as part of a quarterly secret-hygiene sweep
- A teammate or contractor with access is being offboarded
- The CI build is failing on `RESEND_API_KEY` and the existing key is confirmed revoked at Resend's end

Do **not** use this runbook for:
- Changing the `RESEND_FROM_EMAIL` or `RESEND_FROM_NAME` (those are config, not secrets — edit them in place without revocation)
- Local-dev `.env.local` rotation (those are not connected to production; just edit the file)

---

## Pre-flight check (90 seconds)

Confirm the current state of the three storage locations BEFORE generating a new key, so you can compare timestamps after.

```bash
# 1. GitHub Actions secret timestamp
gh secret list -R pilotspry-maker/Atlas-Passport --json name,updatedAt \
  | python3 -c "import sys,json; [print(r) for r in json.load(sys.stdin) if 'RESEND' in r['name']]"

# 2. Vercel production env presence (does not print the value)
vercel env ls production --scope ramon-spry --project prj_iGrq8qqC6xvRzRgROjt1VX7epXH1 \
  | grep RESEND_API_KEY

# 3. Confirm the CI workflow still references it
grep -n RESEND_API_KEY .github/workflows/ci.yml
```

Expected before rotation:
- GitHub secret exists, with whatever `updatedAt` it last had
- Vercel env var exists in `production` scope (and only production — never preview/development for a server-only secret)
- `ci.yml` line ~74: `RESEND_API_KEY: ${{ secrets.RESEND_API_KEY }}`

If any of these is missing, STOP and figure out why before rotating.

---

## Step 1 — Generate a new key in the Resend dashboard

1. Sign in to https://resend.com/api-keys.
2. Click **Create API Key**.
3. Name it `atlas-passport-prod-<YYYY-MM-DD>` (date helps future audits).
4. Permission: **Sending access** (NOT full access — least privilege).
5. Restrict to the verified sending domain (e.g. `kaelo@<verified-domain>`).
6. Copy the new key (starts with `re_`). It's only shown once.
7. **Do NOT revoke the old key yet** — we revoke it in Step 5 after the new one is confirmed working in CI + Vercel.

Paste the new key into a secure scratchpad (1Password, etc.) for the next two steps. Never paste it into a shared doc, a Slack channel, or any file under git control.

---

## Step 2 — Update the GitHub Actions secret

```bash
# Paste the new key when prompted. The value is read from stdin, never echoed.
gh secret set RESEND_API_KEY -R pilotspry-maker/Atlas-Passport
```

Verify the timestamp updated:

```bash
gh secret list -R pilotspry-maker/Atlas-Passport \
  | grep RESEND_API_KEY
```

The `Updated` column should now show today's date/time. If it still shows the old timestamp, the `gh secret set` did not actually run — re-check authentication and try again.

---

## Step 3 — Update the Vercel production environment

```bash
# Remove the old value (Vercel does not support in-place update via CLI)
vercel env rm RESEND_API_KEY production \
  --scope ramon-spry \
  --project prj_iGrq8qqC6xvRzRgROjt1VX7epXH1 \
  --yes

# Add the new value — paste when prompted
vercel env add RESEND_API_KEY production \
  --scope ramon-spry \
  --project prj_iGrq8qqC6xvRzRgROjt1VX7epXH1
```

When prompted for the value, paste the new `re_…` key from Step 1. Confirm only `Production` is checked — `Preview` and `Development` should remain unset for this server-only secret (matches the CLAUDE.md INF-1 rule).

Trigger a new production deploy so the build picks up the new value:

```bash
vercel --prod \
  --scope ramon-spry \
  --project prj_iGrq8qqC6xvRzRgROjt1VX7epXH1
```

Or push any trivial commit to `main` if you prefer the CI path.

---

## Step 4 — Verify CI and production are healthy

Watch the next CI run on `main`:

```bash
gh run list -R pilotspry-maker/Atlas-Passport \
  --workflow ci.yml --branch main --limit 1
gh run watch -R pilotspry-maker/Atlas-Passport <run-id>
```

The build step (`pnpm build` / `npm run build`) must pass. If it fails with a Resend-related error, the GitHub secret value is wrong — go back to Step 2.

Smoke-test an actual send via the production app:

1. In an incognito window, sign up with a throwaway email.
2. Click **Send magic link**.
3. Confirm the email arrives within 30 seconds at the inbox.
4. Cross-check Resend dashboard → **Logs** → there should be a `delivered` event from the new key's name (`atlas-passport-prod-<YYYY-MM-DD>`).

If any of these fail, do NOT proceed to Step 5 — the old key is still active and you can roll back by re-pasting the old value in Steps 2 and 3.

---

## Step 5 — Revoke the old key

Only after Step 4 fully succeeds:

1. Resend dashboard → API Keys → find the previous key (whatever name it had).
2. Click **Revoke** / delete.
3. Confirm revocation. The key is dead the moment you click — there is no grace period.

---

## Step 6 — Update the rotation log

Append one line to `docs/runbooks/secret-rotation-log.md` (create the file if it doesn't exist):

```
| YYYY-MM-DD HH:MM ET | RESEND_API_KEY | <new key name> | <your initials> | <reason> |
```

Commit and push:

```bash
git add docs/runbooks/secret-rotation-log.md
git commit -m "ops: log RESEND_API_KEY rotation <YYYY-MM-DD>"
git push
```

This is the only paper trail — the secret values themselves are never committed, but the fact that a rotation happened needs to be visible to future operators and audit reviewers.

---

## Rollback procedure

If anything in Steps 2–4 goes sideways and you need to revert to the old key BEFORE Step 5 (revocation):

1. Re-paste the OLD `re_…` value into the GitHub secret:
   ```bash
   gh secret set RESEND_API_KEY -R pilotspry-maker/Atlas-Passport
   ```
2. Re-paste the OLD value into Vercel:
   ```bash
   vercel env rm RESEND_API_KEY production --scope ramon-spry --project prj_iGrq8qqC6xvRzRgROjt1VX7epXH1 --yes
   vercel env add RESEND_API_KEY production --scope ramon-spry --project prj_iGrq8qqC6xvRzRgROjt1VX7epXH1
   ```
3. Trigger a redeploy.
4. At Resend dashboard, leave the NEW key revoked (or revoke it now) and keep the OLD one active.

Rollback only works if you haven't completed Step 5 yet. Once the old key is revoked at Resend's end, it cannot be un-revoked — you'd have to generate yet another new key and start over.

---

## How to confirm a rotation actually happened (after the fact)

This is the diagnostic that surfaced the question that produced this runbook. Run it any time you need to verify whether `RESEND_API_KEY` has been rotated recently:

```bash
gh secret list -R pilotspry-maker/Atlas-Passport --json name,updatedAt \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
data.sort(key=lambda r: r['updatedAt'], reverse=True)
for r in data:
    print(f\"{r['name']:35s}  {r['updatedAt']}\")
"
```

**Signature of a real rotation vs. an initial seed:**
- **Initial bulk seed:** all three `RESEND_*` secrets share a 1-second timestamp window (set by a single `gh secret set` script run).
- **Real rotation:** `RESEND_API_KEY` has a newer `updatedAt` than `RESEND_FROM_EMAIL` and `RESEND_FROM_NAME` (because Step 2 above only touches the key, not the config secrets).

Example from 2026-06-29 audit — these timestamps reveal the key was never rotated since initial seed:

```
RESEND_API_KEY        2026-06-23T02:32:20Z   ← same second as FROM_EMAIL/FROM_NAME
RESEND_FROM_EMAIL     2026-06-23T02:32:20Z   ← initial bulk seed signature
RESEND_FROM_NAME      2026-06-23T02:32:21Z
```

A post-rotation snapshot should look like:

```
RESEND_API_KEY        2026-MM-DDTHH:MM:SSZ   ← newer, distinct
RESEND_FROM_EMAIL     2026-06-23T02:32:20Z   ← unchanged
RESEND_FROM_NAME      2026-06-23T02:32:21Z   ← unchanged
```

---

## Related docs

- `CLAUDE.md` § "Environment variables" — full env-var inventory and `NEXT_PUBLIC_` rules
- `CLAUDE.md` § "Vercel target rules (audit finding INF-1)" — Production / Preview / Development scoping
- `docs/runbooks/migration-rollback.md` — adjacent operational runbook
- `.github/workflows/ci.yml` lines 74–76 — where `RESEND_API_KEY` is injected into the build
- `.github/workflows/check-env-vars.yml` — presence check (fails CI if the secret is missing)

— Atlas Passport ops
