-- ============================================================
-- Atlas Passport — Schema Verification Script
-- Run after 000_idempotent_full_schema.sql to confirm all
-- objects exist and are correctly configured.
-- ============================================================

-- ─── Tables ────────────────────────────────────────────────
SELECT
  t.table_name,
  CASE WHEN t.table_name IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS status
FROM (VALUES
  ('profiles'), ('corridors'), ('nodes'),
  ('passports'), ('check_ins'), ('rewards')
) AS expected(table_name)
LEFT JOIN information_schema.tables t
  ON t.table_schema = 'public' AND t.table_name = expected.table_name
ORDER BY expected.table_name;

-- ─── Columns (referral_code) ───────────────────────────────
SELECT
  CASE WHEN COUNT(*) = 1 THEN 'EXISTS' ELSE 'MISSING' END AS referral_code_column
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'profiles'
  AND column_name  = 'referral_code';

-- ─── Indexes ───────────────────────────────────────────────
SELECT
  expected.name AS index_name,
  CASE WHEN i.indexname IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS status
FROM (VALUES
  ('idx_nodes_corridor_id'),
  ('idx_nodes_sequence'),
  ('idx_passports_user_id'),
  ('idx_passports_status'),
  ('idx_passports_expires_at'),
  ('idx_check_ins_passport_id'),
  ('idx_check_ins_status'),
  ('idx_check_ins_user_id'),
  ('idx_check_ins_submitted_at')
) AS expected(name)
LEFT JOIN pg_indexes i
  ON i.schemaname = 'public' AND i.indexname = expected.name
ORDER BY expected.name;

-- ─── RLS Enabled ───────────────────────────────────────────
SELECT
  relname AS table_name,
  CASE WHEN relrowsecurity THEN 'ENABLED' ELSE 'DISABLED' END AS rls_status
FROM pg_class
WHERE relnamespace = 'public'::regnamespace
  AND relname IN ('profiles','corridors','nodes','passports','check_ins','rewards')
ORDER BY relname;

-- ─── RLS Policies ──────────────────────────────────────────
SELECT
  tablename,
  policyname,
  cmd AS operation
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- ─── Trigger ───────────────────────────────────────────────
SELECT
  CASE WHEN COUNT(*) = 1 THEN 'EXISTS' ELSE 'MISSING' END AS on_auth_user_created_trigger
FROM pg_trigger
WHERE tgname = 'on_auth_user_created';

-- ─── Storage Buckets ───────────────────────────────────────
SELECT
  expected.id,
  CASE WHEN b.id IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS status,
  b.public,
  b.file_size_limit
FROM (VALUES ('check-in-proofs'), ('corridor-covers')) AS expected(id)
LEFT JOIN storage.buckets b ON b.id = expected.id
ORDER BY expected.id;

-- ─── Storage Policies ──────────────────────────────────────
SELECT
  policyname,
  cmd AS operation
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects'
ORDER BY policyname;

-- ─── Realtime Publication ──────────────────────────────────
SELECT
  expected.tablename,
  CASE WHEN pt.tablename IS NOT NULL THEN 'IN PUBLICATION' ELSE 'MISSING' END AS realtime_status
FROM (VALUES ('check_ins'), ('passports')) AS expected(tablename)
LEFT JOIN pg_publication_tables pt
  ON pt.pubname = 'supabase_realtime'
  AND pt.schemaname = 'public'
  AND pt.tablename = expected.tablename
ORDER BY expected.tablename;
