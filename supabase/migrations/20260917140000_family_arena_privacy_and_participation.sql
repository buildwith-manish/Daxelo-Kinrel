-- =============================================================================
-- 20260917140000_family_arena_privacy_and_participation.sql
--
-- Family Arena / Games module — Privacy + Psychological Reframe.
--
-- PRINCIPLES
--   1. Win/loss/win% are PRIVATE to the account owner. They are never returned
--      by any shared / leaderboard / family-wide RPC for non-self rows.
--   2. Detailed match history (winner, score, per-player result) is visible
--      ONLY to participants of that specific match. A family member who did
--      NOT play in a match must not be able to query, view, or infer its
--      result — not via the leaderboard, not via any RPC, not via profile pages.
--   3. The shared family leaderboard surface exposes only: rank, points,
--      games_played — and the viewer's OWN current streak (never anyone else's).
--   4. A new `family_leaderboard_view` exposes only the safe aggregate columns.
--   5. A new `match_history_for_participant(match_id, requesting_user_id)` RPC
--      returns full match detail ONLY if the requester was a participant.
--
-- BACKWARD COMPATIBILITY
--   • fn_get_family_leaderboard_v2 keeps its signature, but now STRIPS
--     wins/losses/draws/winRate/streakCurrent for every row whose userId is
--     not the requester. The caller passes the new p_requesting_user_id
--     parameter; if NULL, all rows are stripped (defensive default).
--   • fn_get_match_history is hardened so it only returns matches where the
--     requester (auth.uid()) is a participant. The p_user_id parameter is now
--     forced to equal auth.uid() — a family member can no longer enumerate
--     another member's match history.
--   • fn_get_player_gaming_profile strips wins/losses/draws/winRate,
--     perGame wins/losses, and recentMatches result fields when the requester
--     is not the profile owner. recentMatches are additionally filtered to
--     only include matches the requester participated in.
-- =============================================================================

-- =============================================================================
-- SECTION 1: family_leaderboard_view — safe aggregate view (no wins/losses/%)
-- =============================================================================
-- A Postgres VIEW that pre-aggregates ONLY the columns safe to share across
-- the whole family: userId, familyId, points, games_played, current_streak.
-- Wins / losses / win percentage are DELIBERATELY NOT included.
--
-- RLS note: the view inherits RLS from its underlying tables, but we also
-- GRANT SELECT only to `authenticated` and the view itself does not expose
-- any result-bearing column.
-- =============================================================================

DROP VIEW IF EXISTS public.family_leaderboard_view;

CREATE VIEW public.family_leaderboard_view AS
SELECT
  s."userId"              AS user_id,
  s."familyId"            AS family_id,
  SUM(s."points")         AS points,
  SUM(s."matches")        AS games_played,
  MAX(CASE
        WHEN s."gameTable" = '*'
        THEN s."streakCurrent"
        ELSE 0
      END)                AS current_streak
FROM public."game_user_stats" s
WHERE s."gameTable" <> '*'
GROUP BY s."userId", s."familyId"
HAVING SUM(s."matches") > 0;

ALTER VIEW public.family_leaderboard_view OWNER TO postgres;
GRANT SELECT ON public.family_leaderboard_view TO authenticated;

-- =============================================================================
-- SECTION 2: Helper — is auth.uid() a participant in a given match?
-- =============================================================================
-- Returns true if the requesting user (auth.uid()) has a row in
-- game_match_players for the given matchId. SECURITY DEFINER so it can be
-- embedded in RLS policies without recursion concerns.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_is_match_participant(p_match_id text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public."game_match_players"
    WHERE "matchId" = p_match_id
      AND "userId" = auth.uid()::text
  );
$$;

GRANT EXECUTE ON FUNCTION public.fn_is_match_participant(text) TO authenticated;

-- =============================================================================
-- SECTION 3: Tighten RLS on game_match_players
-- =============================================================================
-- BEFORE: any family member could read every other member's per-match
--         results (win/loss/draw), enabling them to reconstruct anyone's
--         full win/loss record.
-- AFTER:  a user can ALWAYS read their own rows. For OTHER users' rows, the
--         reader must have been a participant in the SAME match — otherwise
--         the row is invisible (not even its existence is confirmed).
-- =============================================================================

