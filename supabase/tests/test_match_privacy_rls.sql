-- =============================================================================
-- 20260917140000_test_match_privacy_rls.sql
--
-- RLS TEST: A non-participant Supabase user querying match details for a match
-- they didn't join MUST get zero rows from `game_match_players`, and the
-- `match_history_for_participant` RPC MUST return an empty jsonb object (`{}`).
--
-- Setup:
--   • Two family members: viewer (the requesting user) and a player who is in
--     a match the viewer did NOT participate in.
--   • The viewer is a bona fide family member of the same family — so the
--     `fn_user_is_family_member` row policy would normally allow the row.
--     The new co-participant policy is what blocks it.
--
-- Verifications:
--   V1: direct SELECT on game_match_players for the non-participant match
--       returns 0 rows (RLS co-participant policy enforced).
--   V2: direct SELECT on game_match_history for the result columns
--       (winnerUserIds, winnerNames, resultKind) raises a permission error
--       (column-level GRANT enforces).
--   V3: match_history_for_participant(non_participant_match_id, viewer_id)
--       returns '{}'::jsonb (participant gate in the RPC).
--   V4: fn_get_match_history(viewer_id, family_id) does NOT include the
--       non-participant match (auth-gated to self).
--   V5: fn_get_player_gaming_profile(player_id, family_id) called AS the
--       viewer returns wins=0, losses=0, winRate=0, and recentMatches
--       excludes the non-participant match.
--
-- This file is idempotent — running it multiple times produces the same
-- assertions. It uses ON CONFLICT DO NOTHING for setup inserts.
-- =============================================================================

\set test_family '\'test-rls-fam-001\''
\set viewer_id   '\'aa7ece5f-47ff-4309-9333-450c5fbf1985\''
\set player_id   '\'a4e58129-8397-4c84-86ca-bbfa2a0b6660\''
\set other_player_id '\'23aa1702-4b7e-4ac9-a39a-a5d612e141f2\''
\set match_in    '\'test-rls-match-in-001\''
\set match_out   '\'test-rls-match-out-002\''

