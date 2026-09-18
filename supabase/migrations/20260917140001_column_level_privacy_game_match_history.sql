-- =============================================================================
-- 20260917140001_column_level_privacy_game_match_history.sql
-- =============================================================================
-- Tighten column-level access on game_match_history so the result-bearing
-- columns (winnerUserIds, winnerNames, resultKind) are NOT directly SELECT-able
-- by the `authenticated` role via PostgREST / REST API. Only the non-result
-- columns (existence, timing, player count, game table) are exposed at the
-- table level — the result columns are reachable ONLY through the
-- SECURITY DEFINER RPC `match_history_for_participant`, which enforces the
-- participant gate.
--
-- The RLS row policy (`game_match_history_select_family`) stays in place so
-- family members can still see that a match happened (for participation
-- counts), but the column-level GRANT strips the result columns from raw
-- SELECT.
-- =============================================================================

-- 1. Drop all existing column grants on game_match_history for authenticated.
REVOKE SELECT ON public."game_match_history" FROM authenticated;

-- 2. Re-grant SELECT only on the SAFE (non-result) columns.
--    Result columns (winnerUserIds, winnerNames, resultKind) are deliberately
--    NOT granted — they are reachable only through the SECURITY DEFINER RPC.
GRANT SELECT (
  "id",
  "gameTable",
  "gameId",
  "familyId",
  "playerCount",
  "finishedAt",
  "startedAt",
  "durationSeconds",
  "createdAt"
) ON public."game_match_history" TO authenticated;

-- 3. Same treatment for game_match_players: the `result` column is the only
--    result-bearing column. Strip it from direct SELECT; expose only via
--    fn_get_match_history (auth-self-gated) and match_history_for_participant.
REVOKE SELECT ON public."game_match_players" FROM authenticated;

GRANT SELECT (
  "id",
  "matchId",
  "gameTable",
  "gameId",
  "familyId",
  "userId",
  "userName",
  "finishedAt",
  "createdAt"
) ON public."game_match_players" TO authenticated;
-- NOTE: the `result` column is NOT granted. RLS still allows the row to be
-- visible (own + co-participant), but the result value itself is only
-- returned by the SECURITY DEFINER RPCs (which run as postgres).

-- 4. Tighten game_user_stats: the `wins`, `losses`, `draws` columns are
--    aggregate result data. The `points`, `matches`, `streakCurrent`,
--    `streakBest`, `sportsmanshipReceived` columns are participation metrics.
REVOKE SELECT ON public."game_user_stats" FROM authenticated;

GRANT SELECT (
  "id",
  "userId",
  "familyId",
  "gameTable",
  "matches",
  "points",
  "streakCurrent",
  "streakBest",
  "spectated",
  "sportsmanshipGiven",
  "sportsmanshipReceived",
  "lastPlayedAt",
  "updatedAt"
) ON public."game_user_stats" TO authenticated;
-- NOTE: `wins`, `losses`, `draws`, `played` are NOT granted directly. The
-- account owner reads their own full stats via fn_get_player_gaming_profile
-- (which runs as postgres and is participant-gated to the requester).
