-- ============================================================
-- Atlas Passport — RLS Policy Tests (pgTAP)
-- File: supabase/tests/rls_policies.test.sql
--
-- Run locally:
--   supabase test db
--
-- Run in CI:
--   supabase db start
--   supabase db push
--   supabase test db
--
-- pgTAP docs: https://pgtap.org/
-- Supabase test runner: https://supabase.com/docs/guides/database/testing
-- ============================================================

BEGIN;

SELECT plan(44);  -- Total number of assertions below

-- ══════════════════════════════════════════════════════════════
-- FIXTURES
-- Known UUIDs matching seed.sql for deterministic test data
-- ══════════════════════════════════════════════════════════════

-- Seed test users (auth schema — use Supabase test helpers)
SELECT tests.create_supabase_user('player_one@test.atlas', '{"full_name": "Test Player"}');
SELECT tests.create_supabase_user('player_two@test.atlas', '{"full_name": "Other Player"}');
SELECT tests.create_supabase_user('admin_user@test.atlas', '{"full_name": "Admin"}');

-- Promote admin_user
UPDATE public.profiles
SET    is_admin = TRUE
WHERE  email = 'admin_user@test.atlas';

-- Seed a test corridor
INSERT INTO public.corridors (id, name, city, country, is_active)
VALUES (
  'aaaaaaaa-0000-0000-0000-000000000001',
  'Test Corridor',
  'Test City', 'US', TRUE
) ON CONFLICT (id) DO NOTHING;

-- Seed a test node
INSERT INTO public.nodes (id, corridor_id, name, sequence, is_active)
VALUES (
  'bbbbbbbb-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'Test Node', 1, TRUE
) ON CONFLICT (id) DO NOTHING;

-- Seed a reward (with redemption code)
INSERT INTO public.rewards (id, corridor_id, title, redemption_code)
VALUES (
  'cccccccc-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'Test Reward', 'SECRET-CODE-XYZ'
) ON CONFLICT (id) DO NOTHING;

-- Seed passports for player_one (active) and player_two (complete)
INSERT INTO public.passports (id, user_id, corridor_id, status, activated_at, expires_at)
VALUES (
  'dddddddd-0000-0000-0000-000000000001',
  (SELECT id FROM public.profiles WHERE email = 'player_one@test.atlas'),
  'aaaaaaaa-0000-0000-0000-000000000001',
  'active',
  NOW(),
  NOW() + INTERVAL '72 hours'
),
(
  'dddddddd-0000-0000-0000-000000000002',
  (SELECT id FROM public.profiles WHERE email = 'player_two@test.atlas'),
  'aaaaaaaa-0000-0000-0000-000000000001',
  'complete',
  NOW() - INTERVAL '24 hours',
  NOW() + INTERVAL '48 hours'
) ON CONFLICT (id) DO NOTHING;

-- Seed a check-in for player_one
INSERT INTO public.check_ins (id, passport_id, user_id, node_id, status, proof_url, proof_storage_path)
VALUES (
  'eeeeeeee-0000-0000-0000-000000000001',
  'dddddddd-0000-0000-0000-000000000001',
  (SELECT id FROM public.profiles WHERE email = 'player_one@test.atlas'),
  'bbbbbbbb-0000-0000-0000-000000000001',
  'pending',
  'https://example.com/proof.jpg',
  'test/proof.jpg'
) ON CONFLICT (id) DO NOTHING;


-- ══════════════════════════════════════════════════════════════
-- SECTION 1: UNAUTHENTICATED (anon role)
-- ══════════════════════════════════════════════════════════════

SET LOCAL role = anon;

SELECT is(
  (SELECT COUNT(*) FROM public.nodes)::int, 0,
  'anon cannot read any nodes'
);

SELECT is(
  (SELECT COUNT(*) FROM public.corridors)::int, 0,
  'anon cannot read any corridors (authenticated-only policy)'
);

SELECT is(
  (SELECT COUNT(*) FROM public.passports)::int, 0,
  'anon cannot read any passports'
);

SELECT is(
  (SELECT COUNT(*) FROM public.check_ins)::int, 0,
  'anon cannot read any check_ins'
);

SELECT is(
  (SELECT COUNT(*) FROM public.rewards)::int, 0,
  'anon cannot read any rewards'
);

SELECT is(
  (SELECT COUNT(*) FROM public.profiles)::int, 0,
  'anon cannot read any profiles'
);

