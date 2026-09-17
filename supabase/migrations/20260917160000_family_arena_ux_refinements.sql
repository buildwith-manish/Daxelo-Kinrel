-- =============================================================================
-- 20260917160000_family_arena_ux_refinements.sql
--
-- Three UX refinements backend support:
--   1. get_family_quick_picks(family_id, requesting_user_id, limit) —
--      returns the family's most-played games in the last 30 days, with
--      a hardcoded default backfill when the family has < limit distinct
--      games played. Used by the new "Quick picks" row on the home screen.
--   2. fn_get_family_leaderboard_v3 — participation-based leaderboard.
--      Orders by games_played DESC (not points), excludes wins/losses/win%
--      (already done in v2), and splits the result into "ranked" rows
--      (games_played >= 1) and "not_yet_played" rows (games_played == 0)
--      so the Flutter layer can render the latter as a separate
--      NotYetPlayedPrompt below the ranked list. v2 is kept for backward
--      compatibility.
--
-- Privacy contract (unchanged from prior migrations):
--   • wins / losses / winRate are NEVER returned for any row.
--   • streakCurrent / streakBest are returned ONLY for the requester's
--     own row (every other row gets 0).
--   • points are still returned for internal use (Family Cup etc.) but
--     the Flutter leaderboard UI no longer displays them.
-- =============================================================================

