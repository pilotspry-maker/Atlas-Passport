-- Atlas Passport — Storage Buckets, Policies & Realtime
-- Run after 001_initial_schema.sql

-- ─── Storage Buckets ───────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  (
    'check-in-proofs',
    'check-in-proofs',
    FALSE,
    10485760,  -- 10MB
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
  ),
  (
    'corridor-covers',
    'corridor-covers',
    TRUE,
    5242880,   -- 5MB
    ARRAY['image/jpeg', 'image/png', 'image/webp']
  )
ON CONFLICT (id) DO NOTHING;

-- ─── Storage RLS Policies — check-in-proofs (private) ─────────────────────
-- Authenticated users can upload to their own user_id folder
CREATE POLICY "check_in_proofs_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'check-in-proofs' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Users can view their own uploads
CREATE POLICY "check_in_proofs_select_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'check-in-proofs' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Users can delete their own uploads
CREATE POLICY "check_in_proofs_delete_own" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'check-in-proofs' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- ─── Storage RLS Policies — corridor-covers (public) ──────────────────────
CREATE POLICY "corridor_covers_select_public" ON storage.objects
  FOR SELECT USING (bucket_id = 'corridor-covers');

-- ─── Realtime ──────────────────────────────────────────────────────────────
-- REPLICA IDENTITY FULL lets Supabase Realtime filter UPDATE events via RLS
ALTER TABLE public.check_ins REPLICA IDENTITY FULL;
ALTER TABLE public.passports REPLICA IDENTITY FULL;

-- Enable realtime publication for these tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.check_ins;
ALTER PUBLICATION supabase_realtime ADD TABLE public.passports;
