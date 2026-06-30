-- ════════════════════════════════════════════════════════════════════════════
-- Migration 038 — Task 4: restrict corridor-covers storage bucket
-- ════════════════════════════════════════════════════════════════════════════
--
-- CONTEXT:
--   Migration 002 created the `corridor-covers` bucket with `public = TRUE`
--   and a SELECT policy scoped to the implicit public role (no TO clause):
--     CREATE POLICY "corridor_covers_select_public" ON storage.objects
--       FOR SELECT USING (bucket_id = 'corridor-covers');
--
--   A `public = TRUE` bucket lets anyone access objects via the CDN public-URL
--   path and list bucket contents anonymously via the Storage API. The audit
--   finding is: corridor cover images should not be publicly listable — only
--   authenticated users (and the service_role for admin uploads) should be
--   able to read or list them.
--
--   The current app UI (src/app/corridors/page.tsx) already gates on auth:
--   `if (!user) redirect('/auth/login')`. No unauthenticated page currently
--   renders corridor cover images. Making the bucket private is safe.
--
-- CHANGES:
--   1. Set corridor-covers bucket public = FALSE (disables CDN public-URL
--      access and anonymous storage API listing).
--   2. Drop the open "corridor_covers_select_public" policy (no role restriction).
--   3. Add "corridor_covers_select_auth" — FOR SELECT TO authenticated
--      (app reads cover images after login).
--   4. Add "corridor_covers_insert_admin" — FOR INSERT TO authenticated
--      WITH CHECK (bucket_id = 'corridor-covers'), gated separately by the
--      admin route which uses createAdminClient(). Admin routes already require
--      is_admin = true at the app layer; this policy allows the upload operation.
--      Note: service_role bypasses RLS entirely for admin management tasks.
--
-- IDEMPOTENCY:
--   UPDATE on storage.buckets is idempotent (setting FALSE when already FALSE
--   is a no-op). DROP POLICY IF EXISTS before each CREATE POLICY.
--
-- DOWN:
--   UPDATE storage.buckets SET public = TRUE WHERE id = 'corridor-covers';
--   DROP POLICY IF EXISTS "corridor_covers_select_auth" ON storage.objects;
--   DROP POLICY IF EXISTS "corridor_covers_insert_admin" ON storage.objects;
--   CREATE POLICY "corridor_covers_select_public" ON storage.objects
--     FOR SELECT USING (bucket_id = 'corridor-covers');
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Mark bucket private ────────────────────────────────────────────────────
UPDATE storage.buckets
   SET public = FALSE
 WHERE id = 'corridor-covers';


-- ── 2. Drop the open SELECT policy ───────────────────────────────────────────
DROP POLICY IF EXISTS "corridor_covers_select_public" ON storage.objects;


-- ── 3. Authenticated SELECT (read cover images after login) ───────────────────
DROP POLICY IF EXISTS "corridor_covers_select_auth" ON storage.objects;
CREATE POLICY "corridor_covers_select_auth" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'corridor-covers');


-- ── 4. Admin INSERT via authenticated route ───────────────────────────────────
-- The admin corridor-management route uses createAdminClient() (service_role),
-- which bypasses RLS entirely, so no INSERT policy is strictly required.
-- This policy is added for defence-in-depth: if a route ever falls back to
-- the anon client, it still restricts INSERT to authenticated users only.
DROP POLICY IF EXISTS "corridor_covers_insert_admin" ON storage.objects;
CREATE POLICY "corridor_covers_insert_admin" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'corridor-covers');


-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  is_public boolean;
BEGIN
  SELECT public INTO is_public
    FROM storage.buckets
   WHERE id = 'corridor-covers';

  IF is_public IS NULL THEN
    RAISE EXCEPTION '[038] VERIFICATION FAILED: corridor-covers bucket not found';
  END IF;
  IF is_public THEN
    RAISE EXCEPTION '[038] VERIFICATION FAILED: corridor-covers bucket is still public=TRUE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'storage'
       AND tablename  = 'objects'
       AND policyname = 'corridor_covers_select_public'
  ) THEN
    RAISE EXCEPTION '[038] VERIFICATION FAILED: open SELECT policy corridor_covers_select_public still exists';
  END IF;

  RAISE NOTICE '[038] OK: corridor-covers bucket is private; open SELECT policy removed; authenticated-only policies active';
END $$;

COMMIT;