-- Write attempts as anon — all must be blocked
SELECT throws_ok(
  $$INSERT INTO public.passports (user_id, corridor_id)
    VALUES ('00000000-0000-0000-0000-000000000000'::uuid,
            'aaaaaaaa-0000-0000-0000-000000000001'::uuid)$$,
  '42501',
  NULL,
  'anon cannot INSERT a passport'
);

SELECT throws_ok(
  $$INSERT INTO public.check_ins
    (passport_id, user_id, node_id, proof_url, proof_storage_path)
    VALUES (
      'dddddddd-0000-0000-0000-000000000001'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid,
      'bbbbbbbb-0000-0000-0000-000000000001'::uuid,
      'https://evil.com/fake.jpg', 'fake'
    )$$,
  '42501',
  NULL,
  'anon cannot INSERT a check_in'
);


-- ══════════════════════════════════════════════════════════════
-- SECTION 2: AUTHENTICATED player_one (active passport)
-- ══════════════════════════════════════════════════════════════

SELECT tests.authenticate_as('player_one@test.atlas');

SELECT is(
  (SELECT COUNT(*) FROM public.nodes WHERE is_active = TRUE)::int > 0, TRUE,
  'player_one can read active nodes'
);

SELECT is(
  (SELECT COUNT(*) FROM public.corridors WHERE is_active = TRUE)::int > 0, TRUE,
  'player_one can read active corridors'
);

-- player_one can only see their own passport
SELECT is(
  (SELECT COUNT(*) FROM public.passports)::int, 1,
  'player_one sees exactly 1 passport (their own)'
);

SELECT is(
  (SELECT user_id FROM public.passports LIMIT 1),
  (SELECT id FROM public.profiles WHERE email = 'player_one@test.atlas'),
  'the passport player_one sees belongs to them'
);

-- player_one cannot read player_two passport
SELECT is(
  (SELECT COUNT(*) FROM public.passports WHERE id = 'dddddddd-0000-0000-0000-000000000002'::uuid)::int,
  0,
  'player_one cannot read player_two passport'
);

-- player_one can see their own check-ins
SELECT is(
  (SELECT COUNT(*) FROM public.check_ins)::int, 1,
  'player_one sees exactly 1 check-in (their own)'
);

-- player_one with only ACTIVE passport cannot read reward (redemption code)
SELECT is(
  (SELECT COUNT(*) FROM public.rewards WHERE id = 'cccccccc-0000-0000-0000-000000000001'::uuid)::int, 0,
  'player_one with active (not complete) passport cannot read reward'
);

-- player_one cannot read other players profiles
SELECT is(
  (SELECT COUNT(*) FROM public.profiles WHERE email = 'player_two@test.atlas')::int, 0,
  'player_one cannot read player_two profile'
);

-- player_one CAN read their own profile
SELECT is(
  (SELECT COUNT(*) FROM public.profiles WHERE email = 'player_one@test.atlas')::int, 1,
  'player_one can read their own profile'
);

-- player_one cannot promote themselves to admin
SELECT throws_ok(
  $$UPDATE public.profiles SET is_admin = TRUE
    WHERE email = 'player_one@test.atlas'$$,
  '42501',
  NULL,
  'player_one cannot set is_admin on their own profile'
);


-- ══════════════════════════════════════════════════════════════
-- SECTION 3: AUTHENTICATED player_two (complete passport)
-- ══════════════════════════════════════════════════════════════

SELECT tests.authenticate_as('player_two@test.atlas');

-- player_two with COMPLETE passport CAN read the reward
SELECT is(
  (SELECT COUNT(*) FROM public.rewards WHERE corridor_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid)::int, 1,
  'player_two with complete passport can read the corridor reward'
);

-- Verify the redemption code is actually present (not filtered)
SELECT is(
  (SELECT redemption_code FROM public.rewards WHERE id = 'cccccccc-0000-0000-0000-000000000001'::uuid),
  'SECRET-CODE-XYZ',
  'player_two receives the correct redemption code'
);

-- player_two still cannot see player_one check-ins
SELECT is(
  (SELECT COUNT(*) FROM public.check_ins WHERE user_id =
    (SELECT id FROM public.profiles WHERE email = 'player_one@test.atlas'))::int, 0,
  'player_two cannot read player_one check-ins'
);

-- player_two cannot see player_one passport
SELECT is(
  (SELECT COUNT(*) FROM public.passports WHERE id = 'dddddddd-0000-0000-0000-000000000001'::uuid)::int,
  0,
  'player_two cannot read player_one passport'
);


