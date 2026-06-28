# Atlas Passport — RLS Post-Migration Audit

**Scope:** Migrations 004, 005, 006 · PR #18 (`fix/005-rls-exploit-patches`)  
**Date:** 2026-06-23  
**Supabase project:** `gaavynmmysdhovpatzlp`

---

## Complete Policy Inventory (post-migration state)

| Table | Policy | Op | Role | USING / WITH CHECK | Status |
|---|---|---|---|---|---|
| `profiles` | `profiles_select_own` | SELECT | authenticated | `auth.uid() = id` | ✅ Correct |
| `profiles` | `profiles_update_own` | UPDATE | authenticated | USING: `auth.uid() = id`<br>WITH CHECK: `auth.uid() = id AND is_admin = (SELECT is_admin FROM profiles WHERE id = auth.uid())` | ✅ Fixed in 005 |
| `corridors` | `corridors_select_active` | SELECT | authenticated | `is_active = TRUE` | ✅ Correct |
| `nodes` | `nodes_select_active` | SELECT | authenticated | `is_active = TRUE AND auth.role() = 'authenticated'` | ✅ Fixed in 004 |
| `passports` | `passports_select_own` | SELECT | authenticated | `user_id = auth.uid()` | ✅ Correct |
| `passports` | `passports_insert_own` | INSERT | authenticated | `user_id = auth.uid()` | ⚠️ See GAP-A |
| `check_ins` | `check_ins_select_own` | SELECT | authenticated | `user_id = auth.uid()` | ✅ Correct |
| `check_ins` | `check_ins_insert_own` | INSERT | authenticated | `user_id = auth.uid() AND EXISTS (SELECT 1 FROM passports p WHERE p.id = passport_id AND p.user_id = auth.uid() AND p.status = 'active')` | ✅ Fixed in 005 |
| `rewards` | `rewards_select_own` | SELECT | authenticated | `EXISTS (SELECT 1 FROM passports p WHERE p.corridor_id = rewards.corridor_id AND p.user_id = auth.uid() AND p.status = 'complete')` | ✅ Fixed in 004 |
| `rewards` | `rewards_select_admin` | SELECT | authenticated | `EXISTS (SELECT 1 FROM profiles pr WHERE pr.id = auth.uid() AND pr.is_admin = TRUE)` | ✅ Correct |
| `passports` | trigger `check_reward_claimed_immutable` | BEFORE UPDATE | all (incl. service-role) | Raises EXCEPTION if `OLD.reward_claimed = TRUE AND NEW.reward_claimed = FALSE` | ✅ Fixed in 005 |
| `storage.check-in-proofs` | `check_in_proofs_insert` | INSERT | authenticated | `bucket_id = 'check-in-proofs' AND foldername[1] = auth.uid()::text` | ✅ Correct |
| `storage.check-in-proofs` | `check_in_proofs_select_own` | SELECT | authenticated | `bucket_id = 'check-in-proofs' AND foldername[1] = auth.uid()::text` | ✅ Correct |
| `storage.check-in-proofs` | `check_in_proofs_delete_own` | DELETE | authenticated | `bucket_id = 'check-in-proofs' AND foldername[1] = auth.uid()::text` | ✅ Correct |
| `storage.corridor-covers` | `corridor_covers_select_public` | SELECT | anon | `bucket_id = 'corridor-covers'` | ✅ Intentional public |

**Missing policies (intentional — enforced at application layer via `createAdminClient`):**

| Table | Op | Enforcement |
|---|---|---|
| `profiles` | INSERT | `handle_new_user` SECURITY DEFINER trigger on `auth.users` |
| `profiles` | DELETE | No user-facing delete; cascade from `auth.users` |
| `passports` | UPDATE | No player-facing UPDATE; admin routes use `createAdminClient` (bypasses RLS) |
| `passports` | DELETE | No delete path exists |
| `check_ins` | UPDATE | Admin routes use `createAdminClient`; player resubmit goes through app route with `.eq('user_id', user.id)` guard |
| `check_ins` | DELETE | No delete path exists |
| `rewards` | INSERT/UPDATE/DELETE | Admin only, via `createAdminClient` |
| `corridors` | INSERT/UPDATE/DELETE | Admin only, via `createAdminClient` |
| `nodes` | INSERT/UPDATE/DELETE | Admin only, via `createAdminClient` |