-- ---------------------------------------------------------------------------
-- Setup: family, members, matches
-- ---------------------------------------------------------------------------
INSERT INTO "Family" (id, name, "createdBy", "memberCount", "createdAt", "updatedAt")
VALUES (:test_family, 'RLS Test Family', NULL, 3, now(), now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO "FamilyMember" (id, "familyId", "userId", "role", "joinedAt")
VALUES
  ('fm-rls-viewer',  :test_family, :viewer_id,         'member', now()),
  ('fm-rls-player',  :test_family, :player_id,         'member', now()),
  ('fm-rls-other',   :test_family, :other_player_id,   'member', now())
ON CONFLICT DO NOTHING;

-- Match the viewer IS in (with player)
INSERT INTO "game_match_history" ("id", "gameTable", "gameId", "familyId", "playerCount",
                                   "winnerUserIds", "winnerNames", "resultKind",
                                   "finishedAt", "startedAt", "durationSeconds", "createdAt")
VALUES
  (:match_in, 'tictactoe', :match_in, :test_family, 2,
   ARRAY[:player_id]::text[], ARRAY['Player']::text[], 'win',
   now(), now() - interval '3 minutes', 180, now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO "game_match_players" ("matchId", "gameTable", "gameId", "familyId", "userId", "userName", "result", "finishedAt")
VALUES
  (:match_in, 'tictactoe', :match_in, :test_family, :viewer_id,  'Viewer', 'loss', now()),
  (:match_in, 'tictactoe', :match_in, :test_family, :player_id,  'Player', 'win',  now())
ON CONFLICT DO NOTHING;

-- Match the viewer is NOT in (player vs other_player)
INSERT INTO "game_match_history" ("id", "gameTable", "gameId", "familyId", "playerCount",
                                   "winnerUserIds", "winnerNames", "resultKind",
                                   "finishedAt", "startedAt", "durationSeconds", "createdAt")
VALUES
  (:match_out, 'checkers', :match_out, :test_family, 2,
   ARRAY[:player_id]::text[], ARRAY['Player']::text[], 'win',
   now(), now() - interval '5 minutes', 300, now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO "game_match_players" ("matchId", "gameTable", "gameId", "familyId", "userId", "userName", "result", "finishedAt")
VALUES
  (:match_out, 'checkers', :match_out, :test_family, :player_id,        'Player', 'win',  now()),
  (:match_out, 'checkers', :match_out, :test_family, :other_player_id,  'Other',  'loss', now())
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- V1: Viewer (auth.uid = viewer_id) cannot SELECT player rows from match_out
-- ---------------------------------------------------------------------------
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = jsonb_build_object(
  'role', 'authenticated',
  'sub',  :viewer_id,
  'email','viewer@test.local'
);

SELECT 'V1: viewer cannot see match_out player rows' AS test,
       COUNT(*) AS rows_visible
FROM "game_match_players"
WHERE "matchId" = :match_out;
-- Expected: rows_visible = 0

-- ---------------------------------------------------------------------------
-- V1b: Viewer CAN see match_in player rows (was a co-participant)
-- ---------------------------------------------------------------------------
SELECT 'V1b: viewer can see match_in player rows (co-participant)' AS test,
       COUNT(*) AS rows_visible
FROM "game_match_players"
WHERE "matchId" = :match_in;
-- Expected: rows_visible = 2

-- ---------------------------------------------------------------------------
-- V2: Viewer cannot SELECT result columns (winnerUserIds, winnerNames,
--     resultKind) from game_match_history — column-level GRANT blocks it.
-- ---------------------------------------------------------------------------
-- Run inside a DO block so a permission error is caught, not raised.
DO $$
DECLARE
  v_dummy record;
  v_blocked boolean := false;
BEGIN
  BEGIN
    EXECUTE 'SELECT "winnerNames", "resultKind" FROM "game_match_history" WHERE id = ' || quote_literal(:match_out) || ' LIMIT 1'
      INTO v_dummy;
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked := true;
  END;
  ASSERT v_blocked, 'V2 FAILED: viewer was able to SELECT result columns';
  RAISE NOTICE 'V2 OK: result columns blocked for authenticated role';
END $$;

RESET role;
RESET request.jwt.claims;

-- ---------------------------------------------------------------------------
-- V3: match_history_for_participant — viewer queries match_out (NOT a
--     participant). Must return '{}'::jsonb.
-- ---------------------------------------------------------------------------
SELECT 'V3: match_history_for_participant returns empty for non-participant' AS test,
       public.match_history_for_participant(:match_out, :viewer_id) AS detail;
-- Expected: detail = '{}'::jsonb

-- ---------------------------------------------------------------------------
-- V3b: match_history_for_participant — viewer queries match_in (IS a
--      participant). Must return full detail.
-- ---------------------------------------------------------------------------
SELECT 'V3b: match_history_for_participant returns detail for participant' AS test,
       public.match_history_for_participant(:match_in, :viewer_id)->>'matchId' AS matchId,
       jsonb_array_length(public.match_history_for_participant(:match_in, :viewer_id)->'players') AS players;
-- Expected: matchId = match_in, players = 2

-- ---------------------------------------------------------------------------
-- V4: fn_get_match_history called AS the viewer — must NOT include match_out
-- ---------------------------------------------------------------------------
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = jsonb_build_object(
  'role', 'authenticated',
  'sub',  :viewer_id,
  'email','viewer@test.local'
);

SELECT 'V4: fn_get_match_history does not include non-participant match' AS test,
       (SELECT COUNT(*) FROM jsonb_array_elements(
         (public.fn_get_match_history(:viewer_id, :test_family, 50, 0))->'matches'
       ) WHERE value->>'matchId' = :match_out) AS match_out_count;
-- Expected: match_out_count = 0

RESET role;
RESET request.jwt.claims;

-- ---------------------------------------------------------------------------
-- V5: fn_get_player_gaming_profile for the player, called AS the viewer.
--     wins/losses/winRate MUST be 0 (stripped for non-self).
--     recentMatches MUST exclude match_out (the viewer wasn't in it).
-- ---------------------------------------------------------------------------
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = jsonb_build_object(
  'role', 'authenticated',
  'sub',  :viewer_id,
  'email','viewer@test.local'
);

SELECT 'V5: player profile strips wins/losses/winRate for non-self viewer' AS test,
       (public.fn_get_player_gaming_profile(:player_id, :test_family)->>'wins')::int AS wins,
       (public.fn_get_player_gaming_profile(:player_id, :test_family)->>'losses')::int AS losses,
       (public.fn_get_player_gaming_profile(:player_id, :test_family)->>'winRate')::numeric AS winRate,
       (public.fn_get_player_gaming_profile(:player_id, :test_family)->>'isSelf')::boolean AS is_self;
-- Expected: wins = 0, losses = 0, winRate = 0, is_self = false

SELECT 'V5b: player profile recentMatches excludes non-participant match' AS test,
       (SELECT COUNT(*) FROM jsonb_array_elements(
         (public.fn_get_player_gaming_profile(:player_id, :test_family)->'recentMatches')
       )) AS recent_count;
-- Expected: recent_count <= 1 (only match_in if at all; match_out must be excluded)

RESET role;
RESET request.jwt.claims;

-- ---------------------------------------------------------------------------
-- V6: fn_get_family_leaderboard_v2 — wins/losses/winRate fields are NOT
--     present in any returned row (for ANY user, including self).
-- ---------------------------------------------------------------------------
SELECT 'V6: leaderboard entries do not contain wins/losses/winRate keys' AS test,
       (SELECT COUNT(*) FROM jsonb_array_elements(
         (public.fn_get_family_leaderboard_v2(:test_family, 'all_time', NULL, 50, :viewer_id))->'entries'
       ) WHERE value ? 'wins' OR value ? 'losses' OR value ? 'winRate') AS leak_count;
-- Expected: leak_count = 0

SELECT 'V6b: leaderboard viewer row has streakCurrent, others do not' AS test,
       (SELECT COUNT(*) FROM jsonb_array_elements(
         (public.fn_get_family_leaderboard_v2(:test_family, 'all_time', NULL, 50, :viewer_id))->'entries'
       ) WHERE (value->>'streakCurrent')::int > 0 AND value->>'userId' <> :viewer_id) AS others_with_streak;
-- Expected: others_with_streak = 0
