-- ════════════════════════════════════════════════════════════════════════════
-- Migration 009 — create_regression_users helper (superseded by 008)
-- ════════════════════════════════════════════════════════════════════════════
--
-- IMPORTANT: migration 008 already contains create_regression_users with the
-- correct auth.identities INSERT.  This file re-applies the same function
-- body so that if 009 runs after 008 (alphabetical order), the production DB
-- ends up with the correct version rather than the old one without identities.
--
-- Design invariants (same as 008):
--   - DELETE auth.identities first (FK order), then DELETE auth.users
--   - INSERT both auth.users AND auth.identities
--   - auth.identities.id = user UUID as text; provider_id = same UUID text
--   - No confirmed_at write; auth.identities.email is GENERATED ALWAYS
--   - No ON CONFLICT — surfaces real conflicts as hard errors
-- ════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_regression_users();

CREATE OR REPLACE FUNCTION public.create_regression_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public, extensions
AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
BEGIN
  -- Delete identities first (FK order), then users.
  DELETE FROM auth.identities
  WHERE user_id IN (
    'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0002-0000-0000-000000000000'::uuid
  );

  DELETE FROM auth.users
  WHERE id IN (
    'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0002-0000-0000-000000000000'::uuid
  );

  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, is_super_admin, is_sso_user, deleted_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change_token_current, reauthentication_token, phone_change_token
  ) VALUES
  (
    'bbbbbbbb-0001-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_one@test.atlasci.com',
    crypt('RegPlayer1!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"CI Regression Player One"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', ''
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'reg_player_two@test.atlasci.com',
    crypt('RegPlayer2!RLS', gen_salt('bf')), v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"CI Regression Player Two"}'::jsonb,
    v_now, v_now, false, false, NULL,
    '', '', '', '', '', ''
  );

  -- GoTrue v2 requires auth.identities for email/password sign-in.
  -- id = user UUID as text; provider_id = same UUID text.
  -- DO NOT include `email` column — GENERATED ALWAYS AS (lower(identity_data->>'email')).
  INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES
  (
    'bbbbbbbb-0001-0000-0000-000000000000',
    'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0001-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'bbbbbbbb-0001-0000-0000-000000000000',
      'reg_player_one@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
  ),
  (
    'bbbbbbbb-0002-0000-0000-000000000000',
    'bbbbbbbb-0002-0000-0000-000000000000'::uuid,
    'bbbbbbbb-0002-0000-0000-000000000000',
    format('{"sub":"%s","email":"%s"}',
      'bbbbbbbb-0002-0000-0000-000000000000',
      'reg_player_two@test.atlasci.com')::jsonb,
    'email', v_now, v_now, v_now
  );

  RETURN jsonb_build_object(
    'reg_player_one_id', 'bbbbbbbb-0001-0000-0000-000000000000'::uuid,
    'reg_player_two_id', 'bbbbbbbb-0002-0000-0000-000000000000'::uuid,
    'status', 'ok'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_regression_users() TO anon;
GRANT EXECUTE ON FUNCTION public.create_regression_users() TO authenticated;

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'create_regression_users'
  ) THEN
    RAISE EXCEPTION '[009] VERIFICATION FAILED: create_regression_users function not found.';
  END IF;
  RAISE NOTICE '[009] create_regression_users: present. ✓';
END;
$$;