---

## Patches Applied — Confirmed Closed

### GAP 1 — `profiles` `is_admin` self-escalation (Critical) ✅ CLOSED

**Before 005:** `profiles_update_own` WITH CHECK was `auth.uid() = id` — any column writable.

**After 005:** WITH CHECK adds `AND is_admin = (SELECT is_admin FROM profiles WHERE id = auth.uid())`. The subquery re-reads the committed value; the WITH CHECK fails if the PATCH body sends a different value. PostgREST returns 403.

**Residual risk:** The subquery reads from `public.profiles` which is governed by `profiles_select_own` (`auth.uid() = id`). The SECURITY DEFINER context of the WITH CHECK evaluation means it runs as the session user — correct behavior. No bypass path via the PostgREST layer.

---

### GAP 2 — `check_ins` cross-passport insert IDOR (High) ✅ CLOSED

**Before 005:** `check_ins_insert_own` WITH CHECK was `user_id = auth.uid()` — passport ownership not verified.

**After 005:** EXISTS subquery requires `p.user_id = auth.uid() AND p.status = 'active'`. Both passport ownership and active status are enforced at the DB layer.

**Residual risk:** The app-layer route (`/api/checkins`) also verifies passport ownership via `createAdminClient`. Double enforcement is defense-in-depth. No bypass path.

---

### GAP 3 — `passports` `reward_claimed` immutability (Medium) ✅ CLOSED

**Before 005:** No DB-level guard on `reward_claimed`. Any UPDATE (including service-role) could flip it.

**After 005:** `BEFORE UPDATE` trigger `check_reward_claimed_immutable` raises `EXCEPTION` with SQLSTATE 23514 if `OLD.reward_claimed = TRUE AND NEW.reward_claimed = FALSE`. Fires for all callers including service-role — it is a database-layer guarantee, not a policy.

**Residual risk:** See GAP-B below (trigger fire condition is one-directional).

---

## Remaining Edge Cases — Identified in This Audit

### GAP-A — `passports_insert_own`: no active corridor guard (Low)

**What is unpatched:** `passports_insert_own` checks only `user_id = auth.uid()`. A player can call `POST /rest/v1/passports` directly with a `corridor_id` pointing to a deactivated corridor (`is_active = FALSE`). The DB will accept the INSERT.

**Why the risk is contained but not eliminated:**
- The app route (`/api/passport/activate`) queries the corridor with `.eq('is_active', true)` before inserting. Players going through the app are blocked.
- Direct PostgREST calls bypass this app-layer check.
- The passport would be functionally broken (no active nodes to check into), but it creates data inconsistency and could affect aggregate stats or admin views.

**Recommended fix (migration 007 candidate):**
```sql
DROP POLICY IF EXISTS "passports_insert_own" ON public.passports;

CREATE POLICY "passports_insert_own" ON public.passports
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.corridors c
      WHERE c.id        = passports.corridor_id
      AND   c.is_active = TRUE
    )
  );
```

---

### GAP-B — `reward_claimed` trigger only guards true→false (Informational)

**What it does:** `prevent_reward_unclaim` only fires when `OLD.reward_claimed = TRUE AND NEW.reward_claimed = FALSE`. It does not block false→true updates or any other column changes.

**Why this is acceptable as-is:**
- No player-facing UPDATE policy exists on `passports`. The only path to set `reward_claimed = true` is the admin approve route, which uses `createAdminClient` and is gated by `requireAdmin`.
- The trigger guards specifically against reversal, which is the attack vector.

**What to watch for:** If a `passports` UPDATE policy is ever added for players (e.g., to let them cancel their own passport), ensure the WITH CHECK explicitly excludes `reward_claimed` from writable columns. Without that guard, the trigger alone stops reversal but not a direct write to `true` by a non-admin player.

---

### GAP-C — `check_ins` `admin_notes` column readable by the check-in owner (Low)

**What is unpatched:** `check_ins_select_own` returns `SELECT *` to the authenticated player who owns the check-in. This includes `admin_notes`, `reviewed_by`, and `reviewed_at` — fields intended for internal admin use.