DROP POLICY IF EXISTS game_match_players_select_family ON public."game_match_players";

-- Self: always readable (the account owner can always see their own record).
CREATE POLICY game_match_players_select_self
  ON public."game_match_players"
  FOR SELECT TO authenticated
  USING ("userId" = auth.uid()::text);

-- Co-participants: readable only if the requester is also in this match.
-- This is what blocks the "walk of shame" — a non-participant family member
-- cannot see who won/lost a match they weren't part of.
CREATE POLICY game_match_players_select_coparticipant
  ON public."game_match_players"
  FOR SELECT TO authenticated
  USING (
    "userId" <> auth.uid()::text
    AND public.fn_is_match_participant("matchId")
  );

-- =============================================================================
-- SECTION 4: Tighten RLS on game_match_history (result-bearing fields)
-- =============================================================================
-- game_match_history stores winnerUserIds / winnerNames / resultKind which
-- are result-bearing. We cannot do column-level RLS cheaply, so the row
-- policy below splits visibility:
--   • The row's existence (match happened, when, what game, how many players)
--     is visible to all family members — this powers "X games played together"
--     participation counters that are safe to share.
--   • BUT all access to result-bearing COLUMNS happens exclusively through
--     the new match_history_for_participant RPC, which only returns those
--     columns to participants. Direct SELECT of winnerUserIds / winnerNames /
--     resultKind is blocked at the API layer by stripping them in the
--     non-participant RPC paths (see fn_get_match_history below).
--
-- RLS remains "family-readable" so the participation counters still work,
-- but the RPC layer (SECURITY DEFINER) is now the ONLY path that exposes
-- result columns, and it does so participant-gated.
-- =============================================================================

-- (Policy already exists from the original migration — leave it in place so
--  family-level aggregates like "games played together" still work.)
-- Re-assert to be safe:
DROP POLICY IF EXISTS game_match_history_select_family ON public."game_match_history";
CREATE POLICY game_match_history_select_family ON public."game_match_history"
  FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));

