# Engine Sweep — 2026-06-27 (Post-launch +25h)

**Window:** 2026-06-27 23:27 → 2026-06-28 00:10 EDT
**Operator:** Computer (on `pilotspry-maker` authority)
**Production state at start:** `ACTIVE_HEALTHY`, 0 traveler_profiles, 0 passport_activations, 1 check_in, 2 passports, 8 profiles. Pre-traffic.

## Outcome

| Action | Status |
| --- | --- |
| Vercel: rotate `NEXT_PUBLIC_SUPABASE_URL` (Production) | ✅ Done |
| Vercel: rotate `NEXT_PUBLIC_SUPABASE_ANON_KEY` → `sb_publishable_…` (Production) | ✅ Done |
| Vercel: `SUPABASE_SERVICE_ROLE_KEY` | ⏸ Deferred — placeholder in user's instructions |
| Vercel: Production redeploy | ✅ `dpl_DuoR9qyxvJLyWCnYTP7Uhgq6fJab` — HTTP 200, no legacy JWT in bundle |
| Vercel: Preview env vars | ⚠ Not added — CLI prompt could not be answered non-interactively. Add via Vercel UI. |
| Supabase: dev branch `lockdown-024` | ❌ MIGRATIONS_FAILED (source drift, see below). Deleted to stop billing. |
| Supabase: migration 024 dry-run on prod (BEGIN/ROLLBACK) | ✅ Clean |
| Supabase: migration 024 applied to prod | ⏸ Pending PR review per user direction |
| Source: migrations 020–023 recovered from `schema_migrations` | ✅ Saved to repo |
| Source: PR with 020–024 | ⏸ Building |
| Dashboards | ⏸ Building |

## Findings, by severity

### CRITICAL — `ap_events` and `referral_events` are anon-writable

Two RLS policies grant INSERT to role `{public}` with `WITH CHECK (true)`:

- `public.ap_events` / `Service inserts ap events`
- `public.referral_events` / `Service inserts referrals`

Any client with the publishable key can insert arbitrary rows — meaning mint AP points, fabricate referrals on any traveler ID. Migration 024 § A closes both by restricting to `TO service_role`.

### HIGH — Source ⇄ database drift

Production has 23 applied migrations; repo has 19. Migrations `020`–`023` were applied directly to prod with no source commit. This is why the Supabase dev branch failed to provision (history replay can't find 020+). All four have been recovered from `supabase_migrations.schema_migrations.statements` and committed in this PR.

### HIGH — Three functions with mutable `search_path`

`public.prevent_reward_unclaim`, `corridor.claim_jobs`, `corridor.set_updated_at` have no `SET search_path` clause. Trojan-search-path is a real privilege-escalation surface for SECURITY DEFINER calls. Migration 024 § B pins all three.

### MEDIUM — Auth init-plan: 13 RLS policies re-evaluate `auth.<fn>()` per row

Detected by the Supabase performance advisor. At zero traffic it's invisible; once any traveler accumulates ~100 activations/check-ins, the per-row function call becomes the dominant cost on every list query. Migration 024 § C wraps every call in `(select auth.uid())` so the planner caches a single value per query. Identical semantics, sub-linear cost.

### MEDIUM — 16 foreign keys without covering indexes

The hot ones: `ap_events.traveler_id`, all 7 FKs on `check_ins`, `mission_progress.activation_id`, both FKs on `passport_activations`, both FKs on `passports`, both FKs on `referral_events`, `waitlist_entries.city_id`. Migration 024 § D adds covering indexes for all 16. At current row counts the index creation is instant.

### MEDIUM — `corridor.audit_log` and `corridor.jobs` have RLS on with no policies

This means anything not running as `service_role` (or other bypass) reads/writes nothing. Workers calling `corridor.claim_jobs` work today because they run as service_role and `claim_jobs` is plain SECURITY INVOKER returning rows the caller can already see by virtue of role. But the no-policy state is fragile: any future code path that hits these tables under a different role will silently fail. Migration 024 § E adds explicit service_role-only ALL policies.

### LOW — Public bucket `corridor-covers` allows listing

Read-by-URL is intentional. The current policy `corridor_covers_select_public` is broad SELECT on `storage.objects`, which lets a client enumerate the bucket. Migration 024 § F replaces it with a name-required SELECT (object lookups still work; LIST does not).

### LOW — Leaked-password protection disabled in Supabase Auth

Not fixed in 024 (config, not SQL). Enable in Supabase Auth settings → Password Protection. Cost: zero. Toggle via UI.

### Informational — Schema duplication still unresolved

`traveler_profiles` (PK `id` → `auth.users.id`) and `passports` (`user_id` → `public.profiles.id`, itself → `auth.users.id`) represent two parallel player models. `check_ins` carries both `traveler_id` AND `user_id`, AND `passport_id` AND `activation_id`. Two-stack RLS is intact (both sides have own-rows policies) but inserts must satisfy both — verify app code only writes one stack consistently. Out of scope for tonight's lockdown.

## Stale launch-blocker notes corrected

Memory recorded these as blockers; they are not:

- ✅ Next.js 14.2.35 CVEs — repo is on `next@^16.2.9` (was bumped via `c3a6da2`).
- ✅ ws 8.20.1 DoS — lockfile shows `ws 8.21.0` via overrides.
- ✅ The `traveler_profiles.id` "hidden FK" — it's an explicit, visible FK constraint (`traveler_profiles_id_fkey`).

Memory will be updated post-merge.

## Repo state

- Branch protection on `main`: 4 required checks including RLS Exploit Tests (24) and RLS Regression Tests (reg-01 → reg-04). Admins enforced. Force pushes off. Strong.
- ⚠ Repo is PUBLIC. Source is therefore world-readable. Not changed tonight, but consider before adding any second-class secret to source.

## What remains for the user

1. **Merge the PR**, then `apply_migration 024_lockdown_engine_sweep` (or let CI do it).
2. Add `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` to Vercel Preview environment via Vercel UI.
3. Rotate `SUPABASE_SERVICE_ROLE_KEY` when ready — current value untouched in Vercel + Supabase.
4. (Optional) Enable HaveIBeenPwned password protection in Supabase Auth settings.
5. (Optional) Reconcile `traveler_profiles` ⇄ `passports` — pick one player model.