**Why it matters:** `admin_notes` may contain internal review reasoning that was not intended for the player to see (e.g., "Rejected — photo appears edited", "Flag for review — duplicate GPS"). `reviewed_by` exposes the admin's profile UUID.

**Recommended fix (migration 007 candidate):**
```sql
-- Either restrict the SELECT policy to specific columns:
DROP POLICY IF EXISTS "check_ins_select_own" ON public.check_ins;

CREATE POLICY "check_ins_select_own" ON public.check_ins
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());
-- AND in Next.js routes, explicitly select only player-safe columns:
-- .select('id, passport_id, node_id, status, proof_url, notes, submitted_at, created_at')
-- (PostgREST enforces column-level projection client-side, not DB-layer)
```

Note: Supabase RLS does not support column-level restrictions within a policy's USING clause — this requires either projecting at the query level or using a view with a restricted SELECT. The Next.js app routes already use `createAdminClient` for admin reads; the gap is only for player-facing reads via PostgREST.

---

### GAP-D — `seed_ci_fixtures` SECURITY DEFINER writable by anon (Informational)

**What it does:** Migration 006's `seed_ci_fixtures()` is granted EXECUTE to the `anon` role. It inserts rows into `corridors`, `nodes`, and `rewards` using hardcoded fixture UUIDs with `ON CONFLICT DO NOTHING`.

**Why the risk is bounded:**
- The function only writes to fixed UUIDs (`aaaaaaaa-...`, `bbbbbbbb-...`, `cccccccc-...`). Conflict handling means repeated calls are no-ops.
- Corridors/nodes/rewards have no sensitive columns in these fixture rows.
- An adversary who calls it succeeds only in creating the same CI test data — no meaningful production impact.

**What to watch for:** If production corridors are ever assigned the same deterministic UUID pattern (unlikely but possible via a copy-paste error), the ON CONFLICT DO NOTHING would silently skip the production row. Recommended: prefix fixture UUIDs with `00000000-` rather than `aaaaaaaa-` in a future migration to make them visually distinct from production UUIDs.

---

### GAP-E — `requireAdmin` reads `is_admin` via user-owned Supabase client (Medium)

**What it does:** `requireAdmin()` in `src/lib/auth.ts` calls `createClient()` (user-scoped JWT client) and queries `profiles.is_admin` for the calling user. Since `profiles_select_own` allows `auth.uid() = id`, this correctly reads the calling user's own profile — the user cannot see other profiles.

**The edge case:** After migration 005 patches `profiles_update_own`, a player can no longer self-escalate via PostgREST. But the `requireAdmin` gate reads `is_admin` from the DB at request time. If `is_admin` was set to `true` on any profile **before migration 005 was applied** (i.e., a pre-patch self-escalation), that value persists in the DB until manually cleared.

**Action required (one-time):** After applying migration 005, run the triage query from the rollback runbook (Section 1, query 1c) to confirm no profile has `is_admin = TRUE` unexpectedly. If any do, run the Section 2 remediation query.

---

## 5-Step Manual Penetration Test Checklist

Run these in sequence using two browser sessions (or two terminal windows) logged in as two separate test accounts. You need:
- **Player A** — a regular test account (not admin)
- **Player B** — a second regular test account with a complete corridor passport

Get both players' JWTs by signing in. The snippets reference `$NEXT_PUBLIC_SUPABASE_ANON_KEY` — export it first from your local `.env` or the Supabase dashboard:

```bash
export NEXT_PUBLIC_SUPABASE_ANON_KEY="sb_publishable_..."
```

```bash
# Replace with your test account credentials
P1_JWT=$(curl -s "https://gaavynmmysdhovpatzlp.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: $NEXT_PUBLIC_SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"player_one_rls@test.atlas","password":"TestPlayer1!RLS"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

P2_JWT=$(curl -s "https://gaavynmmysdhovpatzlp.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: $NEXT_PUBLIC_SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"player_two_rls@test.atlas","password":"TestPlayer2!RLS"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

ANON="$NEXT_PUBLIC_SUPABASE_ANON_KEY"
URL="https://gaavynmmysdhovpatzlp.supabase.co/rest/v1"
```