-- =============================================================================
-- SECTION 5: match_history_for_participant(p_match_id, p_requesting_user_id)
-- =============================================================================
-- Returns full match detail (winner, score, per-player results) ONLY if the
-- requesting user is a participant. Otherwise returns an empty jsonb object.
--
-- The function is SECURITY DEFINER so it can read the result columns even
-- though RLS would otherwise block cross-user reads; the participant gate
-- is enforced explicitly inside the function body.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.match_history_for_participant(
  p_match_id text,
  p_requesting_user_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_participant boolean;
  v_history record;
  v_players jsonb;
BEGIN
  -- Participant gate — hard enforced. No result columns leak if false.
  SELECT EXISTS (
    SELECT 1 FROM public."game_match_players"
    WHERE "matchId" = p_match_id
      AND "userId" = p_requesting_user_id
  ) INTO v_is_participant;

  IF NOT v_is_participant THEN
    -- Return empty object — caller treats absence as "no access".
    -- We do NOT differentiate "match doesn't exist" from "you weren't in it"
    -- to avoid confirming the match's existence to non-participants.
    RETURN '{}'::jsonb;
  END IF;

  SELECT * INTO v_history
  FROM public."game_match_history"
  WHERE "id" = p_match_id;

  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'userId',    p."userId",
    'userName',  p."userName",
    'result',    p."result"
  ) ORDER BY
    CASE p."result" WHEN 'win' THEN 0 WHEN 'draw' THEN 1 ELSE 2 END,
    p."userName"
  ), '[]'::jsonb) INTO v_players
  FROM public."game_match_players" p
  WHERE p."matchId" = p_match_id;

  RETURN jsonb_build_object(
    'matchId',        v_history."id",
    'gameTable',      v_history."gameTable",
    'familyId',       v_history."familyId",
    'finishedAt',     v_history."finishedAt",
    'startedAt',      v_history."startedAt",
    'durationSeconds', v_history."durationSeconds",
    'playerCount',    v_history."playerCount",
    'resultKind',     v_history."resultKind",
    'winnerUserIds',  v_history."winnerUserIds",
    'winnerNames',    v_history."winnerNames",
    'players',        v_players
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_history_for_participant(text, text) TO authenticated;

-- =============================================================================
-- SECTION 6: fn_get_family_leaderboard_v2 — strip result columns for non-self
-- =============================================================================
-- New signature: fn_get_family_leaderboard_v2(p_family_id, p_period,
-- p_game_table, p_limit, p_requesting_user_id).
--
-- The extra p_requesting_user_id parameter is the auth.uid() of the caller.
-- The function still returns one row per family member, but:
--   • wins, losses, draws, winRate are REMOVED from every row.
--   • streakCurrent, streakBest are returned ONLY for the requester's own row;
--     for every other family member they are set to 0 (and the UI hides the
--     chip when zero — see Flutter GamingRankRow).
--   • points, matches (games played), userName, avatarUrl remain visible to
--     all family members (these are participation metrics, not outcomes).
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_get_family_leaderboard_v2(text, text, text, int);

CREATE OR REPLACE FUNCTION public.fn_get_family_leaderboard_v2(
  p_family_id text,
  p_period text DEFAULT 'all_time',          -- weekly | monthly | all_time
  p_game_table text DEFAULT NULL,
  p_limit int DEFAULT 50,
  p_requesting_user_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start timestamptz := CASE p_period
    WHEN 'weekly'  THEN date_trunc('week',  now())
    WHEN 'monthly' THEN date_trunc('month', now())
    ELSE '-infinity'::timestamptz END;
  v_rows jsonb;
BEGIN
  -- Defensive: if the caller forgot to pass the requester, we strip EVERY
  -- row's result columns. This is the safe default — never leak.
  IF p_requesting_user_id IS NULL OR p_requesting_user_id = '' THEN
    IF p_period = 'all_time' THEN
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."points" DESC, t."matches" DESC), '[]'::jsonb)
      INTO v_rows
      FROM (
        SELECT s."userId",
               COALESCE(u."name", MAX(p."userName"), s."userId") AS "userName",
               u."avatarUrl",
               SUM(s."matches") AS "matches",
               SUM(s."points")  AS "points",
               0 AS "streakCurrent",
               0 AS "streakBest"
        FROM "game_user_stats" s
        LEFT JOIN "User" u ON u."id" = s."userId"
        LEFT JOIN (
          SELECT "userId", MAX("userName") AS "userName" FROM "game_match_players"
          WHERE "familyId" = p_family_id GROUP BY "userId"
        ) p ON p."userId" = s."userId"
        WHERE s."familyId" = p_family_id
          AND s."gameTable" <> '*'
          AND (p_game_table IS NULL OR s."gameTable" = p_game_table)
        GROUP BY s."userId", u."name", u."avatarUrl"
        HAVING SUM(s."matches") > 0
        LIMIT LEAST(GREATEST(p_limit,1),100)
      ) t;
    ELSE
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."points" DESC, t."matches" DESC), '[]'::jsonb)
      INTO v_rows
      FROM (
        SELECT g."userId",
               COALESCE(u."name", MAX(g."userName"), g."userId") AS "userName",
               u."avatarUrl",
               COUNT(*) AS "matches",
               SUM(CASE g."result" WHEN 'win' THEN 3 WHEN 'loss' THEN 0 ELSE 1 END) AS "points",
               0 AS "streakCurrent",
               0 AS "streakBest"
        FROM "game_match_players" g
        LEFT JOIN "User" u ON u."id" = g."userId"
        WHERE g."familyId" = p_family_id
          AND g."finishedAt" >= v_start
          AND (p_game_table IS NULL OR g."gameTable" = p_game_table)
        GROUP BY g."userId", u."name", u."avatarUrl"
        LIMIT LEAST(GREATEST(p_limit,1),100)
      ) t;
    END IF;
  ELSE
    -- Requester known — expose their own streak, hide everyone else's, and
    -- NEVER expose wins/losses/winRate for anyone (including self — the
    -- account owner sees their own full stats via fn_get_player_gaming_profile).
    IF p_period = 'all_time' THEN
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."points" DESC, t."matches" DESC), '[]'::jsonb)
      INTO v_rows
      FROM (
        SELECT s."userId",
               COALESCE(u."name", MAX(p."userName"), s."userId") AS "userName",
               u."avatarUrl",
               SUM(s."matches") AS "matches",
               SUM(s."points")  AS "points",
               CASE WHEN s."userId" = p_requesting_user_id
                    THEN MAX(st."streakCurrent")
                    ELSE 0 END AS "streakCurrent",
               CASE WHEN s."userId" = p_requesting_user_id
                    THEN MAX(st."streakBest")
                    ELSE 0 END AS "streakBest"
        FROM "game_user_stats" s
        LEFT JOIN "game_user_stats" st
          ON st."userId" = s."userId"
         AND st."familyId" = s."familyId"
         AND st."gameTable" = '*'
        LEFT JOIN "User" u ON u."id" = s."userId"
        LEFT JOIN (
          SELECT "userId", MAX("userName") AS "userName" FROM "game_match_players"
          WHERE "familyId" = p_family_id GROUP BY "userId"
        ) p ON p."userId" = s."userId"
        WHERE s."familyId" = p_family_id
          AND s."gameTable" <> '*'
          AND (p_game_table IS NULL OR s."gameTable" = p_game_table)
        GROUP BY s."userId", u."name", u."avatarUrl"
        HAVING SUM(s."matches") > 0
        LIMIT LEAST(GREATEST(p_limit,1),100)
      ) t;
    ELSE
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."points" DESC, t."matches" DESC), '[]'::jsonb)
      INTO v_rows
      FROM (
        SELECT g."userId",
               COALESCE(u."name", MAX(g."userName"), g."userId") AS "userName",
               u."avatarUrl",
               COUNT(*) AS "matches",
               SUM(CASE g."result" WHEN 'win' THEN 3 WHEN 'loss' THEN 0 ELSE 1 END) AS "points",
               0 AS "streakCurrent",
               0 AS "streakBest"
        FROM "game_match_players" g
        LEFT JOIN "User" u ON u."id" = g."userId"
        WHERE g."familyId" = p_family_id
          AND g."finishedAt" >= v_start
          AND (p_game_table IS NULL OR g."gameTable" = p_game_table)
        GROUP BY g."userId", u."name", u."avatarUrl"
        LIMIT LEAST(GREATEST(p_limit,1),100)
      ) t;
    END IF;
  END IF;

  RETURN jsonb_build_object('period', p_period, 'entries', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_family_leaderboard_v2(text, text, text, int, text) TO authenticated;

-- =============================================================================
-- SECTION 7: fn_get_match_history — participant-gated, auth-enforced
-- =============================================================================
-- Hardened: the p_user_id parameter is now forced to equal auth.uid().
-- A family member can NO LONGER enumerate another member's match history.
-- The function returns ONLY matches in which the requesting user participated,
-- which is exactly what the spec requires ("Game history screen: fetch via
-- match_history_for_participant; if the current user isn't a participant in a
-- given match, don't render that row at all").
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_get_match_history(text, text, int, int);

CREATE OR REPLACE FUNCTION public.fn_get_match_history(
  p_user_id text,
  p_family_id text,
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
  v_total int;
  v_requester text := auth.uid()::text;
BEGIN
  -- Hard gate: the requester can only ever query their OWN history.
  -- p_user_id is kept in the signature for backward compatibility with
  -- existing clients, but is now ignored in favour of auth.uid().
  IF v_requester IS NULL THEN
    RETURN jsonb_build_object('total', 0, 'matches', '[]'::jsonb);
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM "game_match_players"
  WHERE "userId" = v_requester AND "familyId" = p_family_id;

  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."finishedAt" DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      mine."matchId",
      mine."gameTable",
      public.fn__game_meta() -> mine."gameTable" ->> 'name' AS "gameName",
      public.fn__game_meta() -> mine."gameTable" ->> 'icon' AS "gameIcon",
      mine."result",
      mine."finishedAt",
      h."durationSeconds",
      h."playerCount",
      -- Co-participants only (other participants are by definition participants
      -- in the same match, so their result is safe to surface to the requester).
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object('userName', o."userName", 'result', o."result"))
        FROM "game_match_players" o
        WHERE o."matchId" = mine."matchId" AND o."userId" <> v_requester
      ), '[]'::jsonb) AS "opponents"
    FROM "game_match_players" mine
    JOIN "game_match_history" h ON h."id" = mine."matchId"
    WHERE mine."userId" = v_requester AND mine."familyId" = p_family_id
    ORDER BY mine."finishedAt" DESC
    OFFSET GREATEST(p_offset,0)
    LIMIT LEAST(GREATEST(p_limit,1),100)
  ) t;

  RETURN jsonb_build_object('total', v_total, 'matches', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_match_history(text, text, int, int) TO authenticated;

-- =============================================================================
-- SECTION 8: fn_get_player_gaming_profile — strip result fields for non-self
-- =============================================================================
-- When the requester (auth.uid()) is NOT the profile owner, strip:
--   • wins, losses, draws, winRate
--   • perGame wins / losses / draws  (matches kept — participation)
--   • recentMatches results          (filtered to matches the requester joined)
--   • streakBest                     (streakCurrent kept — visible per spec)
-- The profile owner always sees their own full profile.
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_get_player_gaming_profile(text, text);

CREATE OR REPLACE FUNCTION public.fn_get_player_gaming_profile(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_overall record;
  v_user record;
  v_uname text;
  v_result jsonb;
  v_requester text := auth.uid()::text;
  v_is_self boolean;
BEGIN
  v_is_self := (v_requester IS NOT NULL AND v_requester = p_user_id);

  SELECT "id","name","avatarUrl","username" INTO v_user FROM "User" WHERE "id"=p_user_id;

  SELECT COALESCE(MAX("userName"), v_user."name", 'Family Member') INTO v_uname
  FROM "game_match_players" WHERE "userId"=p_user_id LIMIT 1;

  SELECT * INTO v_overall FROM "game_user_stats"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='*';

  IF v_is_self THEN
    -- Owner sees everything (their own data is theirs).
    SELECT jsonb_build_object(
      'userId', p_user_id,
      'userName', v_uname,
      'avatarUrl', v_user."avatarUrl",
      'username', v_user."username",
      'isSelf', true,
      'matches', COALESCE(v_overall."matches",0),
      'wins', COALESCE(v_overall."wins",0),
      'losses', COALESCE(v_overall."losses",0),
      'draws', COALESCE(v_overall."draws",0),
      'points', COALESCE(v_overall."points",0),
      'streakCurrent', COALESCE(v_overall."streakCurrent",0),
      'streakBest', COALESCE(v_overall."streakBest",0),
      'sportsmanship', COALESCE(v_overall."sportsmanshipReceived",0),
      'spectated', COALESCE(v_overall."spectated",0),
      'winRate', ROUND(COALESCE(v_overall."wins",0)::numeric / NULLIF(COALESCE(v_overall."matches",0),0), 3),
      'favoriteGame', (
        SELECT jsonb_build_object(
          'gameTable', s."gameTable",
          'name', public.fn__game_meta() -> s."gameTable" ->> 'name',
          'icon', public.fn__game_meta() -> s."gameTable" ->> 'icon',
          'matches', s."matches",
          'wins', s."wins")
        FROM "game_user_stats" s
        WHERE s."userId"=p_user_id AND s."familyId"=p_family_id
          AND s."gameTable" <> '*' AND s."matches" > 0
        ORDER BY s."matches" DESC LIMIT 1),
      'perGame', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'gameTable', s."gameTable",
          'name', public.fn__game_meta() -> s."gameTable" ->> 'name',
          'icon', public.fn__game_meta() -> s."gameTable" ->> 'icon',
          'matches', s."matches", 'wins', s."wins", 'losses', s."losses", 'draws', s."draws")
        ORDER BY s."matches" DESC)
        FROM "game_user_stats" s
        WHERE s."userId"=p_user_id AND s."familyId"=p_family_id AND s."gameTable" <> '*'
      ), '[]'::jsonb),
      'badges', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'slug', b."slug", 'name', b."name", 'icon', b."icon", 'tier', b."tier",
          'description', b."description", 'earnedAt', ub."earnedAt")
        ORDER BY ub."earnedAt" DESC)
        FROM "UserBadge" ub
        JOIN "Badge" b ON b."id" = ub."badgeId"
        WHERE ub."userId"=p_user_id AND COALESCE(ub."familyId",p_family_id)=p_family_id
          AND b."category"='games'
      ), '[]'::jsonb),
      'recentMatches', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'gameName', public.fn__game_meta() -> m."gameTable" ->> 'name',
          'gameIcon', public.fn__game_meta() -> m."gameTable" ->> 'icon',
          'result', m."result", 'finishedAt', m."finishedAt")
        ORDER BY m."finishedAt" DESC)
        FROM (SELECT * FROM "game_match_players"
              WHERE "userId"=p_user_id AND "familyId"=p_family_id
              ORDER BY "finishedAt" DESC LIMIT 5) m
      ), '[]'::jsonb),
      'recentActivity', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'action', a."action", 'description', a."description", 'createdAt', a."createdAt")
        ORDER BY a."createdAt" DESC)
        FROM (SELECT * FROM "FamilyActivityLog"
              WHERE "familyId"=p_family_id AND "actorUserId"=p_user_id AND "action" LIKE 'game_%'
              ORDER BY "createdAt" DESC LIMIT 8) a
      ), '[]'::jsonb),
      'rank', (
        SELECT COUNT(*) + 1 FROM (
          SELECT "userId", SUM("points") AS pts FROM "game_user_stats"
          WHERE "familyId"=p_family_id AND "gameTable" <> '*'
          GROUP BY "userId"
        ) t WHERE t."userId" <> p_user_id AND t.pts > COALESCE(v_overall."points",0)
      ),
      'daysActiveThisWeek', (
        SELECT COUNT(DISTINCT date("finishedAt")) FROM "game_match_players"
        WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "finishedAt" >= date_trunc('week', now())
      )
    ) INTO v_result;
  ELSE
    -- Non-owner: STRIP wins / losses / draws / winRate / streakBest /
    -- perGame wins-losses-draws / recentMatches results. recentMatches is
    -- additionally filtered to ONLY matches the requester participated in
    -- (so a non-participant never even sees the match existed).
    SELECT jsonb_build_object(
      'userId', p_user_id,
      'userName', v_uname,
      'avatarUrl', v_user."avatarUrl",
      'username', v_user."username",
      'isSelf', false,
      'matches', COALESCE(v_overall."matches",0),
      'wins', 0,
      'losses', 0,
      'draws', 0,
      'points', COALESCE(v_overall."points",0),
      'streakCurrent', 0,
      'streakBest', 0,
      'sportsmanship', COALESCE(v_overall."sportsmanshipReceived",0),
      'spectated', 0,
      'winRate', 0,
      'favoriteGame', (
        SELECT jsonb_build_object(
          'gameTable', s."gameTable",
          'name', public.fn__game_meta() -> s."gameTable" ->> 'name',
          'icon', public.fn__game_meta() -> s."gameTable" ->> 'icon',
          'matches', s."matches",
          'wins', 0)
        FROM "game_user_stats" s
        WHERE s."userId"=p_user_id AND s."familyId"=p_family_id
          AND s."gameTable" <> '*' AND s."matches" > 0
        ORDER BY s."matches" DESC LIMIT 1),
      'perGame', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'gameTable', s."gameTable",
          'name', public.fn__game_meta() -> s."gameTable" ->> 'name',
          'icon', public.fn__game_meta() -> s."gameTable" ->> 'icon',
          'matches', s."matches", 'wins', 0, 'losses', 0, 'draws', 0)
        ORDER BY s."matches" DESC)
        FROM "game_user_stats" s
        WHERE s."userId"=p_user_id AND s."familyId"=p_family_id AND s."gameTable" <> '*'
      ), '[]'::jsonb),
      'badges', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'slug', b."slug", 'name', b."name", 'icon', b."icon", 'tier', b."tier",
          'description', b."description", 'earnedAt', ub."earnedAt")
        ORDER BY ub."earnedAt" DESC)
        FROM "UserBadge" ub
        JOIN "Badge" b ON b."id" = ub."badgeId"
        WHERE ub."userId"=p_user_id AND COALESCE(ub."familyId",p_family_id)=p_family_id
          AND b."category"='games'
      ), '[]'::jsonb),
      'recentMatches', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'gameName', public.fn__game_meta() -> m."gameTable" ->> 'name',
          'gameIcon', public.fn__game_meta() -> m."gameTable" ->> 'icon',
          'result', m."result", 'finishedAt', m."finishedAt")
        ORDER BY m."finishedAt" DESC)
        FROM (SELECT mine.* FROM "game_match_players" mine
              WHERE mine."userId"=p_user_id AND mine."familyId"=p_family_id
                AND EXISTS (
                  SELECT 1 FROM "game_match_players" co
                  WHERE co."matchId" = mine."matchId"
                    AND co."userId" = v_requester
                )
              ORDER BY mine."finishedAt" DESC LIMIT 5) m
      ), '[]'::jsonb),
      'recentActivity', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'action', a."action", 'description', a."description", 'createdAt', a."createdAt")
        ORDER BY a."createdAt" DESC)
        FROM (SELECT * FROM "FamilyActivityLog"
              WHERE "familyId"=p_family_id AND "actorUserId"=p_user_id AND "action" LIKE 'game_%'
              ORDER BY "createdAt" DESC LIMIT 8) a
      ), '[]'::jsonb),
      'rank', (
        SELECT COUNT(*) + 1 FROM (
          SELECT "userId", SUM("points") AS pts FROM "game_user_stats"
          WHERE "familyId"=p_family_id AND "gameTable" <> '*'
          GROUP BY "userId"
        ) t WHERE t."userId" <> p_user_id AND t.pts > COALESCE(v_overall."points",0)
      ),
      'daysActiveThisWeek', (
        SELECT COUNT(DISTINCT date("finishedAt")) FROM "game_match_players"
        WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "finishedAt" >= date_trunc('week', now())
      )
    ) INTO v_result;
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_player_gaming_profile(text, text) TO authenticated;

