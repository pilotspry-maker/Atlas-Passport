-- Atlas Passport — Seed Data
-- Paste this after running 001_initial_schema.sql

-- ─── Corridors ─────────────────────────────────────────────────────────────
INSERT INTO public.corridors (id, name, description, city, country, is_active)
VALUES
  (
    'c1000000-0000-0000-0000-000000000001',
    'The Midnight Corridor',
    'A journey through the city''s hidden night culture — from the first neon light to the last jazz note. Move fast. The city changes after dark.',
    'New York',
    'US',
    TRUE
  ),
  (
    'c1000000-0000-0000-0000-000000000002',
    'The Golden Hour Route',
    'Chase the sun through landmark murals, rooftop terraces, and the streets that glow amber at dusk. Every stop is worth the light.',
    'Los Angeles',
    'US',
    TRUE
  ),
  (
    'c1000000-0000-0000-0000-000000000003',
    'The Harbor Line',
    'Follow the waterfront from the old fishing docks to the contemporary piers. History runs deep here — go find it.',
    'San Francisco',
    'US',
    FALSE
  );

-- ─── Nodes for The Midnight Corridor ───────────────────────────────────────
INSERT INTO public.nodes (corridor_id, name, description, address, hint, sequence)
VALUES
  (
    'c1000000-0000-0000-0000-000000000001',
    'The Beacon',
    'Your first stamp is waiting. Start where the city''s oldest neon sign still blinks its irregular rhythm into the night.',
    '94 Orchard St, New York, NY 10002',
    'Kaelo says: "Find the sign that never sleeps. It''s been blinking since before you were born. Stand beneath it."',
    1
  ),
  (
    'c1000000-0000-0000-0000-000000000001',
    'The Archive',
    'A bookshop that only opens at night. The stamp is hidden in the philosophy section. The proprietor knows you''re coming.',
    '192 E 2nd St, New York, NY 10009',
    'Kaelo says: "Seek the shop that trades in ideas after midnight. Go where Nietzsche meets Neruda."',
    2
  ),
  (
    'c1000000-0000-0000-0000-000000000001',
    'The Final Note',
    'The corridor ends where the music begins. A jazz venue on the Lower East Side. Show your passport at the door. Your third stamp waits inside.',
    '35 E 1st St, New York, NY 10003',
    'Kaelo says: "Every journey ends in music. Find the place where improvisation is the only rule."',
    3
  );

-- ─── Nodes for The Golden Hour Route ───────────────────────────────────────
INSERT INTO public.nodes (corridor_id, name, description, address, hint, sequence)
VALUES
  (
    'c1000000-0000-0000-0000-000000000002',
    'The Mural Wall',
    'Start at the largest mural in the Arts District. The artist''s signature is your first proof.',
    'E 6th St & Mateo St, Los Angeles, CA 90021',
    'Kaelo says: "Find the wall that tells a story taller than a building. Look for the artist''s name in the corner."',
    1
  ),
  (
    'c1000000-0000-0000-0000-000000000002',
    'The Sky Terrace',
    'A rooftop bar in Silver Lake that faces west. Photograph the horizon when the sun touches the hills.',
    '3818 W Sunset Blvd, Los Angeles, CA 90026',
    'Kaelo says: "Go high. Face west. Wait for the moment when the city turns to gold."',
    2
  ),
  (
    'c1000000-0000-0000-0000-000000000002',
    'The Amber Doorway',
    'The route ends at a vintage cinema on Cahuenga. The last screening begins at golden hour. Your seat is reserved.',
    '6712 Hollywood Blvd, Los Angeles, CA 90028',
    'Kaelo says: "The final frame is yours to witness. Find the cinema that still runs films on celluloid."',
    3
  );

-- ─── Rewards ───────────────────────────────────────────────────────────────
INSERT INTO public.rewards (corridor_id, title, description, redemption_code)
VALUES
  (
    'c1000000-0000-0000-0000-000000000001',
    'Midnight Corridor — Collector''s Edition',
    'A limited-edition Relevant Artist print, signed by the team. Ships within 3 weeks. You earned this.',
    'MIDNIGHT-ATLAS-001'
  ),
  (
    'c1000000-0000-0000-0000-000000000002',
    'Golden Hour — Early Access Pass',
    'Priority access to the next Relevant Artist drop, 48 hours before public release. Plus an exclusive digital wallpaper set.',
    'GOLDEN-ATLAS-001'
  );