---

### ✅ Step 1 — Privilege Escalation: `is_admin` self-PATCH

**Exploit:** Player A attempts to promote themselves to admin via a direct PATCH.

```bash
# Get Player A's profile UUID from their JWT
P1_ID=$(echo $P1_JWT | python3 -c "
import sys, json, base64
jwt = sys.stdin.read().strip()
p = json.loads(base64.b64decode(jwt.split('.')[1] + '=='))
print(p['sub'])
")

curl -s -w "\n%{http_code}" \
  "$URL/profiles?id=eq.$P1_ID" \
  -X PATCH \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $P1_JWT" \
  -H "Content-Type: application/json" \
  -d '{"is_admin": true}'
```

**Expected result:** HTTP `403` (PostgREST WITH CHECK failure).

**Verify DB state:**
```bash
# Confirm is_admin is still false (use Supabase SQL Editor)
# SELECT id, email, is_admin FROM profiles WHERE id = '<P1_ID>';
# Expected: is_admin = false
```

**Pass criteria:** HTTP 403 AND `is_admin = false` in the DB.  
**Fail action:** Do NOT merge PR #18. Re-apply migration 005 and recheck `pg_policies` for `profiles_update_own`.

---

### ✅ Step 2 — Reward Gating: non-completer cannot read redemption code

**Exploit:** Player A (active passport, not complete) directly queries the rewards table.

```bash
CORRIDOR_ID="aaaaaaaa-0000-0000-0000-000000000001"  # CI fixture corridor
# Replace with a real corridor UUID for production verification

curl -s -w "\n%{http_code}" \
  "$URL/rewards?corridor_id=eq.$CORRIDOR_ID&select=id,title,redemption_code" \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $P1_JWT"
```

**Expected result:** HTTP `200` with an **empty array** `[]`.

**Also test with anonymous (no JWT):**
```bash
curl -s -w "\n%{http_code}" \
  "$URL/rewards?select=id,redemption_code" \
  -H "apikey: $ANON"
```

**Expected result:** HTTP `200` with `[]` (RLS silently filters, not 401).

**Pass criteria:** Both return `[]`. Any `redemption_code` in the response body is a failure.  
**Fail action:** Check `rewards_select_own` policy — confirm it requires `p.status = 'complete'`. Recheck whether `rewards_select_auth` (the pre-004 permissive policy) was accidentally left in place.

---

### ✅ Step 3 — IDOR: cross-passport check-in insert

**Exploit:** Player A attempts to attach a check-in to Player B's passport UUID.

```bash
# Get Player B's passport UUID — use the complete fixture passport or find it via SQL Editor:
# SELECT id FROM passports WHERE user_id = '<P2_ID>';
P2_PASSPORT_ID="dddddddd-0000-0000-0000-000000000002"  # CI fixture

P1_ID=$(echo $P1_JWT | python3 -c "
import sys, json, base64
jwt = sys.stdin.read().strip()
p = json.loads(base64.b64decode(jwt.split('.')[1] + '=='))
print(p['sub'])
")

curl -s -w "\n%{http_code}" \
  "$URL/check_ins" \
  -X POST \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $P1_JWT" \
  -H "Content-Type: application/json" \
  -d "{
    \"passport_id\": \"$P2_PASSPORT_ID\",
    \"user_id\": \"$P1_ID\",
    \"node_id\": \"bbbbbbbb-0000-0000-0000-000000000001\",
    \"status\": \"pending\",
    \"proof_url\": \"https://evil.example.com/fake.jpg\",
    \"proof_storage_path\": \"exploit/fake.jpg\"
  }"
```

**Expected result:** HTTP `403`.

**Verify no row was persisted (Supabase SQL Editor):**
```sql
SELECT id, passport_id, user_id FROM check_ins
WHERE passport_id = 'dddddddd-0000-0000-0000-000000000002'
AND   user_id != (SELECT user_id FROM passports WHERE id = 'dddddddd-0000-0000-0000-000000000002');
-- Expected: 0 rows
```

