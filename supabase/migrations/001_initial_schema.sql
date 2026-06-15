-- Atlas Passport — Initial Schema
-- Run this in your Supabase SQL editor or via supabase db push

-- ─── Profiles ──────────────────────────────────────────────────────────────
CREATE TABLE public.profiles (
  id           UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email        TEXT        NOT NULL,
  full_name    TEXT,
  is_admin     BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create profile when a user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─── Corridors ─────────────────────────────────────────────────────────────
CREATE TABLE public.corridors (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT        NOT NULL,
  description  TEXT,
  city         TEXT        NOT NULL,
  country      TEXT        NOT NULL DEFAULT 'US',
  cover_image  TEXT,
  is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Nodes (stops within a corridor) ───────────────────────────────────────
CREATE TABLE public.nodes (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  corridor_id  UUID        NOT NULL REFERENCES public.corridors(id) ON DELETE CASCADE,
  name         TEXT        NOT NULL,
  description  TEXT,
  address      TEXT,
  hint         TEXT,       -- Kaelo's clue shown before arrival
  sequence     INTEGER     NOT NULL,
  latitude     NUMERIC(9, 6),
  longitude    NUMERIC(9, 6),
  is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(corridor_id, sequence)
);

-- ─── Passports ─────────────────────────────────────────────────────────────
CREATE TABLE public.passports (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  corridor_id      UUID        NOT NULL REFERENCES public.corridors(id),
  status           TEXT        NOT NULL DEFAULT 'active'
                               CHECK (status IN ('active', 'expired', 'complete')),
  activated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at       TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '72 hours'),
  completed_at     TIMESTAMPTZ,
  warning_sent_at  TIMESTAMPTZ, -- tracks 24h warning email
  reward_claimed   BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, corridor_id)
);

-- ─── Check-ins ─────────────────────────────────────────────────────────────
CREATE TABLE public.check_ins (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  passport_id        UUID        NOT NULL REFERENCES public.passports(id) ON DELETE CASCADE,
  user_id            UUID        NOT NULL REFERENCES public.profiles(id),
  node_id            UUID        NOT NULL REFERENCES public.nodes(id),
  status             TEXT        NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'approved', 'rejected')),
  proof_url          TEXT        NOT NULL,
  proof_storage_path TEXT        NOT NULL,
  notes              TEXT,
  admin_notes        TEXT,
  reviewed_by        UUID        REFERENCES public.profiles(id),
  reviewed_at        TIMESTAMPTZ,
  submitted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(passport_id, node_id)
);

-- ─── Rewards ───────────────────────────────────────────────────────────────
CREATE TABLE public.rewards (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  corridor_id      UUID        NOT NULL REFERENCES public.corridors(id) ON DELETE CASCADE,
  title            TEXT        NOT NULL,
  description      TEXT,
  redemption_code  TEXT,
  redemption_url   TEXT,
  image_url        TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Indexes ───────────────────────────────────────────────────────────────
CREATE INDEX idx_nodes_corridor_id       ON public.nodes(corridor_id);
CREATE INDEX idx_nodes_sequence          ON public.nodes(corridor_id, sequence);
CREATE INDEX idx_passports_user_id       ON public.passports(user_id);
CREATE INDEX idx_passports_status        ON public.passports(status);
CREATE INDEX idx_passports_expires_at    ON public.passports(expires_at);
CREATE INDEX idx_check_ins_passport_id   ON public.check_ins(passport_id);
CREATE INDEX idx_check_ins_status        ON public.check_ins(status);
CREATE INDEX idx_check_ins_user_id       ON public.check_ins(user_id);
CREATE INDEX idx_check_ins_submitted_at  ON public.check_ins(submitted_at DESC);

-- ─── Row Level Security ────────────────────────────────────────────────────
ALTER TABLE public.profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.corridors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nodes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.passports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rewards   ENABLE ROW LEVEL SECURITY;

-- profiles: users see/edit only their own row
-- (admin operations use the service-role client which bypasses RLS)
CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- corridors: any authenticated user can read active corridors
CREATE POLICY "corridors_select_active" ON public.corridors
  FOR SELECT TO authenticated USING (is_active = TRUE);

-- nodes: any authenticated user can read active nodes
CREATE POLICY "nodes_select_active" ON public.nodes
  FOR SELECT TO authenticated USING (is_active = TRUE);

-- passports: users see their own passports
CREATE POLICY "passports_select_own" ON public.passports
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "passports_insert_own" ON public.passports
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- check_ins: users see their own check-ins
CREATE POLICY "check_ins_select_own" ON public.check_ins
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "check_ins_insert_own" ON public.check_ins
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- rewards: any authenticated user can read
CREATE POLICY "rewards_select_auth" ON public.rewards
  FOR SELECT TO authenticated USING (TRUE);

-- ─── Storage Buckets ───────────────────────────────────────────────────────
-- Run these via Supabase dashboard or Storage API:
-- 1. Create bucket "check-in-proofs" (private)
-- 2. Create bucket "corridor-covers" (public)

-- Storage policies for check-in-proofs (private bucket):
-- INSERT: authenticated users uploading to their own user_id folder
-- SELECT: users reading their own uploads
-- These are set via the Supabase dashboard Storage policies UI.
