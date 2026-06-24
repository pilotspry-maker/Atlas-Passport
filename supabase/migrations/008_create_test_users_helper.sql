-- ════════════════════════════════════════════════════════════════════════════
-- Migration 008 — create_test_users helper
-- ════════════════════════════════════════════════════════════════════════════
--
-- ROOT CAUSE FIX: Prior versions deleted stale rows WHERE email = '...' before
-- inserting. Stale rows from prior runs may have the same fixed UUIDs but
-- different emails — the email-based DELETE misses them, the INSERT hits a
-- PRIMARY KEY conflict, ON CONFLICT DO NOTHING silences it, and the return
-- SELECT WHERE email = '...' finds nothing. Both IDs returned NULL.
--
-- FIX: Delete by UUID (not by email) and drop ON CONFLICT DO NOTHING so any
-- remaining conflict surfaces as a real error rather than a silent skip.
-- ════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_test_users();

CREATE OR REPLACE FUNCTION public.create_test_users()
RETURNS TABLE(user_id uuid, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  v_now timestamptz := now();
BEGIN
  -- Delete by UUID (not by email) — removes stale rows regardless of email
  DELETE FROM auth.users
  WHERE id IN (
    'aaaaaaaa-0001-0000-0000-000000000000'::uuid,
    'aaaaaaaa-0002-0000-0000-000000000000'::uuid
  );

  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, is_super_admin, is_sso_user, deleted_at
  ) VALUES
  (
    'aaaaaaaa-0001-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_player@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    v_now, v_now, false, false, NULL
  ),
  (
    'aaaaaaaa-0002-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'ci_admin@test.local',
    crypt('TestPassword123!', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"is_admin":true}'::jsonb,
    v_now, v_now, false, false, NULL
  );

  -- Return by UUID (not by email) to avoid stale-email lookup race
  RETURN QUERY
    SELECT u.id, u.email FROM auth.users u
    WHERE u.id IN (
      'aaaaaaaa-0001-0000-0000-000000000000',
      'aaaaaaaa-0002-0000-0000-000000000000'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_test_users() TO anon;
GRANT EXECUTE ON FUNCTION public.create_test_users() TO authenticated;

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_test_users'
  ) THEN
    RAISE EXCEPTION '[008] VERIFICATION FAILED: create_test_users function not found.';
  END IF;
  RAISE NOTICE '[008] create_test_users: present. ✓';
END;
$$;