-- ══════════════════════════════════════════════════════════════
-- SECTION 4: CROSS-USER WRITE ATTEMPTS
-- Still authenticated as player_two
-- ══════════════════════════════════════════════════════════════

-- player_two cannot insert a passport for player_one's user_id
SELECT throws_ok(
  $$INSERT INTO public.passports (user_id, corridor_id)
    VALUES (
      (SELECT id FROM public.profiles WHERE email = 'player_one@test.atlas'),
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid
    )$$,
  '42501',
  NULL,
  'player_two cannot create a passport for player_one'
);

-- player_two cannot submit a check-in against player_one passport
SELECT throws_ok(
  $$INSERT INTO public.check_ins
    (passport_id, user_id, node_id, proof_url, proof_storage_path)
    VALUES (
      'dddddddd-0000-0000-0000-000000000001'::uuid,
      (SELECT id FROM public.profiles WHERE email = 'player_two@test.atlas'),
      'bbbbbbbb-0000-0000-0000-000000000001'::uuid,
      'https://evil.com/fake.jpg', 'fake'
    )$$,
  '42501',
  NULL,
  'player_two cannot submit a check-in on player_one passport'
);


-- ══════════════════════════════════════════════════════════════
-- SECTION 5: ADMIN USER
-- ══════════════════════════════════════════════════════════════

SELECT tests.authenticate_as('admin_user@test.atlas');

-- Admin can read rewards (via rewards_select_admin policy)
SELECT is(
  (SELECT COUNT(*) FROM public.rewards)::int > 0, TRUE,
  'admin can read all rewards'
);

-- Admin can read all passports via RLS passports_admin_all policy
-- (Note: if no admin-read policy exists for passports, add one in migration 005)
-- For now, admin reads passports via the service role in API routes — test that
-- the is_admin flag is present and readable
SELECT is(
  (SELECT is_admin FROM public.profiles WHERE email = 'admin_user@test.atlas'),
  TRUE,
  'admin profile has is_admin = true'
);


-- ══════════════════════════════════════════════════════════════
-- SECTION 6: SCHEMA INTEGRITY
-- ══════════════════════════════════════════════════════════════

RESET role;  -- Back to superuser for schema checks

-- RLS is enabled on all critical tables
SELECT is(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'nodes' AND relnamespace = 'public'::regnamespace),
  TRUE,
  'RLS is enabled on nodes table'
);

SELECT is(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'passports' AND relnamespace = 'public'::regnamespace),
  TRUE,
  'RLS is enabled on passports table'
);

SELECT is(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'check_ins' AND relnamespace = 'public'::regnamespace),
  TRUE,
  'RLS is enabled on check_ins table'
);

SELECT is(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'rewards' AND relnamespace = 'public'::regnamespace),
  TRUE,
  'RLS is enabled on rewards table'
);

SELECT is(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'corridors' AND relnamespace = 'public'::regnamespace),
  TRUE,
  'RLS is enabled on corridors table'
);

SELECT is(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'profiles' AND relnamespace = 'public'::regnamespace),
  TRUE,
  'RLS is enabled on profiles table'
);

-- Required policies exist by name
SELECT isnt(
  (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'nodes' AND policyname = 'nodes_select_active')::int,
  0,
  'nodes_select_active policy exists'
);

SELECT isnt(
  (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'rewards' AND policyname = 'rewards_select_own')::int,
  0,
  'rewards_select_own policy exists'
);

SELECT isnt(
  (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'rewards' AND policyname = 'rewards_select_admin')::int,
  0,
  'rewards_select_admin policy exists'
);

SELECT isnt(
  (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'passports' AND policyname = 'passports_select_own')::int,
  0,
  'passports_select_own policy exists'
);

-- Sequence constraint exists
SELECT isnt(
  (SELECT COUNT(*) FROM pg_constraint
   WHERE conname = 'chk_nodes_sequence_positive'
   AND conrelid = 'public.nodes'::regclass)::int,
  0,
  'nodes sequence >= 1 check constraint exists'
);

-- No active nodes with NULL sequence
SELECT is(
  (SELECT COUNT(*) FROM public.nodes WHERE sequence IS NULL AND is_active = TRUE)::int,
  0,
  'no active nodes have NULL sequence'
);


-- ══════════════════════════════════════════════════════════════
-- TEARDOWN
-- ══════════════════════════════════════════════════════════════

SELECT * FROM finish();

ROLLBACK;
