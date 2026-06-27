-- ════════════════════════════════════════════════════════════════════════════
-- Migration 010 — fix NULL token columns on directly-seeded auth.users rows
-- ════════════════════════════════════════════════════════════════════════════
--
-- Root cause: GoTrue v2 reads token columns into non-nullable Go strings.
-- When auth.users rows are seeded via direct INSERT (bypassing GoTrue signup),
-- token columns (confirmation_token, recovery_token, etc.) are not specified
-- and land as NULL. GoTrue then fails to scan the row on sign-in and returns:
--   500 {"error_code":"unexpected_failure","msg":"Database error querying schema"}
--
-- Fix: set all NULL token columns to '' (empty string) for the six known CI
-- seed users. Also idempotent for any other directly-seeded users in the DB.
-- ════════════════════════════════════════════════════════════════════════════

UPDATE auth.users
SET
  confirmation_token         = COALESCE(confirmation_token, ''),
  recovery_token             = COALESCE(recovery_token, ''),
  email_change_token_new     = COALESCE(email_change_token_new, ''),
  email_change_token_current = COALESCE(email_change_token_current, ''),
  reauthentication_token     = COALESCE(reauthentication_token, ''),
  phone_change_token         = COALESCE(phone_change_token, '')
WHERE
  confirmation_token         IS NULL
  OR recovery_token          IS NULL
  OR email_change_token_new  IS NULL
  OR email_change_token_current IS NULL
  OR reauthentication_token  IS NULL
  OR phone_change_token      IS NULL;

-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  null_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO null_count
  FROM auth.users
  WHERE confirmation_token IS NULL
     OR recovery_token IS NULL
     OR email_change_token_new IS NULL
     OR email_change_token_current IS NULL
     OR reauthentication_token IS NULL
     OR phone_change_token IS NULL;

  IF null_count > 0 THEN
    RAISE EXCEPTION '[010] VERIFICATION FAILED: % auth.users rows still have NULL token columns.', null_count;
  END IF;
  RAISE NOTICE '[010] NULL token columns repaired. All auth.users rows clean. ✓';
END;
$$;
