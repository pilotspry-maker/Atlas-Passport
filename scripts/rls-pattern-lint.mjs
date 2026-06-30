#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// rls-pattern-lint.mjs — Atlas Passport RLS recursion lint
// ════════════════════════════════════════════════════════════════════════════
//
// Lints Supabase migration files in `supabase/migrations/*.sql` against the
// four RLS recursion / privilege-escalation patterns documented in
// docs/rls_security_patterns.md.
//
//   Pattern A — RLS recursion seed (inline same-table subquery in policy)
//   Pattern B — auth.uid() wrap mismatch (bare vs (select auth.uid()) drift)
//   Pattern C — DROP of a guardrail policy without same-file recreation
//   Pattern D — SECURITY DEFINER function missing SET search_path pin
//
// Usage:
//   node scripts/rls-pattern-lint.mjs                    # lint every migration
//   node scripts/rls-pattern-lint.mjs file1.sql file2... # lint specific files
//   node scripts/rls-pattern-lint.mjs --changed BASE     # lint files changed
//                                                       # vs BASE (git ref)
//   node scripts/rls-pattern-lint.mjs --json             # JSON output
//
// Exit codes:
//   0  no findings
//   1  one or more findings
//   2  invocation / IO error
//
// Designed to be runnable in CI (no external deps — pure Node stdlib) and
// from the pre-commit hook (`scripts/pre-commit-rls.sh`).
//
// Pattern B uses a REPLAY model: for each scanned file, the wrap-form
// distribution is built by replaying all earlier migrations (creates +
// drops) so we compare against the state of the world at the moment that
// file was applied, not the post-PR baseline. Historical rescope migrations
// that intentionally swept all policies on a table to the wrapped form are
// therefore NOT retroactively flagged.
// ════════════════════════════════════════════════════════════════════════════

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, relative } from "node:path";
import { execSync } from "node:child_process";

const REPO_ROOT = process.cwd();
const MIGRATIONS_DIR = "supabase/migrations";
const DOCS_LINK =
  "https://github.com/pilotspry-maker/Atlas-Passport/blob/main/docs/rls_security_patterns.md";

const GUARDRAIL_POLICIES = [
  "profiles_update_own",
  "profiles_select_own",
  "passports_insert_own",
  "check_ins_insert_own",
  "rewards_select_own",
];

const BYPASS_HELPER_PREFIXES = ["committed_", "bypass_rls_", "rls_bypass_"];

// ─── arg parsing ────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const jsonOut = args.includes("--json");
let changedBase = null;
const explicitFiles = [];

for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--changed") {
    changedBase = args[i + 1];
    i++;
  } else if (a.startsWith("--")) {
    // forward-compat: ignore unknown flags
  } else {
    explicitFiles.push(a);
  }
}

// ─── file selection ─────────────────────────────────────────────────────────

function listAllMigrations() {
  if (!existsSync(MIGRATIONS_DIR)) return [];
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql"))
    .map((f) => join(MIGRATIONS_DIR, f))
    .sort();
}

function listChangedMigrations(base) {
  try {
    const out = execSync(
      `git diff --name-only --diff-filter=AMR ${base}...HEAD -- '${MIGRATIONS_DIR}/*.sql'`,
      { encoding: "utf8" },
    );
    return out
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);
  } catch (err) {
    console.error(`error: git diff against ${base} failed: ${err.message}`);
    process.exit(2);
  }
}

let targetFiles;
if (explicitFiles.length > 0) {
  targetFiles = explicitFiles;
} else if (changedBase) {
  targetFiles = listChangedMigrations(changedBase);
} else {
  targetFiles = listAllMigrations();
}

// ─── helpers ────────────────────────────────────────────────────────────────

function readSql(path) {
  try {
    return readFileSync(path, "utf8");
  } catch (err) {
    console.error(`error: cannot read ${path}: ${err.message}`);
    process.exit(2);
  }
}

function lineOfOffset(text, offset) {
  let line = 1;
  for (let i = 0; i < offset && i < text.length; i++) {
    if (text[i] === "\n") line++;
  }
  return line;
}

