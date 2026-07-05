-- =============================================================================
-- Daxelo-Kinrel — Game-related badges (section 6 data migration)
-- =============================================================================
-- Adds 4 new game-related badge rows to the existing Badge table. These are
-- evaluated by the check_game_badges Edge Function, which fires after each
-- game completes and inserts into UserBadge when a threshold is met.
--
-- Badges added:
--   1. played-5-games-week     — Played 5 games in the last 7 days
--   2. win-streak-3            — Won 3 games in a row
--   3. family-game-night-regular — Attended 4 scheduled game nights
--   4. first-game-win          — Won your first game
-- =============================================================================

INSERT INTO "Badge" ("id", "slug", "name", "nameHi", "description", "icon", "category", "tier", "threshold", "isSecret", "createdAt")
VALUES
  (
    gen_random_uuid()::text,
    'played-5-games-week',
    'Week Warrior',
    'सप्ताह योद्धा',
    'Play 5 games in a single week',
    '🎮',
    'games',
    'bronze',
    5,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'win-streak-3',
    'Hat Trick Hero',
    'हैट ट्रिक हीरो',
    'Win 3 games in a row',
    '🔥',
    'games',
    'silver',
    3,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'family-game-night-regular',
    'Game Night Regular',
    'गेम नाइट नियमित',
    'Attend 4 scheduled game nights',
    '🌙',
    'games',
    'gold',
    4,
    false,
    now()
  ),
  (
    gen_random_uuid()::text,
    'first-game-win',
    'First Victory',
    'पहली जीत',
    'Win your first game',
    '🏆',
    'games',
    'bronze',
    1,
    false,
    now()
  )
ON CONFLICT ("slug") DO NOTHING;

-- Verify the rows landed
DO $$
DECLARE
  cnt int;
BEGIN
  SELECT COUNT(*) INTO cnt FROM "Badge" WHERE category = 'games';
  RAISE NOTICE 'Game-related badges in Badge table: %', cnt;
END $$;