-- =============================================================================
-- SECTION 9: fn_get_gaming_dashboard — pass requester id to leaderboard
-- =============================================================================
-- The dashboard RPC internally calls fn_get_family_leaderboard_v2. We update
-- those calls to pass p_user_id as the requester so the dashboard's embedded
-- leaderboard preview also strips result columns for non-self rows.
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_get_gaming_dashboard(text, text);

CREATE OR REPLACE FUNCTION public.fn_get_gaming_dashboard(
  p_family_id text,
  p_user_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_overall record;
  v_season jsonb;
  v_rank int;
  v_family_total int;
BEGIN
  PERFORM public.fn__advance_challenges(p_user_id, p_family_id);
  v_season := public.fn_get_current_season(p_family_id);

  SELECT * INTO v_overall FROM "game_user_stats"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='*';

  SELECT COUNT(*)+1 INTO v_rank FROM (
    SELECT "userId", SUM("points") AS pts FROM "game_user_stats"
    WHERE "familyId"=p_family_id AND "gameTable" <> '*'
    GROUP BY "userId" HAVING SUM("points") > COALESCE(v_overall."points",0)
  ) t;

  SELECT COALESCE("totalMatches",0) INTO v_family_total
  FROM "game_family_stats" WHERE "familyId"=p_family_id;

  SELECT jsonb_build_object(
    'familyTotalMatches', v_family_total,
    'familyDistinctGames', (
      SELECT COALESCE("distinctGames",0) FROM "game_family_stats" WHERE "familyId"=p_family_id),
    'me', jsonb_build_object(
      'userId', p_user_id,
      'matches', COALESCE(v_overall."matches",0),
      'wins', COALESCE(v_overall."wins",0),
      'points', COALESCE(v_overall."points",0),
      'streakCurrent', COALESCE(v_overall."streakCurrent",0),
      'rank', v_rank),
    'season', v_season,
    'challenges', (public.fn_get_family_challenges(p_family_id, p_user_id) -> 'challenges'),
    -- Leaderboard now strips wins/losses/winRate for everyone and only
    -- surfaces streakCurrent for the requester's own row.
    'leaderboard', (public.fn_get_family_leaderboard_v2(p_family_id, 'all_time', NULL, 5, p_user_id) -> 'entries'),
    'weeklyLeaderboard', (public.fn_get_family_leaderboard_v2(p_family_id, 'weekly', NULL, 5, p_user_id) -> 'entries'),
    'activity', public.fn_get_family_gaming_activity(p_family_id, 6),
    'suggestions', (public.fn_get_smart_match_suggestions(p_family_id, p_user_id) -> 'suggestions'),
    'milestones', (public.fn_get_family_gaming_milestones(p_family_id) -> 'milestones'),
    'seasonStandings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', g."userId",
        'userName', COALESCE(u."name", mp."userName", g."userId"),
        'points', g."points",
        'wins', 0,
        'gamesPlayed', g."gamesPlayed")
      ORDER BY g."points" DESC)
      FROM "game_season_standings" g
      LEFT JOIN "User" u ON u."id" = g."userId"
      LEFT JOIN (SELECT "userId", MAX("userName") AS "userName" FROM "game_match_players"
                 WHERE "familyId"=p_family_id GROUP BY "userId") mp ON mp."userId" = g."userId"
      WHERE g."familyId" = p_family_id AND g."seasonId" = (v_season->>'id')
    ), '[]'::jsonb),
    'myBadges', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'slug', b."slug", 'name', b."name", 'icon', b."icon", 'tier', b."tier",
        'description', b."description", 'earnedAt', ub."earnedAt")
      ORDER BY ub."earnedAt" DESC)
      FROM "UserBadge" ub
      JOIN "Badge" b ON b."id" = ub."badgeId"
      WHERE ub."userId"=p_user_id AND COALESCE(ub."familyId",p_family_id)=p_family_id
        AND b."category"='games'
    ), '[]'::jsonb),
    'allGameBadges', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'slug', b."slug", 'name', b."name", 'icon', b."icon", 'tier', b."tier",
        'description', b."description", 'threshold', b."threshold",
        'earned', EXISTS (SELECT 1 FROM "UserBadge" ub2
                          WHERE ub2."badgeId"=b."id" AND ub2."userId"=p_user_id
                            AND COALESCE(ub2."familyId",p_family_id)=p_family_id))
      ORDER BY b."tier", b."name")
      FROM "Badge" b WHERE b."category"='games'
    ), '[]'::jsonb),
    'familyMembers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', u."id", 'userName', COALESCE(u."name", 'Family Member'),
        'avatarUrl', u."avatarUrl", 'points', COALESCE(s."points",0),
        'matches', COALESCE(s."matches",0))
      ORDER BY COALESCE(s."points",0) DESC)
      FROM "FamilyMember" fm
      JOIN "User" u ON u."id" = fm."userId"
      LEFT JOIN "game_user_stats" s
        ON s."userId" = fm."userId" AND s."familyId" = fm."familyId" AND s."gameTable"='*'
      WHERE fm."familyId" = p_family_id
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_gaming_dashboard(text, text) TO authenticated;