-- =============================================================================
-- SECTION 1: get_family_quick_picks(family_id, requesting_user_id, limit)
-- =============================================================================
-- Returns up to `limit` game rows ordered by play_count_last_30d DESC.
-- Each row: game_id, game_name, game_icon, player_count_range,
-- play_count_last_30d.
--
-- Backfill: when the family has fewer than `limit` distinct games played
-- in the last 30 days, the result is padded with a curated default set
-- suited to small groups (2-4 players): Tic-Tac-Toe, Checkers,
-- Memory Match, Chess. Default games already played by the family are
-- skipped during backfill (no duplicates).
--
-- The requesting_user_id is currently used only for the family-membership
-- gate (defensive — the RPC could later personalise picks per viewer,
-- e.g. exclude games the viewer has already over-played).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_family_quick_picks(
  p_family_id text,
  p_requesting_user_id text DEFAULT NULL,
  p_limit int DEFAULT 6
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit int := LEAST(GREATEST(p_limit, 1), 12);
  v_meta jsonb := public.fn__game_meta();
  v_played jsonb;
  v_played_count int;
  v_rows jsonb;
  v_default_game_ids text[] := ARRAY[
    'tictactoe_games',
    'checkers_games',
    'memorymatch_games',
    'chess_games'
  ]::text[];
  v_existing_tables text[];
  v_game_table text;
  v_backfill_rows jsonb := '[]'::jsonb;
  v_backfill_count int := 0;
BEGIN
  -- Defensive: requester must be a family member.
  IF p_requesting_user_id IS NOT NULL AND NOT public.fn_user_is_family_member(p_family_id) THEN
    RETURN jsonb_build_object('picks', '[]'::jsonb);
  END IF;

  -- 1. Aggregate the family's most-played games in the last 30 days.
  --    We read from game_match_history (family-scoped, RLS-visible to
  --    family members). Each row counts the # of finished matches per
  --    gameTable. We never read result columns — participation count only.
  --
  --    NOTE: fn__game_meta() returns {id, name, icon, accent} but NOT a
  --    player-count-range field. We derive player_count_range from the
  --    actual player counts observed in game_match_history (min/max).
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.play_count_last_30d DESC), '[]'::jsonb)
  INTO v_played
  FROM (
    SELECT
      h."gameTable"                          AS game_id,
      v_meta -> h."gameTable" ->> 'name'     AS game_name,
      v_meta -> h."gameTable" ->> 'icon'     AS game_icon,
      -- Derive a "2-4 players" style label from observed min/max.
      CASE
        WHEN MIN(h."playerCount") = MAX(h."playerCount") AND MIN(h."playerCount") > 0
          THEN MIN(h."playerCount")::text || ' players'
        WHEN MIN(h."playerCount") > 0
          THEN MIN(h."playerCount")::text || '–' || MAX(h."playerCount")::text || ' players'
        ELSE '2+ players'
      END                                    AS player_count_range,
      COUNT(*)::int                          AS play_count_last_30d
    FROM "game_match_history" h
    WHERE h."familyId" = p_family_id
      AND h."finishedAt" >= now() - interval '30 days'
    GROUP BY h."gameTable"
    ORDER BY play_count_last_30d DESC
    LIMIT v_limit
  ) t;

  v_played_count := jsonb_array_length(v_played);

  -- 2. Backfill with defaults when the family has < v_limit distinct games.
  IF v_played_count < v_limit THEN
    -- Collect gameTables already in the played list so we don't duplicate.
    SELECT COALESCE(array_agg(value->>'game_id'), ARRAY[]::text[])
      INTO v_existing_tables
      FROM jsonb_array_elements(v_played);

    FOR v_game_table IN SELECT * FROM unnest(v_default_game_ids) LOOP
      EXIT WHEN v_played_count + v_backfill_count >= v_limit;
      -- Skip defaults already played (in v_existing_tables) or already
      -- added to the backfill (defensive — shouldn't happen since the
      -- default list has unique entries, but be safe).
      CONTINUE WHEN v_game_table = ANY(v_existing_tables);

      -- Skip defaults that aren't in the catalog metadata (defensive —
      -- if a game was renamed/removed, we don't want a null name).
      CONTINUE WHEN v_meta -> v_game_table IS NULL;

      -- Hardcoded player-count labels for the 4 default games (matches
      -- the Flutter GameCatalogEntry.playersLabel values). fn__game_meta()
      -- does NOT return a players field, so we hardcode here.
      v_backfill_rows := v_backfill_rows || jsonb_build_object(
        'game_id', v_game_table,
        'game_name', v_meta -> v_game_table ->> 'name',
        'game_icon', v_meta -> v_game_table ->> 'icon',
        'player_count_range',
          CASE v_game_table
            WHEN 'tictactoe_games'   THEN '2 players'
            WHEN 'checkers_games'    THEN '2 players'
            WHEN 'memorymatch_games' THEN '2–4 players'
            WHEN 'chess_games'       THEN '2 players'
            ELSE '2+ players'
          END,
        'play_count_last_30d', 0
      );
      v_backfill_count := v_backfill_count + 1;
      v_existing_tables := array_append(v_existing_tables, v_game_table);
    END LOOP;
  END IF;

  -- 3. Merge played + backfill. The played list is already sorted by
  --    play_count_last_30d DESC and limited to v_limit. The backfill
  --    rows have play_count_last_30d = 0 and are appended in default-list
  --    order. We re-sort the merged list so backfill rows (count=0) sort
  --    after played rows (count>0), then truncate to v_limit.
  --
  --    We avoid the LATERAL + jsonb_array_elements approach (which had
  --    a column-aliasing issue) by rebuilding the merged array via a
  --    simple jsonb_path_query + ORDER BY.
  v_rows := v_played || v_backfill_rows;

  -- Re-sort + truncate using a cleaner jsonb aggregation.
  SELECT COALESCE(jsonb_agg(elem ORDER BY (elem->>'play_count_last_30d')::int DESC,
                                       elem->>'game_name' ASC), '[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(v_rows) AS elem
  LIMIT v_limit;

  RETURN jsonb_build_object('picks', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_family_quick_picks(text, text, int) TO authenticated;

COMMENT ON FUNCTION public.get_family_quick_picks(text, text, int) IS
  'Quick picks row for the Family Arena home screen. Returns the family''s most-played games in the last 30 days, with a curated default backfill (Tic-Tac-Toe, Checkers, Memory Match, Chess) when the family has fewer than `limit` distinct games played. Never returns win/loss data — participation count only.';

-- =============================================================================
-- SECTION 2: fn_get_family_leaderboard_v3 — participation-based leaderboard
-- =============================================================================
-- Mirrors v2 but:
--   • Orders by games_played DESC (not points DESC).
--   • Splits the result into "ranked" (games_played >= 1) and
--     "not_yet_played" (games_played == 0) so the Flutter layer can
--     render the latter as a separate NotYetPlayedPrompt below the
--     ranked list, never inside it.
--   • Keeps returning `points` for internal use (Family Cup etc.) but
--     the Flutter UI no longer displays it.
--   • Keeps the streakCurrent/streakBest self-only gating from v2.
--   • Continues to NEVER return wins/losses/winRate.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_family_leaderboard_v3(
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
  v_ranked jsonb;
  v_not_played jsonb;
BEGIN
  -- Defensive: if the caller forgot the requester, strip everything
  -- (same as v2). Streak fields become 0 for all rows.
  IF p_requesting_user_id IS NULL OR p_requesting_user_id = '' THEN
    IF p_period = 'all_time' THEN
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."matches" DESC, t."points" DESC), '[]'::jsonb)
      INTO v_ranked
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
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."matches" DESC, t."points" DESC), '[]'::jsonb)
      INTO v_ranked
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
        HAVING COUNT(*) > 0
        LIMIT LEAST(GREATEST(p_limit,1),100)
      ) t;
    END IF;
    v_not_played := '[]'::jsonb;
  ELSE
    -- Requester known — participation-ordered leaderboard, split into
    -- ranked (games_played >= 1) and not_yet_played (games_played == 0).
    IF p_period = 'all_time' THEN
      -- RANKED rows (games_played >= 1)
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."matches" DESC, t."points" DESC), '[]'::jsonb)
      INTO v_ranked
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
        HAVING SUM(s."matches") >= 1
        LIMIT LEAST(GREATEST(p_limit,1),100)
      ) t;

      -- NOT-YET-PLAYED rows (members with no game_user_stats matches,
      -- i.e. family members who have never played any game in this family).
      -- We pull from FamilyMember + User so we have avatarUrl/name for the
      -- NotYetPlayedPrompt UI.
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."userName" ASC), '[]'::jsonb)
      INTO v_not_played
      FROM (
        SELECT fm."userId"             AS "userId",
               COALESCE(u."name", fm."userId") AS "userName",
               u."avatarUrl"           AS "avatarUrl",
               0 AS "matches",
               0 AS "points"
        FROM "FamilyMember" fm
        LEFT JOIN "User" u ON u."id" = fm."userId"
        WHERE fm."familyId" = p_family_id
          AND fm."userId" <> p_requesting_user_id  -- don't show self here
          AND NOT EXISTS (
            SELECT 1 FROM "game_user_stats" s
            WHERE s."userId" = fm."userId"
              AND s."familyId" = p_family_id
              AND s."gameTable" <> '*'
              AND s."matches" > 0
          )
          AND NOT EXISTS (
            SELECT 1 FROM "game_match_players" g
            WHERE g."userId" = fm."userId"
              AND g."familyId" = p_family_id
              AND (p_game_table IS NULL OR g."gameTable" = p_game_table)
          )
      ) t;
    ELSE
      -- Weekly/monthly — only count matches within the period.
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t."matches" DESC, t."points" DESC), '[]'::jsonb)
      INTO v_ranked
      FROM (
        SELECT g."userId",
               COALESCE(u."name", MAX(g."userName"), g."userId") AS "userName",
               u."avatarUrl",
               COUNT(*) AS "matches",
               SUM(CASE g."result" WHEN 'win' THEN 3 WHEN 'loss' THEN 0 ELSE 1 END) AS "points",
               CASE WHEN g."userId" = p_requesting_user_id
                    THEN COALESCE(MAX(st."streakCurrent"), 0)
                    ELSE 0 END AS "streakCurrent",
               CASE WHEN g."userId" = p_requesting_user_id
                    THEN COALESCE(MAX(st."streakBest"), 0)
                    ELSE 0 END AS "streakBest"
        FROM "game_match_players" g
        LEFT JOIN "game_user_stats" st
          ON st."userId" = g."userId"
         AND st."familyId" = g."familyId"
         AND st."gameTable" = '*'
        LEFT JOIN "User" u ON u."id" = g."userId"
        WHERE g."familyId" = p_family_id
          AND g."finishedAt" >= v_start
          AND (p_game_table IS NULL OR g."gameTable" = p_game_table)
        GROUP BY g."userId", u."name", u."avatarUrl"
        HAVING COUNT(*) >= 1
        LIMIT LEAST(GREATEST(p_limit,1),100)
      ) t;

      -- For weekly/monthly we don't surface a "not yet played" section
      -- (a member might have played historically but not this week — that's
      -- different from never having played at all). The home-screen
      -- NotYetPlayedPrompt is intended for the all_time view.
      v_not_played := '[]'::jsonb;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'period', p_period,
    'ranked', v_ranked,
    'notYetPlayed', v_not_played
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_family_leaderboard_v3(text, text, text, int, text) TO authenticated;

COMMENT ON FUNCTION public.fn_get_family_leaderboard_v3(text, text, text, int, text) IS
  'Participation-based family leaderboard. Orders by games_played DESC (NOT points). Returns {ranked: [...], notYetPlayed: [...]} so the Flutter layer can render members with 0 games in a separate NotYetPlayedPrompt section below the ranked list. Streak fields are returned ONLY for the requester''s own row. Wins/losses/winRate are NEVER returned (same privacy contract as v2).';