function snippet(text, max = 200) {
  const collapsed = text.replace(/\s+/g, " ").trim();
  return collapsed.length > max ? collapsed.slice(0, max) + "…" : collapsed;
}

function tableShortName(qualified) {
  if (!qualified) return null;
  const parts = qualified.split(".");
  return parts[parts.length - 1];
}

// Extract every CREATE POLICY ... ; block (case-insensitive).
function extractPolicyBlocks(sql) {
  const blocks = [];
  const re = /create\s+policy\s+/gi;
  let match;
  while ((match = re.exec(sql)) !== null) {
    const start = match.index;
    let i = re.lastIndex;
    let inSingle = false;
    let inDollar = false;
    while (i < sql.length) {
      const c = sql[i];
      const c2 = sql.slice(i, i + 2);
      if (!inDollar && c === "'") inSingle = !inSingle;
      if (!inSingle && c2 === "$$") {
        inDollar = !inDollar;
        i += 2;
        continue;
      }
      if (!inSingle && !inDollar && c === ";") break;
      i++;
    }
    const body = sql.slice(start, i);
    const tblMatch = body.match(
      /\bon\s+((?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*)/i,
    );
    const table = tblMatch ? tblMatch[1].toLowerCase() : null;
    blocks.push({ start, end: i, body, table });
    re.lastIndex = i + 1;
  }
  return blocks;
}

function extractFunctionBlocks(sql) {
  const blocks = [];
  const re = /create\s+(?:or\s+replace\s+)?function\s+/gi;
  let match;
  while ((match = re.exec(sql)) !== null) {
    const start = match.index;
    let i = re.lastIndex;
    const open = sql.indexOf("$$", i);
    if (open < 0) {
      re.lastIndex = i + 1;
      continue;
    }
    const close = sql.indexOf("$$", open + 2);
    if (close < 0) {
      re.lastIndex = i + 1;
      continue;
    }
    let end = sql.indexOf(";", close + 2);
    if (end < 0) end = sql.length;
    const body = sql.slice(start, end);
    blocks.push({ start, end, body });
    re.lastIndex = end + 1;
  }
  return blocks;
}

function policyMentionsBypassHelper(body) {
  return BYPASS_HELPER_PREFIXES.some((pfx) =>
    new RegExp(`\\b${pfx}`, "i").test(body),
  );
}

function classifyPolicyForm(body) {
  const bodyNoWrapped = body.replace(
    /\(\s*select\s+auth\.uid\s*\(\s*\)\s*\)/gi,
    "",
  );
  return {
    usesBare: /\bauth\.uid\s*\(\s*\)/i.test(bodyNoWrapped),
    usesWrapped: /\(\s*select\s+auth\.uid\s*\(\s*\)\s*\)/i.test(body),
  };
}

// ─── pattern detectors ──────────────────────────────────────────────────────

function detectPatternA(file, sql, allFindings) {
  const blocks = extractPolicyBlocks(sql);
  for (const blk of blocks) {
    if (!blk.table) continue;
    if (policyMentionsBypassHelper(blk.body)) continue;
    const short = tableShortName(blk.table);
    const subRe = /\(\s*select\b[\s\S]*?\)/gi;
    let m;
    while ((m = subRe.exec(blk.body)) !== null) {
      const sub = m[0];
      const tableRe = new RegExp(
        `\\b(?:from|join|update|into)\\s+(?:[a-z_][a-z0-9_]*\\.)?${short}\\b`,
        "i",
      );
      if (tableRe.test(sub)) {
        const line = lineOfOffset(sql, blk.start + m.index);
        allFindings.push({
          file,
          line,
          pattern: "A",
          title: "RLS recursion seed — inline subquery against same table",
          why: `Inline SELECT against ${blk.table} inside a policy that protects ${blk.table}. Postgres re-applies the table's own RLS to the subquery → "infinite recursion detected in policy" → PostgREST HTTP 500. Move the subquery into a SECURITY DEFINER helper (see migration 034).`,
          snippet: snippet(sub),
          docs: `${DOCS_LINK}#pattern-a--rls-recursion-seed`,
        });
        break;
      }
    }
  }
}

function detectPatternB(file, sql, wrapFormsBefore, allFindings) {
  const blocks = extractPolicyBlocks(sql);
  for (const blk of blocks) {
    if (!blk.table) continue;
    const { usesBare, usesWrapped } = classifyPolicyForm(blk.body);
    if (!usesBare && !usesWrapped) continue;
    const tableKey = blk.table.toLowerCase();
    // Approximation: if this file already DROPped any policy on this table
    // earlier than the current block, treat the prior wrap-form set as
    // cleared — the migration is sweeping the table.
    const preBlk = sql.slice(0, blk.start);
    const short = tableShortName(blk.table);
    const dropOnSameTable = new RegExp(
      `drop\\s+policy\\s+(?:if\\s+exists\\s+)?"?[a-z_][a-z0-9_]*"?\\s+on\\s+(?:[a-z_][a-z0-9_]*\\.)?${short}\\b`,
      "i",
    );
    const observed = new Set(wrapFormsBefore.get(tableKey) ?? []);
    if (dropOnSameTable.test(preBlk)) observed.clear();

    const conflict =
      (usesBare && observed.has("wrapped")) ||
      (usesWrapped && observed.has("bare"));

    if (conflict) {
      const line = lineOfOffset(sql, blk.start);
      const thisForm = usesBare ? "bare auth.uid()" : "(select auth.uid())";
      const otherForm = usesBare ? "(select auth.uid())" : "bare auth.uid()";
      allFindings.push({
        file,
        line,
        pattern: "B",
        title: "auth.uid() wrap-form mismatch with sibling policies",
        why: `New policy on ${blk.table} uses ${thisForm} but existing policies on the same table use ${otherForm}. Mixing forms creates a recursive evaluation edge — the same drift that caused PR #42 → migration 034. Match the existing wrap form, or rescope every policy on this table in a single migration.`,
        snippet: snippet(blk.body),
        docs: `${DOCS_LINK}#pattern-b--authuid-wrap-mismatch`,
      });
    }
  }
}

function detectPatternC(file, sql, allFindings) {
  for (const name of GUARDRAIL_POLICIES) {
    const dropRe = new RegExp(
      `drop\\s+policy\\s+(?:if\\s+exists\\s+)?"?${name}"?\\s+on\\s+`,
      "gi",
    );
    let m;
    while ((m = dropRe.exec(sql)) !== null) {
      const after = sql.slice(m.index + m[0].length);
      const recreateRe = new RegExp(
        `create\\s+policy\\s+"?${name}"?\\s+on\\s+`,
        "i",
      );
      if (!recreateRe.test(after)) {
        const line = lineOfOffset(sql, m.index);
        allFindings.push({
          file,
          line,
          pattern: "C",
          title: `Guardrail policy "${name}" dropped without recreation`,
          why: `${name} is a named guardrail. Dropping it without a matching CREATE POLICY in the same migration opens a privilege-escalation window. Pair every DROP with a CREATE of the same name before EOF.`,
          snippet: snippet(sql.slice(m.index, m.index + 200)),
          docs: `${DOCS_LINK}#pattern-c--drop-of-a-guardrail-policy-without-recreation`,
        });
      }
    }
  }
}

function detectPatternD(file, sql, allFindings) {
  const blocks = extractFunctionBlocks(sql);
  for (const blk of blocks) {
    if (!/security\s+definer/i.test(blk.body)) continue;
    if (/\bset\s+search_path\b/i.test(blk.body)) continue;
    const line = lineOfOffset(sql, blk.start);
    const nameMatch = blk.body.match(
      /create\s+(?:or\s+replace\s+)?function\s+([a-z_][a-z0-9_.]*)/i,
    );
    const fnName = nameMatch ? nameMatch[1] : "<anonymous>";
    allFindings.push({
      file,
      line,
      pattern: "D",
      title: `SECURITY DEFINER function ${fnName} missing SET search_path`,
      why: `SECURITY DEFINER functions run with the owner's privileges. Without SET search_path = '' an attacker who can create objects in any schema on the caller's path can shadow built-ins or unqualified references and execute their code with elevated rights. Add SET search_path = '' and fully-qualify every table reference inside the function.`,
      snippet: snippet(blk.body),
      docs: `${DOCS_LINK}#pattern-d--security-definer-without-search_path-pin`,
    });
  }
}

// ─── Pattern B replay model ─────────────────────────────────────────────────

function wrapFormsBefore(untilFile, allMigrationFiles) {
  const map = new Map();
  for (const f of allMigrationFiles) {
    if (relative(REPO_ROOT, f) === untilFile) break;
    const sql = readSql(f);
    // Drops first (approximate: clear the form-set on any dropped table).
    const dropRe =
      /drop\s+policy\s+(?:if\s+exists\s+)?"?[a-z_][a-z0-9_]*"?\s+on\s+((?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*)/gi;
    let dm;
    while ((dm = dropRe.exec(sql)) !== null) {
      const t = dm[1].toLowerCase();
      if (map.has(t)) map.get(t).clear();
    }
    // Then creates.
    for (const blk of extractPolicyBlocks(sql)) {
      if (!blk.table) continue;
      const tableKey = blk.table.toLowerCase();
      const { usesBare, usesWrapped } = classifyPolicyForm(blk.body);
      if (!map.has(tableKey)) map.set(tableKey, new Set());
      if (usesBare) map.get(tableKey).add("bare");
      if (usesWrapped) map.get(tableKey).add("wrapped");
    }
  }
  return map;
}

// ─── main ───────────────────────────────────────────────────────────────────

if (targetFiles.length === 0) {
  if (jsonOut) {
    console.log(JSON.stringify({ findings: [], scanned: 0 }, null, 2));
  } else {
    console.log("rls-pattern-lint: no migration files to scan.");
  }
  process.exit(0);
}

const allMigrations = listAllMigrations();
const findings = [];

for (const file of targetFiles) {
  const rel = relative(REPO_ROOT, file);
  if (!existsSync(file)) {
    console.error(`warn: ${rel} not found, skipping`);
    continue;
  }
  const sql = readSql(file);
  const wrapForms = wrapFormsBefore(rel, allMigrations);
  detectPatternA(rel, sql, findings);
  detectPatternB(rel, sql, wrapForms, findings);
  detectPatternC(rel, sql, findings);
  detectPatternD(rel, sql, findings);
}

// ─── reporting ──────────────────────────────────────────────────────────────

if (jsonOut) {
  console.log(
    JSON.stringify(
      { findings, scanned: targetFiles.length, docs: DOCS_LINK },
      null,
      2,
    ),
  );
} else if (findings.length === 0) {
  console.log(
    `✅ rls-pattern-lint: ${targetFiles.length} migration file(s) scanned, no findings.`,
  );
} else {
  console.log(
    `🚨 rls-pattern-lint: ${findings.length} finding(s) across ${targetFiles.length} file(s).\n`,
  );
  console.log(`Reference: ${DOCS_LINK}\n`);
  for (const f of findings) {
    console.log(`── Pattern ${f.pattern} — ${f.title}`);
    console.log(`   ${f.file}:${f.line}`);
    console.log(`   Why: ${f.why}`);
    console.log(`   ${f.snippet}`);
    console.log(`   Docs: ${f.docs}`);
    console.log("");
  }
}

if (process.env.GITHUB_ACTIONS === "true") {
  for (const f of findings) {
    const msg = `Pattern ${f.pattern}: ${f.title}. ${f.why} See ${f.docs}`;
    const esc = (s) =>
      s.replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");
    console.log(
      `::error file=${f.file},line=${f.line},title=RLS Pattern ${f.pattern}::${esc(msg)}`,
    );
  }
}

process.exit(findings.length > 0 ? 1 : 0);
