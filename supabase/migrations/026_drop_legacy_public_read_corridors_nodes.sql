-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║ Migration 026: Drop legacy USING(true) PUBLIC-read policies                  ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║ tests/rls/test_rls_policies.py::TestNodeEnumeration::                        ║
-- ║   test_anon_cannot_enumerate_via_corridor_join — and the related anon-       ║
-- ║   only test — were failing because two legacy policies                       ║
-- ║                                                                              ║
-- ║     "Public read corridors"  -- USING (true), role PUBLIC                    ║
-- ║     "Public read nodes"      -- USING (true), role PUBLIC                    ║
-- ║                                                                              ║
-- ║   were OR-merging with the newer authenticated-only is_active=true policies  ║
-- ║   and silently letting anonymous clients enumerate every corridor + node     ║
-- ║   (including via PostgREST nested-select corridor→nodes joins).              ║
-- ║                                                                              ║
-- ║   Verified post-drop:                                                        ║
-- ║     - anon GET /rest/v1/nodes      → []                                      ║
-- ║     - anon GET /rest/v1/corridors  → []                                      ║
-- ║     - authenticated GET /rest/v1/nodes → 16 active nodes                     ║
-- ║                                                                              ║
-- ║   This closes the pre-auth enumeration vector before tonight's player        ║
-- ║   activation while keeping every signed-in player's read path intact.        ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

DROP POLICY IF EXISTS "Public read corridors" ON public.corridors;
DROP POLICY IF EXISTS "Public read nodes"     ON public.nodes;

DO $$
BEGIN
  RAISE NOTICE '[026] Dropped legacy USING(true) policies on public.corridors and public.nodes';
END;
$$;