**Pass criteria:** HTTP 403 AND 0 rows in DB.  
**Fail action:** Check `check_ins_insert_own` for the EXISTS subquery. If the row was persisted, run the cleanup DELETE from the exploit-02 test comments and block the merge.

---

### ✅ Step 4 — Trigger: `reward_claimed` immutability

**Exploit:** Attempt to reset `reward_claimed` from `true` to `false` — both via the app and directly.

This requires running a SQL block in Supabase SQL Editor (no PostgREST path for players since no UPDATE policy exists):

```sql
-- STEP 4A: Set up known state (reward_claimed = true)
UPDATE public.passports
SET reward_claimed = TRUE
WHERE id = 'dddddddd-0000-0000-0000-000000000002';

-- STEP 4B: Attempt reversal — this must FAIL
UPDATE public.passports
SET reward_claimed = FALSE
WHERE id = 'dddddddd-0000-0000-0000-000000000002';
-- Expected: ERROR — "reward_claimed cannot be reversed once set to true"
-- SQLSTATE 23514

-- STEP 4C: Confirm value is still true
SELECT id, reward_claimed FROM public.passports
WHERE id = 'dddddddd-0000-0000-0000-000000000002';
-- Expected: reward_claimed = true
```

**Also verify the trigger is present and enabled:**
```sql
SELECT tgname, tgenabled, tgtype
FROM   pg_trigger
WHERE  tgrelid = 'public.passports'::regclass
AND    tgname  = 'check_reward_claimed_immutable';
-- Expected: 1 row, tgenabled = 'O' (fires on origin transactions)
```

**Pass criteria:** Step 4B raises an ERROR and Step 4C shows `true`. If 4B silently succeeds (no error), the trigger is missing or disabled — block the merge.

---

### ✅ Step 5 — Migration 006 allow-list: `confirm_test_users` rejects non-CI emails

**Exploit:** Attempt to use the `confirm_test_users` RPC to confirm an arbitrary account — if the allow-list check is broken, an attacker could self-confirm any email.

```bash
# Should be REJECTED (not in allow-list)
curl -s -w "\n%{http_code}" \
  "$URL/rpc/confirm_test_users" \
  -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d '{"user_email": "attacker@evil.com"}'
# Expected: 403 (PostgREST maps SQLSTATE 42501 → 403)

# Should be REJECTED too (production email format)
curl -s -w "\n%{http_code}" \
  "$URL/rpc/confirm_test_users" \
  -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d '{"user_email": "real-user@gmail.com"}'
# Expected: 403

# Should SUCCEED (CI allow-listed)
curl -s -w "\n%{http_code}" \
  "$URL/rpc/confirm_test_users" \
  -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d '{"user_email": "player_one_rls@test.atlas"}'
# Expected: 200 with {"email":"player_one_rls@test.atlas","updated":0,"status":"confirmed"}
```

**Pass criteria:** Non-allow-listed emails return 403. CI emails return 200.  
**Fail action:** Check the `allowed_emails` array in migration 006's `confirm_test_users` function. If any email returns 200 that isn't in the hardcoded array, the function has been modified — re-apply migration 006 and audit who changed it.

---

## Summary: Pre-Merge Security Gate

All five steps must pass before merging PR #18. The matrix:

| Step | Tests | Blocks merge if |
|---|---|---|
| 1 — is_admin escalation | POST 403 + DB value false | Any 2xx response OR `is_admin = true` in DB |
| 2 — Reward gating | Empty array for non-completer + anon | Any `redemption_code` in response |
| 3 — IDOR check-in | POST 403 + 0 rows in DB | Any 2xx response OR row persisted |
| 4 — reward_claimed trigger | UPDATE raises EXCEPTION | UPDATE succeeds silently OR `reward_claimed = false` in DB |
| 5 — confirm_test_users allow-list | Non-CI emails → 403, CI emails → 200 | Non-CI email returns 200 |

**Residual gaps to track (not merge-blockers but scheduled for migration 007):**

- GAP-A: `passports_insert_own` — add active corridor guard
- GAP-C: `check_ins` — restrict `admin_notes` / `reviewed_by` from player SELECT
- GAP-D: Consider prefixing CI fixture UUIDs with `00000000-` to distinguish from production
