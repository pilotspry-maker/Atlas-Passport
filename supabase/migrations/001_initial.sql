-- Artists (approved, public-facing profiles)
CREATE TABLE artists (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name     TEXT NOT NULL,
  bio           TEXT,
  location      TEXT,
  website       TEXT,
  instagram     TEXT,
  portfolio_url TEXT,
  avatar_url    TEXT,
  slug          TEXT UNIQUE NOT NULL,
  discipline    TEXT,
  status        TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Applications (inbound form submissions)
CREATE TABLE applications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT NOT NULL,
  full_name     TEXT NOT NULL,
  bio           TEXT NOT NULL,
  location      TEXT NOT NULL,
  discipline    TEXT NOT NULL,
  website       TEXT,
  instagram     TEXT,
  portfolio_url TEXT,
  why_atlas     TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_at   TIMESTAMPTZ,
  reviewed_by   UUID REFERENCES auth.users(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger: keep updated_at fresh
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER artists_updated_at
  BEFORE UPDATE ON artists
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- RLS
ALTER TABLE artists ENABLE ROW LEVEL SECURITY;
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;

-- Public can read approved artists
CREATE POLICY "Public read approved artists"
  ON artists FOR SELECT
  USING (status = 'approved');

-- Authenticated artists can update their own record
CREATE POLICY "Artists update own record"
  ON artists FOR UPDATE
  USING (auth.uid() = user_id);

-- Artists can insert their own record (approved flow via dashboard)
CREATE POLICY "Artists insert own record"
  ON artists FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Applications: service role only (handled server-side with service key)
-- Anonymous users cannot read/write applications directly
