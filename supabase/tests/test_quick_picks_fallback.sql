-- =============================================================================
-- 20260917160000_test_quick_picks_fallback.sql
--
-- Backend test: get_family_quick_picks falls back to the curated default
-- game list correctly when a family has fewer than `limit` distinct games
-- played in the last 30 days.
--
-- Setup:
--   • Create a brand-new test family with NO match history.
--   • Add the test user as a member (so the family-membership gate passes).
--
-- Verifications:
--   V1: For a family with 0 games played, get_family_quick_picks(fam, user, 6)
--       returns exactly the 4 default games (Tic-Tac-Toe, Checkers, Memory
--       Match, Chess) — each with play_count_last_30d = 0.
--   V2: For the same family with limit=3, returns exactly 3 defaults.
--   V3: For the gaming family (cmtqnt6fabw4euu245obo161b) which HAS match
--       history, the result is NOT all defaults — it includes at least one
--       row with play_count_last_30d > 0.
--   V4: The default list never contains duplicates.
-- =============================================================================

-- Setup: brand-new test family with no match history.
INSERT INTO "Family" (id, name, "createdBy", "memberCount", "createdAt", "updatedAt")
VALUES ('test-quickpicks-fam-001', 'Quick Picks Test Family', NULL, 1, now(), now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO "FamilyMember" (id, "familyId", "userId", "role", "joinedAt")
VALUES ('fm-quickpicks-test', 'test-quickpicks-fam-001',
        'aa7ece5f-47ff-4309-9333-450c5fbf1985', 'member', now())
ON CONFLICT DO NOTHING;

-- V1: 0 games played → 4 defaults (limit=6, but only 4 defaults exist).
SELECT 'V1: 0-game family returns 4 defaults' AS test,
       jsonb_array_length(public.get_family_quick_picks(
         'test-quickpicks-fam-001',
         'aa7ece5f-47ff-4309-9333-450c5fbf1985',
         6
       ) -> 'picks') AS pick_count,
       (SELECT COUNT(*) FROM jsonb_array_elements(
         public.get_family_quick_picks(
           'test-quickpicks-fam-001',
           'aa7ece5f-47ff-4309-9333-450c5fbf1985',
           6
         ) -> 'picks'
       ) WHERE (value->>'play_count_last_30d')::int > 0) AS nonzero_plays;
-- Expected: pick_count = 4, nonzero_plays = 0

-- V2: limit=3 → exactly 3 defaults (truncation works).
SELECT 'V2: limit=3 returns 3 picks' AS test,
       jsonb_array_length(public.get_family_quick_picks(
         'test-quickpicks-fam-001',
         'aa7ece5f-47ff-4309-9333-450c5fbf1985',
         3
       ) -> 'picks') AS pick_count;
-- Expected: pick_count = 3

-- V3: The gaming family (HAS match history) returns at least one pick
--     with play_count_last_30d > 0 (NOT all defaults).
SELECT 'V3: gaming family has played picks' AS test,
       (SELECT COUNT(*) FROM jsonb_array_elements(
         public.get_family_quick_picks(
           'cmtqnt6fabw4euu245obo161b',
           'aa7ece5f-47ff-4309-9333-450c5fbf1985',
           6
         ) -> 'picks'
       ) WHERE (value->>'play_count_last_30d')::int > 0) AS played_picks;
-- Expected: played_picks >= 1

-- V4: No duplicate game_ids in the default backfill.
WITH picks AS (
  SELECT value->>'game_id' AS game_id
  FROM jsonb_array_elements(
    public.get_family_quick_picks(
      'test-quickpicks-fam-001',
      'aa7ece5f-47ff-4309-9333-450c5fbf1985',
      6
    ) -> 'picks'
  )
)
SELECT 'V4: no duplicate game_ids in backfill' AS test,
       COUNT(*) AS total_picks,
       COUNT(DISTINCT game_id) AS distinct_picks
FROM picks;
-- Expected: total_picks = distinct_picks (4 = 4)

-- Cleanup
DELETE FROM "FamilyMember" WHERE id = 'fm-quickpicks-test';
DELETE FROM "Family" WHERE id = 'test-quickpicks-fam-001';
