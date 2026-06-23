-- ============================================================
-- Atlas Passport — Repair Migration (idempotent)
-- Brings a partially-migrated database to full schema state.
-- Safe to run multiple times on any database state.
--
-- Confirmed existing before this migration:
--   Tables:  corridors, nodes, check_ins (all partially created)
--   RLS:     enabled on check_ins, corridors, nodes
--
-- This migration patches existing tables AND adds everything missing.
-- ============================================================

-- ─── Patch existing tables (nodes, corridors, check_ins) ───
-- These tables exist but may be missing columns from a partial migration.

ALTER TABLE public.nodes ADD COLUMN IF NOT EXISTS description  TEXT;
ALTER TABLE public.nodes ADD COLUMN IF NOT EXISTS address      TEXT;
ALTER TABLE public.nodes ADD COLUMN IF NOT EXISTS hint         TEXT;
ALTER TABLE public.nodes ADD COLUMN IF NOT EXISTS sequence     INTEGER;
ALTER TABLE public.nodes ADD COLUMN IF NOT EXISTS latitude     NUMERIC(9,6);
ALTER TABLE public.nodes ADD COLUMN IF NOT EXISTS longitude    NUMERIC(9,6);
ALTER TABLE public.nodes ADD COLUMN IF NOT EXISTS is_active    BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.corridors ADD COLUMN IF NOT EXISTS description  TEXT;
ALTER TABLE public.corridors ADD COLUMN IF NOT EXISTS cover_image  TEXT;
ALTER TABLE public.corridors ADD COLUMN IF NOT EXISTS is_active    BOOLEAN NOT NULL DEFAULT TRUE;

-- ─── Tables ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.profiles (
  id           UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email        TEXT        NOT NULL,
  full_name    TEXT,
  is_admin     BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_code TEXT;

CREATE TABLE IF NOT EXISTS public.passports (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  corridor_id      UUID        NOT NULL REFERENCES public.corridors(id),
  status           TEXT        NOT NULL DEFAULT 'active'
                               CHECK (status IN ('active', 'expired', 'complete')),
  activated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at       TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '72 hours'),
  completed_at     TIMESTAMPTZ,
  warning_sent_at  TIMESTAMPTZ,
  reward_claimed   BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, corridor_id)
);

CREATE TABLE IF NOT EXISTS public.rewards (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  corridor_id      UUID        NOT NULL REFERENCES public.corridors(id) ON DELETE CASCADE,
  title            TEXT        NOT NULL,
  description      TEXT,
  redemption_code  TEXT,
  redemption_url   TEXT,
  image_url        TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Patch check_ins (depends on passports existing above) ─

ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS passport_id        UUID REFERENCES public.passports(id) ON DELETE CASCADE;
ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS node_id            UUID REFERENCES public.nodes(id);
ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS status             TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS proof_url          TEXT;
ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS proof_storage_path TEXT;
ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS notes              TEXT;
ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS admin_notes        TEXT;
ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS reviewed_by        UUID REFERENCES public.profiles(id);
ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS reviewed_at        TIMESTAMPTZ;
ALTER TABLE public.check_ins ADD COLUMN IF NOT EXISTS submitted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- ─── Indexes ───────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_nodes_corridor_id      ON public.nodes(corridor_id);
CREATE INDEX IF NOT EXISTS idx_nodes_sequence         ON public.nodes(corridor_id, sequence);
CREATE INDEX IF NOT EXISTS idx_passports_user_id      ON public.passports(user_id);
CREATE INDEX IF NOT EXISTS idx_passports_status       ON public.passports(status);
CREATE INDEX IF NOT EXISTS idx_passports_expires_at   ON public.passports(expires_at);
CREATE INDEX IF NOT EXISTS idx_check_ins_passport_id  ON public.check_ins(passport_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_status       ON public.check_ins(status);
CREATE INDEX IF NOT EXISTS idx_check_ins_user_id      ON public.check_ins(user_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_submitted_at ON public.check_ins(submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_rewards_corridor_id    ON public.rewards(corridor_id);

-- ─── Row Level Security ────────────────────────────────────
-- ALTER ... ENABLE ROW LEVEL SECURITY is idempotent.

ALTER TABLE public.profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.passports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rewards   ENABLE ROW LEVEL SECURITY;

-- ─── RLS Policies ──────────────────────────────────────────

DO $$ BEGIN

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='profiles_select_own') THEN
    CREATE POLICY "profiles_select_own" ON public.profiles
      FOR SELECT USING (auth.uid() = id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='profiles_update_own') THEN
    CREATE POLICY "profiles_update_own" ON public.profiles
      FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='corridors' AND policyname='corridors_select_active') THEN
    CREATE POLICY "corridors_select_active" ON public.corridors
      FOR SELECT TO authenticated USING (is_active = TRUE);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='nodes' AND policyname='nodes_select_active') THEN
    CREATE POLICY "nodes_select_active" ON public.nodes
      FOR SELECT TO authenticated USING (is_active = TRUE);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='passports' AND policyname='passports_select_own') THEN
    CREATE POLICY "passports_select_own" ON public.passports
      FOR SELECT USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='passports' AND policyname='passports_insert_own') THEN
    CREATE POLICY "passports_insert_own" ON public.passports
      FOR INSERT WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='check_ins' AND policyname='check_ins_select_own') THEN
    CREATE POLICY "check_ins_select_own" ON public.check_ins
      FOR SELECT USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='check_ins' AND policyname='check_ins_insert_own') THEN
    CREATE POLICY "check_ins_insert_own" ON public.check_ins
      FOR INSERT WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rewards' AND policyname='rewards_select_auth') THEN
    CREATE POLICY "rewards_select_auth" ON public.rewards
      FOR SELECT TO authenticated USING (TRUE);
  END IF;

END $$;

-- ─── Trigger & Function ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created'
  ) THEN
    CREATE TRIGGER on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
  END IF;
END $$;

-- ─── Storage Buckets ───────────────────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('check-in-proofs','check-in-proofs',FALSE,10485760,
   ARRAY['image/jpeg','image/png','image/webp','image/heic','image/heif']),
  ('corridor-covers','corridor-covers',TRUE,5242880,
   ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- ─── Storage RLS Policies ──────────────────────────────────

DO $$ BEGIN

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='check_in_proofs_insert') THEN
    CREATE POLICY "check_in_proofs_insert" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'check-in-proofs' AND (storage.foldername(name))[1] = auth.uid()::text);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='check_in_proofs_select_own') THEN
    CREATE POLICY "check_in_proofs_select_own" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'check-in-proofs' AND (storage.foldername(name))[1] = auth.uid()::text);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='check_in_proofs_delete_own') THEN
    CREATE POLICY "check_in_proofs_delete_own" ON storage.objects
      FOR DELETE TO authenticated
      USING (bucket_id = 'check-in-proofs' AND (storage.foldername(name))[1] = auth.uid()::text);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='corridor_covers_select_public') THEN
    CREATE POLICY "corridor_covers_select_public" ON storage.objects
      FOR SELECT USING (bucket_id = 'corridor-covers');
  END IF;

END $$;

-- ─── Realtime ──────────────────────────────────────────────

ALTER TABLE public.check_ins REPLICA IDENTITY FULL;
ALTER TABLE public.passports REPLICA IDENTITY FULL;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'check_ins'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.check_ins;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'passports'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.passports;
  END IF;
END $$;
