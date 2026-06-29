# Atlas Passport — RLS Recursion & Security Patterns (A–D)

**Audience:** any developer authoring a Supabase migration or RLS policy on `pilotspry-maker/Atlas-Passport`.
**Enforced by:**
- Monday RLS recursion sentinel — cron `549768ec` (scans merged migrations, last 7 days)
- Nightly open-PR scanner — cron `e595a672` (scans every open PR before merge)

Both crons grep for the patterns below and post to [issue #43](https://github.com/pilotspry-maker/Atlas-Passport/issues/43) when they find one. Silent on green.

**Canonical fix reference:** migration `034_fix_profiles_update_own_500.sql` (shipped in [PR #46](https://github.com/pilotspry-maker/Atlas-Passport/pull/46)) — the `committed_is_admin()` SECURITY DEFINER helper is the model for resolving Pattern A.

---

## Pattern A — RLS recursion seed

**What it is:** an inline subquery against the *same table* the policy protects, placed directly inside a `CREATE POLICY ... USING` or `WITH CHECK` clause, without a SECURITY DEFINER helper to bypass RLS.

**Why it's dangerous:** when the policy evaluates the subquery, Postgres re-applies the table's own RLS policies to that subquery. If any of those policies also reference the table (even indirectly), Postgres throws `infinite recursion detected in policy for relation "<table>"`. PostgREST translates that into **HTTP 500** — the request is rejected, but with the wrong status code, which is what broke `profiles_update_own` and the three `is_admin` regression tests.

**Canonical broken shape (migration 005, pre-034):**

```sql
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  USING ((select auth.uid()) = id)
  WITH CHECK (
    (select auth.uid()) = id
    AND is_admin = (SELECT is_admin FROM public.profiles WHERE id = auth.uid())
    --              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    --              recursion seed: subquery against public.profiles inside a
    --              policy that itself protects public.profiles
  );
```

**Canonical fix (migration 034):** move the subquery into a `SECURITY DEFINER` helper that runs with the owner's privileges and bypasses RLS:

```sql
CREATE OR REPLACE FUNCTION public.committed_is_admin(uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT is_admin FROM public.profiles WHERE id = uid
$$;

REVOKE ALL ON FUNCTION public.committed_is_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.committed_is_admin(uuid) TO authenticated;

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  USING ((select auth.uid()) = id)
  WITH CHECK (
    (select auth.uid()) = id
    AND is_admin = public.committed_is_admin((select auth.uid()))
  );
```

**Sentinel heuristic:** within every `CREATE POLICY` block (multi-line, ends at the next semicolon), extract the target table name and look for that name inside a parenthesized `SELECT` subquery in the `USING`/`WITH CHECK` body. If found AND the surrounding policy does not invoke a helper whose name starts with `committed_` (or similar bypass-prefix convention), flag it.

---

## Pattern B — `auth.uid()` wrap mismatch

**What it is:** a new policy uses bare `auth.uid()` on a table whose existing policies on `main` have all been rescoped to `(select auth.uid())`, or vice versa.

**Why it's dangerous:** Postgres treats `(select auth.uid())` as an initplan — evaluated **once** per query — while bare `auth.uid()` is evaluated **per row**. When the two forms coexist on the same table, the planner can build a recursive evaluation edge: row N's policy check triggers a re-scan of the table under the *other* policy form, which re-enters policy evaluation on the same table. This is the exact drift that PR #42 introduced and PR #46 / migration 034 had to clean up.

**Broken shape (mixing forms across migrations):**

```sql
-- migration 033 (merged, rescoped to wrapped form)
CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT
  USING ((select auth.uid()) = id);   -- wrapped — initplan, single evaluation

-- new migration in a PR (bare form re-introduced)
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id);            -- bare — per-row evaluation
  --     ^^^^^^^^^^
  --     wrap mismatch with sibling policies on the same table
```

**Fix:** match the existing form on `main`. If sibling policies wrap as `(select auth.uid())`, the new policy must too. If you genuinely want to revert the rescope, do it for **every** policy on that table in a single migration — never half-rescoped.

**Sentinel heuristic:** for each table touched by a new policy in the diff, grep all existing migrations for that table's other policies. If the existing set uses `(select auth.uid())` and the new policy uses bare `auth.uid()` (or vice versa), flag it.

---

## Pattern C — DROP of a guardrail policy without recreation

**What it is:** a `DROP POLICY` statement targeting one of Atlas Passport's named guardrail policies, without a matching `CREATE POLICY` for the same name later in the same SQL file.

**Protected names:**
- `profiles_update_own`
- `profiles_select_own`
- `passports_insert_own`
- `check_ins_insert_own`
- `rewards_select_own`

**Why it's dangerous:** these policies are the only thing standing between an authenticated user and writing arbitrary rows on someone else's profile/passport/check-in/reward. Dropping one without an immediate replacement opens a privilege-escalation window for every request between migration apply and the next migration. If the dropping migration ships solo, that window is permanent.

**Broken shape:**

```sql
-- migration 0XX (DANGEROUS — guardrail dropped, never recreated)
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

-- ...end of file...
-- no matching CREATE POLICY "profiles_update_own" — table is now wide open
-- to any authenticated user with an UPDATE statement
```

**Fix:** every `DROP POLICY` on a guardrail name must be paired with a `CREATE POLICY` of the same name in the same migration file, before the next `COMMIT` or end-of-file:

```sql
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  USING ((select auth.uid()) = id)
  WITH CHECK (
    (select auth.uid()) = id
    AND is_admin = public.committed_is_admin((select auth.uid()))
  );
```

**Sentinel heuristic:** regex for `DROP POLICY (IF EXISTS )?"?<guardrail-name>"?` then scan forward in the same file for a `CREATE POLICY "?<same-name>"?` before the next `COMMIT` or EOF. If absent, flag.

---

## Pattern D — `SECURITY DEFINER` without `search_path` pin

**What it is:** a new `CREATE FUNCTION` (or `CREATE OR REPLACE FUNCTION`) declared `SECURITY DEFINER` whose body does **not** contain `SET search_path = ''` (or any explicit `SET search_path`).

**Why it's dangerous:** a SECURITY DEFINER function runs with the **owner's** privileges, not the caller's. If `search_path` isn't pinned, an attacker who can create a function or table in any schema on the caller's path (e.g. a temp schema or `public` if writable) can shadow a built-in like `pg_catalog.format` or an unqualified table reference inside the function. The next time the function runs, it executes the attacker's shadowed object with the function owner's privileges — classic Supabase privilege-escalation foot-gun, flagged by Supabase's own linter.

**Broken shape:**

```sql
CREATE OR REPLACE FUNCTION public.committed_is_admin(uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
-- ^^^^^^^^^^^^^^^ runs with owner privileges
-- no SET search_path — vulnerable to schema-shadowing attack
AS $$
  SELECT is_admin FROM profiles WHERE id = uid
  --              ^^^^^^^^      ^^^^^^^^
  --              unqualified — resolved through search_path at call time
$$;
```

**Fix:** always pin `search_path` to the empty string and fully-qualify every table reference inside the function:

```sql
CREATE OR REPLACE FUNCTION public.committed_is_admin(uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''                                  -- pin it
AS $$
  SELECT is_admin FROM public.profiles WHERE id = uid -- fully qualified
$$;

REVOKE ALL ON FUNCTION public.committed_is_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.committed_is_admin(uuid) TO authenticated;
```

**Sentinel heuristic:** capture each `CREATE FUNCTION` (or `CREATE OR REPLACE FUNCTION`) block ending at the matching `$$ LANGUAGE` / `$$;`. If `SECURITY DEFINER` appears in the block and `SET search_path` does not, flag it.

---

## Suggested workflow when the sentinel flags your PR

1. **Open the consolidated comment on issue #43** — it identifies the file, line, pattern letter, and a 200-char snippet.
2. **Match the pattern to its fix above.** Pattern A → SECURITY DEFINER helper. Pattern B → match the wrap form on `main`. Pattern C → pair every `DROP POLICY` on a guardrail name with a `CREATE POLICY` in the same file. Pattern D → add `SET search_path = ''` and fully qualify references.
3. **Re-run CI locally** against the RLS regression and exploit suites before pushing the fix. Both suites should return the expected `401`/`403` status codes — not `UNKNOWN (500)`, which is the recursion signature.
4. **If the lint is a false positive** (e.g. you're intentionally using bare `auth.uid()` on a new table that has no existing policies), reply on issue #43 explaining the reasoning so the next reviewer can decide whether to refine the heuristic.

## Reference docs

- `docs/CRON_NO_CREDENTIAL_PROMPT_GUARDRAIL.md` — cron credential hard rules
- `docs/ATLAS_CRON_STANDARDS.md` — cron authoring standards
- Migration `034_fix_profiles_update_own_500.sql` — canonical recursion-fix pattern
- [Supabase: SECURITY DEFINER functions](https://supabase.com/docs/guides/database/functions#security-definer-vs-invoker)
- [PostgreSQL: Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)

— Maintained alongside the Monday sentinel (`549768ec`) and nightly PR scanner (`e595a672`).
