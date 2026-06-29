-- ════════════════════════════════════════════════════════════════════════════
-- Migration 018 — Pin search_path on handle_new_user trigger function
-- ════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS EXISTS:
--   SECURITY DEFINER functions without a pinned search_path are a known
--   PostgreSQL CVE vector — an attacker with CREATE privilege can shadow
--   schema objects (tables, operators) by injecting a schema before `public`
--   in the search path, causing the DEFINER function to resolve objects
--   against attacker-controlled definitions.
--
--   handle_new_user() is a SECURITY DEFINER trigger function defined in
--   migrations 001 and 004 without SET search_path. This migration adds the
--   pin while preserving the exact function body unchanged.
--
--   Risk: MEDIUM. Exploitable only by a database user with CREATE SCHEMA
--   privilege, not by app-layer callers.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Trigger functions are invoked by the trigger mechanism, not by roles —
-- no REVOKE/GRANT needed. The search_path pin is the only security change.

-- ── Verify search_path is now pinned ─────────────────────────────────────────
DO $$
DECLARE
  cfg TEXT;
BEGIN
  SELECT array_to_string(p.proconfig, ', ')
  INTO   cfg
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  p.proname = 'handle_new_user' AND n.nspname = 'public';

  IF cfg IS NULL OR cfg NOT LIKE '%search_path%' THEN
    RAISE EXCEPTION '[018] VERIFICATION FAILED: handle_new_user search_path not pinned. config=%', cfg;
  END IF;

  RAISE NOTICE '[018] handle_new_user: search_path pinned. config=% ✓', cfg;
END $$;
