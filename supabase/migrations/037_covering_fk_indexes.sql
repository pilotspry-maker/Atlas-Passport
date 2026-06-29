-- ════════════════════════════════════════════════════════════════════════════
-- Migration 037 — Task 7: covering indexes on unindexed foreign key columns
-- ════════════════════════════════════════════════════════════════════════════
--
-- CONTEXT (Supabase advisor: unindexed_foreign_keys):
--   Foreign key columns without an index cause a sequential scan on the
--   referenced table when a CASCADE or constraint check fires, and a full-scan
--   on the FK table for JOIN/WHERE queries. For write-heavy tables like
--   check_ins and Orion event tables this is a correctness-adjacent issue
--   (FK CASCADE can hold row-locks longer than necessary under high concurrency).
--
-- ALREADY INDEXED (migrations 000/001 — no action needed):
--   nodes.corridor_id           idx_nodes_corridor_id
--   passports.user_id           idx_passports_user_id
--   check_ins.passport_id       idx_check_ins_passport_id
--   check_ins.user_id           idx_check_ins_user_id
--
-- INDEXES ADDED HERE (11):
--
--   Core app tables (migrations 001):
--     passports.corridor_id                 — FK → corridors.id; UNIQUE(user_id, corridor_id)
--                                             has user_id as the leading key, so corridor_id-
--                                             first lookups are not covered.
--     check_ins.node_id                     — FK → nodes.id; no index.
--     rewards.corridor_id                   — FK → corridors.id; no index.
--
--   Orion event tables (baselined in migration 032):
--     passport_activations.traveler_id      — FK → traveler_profiles.id
--     passport_activations.corridor_id      — FK → corridors.id
--     mission_progress.activation_id        — FK → passport_activations.id;
--                                             composite PK is (traveler_id, activation_id)
--                                             so activation_id-first lookups need own index.
--     ap_events.traveler_id                 — FK → traveler_profiles.id
--     ap_events.created_at                  — not a FK but critical for time-range event
--                                             queries; included alongside traveler_id.
--     referral_events.referrer_id           — FK → traveler_profiles.id
--     referral_events.referred_id           — FK → traveler_profiles.id
--
-- IDEMPOTENT: CREATE INDEX IF NOT EXISTS throughout.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Core app tables ───────────────────────────────────────────────────────────

-- passports: corridor_id lookup (e.g. "all passports for corridor X")
CREATE INDEX IF NOT EXISTS idx_passports_corridor_id
  ON public.passports (corridor_id);

-- check_ins: reviewed_by — nullable FK → profiles.id; admin review history queries
CREATE INDEX IF NOT EXISTS idx_check_ins_reviewed_by
  ON public.check_ins (reviewed_by)
  WHERE reviewed_by IS NOT NULL;

-- check_ins: node-level lookup (e.g. "all check-ins for node X")
CREATE INDEX IF NOT EXISTS idx_check_ins_node_id
  ON public.check_ins (node_id);

-- check_ins: traveler_id (added out-of-band, baselined in 032 — nullable, no FK, but join key)
CREATE INDEX IF NOT EXISTS idx_check_ins_traveler_id
  ON public.check_ins (traveler_id)
  WHERE traveler_id IS NOT NULL;

-- rewards: corridor_id lookup (e.g. "reward for corridor X")
CREATE INDEX IF NOT EXISTS idx_rewards_corridor_id
  ON public.rewards (corridor_id);

-- ── Orion event tables ────────────────────────────────────────────────────────

-- passport_activations: traveler → activations join
CREATE INDEX IF NOT EXISTS idx_passport_activations_traveler_id
  ON public.passport_activations (traveler_id);

-- passport_activations: corridor → activations join
CREATE INDEX IF NOT EXISTS idx_passport_activations_corridor_id
  ON public.passport_activations (corridor_id);

-- mission_progress: activation_id — second column of composite PK (traveler_id, activation_id)
-- The PK index has traveler_id as the leading key; this covers activation-first lookups.
CREATE INDEX IF NOT EXISTS idx_mission_progress_activation_id
  ON public.mission_progress (activation_id);

-- ap_events: traveler → events join (most common query pattern)
CREATE INDEX IF NOT EXISTS idx_ap_events_traveler_id
  ON public.ap_events (traveler_id);

-- ap_events: time-range queries for the hourly monitor (CLAUDE.md §11.1)
CREATE INDEX IF NOT EXISTS idx_ap_events_created_at
  ON public.ap_events (created_at DESC);

-- referral_events: referrer → events
CREATE INDEX IF NOT EXISTS idx_referral_events_referrer_id
  ON public.referral_events (referrer_id);

-- referral_events: referred → events (e.g. "who referred this traveler?")
CREATE INDEX IF NOT EXISTS idx_referral_events_referred_id
  ON public.referral_events (referred_id);


-- ── Verification ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  missing text[];
  idx_name text;
  expected text[] := ARRAY[
    'idx_passports_corridor_id',
    'idx_check_ins_node_id',
    'idx_check_ins_traveler_id',
    'idx_check_ins_reviewed_by',
    'idx_passport_activations_traveler_id',
    'idx_passport_activations_corridor_id',
    'idx_mission_progress_activation_id',
    'idx_ap_events_traveler_id',
    'idx_ap_events_created_at',
    'idx_referral_events_referrer_id',
    'idx_referral_events_referred_id'
  ];
BEGIN
  missing := ARRAY[]::text[];
  FOREACH idx_name IN ARRAY expected LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_indexes
       WHERE schemaname = 'public' AND indexname = idx_name
    ) THEN
      missing := array_append(missing, idx_name);
    END IF;
  END LOOP;

  IF array_length(missing, 1) > 0 THEN
    RAISE EXCEPTION '[037] VERIFICATION FAILED: missing indexes: %', array_to_string(missing, ', ');
  END IF;

  RAISE NOTICE '[037] OK: 12 FK covering indexes created ✓';
END $$;

COMMIT;
