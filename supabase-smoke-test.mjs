/**
 * supabase-smoke-test.mjs
 *
 * Verifies that the anon key + dual-header auth setup is working against
 * the Atlas Passport Supabase project.
 *
 * SAFE TO COMMIT — reads the key from env only. Never hardcode the key here.
 *
 * Usage:
 *   SUPABASE_ANON_KEY=<your anon key> node supabase-smoke-test.mjs
 *
 * Windows PowerShell:
 *   $env:SUPABASE_ANON_KEY = "<your anon key>"
 *   node supabase-smoke-test.mjs
 */

const KEY = process.env.SUPABASE_ANON_KEY;
if (!KEY) {
  console.error('ERROR: SUPABASE_ANON_KEY is not set.');
  console.error('');
  console.error('PowerShell:  $env:SUPABASE_ANON_KEY = "<paste key here>"');
  console.error('Bash:        read -s SUPABASE_ANON_KEY && export SUPABASE_ANON_KEY');
  console.error('');
  console.error('Then run: node supabase-smoke-test.mjs');
  process.exit(1);
}

const BASE = 'https://gaavynmmysdhovpatzlp.supabase.co/rest/v1';

const HEADERS = {
  // Both headers required — PostgREST returns "No API key found" without apikey,
  // and 401 without Authorization: Bearer.
  'apikey': KEY,
  'Authorization': `Bearer ${KEY}`,
  'Content-Type': 'application/json',
  'Prefer': 'return=representation',
};

async function call(method, path, body) {
  const url = `${BASE}${path}`;
  const opts = { method, headers: HEADERS };
  if (body !== undefined) opts.body = JSON.stringify(body);

  const res = await fetch(url, opts);
  const text = await res.text();
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = text; }

  return { status: res.status, ok: res.ok, body: parsed };
}

function truncate(val, n = 500) {
  const s = typeof val === 'string' ? val : JSON.stringify(val, null, 2);
  return s.length > n ? s.slice(0, n) + '  …[truncated]' : s;
}

function label(tag, method, path, { status, ok, body }) {
  console.log('');
  console.log(`── ${tag} ─────────────────────────────────────`);
  console.log(`   ${method} ${path}`);
  console.log(`   status: ${status}  ok: ${ok}`);
  console.log(`   body:   ${truncate(body)}`);
}

function interpret(tag, status, body) {
  const bodyStr = typeof body === 'string' ? body : JSON.stringify(body);
  console.log(`   ↳ interpretation:`);

  if (tag === 'A') {
    if (status === 200) console.log('      ✅ Auth headers accepted. The anon key + dual-header setup is working.');
    else if (status === 404) console.log('      ✅ 404 on / is fine — it still proves the key was accepted (not 401).');
    else if (status === 401) console.log('      ❌ 401 — auth rejected. Re-check the anon key value.');
    else console.log(`      ⚠️  Unexpected status ${status}. Check the key and project URL.`);
  }

  if (tag === 'B') {
    if (status === 200 && Array.isArray(body) && body.length === 0)
      console.log('      ✅ RLS is ON and protecting the table. Anon SELECT returns [] — safe.');
    else if (status === 200 && Array.isArray(body) && body.length > 0)
      console.log('      ℹ️  Rows returned. Either a SELECT policy grants anon access, or RLS is off.');
    else if (status === 404)
      console.log('      ⚠️  Table not found or not exposed in the public schema.');
    else if (status === 401 || status === 403)
      console.log('      ❌ Auth error on a read. The anon key may be wrong or headers are missing.');
    else if (status === 400 && bodyStr.includes('permission denied'))
      console.log('      ⚠️  Permission denied. RLS may be off but the anon role lacks USAGE on schema public.');
    else
      console.log(`      ⚠️  Unexpected status ${status}.`);
  }

  if (tag === 'C') {
    if (status === 201)
      console.log('      ⚠️  INSERT succeeded. An INSERT policy allows anon writes — tighten RLS if not intentional.');
    else if ((status === 401 || status === 403) ||
             (status === 400 && bodyStr.includes('row-level security')))
      console.log('      ✅ RLS blocked the INSERT — expected and safe. This is the correct default.');
    else if (status === 400 && (bodyStr.includes('column') || bodyStr.includes('null value')))
      console.log('      ℹ️  Schema mismatch on the column name — but auth worked. Adjust the POST body to match the schema.');
    else
      console.log(`      ⚠️  Unexpected status ${status}.`);
  }
}

// ── Run probes ────────────────────────────────────────────────────────────────

console.log('Atlas Passport — Supabase anon-key smoke test');
console.log('Project: gaavynmmysdhovpatzlp');
console.log('');

// A) Root / schema sanity
const a = await call('GET', '/');
label('A — schema sanity', 'GET', '/', a);
interpret('A', a.status, a.body);

// B) Read probe — corridors (Atlas table; anon SELECT allowed on active rows)
const b = await call('GET', '/corridors?select=id,name,is_active&limit=1');
label('B — read probe (corridors)', 'GET', '/corridors?select=id,name,is_active&limit=1', b);
interpret('B', b.status, b.body);

// C) Write probe — profiles (should be blocked by RLS; anon INSERT must fail)
const c = await call('POST', '/profiles', { id: '00000000-0000-0000-0000-000000000000', email: 'smoke-test@example.com' });
label('C — write probe (profiles INSERT)', 'POST', '/profiles', c);
interpret('C', c.status, c.body);

console.log('');
console.log('── Summary ──────────────────────────────────────────────────────');
const authOk = a.status === 200 || a.status === 404;
const rlsReadOk = b.status === 200;
const rlsWriteBlocked = c.status !== 201;
console.log(`   Auth (dual-header):  ${authOk ? '✅ working' : '❌ FAILED'}`);
console.log(`   RLS read (corridors): ${rlsReadOk ? '✅ responding' : '⚠️  check status above'}`);
console.log(`   RLS write (profiles): ${rlsWriteBlocked ? '✅ blocked (safe)' : '⚠️  INSERT succeeded — review RLS'}`);
console.log('');