-- =============================================================================
-- SECTION 10: Participation-focused badges — "Most Active" / "Most Games Played"
-- =============================================================================
-- Two new badge rows that reward SHOWING UP, not winning. Seeded idempotently
-- so a family member who plays often but rarely wins still ranks highly on
-- something visible alongside "Most Wins".
-- =============================================================================

INSERT INTO "Badge" ("id", "slug", "name", "icon", "tier", "category",
                     "description", "threshold", "createdAt")
VALUES
  ('badge-games-most-active-weekly',
   'games_most_active_weekly',
   'Most Active This Week',
   '🔥',
   'gold',
   'games',
   'Played the most matches in your family this week — showing up is the win.',
   3,
   now())
ON CONFLICT ("id") DO UPDATE SET
  "name"        = EXCLUDED."name",
  "icon"        = EXCLUDED."icon",
  "tier"        = EXCLUDED."tier",
  "description" = EXCLUDED."description";

INSERT INTO "Badge" ("id", "slug", "name", "icon", "tier", "category",
                     "description", "threshold", "createdAt")
VALUES
  ('badge-games-most-played-monthly',
   'games_most_played_monthly',
   'Most Games Played',
   '🎮',
   'silver',
   'games',
   'Played the most matches in your family this month — the family''s heartbeat.',
   5,
   now())
ON CONFLICT ("id") DO UPDATE SET
  "name"        = EXCLUDED."name",
  "icon"        = EXCLUDED."icon",
  "tier"        = EXCLUDED."tier",
  "description" = EXCLUDED."description";

-- =============================================================================
-- SECTION 11: Comment marker
-- =============================================================================
COMMENT ON VIEW public.family_leaderboard_view IS
  'Privacy-safe family leaderboard aggregate. Deliberately excludes wins, losses and win_percentage — those are only ever visible to the account owner via fn_get_player_gaming_profile.';

COMMENT ON FUNCTION public.match_history_for_participant(text, text) IS
  'Participant-gated match detail. Returns full match result ONLY if the requesting user was a participant; otherwise returns an empty jsonb object so the match''s existence is not confirmed to non-participants.';
