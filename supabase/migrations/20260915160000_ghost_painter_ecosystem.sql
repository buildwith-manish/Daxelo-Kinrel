-- =============================================================================
-- Ghost Painter joins the Family Gaming Ecosystem (game #15 → full parity)
-- =============================================================================
-- Before this migration Ghost Painter lived completely outside the ecosystem:
-- its rounds never archived, so they produced no match history, stats,
-- badges, challenge progress, milestones, activity-feed entries or Family Cup
-- points, and its screens showed no post-match rewards / sportsmanship UI.
--
-- This migration:
--   1. Adds `ghost_painter_rounds` to fn__game_meta / fn__archive_family_match /
--      fn_get_match_ecosystem whitelists with dedicated participant extraction
--      (drawer + guessers) and winner extraction (correct guessers).
--   2. Adds a completion trigger: the moment a round flips to 'completed' the
--      central archive processor runs — regardless of which client caused it.
--   3. Persists the rich rewards payload (newBadges / completedChallenges /
--      milestones) on game_match_history."rewardsJson" and serves it from
--      fn_get_match_ecosystem so EVERY player's results screen shows the
--      celebration banner (previously only the archiving caller saw it).
--   4. Seeds the "Ghost Painter Virtuoso" champion badge (5 round wins).
--   5. Teaches fn_cleanup_completed_games to archive-then-delete finished
--      Ghost Painter rounds and to retire stale abandoned ones.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Persist rewards payload on the permanent match archive
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "game_match_history"
  ADD COLUMN IF NOT EXISTS "rewardsJson" jsonb;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) fn__game_meta — Ghost Painter metadata
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn__game_meta()
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'sos_games',          jsonb_build_object('id','sos','name','SOS','icon','🎯','accent','#F59E0B'),
    'bingo_games',        jsonb_build_object('id','bingo','name','Bingo','icon','🎟️','accent','#06B6D4'),
    'ludo_games',         jsonb_build_object('id','ludo','name','Ludo','icon','🎲','accent','#E11D48'),
    'antakshari_games',   jsonb_build_object('id','antakshari','name','Antakshari','icon','🎤','accent','#8B5CF6'),
    'chitmatch_games',    jsonb_build_object('id','chitmatch','name','TripleMatch','icon','🃏','accent','#EC4899'),
    'checkers_games',     jsonb_build_object('id','checkers','name','Checkers','icon','🔴','accent','#6366F1'),
    'chess_games',        jsonb_build_object('id','chess','name','Chess','icon','♞','accent','#64748B'),
    'carrom_games',       jsonb_build_object('id','carrom','name','Carrom','icon','⚪','accent','#F59E0B'),
    'tictactoe_games',    jsonb_build_object('id','tictactoe','name','Tic-Tac-Toe','icon','#️⃣','accent','#8B5CF6'),
    'truthordare_games',  jsonb_build_object('id','truthordare','name','Truth or Dare','icon','🎭','accent','#EF4444'),
    'twotruths_games',    jsonb_build_object('id','twotruths','name','Two Truths & a Lie','icon','🕵️','accent','#D946EF'),
    'dotsboxes_games',    jsonb_build_object('id','dotsboxes','name','Dots & Boxes','icon','▪️','accent','#06B6D4'),
    'nameplace_games',    jsonb_build_object('id','nameplace','name','Name Place Animal Thing','icon','📖','accent','#10B981'),
    'redlight_rounds',    jsonb_build_object('id','freeze-dash','name','Freeze & Dash','icon','🏃','accent','#10B981'),
    'ghost_painter_rounds', jsonb_build_object('id','ghost-painter','name','Ghost Painter','icon','👻','accent','#EC4899')
  );
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) fn__archive_family_match — Ghost Painter support + rewards persistence
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn__archive_family_match(
  p_game_table text,
  p_game_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_family_id      text;
  v_status         text;
  v_created_at     timestamptz;
  v_finished_at    timestamptz;
  v_end_col        text;
  v_finished_status text;
  v_winner_col     text;
  v_winner_name_col text;
  v_winner_ids     text[] := '{}';
  v_winner_names   text[] := '{}';
  v_is_terminal    boolean := false;
  v_player_count   int := 0;
  v_meta           jsonb;
  v_result_kind    text := 'played';
  v_new_badges     jsonb := '[]'::jsonb;
  v_completed      jsonb := '[]'::jsonb;
  v_milestones     jsonb := '[]'::jsonb;
  v_badges_for_p   jsonb;
  v_chal_for_p     jsonb;
  v_participants   jsonb;
  v_p              jsonb;
  v_i              int;
  v_uid            text;
  v_uname          text;
  v_res            text;
  v_streak_before  int;
  v_duration       int;
  v_season_id      text;
  v_season_name    text;
  v_spectator      record;
  v_already        boolean;
  v_summary        jsonb;
BEGIN
  -- Whitelist game tables (security: p_game_table is used in dynamic SQL)
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games',
    'sos_games','dotsboxes_games','nameplace_games','truthordare_games',
    'twotruths_games','redlight_rounds','chess_games','tictactoe_games',
    'checkers_games','carrom_games','ghost_painter_rounds'
  ) THEN
    RETURN NULL;
  END IF;

  -- Idempotency: already archived → no-op
  SELECT EXISTS (
    SELECT 1 FROM "game_match_history"
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id
  ) INTO v_already;
  IF v_already THEN
    RETURN NULL;
  END IF;

  v_meta := public.fn__game_meta() -> p_game_table;

  -- ── Read the game row (dynamic: column names differ per table) ──
  -- sos_games + redlight_rounds use finishedAt/'finished';
  -- ghost_painter_rounds uses endsAt/'completed'; all others completedAt/'completed'.
  IF p_game_table IN ('sos_games','redlight_rounds') THEN
    v_end_col := 'finishedAt';
    v_finished_status := 'finished';
  ELSIF p_game_table = 'ghost_painter_rounds' THEN
    v_end_col := 'endsAt';
    v_finished_status := 'completed';
  ELSE
    v_end_col := 'completedAt';
    v_finished_status := 'completed';
  END IF;

  EXECUTE format(
    'SELECT "familyId", "status", "createdAt", COALESCE(%I, now())
       FROM public.%I WHERE "id" = $1', v_end_col, p_game_table)
    INTO v_family_id, v_status, v_created_at, v_finished_at
    USING p_game_id;

  IF v_family_id IS NULL THEN
    RETURN NULL; -- game row already gone (e.g. race with cron)
  END IF;
  v_created_at := COALESCE(v_created_at, now());
  v_finished_at := COALESCE(v_finished_at, now());

  -- Terminal statuses per table (from RoomConfig presets)
  v_is_terminal := v_status IN (v_finished_status, 'ended', 'done');

  -- ── Extract winners (column name differs per table) ──
  IF p_game_table = 'truthordare_games' THEN
    v_winner_ids := '{}';  -- party game: no winners, participation only
  ELSIF p_game_table = 'ghost_painter_rounds' THEN
    -- Winner(s) = the guesser(s) who cracked the drawing
    SELECT ARRAY(SELECT g."userId" FROM "ghost_painter_guesses" g
                 WHERE g."roundId" = p_game_id AND g."isCorrect")
      INTO v_winner_ids;
  ELSIF p_game_table IN ('antakshari_games','chitmatch_games','dotsboxes_games',
                          'nameplace_games','twotruths_games') THEN
    -- winnerUserIds is a jsonb array on these tables
    EXECUTE format(
      'SELECT ARRAY(SELECT jsonb_array_elements_text(COALESCE("winnerUserIds", ''[]''::jsonb))) FROM public.%I WHERE "id" = $1',
      p_game_table)
      INTO v_winner_ids USING p_game_id;
  ELSE
    v_winner_col := CASE
      WHEN p_game_table IN ('chess_games','checkers_games','carrom_games','ludo_games') THEN 'winnerId'
      WHEN p_game_table = 'tictactoe_games' THEN 'overallWinnerId'
      WHEN p_game_table = 'bingo_games' THEN 'winnerPlayerId'
      ELSE 'winnerUserId'  -- sos_games, redlight_rounds
    END;
    EXECUTE format(
      'SELECT ARRAY[COALESCE(%I, '''')] FROM public.%I WHERE "id" = $1',
      v_winner_col, p_game_table)
      INTO v_winner_ids USING p_game_id;
  END IF;

  v_winner_ids := COALESCE(v_winner_ids, '{}');
  v_winner_ids := ARRAY(SELECT x FROM unnest(v_winner_ids) AS x WHERE x IS NOT NULL AND x <> '');

  IF array_length(v_winner_ids, 1) IS NULL THEN
    IF NOT v_is_terminal THEN
      RETURN NULL; -- abandoned / cancelled / in-progress → do not archive
    END IF;
    v_result_kind := 'played';   -- finished without winners (party game / draw)
  ELSE
    v_result_kind := 'win';
    -- Winner display names — resolved uniformly from participants
    IF p_game_table = 'ghost_painter_rounds' THEN
      SELECT ARRAY(SELECT g."userName" FROM "ghost_painter_guesses" g
                   WHERE g."roundId" = p_game_id AND g."isCorrect"
                     AND g."userId" = ANY(v_winner_ids))
        INTO v_winner_names;
    ELSE
      SELECT COALESCE(array_agg(gp."userName") FILTER (WHERE gp."userName" IS NOT NULL), '{}')
        INTO v_winner_names
      FROM "game_participants" gp
      WHERE gp."gameTable" = p_game_table
        AND gp."gameId" = p_game_id
        AND gp."userId" = ANY(v_winner_ids);
    END IF;
    IF array_length(v_winner_names, 1) IS NULL AND p_game_table <> 'ghost_painter_rounds' THEN
      -- fallback: the game row's name column (board games)
      v_winner_name_col := CASE
        WHEN p_game_table IN ('chess_games','checkers_games','carrom_games','ludo_games') THEN 'winnerName'
        WHEN p_game_table = 'tictactoe_games' THEN 'overallWinnerName'
        WHEN p_game_table = 'redlight_rounds' THEN 'winnerUserName'
        WHEN p_game_table = 'bingo_games' THEN 'winnerPlayerName'
        ELSE NULL
      END;
      IF v_winner_name_col IS NOT NULL THEN
        EXECUTE format(
          'SELECT ARRAY[COALESCE(%I, '''')] FROM public.%I WHERE "id" = $1',
          v_winner_name_col, p_game_table)
          INTO v_winner_names USING p_game_id;
      ELSE
        v_winner_names := '{}';
      END IF;
      v_winner_names := ARRAY(SELECT x FROM unnest(COALESCE(v_winner_names,'{}')) AS x WHERE x IS NOT NULL AND x <> '');
    END IF;
    v_winner_names := COALESCE(v_winner_names, '{}');
  END IF;

  -- ── Load live participants (rows still exist at this point) ──
  -- role filter includes 'host': the room host IS a player in every game
  -- (RoomController.createRoom records the host with role='host').
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'userId', gp."userId",
      'userName', COALESCE(gp."userName",'Family Member'),
      'role', gp."role")), '[]'::jsonb)
  INTO v_participants
  FROM "game_participants" gp
  WHERE gp."gameTable" = p_game_table
    AND gp."gameId" = p_game_id
    AND gp."role" IN ('player','host');

  v_player_count := jsonb_array_length(v_participants);

  -- ── Inline-player games (Pattern A: chess / checkers / carrom / tictactoe)
  --    create rooms via their own providers (ChallengeLobbyScreen), which do
  --    NOT write game_participants. Derive participants from the game row's
  --    player columns so those matches are archived too.
  IF v_player_count = 0 AND p_game_table IN ('chess_games','checkers_games','carrom_games','tictactoe_games') THEN
    DECLARE
      v_p1_id text; v_p1_name text; v_p2_id text; v_p2_name text;
    BEGIN
      IF p_game_table = 'tictactoe_games' THEN
        EXECUTE format('SELECT "playerXId","playerXName","playerOId","playerOName" FROM public.%I WHERE "id" = $1', p_game_table)
            INTO v_p1_id, v_p1_name, v_p2_id, v_p2_name USING p_game_id;
      ELSIF p_game_table = 'chess_games' THEN
        EXECUTE format('SELECT "playerWhiteId","playerWhiteName","playerBlackId","playerBlackName" FROM public.%I WHERE "id" = $1', p_game_table)
            INTO v_p1_id, v_p1_name, v_p2_id, v_p2_name USING p_game_id;
      ELSE -- checkers + carrom
        EXECUTE format('SELECT "playerOneId","playerOneName","playerTwoId","playerTwoName" FROM public.%I WHERE "id" = $1', p_game_table)
            INTO v_p1_id, v_p1_name, v_p2_id, v_p2_name USING p_game_id;
      END IF;

      v_participants := jsonb_build_array(
        jsonb_build_object('userId', v_p1_id, 'userName', COALESCE(v_p1_name,'Player'), 'role', 'player'),
        jsonb_build_object('userId', v_p2_id, 'userName', COALESCE(v_p2_name,'Player'), 'role', 'player'));
      v_player_count := 2;
    END;
  END IF;

  -- ── Ghost Painter: participants are the drawer plus everyone who guessed ──
  IF v_player_count = 0 AND p_game_table = 'ghost_painter_rounds' THEN
    SELECT jsonb_agg(jsonb_build_object(
             'userId', x."userId",
             'userName', COALESCE(x."userName", 'Family Member'),
             'role', x."role"))
    INTO v_participants
    FROM (
      SELECT g."userId" AS "userId", g."userName" AS "userName", 'player' AS "role"
      FROM "ghost_painter_guesses" g
      WHERE g."roundId" = p_game_id
      UNION ALL
      SELECT r."drawerPersonId", r."drawerPersonName", 'host'
      FROM "ghost_painter_rounds" r
      WHERE r."id" = p_game_id
        AND r."drawerPersonId" IS NOT NULL
        AND r."drawerPersonId" NOT IN (
          SELECT g."userId" FROM "ghost_painter_guesses" g WHERE g."roundId" = p_game_id)
    ) x;
    v_player_count := jsonb_array_length(COALESCE(v_participants, '[]'::jsonb));
  END IF;

  -- Ghost Painter: a round with zero guesses is an abandoned pickup round,
  -- not a family match — never archive it.
  IF p_game_table = 'ghost_painter_rounds' AND NOT EXISTS (
    SELECT 1 FROM "ghost_painter_guesses" WHERE "roundId" = p_game_id) THEN
    RETURN NULL;
  END IF;

  IF v_player_count = 0 THEN
    RETURN NULL; -- nobody recorded → nothing to archive
  END IF;

  v_duration := GREATEST(0, EXTRACT(EPOCH FROM (v_finished_at - v_created_at))::int);

  -- ── 1. Archive the match ──
  INSERT INTO "game_match_history"
    ("id","gameTable","gameId","familyId","playerCount",
     "winnerUserIds","winnerNames","resultKind","finishedAt","startedAt","durationSeconds")
  VALUES
    (p_game_id, p_game_table, p_game_id, v_family_id, v_player_count,
     v_winner_ids, v_winner_names, v_result_kind, v_finished_at, v_created_at, v_duration)
  ON CONFLICT ("gameTable","gameId") DO NOTHING;

  IF NOT EXISTS (SELECT 1 FROM "game_match_history" WHERE "gameTable"=p_game_table AND "gameId"=p_game_id) THEN
    RETURN NULL; -- concurrent call won the race
  END IF;

  -- ── 2. Per-player rows + stats + badges + challenges ──
  FOR v_i IN 0 .. (v_player_count - 1) LOOP
    v_p := v_participants -> v_i;
    v_uid := v_p ->> 'userId';
    v_uname := v_p ->> 'userName';

    -- Result derivation. Ghost Painter is a party game: the correct guesser
    -- wins, everyone else (including the drawer) is recorded as 'played'.
    IF v_winner_ids @> ARRAY[v_uid] THEN
      v_res := 'win';
    ELSIF array_length(v_winner_ids, 1) IS NULL THEN
      v_res := CASE WHEN p_game_table = 'ghost_painter_rounds' THEN 'played'
                    WHEN v_player_count <= 2 THEN 'draw' ELSE 'played' END;
    ELSE
      v_res := CASE WHEN p_game_table = 'ghost_painter_rounds' THEN 'played'
                    WHEN v_player_count <= 2 THEN 'loss' ELSE 'played' END;
    END IF;

    -- Streak snapshot BEFORE this match (for streak-based challenge checks)
    SELECT COALESCE(MAX("streakCurrent"), 0) INTO v_streak_before
    FROM "game_user_stats"
    WHERE "userId" = v_uid AND "familyId" = v_family_id AND "gameTable" = '*';

    INSERT INTO "game_match_players"
      ("matchId","gameTable","gameId","familyId","userId","userName","result","finishedAt")
    VALUES
      (p_game_id, p_game_table, p_game_id, v_family_id, v_uid, v_uname, v_res, v_finished_at)
    ON CONFLICT ("matchId","userId") DO NOTHING;

    -- game_user_stats: per-game row
    INSERT INTO "game_user_stats"
      ("userId","familyId","gameTable",
       "matches","wins","losses","draws","played","points","lastPlayedAt")
    VALUES
      (v_uid, v_family_id, p_game_table,
       1,
       CASE WHEN v_res='win' THEN 1 ELSE 0 END,
       CASE WHEN v_res='loss' THEN 1 ELSE 0 END,
       CASE WHEN v_res='draw' THEN 1 ELSE 0 END,
       CASE WHEN v_res='played' THEN 1 ELSE 0 END,
       CASE WHEN v_res='win' THEN 3 WHEN v_res IN ('draw','played') THEN 1 ELSE 0 END,
       v_finished_at)
    ON CONFLICT ("userId","familyId","gameTable") DO UPDATE SET
      "matches" = "game_user_stats"."matches" + 1,
      "wins" = "game_user_stats"."wins" + EXCLUDED."wins",
      "losses" = "game_user_stats"."losses" + EXCLUDED."losses",
      "draws" = "game_user_stats"."draws" + EXCLUDED."draws",
      "played" = "game_user_stats"."played" + EXCLUDED."played",
      "points" = "game_user_stats"."points" + EXCLUDED."points",
      "lastPlayedAt" = EXCLUDED."lastPlayedAt",
      "updatedAt" = now();

    -- game_user_stats: overall ('*') row with streak maintenance
    INSERT INTO "game_user_stats"
      ("userId","familyId","gameTable",
       "matches","wins","losses","draws","played","points",
       "streakCurrent","streakBest","lastPlayedAt")
    VALUES
      (v_uid, v_family_id, '*',
       1,
       CASE WHEN v_res='win' THEN 1 ELSE 0 END,
       CASE WHEN v_res='loss' THEN 1 ELSE 0 END,
       CASE WHEN v_res='draw' THEN 1 ELSE 0 END,
       CASE WHEN v_res='played' THEN 1 ELSE 0 END,
       CASE WHEN v_res='win' THEN 3 WHEN v_res IN ('draw','played') THEN 1 ELSE 0 END,
       CASE WHEN v_res='win' THEN 1 ELSE 0 END,
       CASE WHEN v_res='win' THEN 1 ELSE 0 END,
       v_finished_at)
    ON CONFLICT ("userId","familyId","gameTable") DO UPDATE SET
      "matches" = "game_user_stats"."matches" + 1,
      "wins" = "game_user_stats"."wins" + EXCLUDED."wins",
      "losses" = "game_user_stats"."losses" + EXCLUDED."losses",
      "draws" = "game_user_stats"."draws" + EXCLUDED."draws",
      "played" = "game_user_stats"."played" + EXCLUDED."played",
      "points" = "game_user_stats"."points" + EXCLUDED."points",
      "streakCurrent" = CASE
        WHEN EXCLUDED."wins" > 0 THEN "game_user_stats"."streakCurrent" + 1
        ELSE 0 END,
      "streakBest" = CASE
        WHEN EXCLUDED."wins" > 0 THEN GREATEST("game_user_stats"."streakBest", "game_user_stats"."streakCurrent" + 1)
        ELSE "game_user_stats"."streakBest" END,
      "lastPlayedAt" = EXCLUDED."lastPlayedAt",
      "updatedAt" = now();

    -- Badges for this player
    v_badges_for_p := public.fn__evaluate_game_badges(v_uid, v_family_id);
    IF v_badges_for_p IS NOT NULL AND jsonb_array_length(v_badges_for_p) > 0 THEN
      v_new_badges := v_new_badges || jsonb_build_object(
        'userId', v_uid, 'userName', v_uname, 'badges', v_badges_for_p);
    END IF;

    -- Challenges for this player
    v_chal_for_p := public.fn__advance_challenges(v_uid, v_family_id);
    IF v_chal_for_p IS NOT NULL AND jsonb_array_length(v_chal_for_p) > 0 THEN
      v_completed := v_completed || jsonb_build_object(
        'userId', v_uid, 'userName', v_uname, 'challenges', v_chal_for_p);
    END IF;
  END LOOP;

  -- ── 3. Spectator archive (rows still exist pre-delete) ──
  FOR v_spectator IN
    SELECT "userId", "userName" FROM "game_spectators"
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id
  LOOP
    INSERT INTO "game_user_stats"
      ("userId","familyId","gameTable","spectated")
    VALUES (v_spectator."userId", v_family_id, '*', 1)
    ON CONFLICT ("userId","familyId","gameTable") DO UPDATE SET
      "spectated" = "game_user_stats"."spectated" + 1,
      "updatedAt" = now();
  END LOOP;

  -- ── 4. Family aggregate ──
  INSERT INTO "game_family_stats" ("familyId","totalMatches","firstMatchAt","lastMatchAt")
  VALUES (v_family_id, 1, v_finished_at, v_finished_at)
  ON CONFLICT ("familyId") DO UPDATE SET
    "totalMatches" = "game_family_stats"."totalMatches" + 1,
    "lastMatchAt" = v_finished_at,
    "updatedAt" = now();

  UPDATE "game_family_stats" SET "distinctGames" = (
    SELECT COUNT(DISTINCT "gameTable") FROM "game_match_history" WHERE "familyId" = v_family_id
  ) WHERE "familyId" = v_family_id;

  -- ── 5. Activity feed: match completed ──
  INSERT INTO "FamilyActivityLog"
    ("id","familyId","actorUserId","actorName","action","description","metadata")
  VALUES (
    gen_random_uuid()::text,
    v_family_id,
    COALESCE(v_winner_ids[1], (v_participants->0->>'userId')),
    COALESCE(v_winner_names[1], (v_participants->0->>'userName'), 'Family'),
    'game_match_completed',
    CASE
      WHEN array_length(v_winner_ids,1) IS NULL
        THEN format('%s · %s players · a fun family moment', (v_meta->>'name'), v_player_count::text)
      ELSE format('%s won %s · %s players', array_to_string(v_winner_names, ' & '), (v_meta->>'name'), v_player_count)
    END,
    jsonb_build_object(
      'gameTable', p_game_table,
      'gameId', p_game_id,
      'gameName', v_meta->>'name',
      'gameIcon', v_meta->>'icon',
      'winners', to_jsonb(v_winner_names),
      'playerCount', v_player_count,
      'durationSeconds', v_duration
    )
  );

  -- ── 6. Season / Family Cup standings ──
  IF v_finished_at >= date_trunc('month', now()) THEN
    PERFORM public.fn_get_current_season(NULL);
  END IF;

  SELECT "id","name" INTO v_season_id, v_season_name
  FROM "game_seasons"
  WHERE v_finished_at >= "startsAt" AND v_finished_at < "endsAt"
  LIMIT 1;

  IF v_season_id IS NOT NULL THEN
    FOR v_i IN 0 .. (v_player_count - 1) LOOP
      v_p := v_participants -> v_i;
      v_uid := v_p ->> 'userId';
      IF v_winner_ids @> ARRAY[v_uid] THEN v_res := 'win';
      ELSIF array_length(v_winner_ids,1) IS NULL THEN v_res := CASE WHEN p_game_table = 'ghost_painter_rounds' THEN 'played' WHEN v_player_count <= 2 THEN 'draw' ELSE 'played' END;
      ELSE v_res := CASE WHEN p_game_table = 'ghost_painter_rounds' THEN 'played' WHEN v_player_count <= 2 THEN 'loss' ELSE 'played' END;
      END IF;
      INSERT INTO "game_season_standings"
        ("seasonId","familyId","userId","points","wins","gamesPlayed")
      VALUES
        (v_season_id, v_family_id, v_uid,
         CASE WHEN v_res='win' THEN 3 WHEN v_res IN ('draw','played') THEN 1 ELSE 0 END,
         CASE WHEN v_res='win' THEN 1 ELSE 0 END, 1)
      ON CONFLICT ("seasonId","familyId","userId") DO UPDATE SET
        "points" = "game_season_standings"."points" + EXCLUDED."points",
        "wins" = "game_season_standings"."wins" + EXCLUDED."wins",
        "gamesPlayed" = "game_season_standings"."gamesPlayed" + 1,
        "updatedAt" = now();
    END LOOP;
  END IF;

  -- ── 7. Family milestones ──
  v_milestones := public.fn__check_family_milestones(v_family_id);

  -- ── 8. Persist the rewards payload on the archive so EVERY player's
  --       results screen can celebrate (not just the archiving caller) ──
  v_summary := jsonb_build_object(
    'matchId', p_game_id,
    'gameTable', p_game_table,
    'gameName', v_meta->>'name',
    'gameIcon', v_meta->>'icon',
    'familyId', v_family_id,
    'winners', to_jsonb(v_winner_names),
    'playerCount', v_player_count,
    'durationSeconds', v_duration,
    'newBadges', v_new_badges,
    'completedChallenges', v_completed,
    'milestones', v_milestones,
    'players', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', p."userId", 'userName', p."userName", 'result', p."result"))
      FROM "game_match_players" p WHERE p."matchId" = p_game_id
    ), '[]'::jsonb)
  );

  UPDATE "game_match_history"
    SET "rewardsJson" = v_summary
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

  RETURN v_summary;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) fn_get_match_ecosystem — Ghost Painter whitelist + stored rewards
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_get_match_ecosystem(
  p_game_table text,
  p_game_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_summary jsonb;
  v_meta jsonb;
BEGIN
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games',
    'sos_games','dotsboxes_games','nameplace_games','truthordare_games',
    'twotruths_games','redlight_rounds','chess_games','tictactoe_games',
    'checkers_games','carrom_games','ghost_painter_rounds'
  ) THEN
    RETURN NULL;
  END IF;

  -- Ensure processing has happened (no-op if already archived or not terminal)
  v_summary := public.fn__archive_family_match(p_game_table, p_game_id);

  -- If this call did the processing, return its rich summary directly
  IF v_summary IS NOT NULL THEN
    RETURN v_summary;
  END IF;

  -- Either already archived, or game row not terminal/gone.
  v_meta := public.fn__game_meta() -> p_game_table;

  SELECT jsonb_build_object(
    'matchId', h."id",
    'gameTable', h."gameTable",
    'gameName', COALESCE(v_meta->>'name', h."gameTable"),
    'gameIcon', COALESCE(v_meta->>'icon', '🎮'),
    'familyId', h."familyId",
    'winners', to_jsonb(h."winnerNames"),
    'playerCount', h."playerCount",
    'durationSeconds', h."durationSeconds",
    'archived', true,
    'newBadges', COALESCE(h."rewardsJson"->'newBadges', '[]'::jsonb),
    'completedChallenges', COALESCE(h."rewardsJson"->'completedChallenges', '[]'::jsonb),
    'milestones', COALESCE(h."rewardsJson"->'milestones', '[]'::jsonb),
    'players', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', p."userId", 'userName', p."userName", 'result', p."result"))
      FROM "game_match_players" p WHERE p."matchId" = h."id"
    ), '[]'::jsonb)
  )
  INTO v_summary
  FROM "game_match_history" h
  WHERE h."gameTable" = p_game_table AND h."gameId" = p_game_id;

  RETURN v_summary;  -- NULL when the room was cancelled (never archived)
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Ghost Painter champion badge + evaluation
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt")
VALUES
  (gen_random_uuid()::text,'ghost-painter-virtuoso','Ghost Painter Virtuoso','घोस्ट पेंटर कलाकार','Guess 5 Ghost Painter drawings correctly','👻','games','silver',5,false,now())
ON CONFLICT ("slug") DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn__evaluate_game_badges(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_overall   record;      -- overall stats row (gameTable='*')
  v_wins      int := 0;
  v_matches   int := 0;
  v_best      int := 0;
  v_spect     int := 0;
  v_given     int := 0;
  v_received  int := 0;
  v_variety   int := 0;
  v_week      int := 0;
  v_weekend   int := 0;
  v_social    int := 0;
  v_early     int := 0;
  v_late      int := 0;
  v_night_reg int := 0;
  v_night_win int := 0;
  v_cup_win   int := 0;
  v_earned    text[] := '{}';
  v_badge     record;
  v_new_badges jsonb := '[]'::jsonb;
  v_user_name text;
BEGIN
  SELECT * INTO v_overall FROM "game_user_stats"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='*';
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  v_wins := v_overall."wins"; v_matches := v_overall."matches";
  v_best := v_overall."streakBest"; v_spect := v_overall."spectated";
  v_given := v_overall."sportsmanshipGiven"; v_received := v_overall."sportsmanshipReceived";

  SELECT COUNT(DISTINCT "gameTable") INTO v_variety
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id;

  SELECT COUNT(*) INTO v_week
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id
    AND "finishedAt" >= now() - interval '7 days';

  SELECT COUNT(*) INTO v_weekend
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id
    AND EXTRACT(ISODOW FROM "finishedAt") IN (6,7);

  SELECT COUNT(*) INTO v_social
  FROM "game_match_players" gmp
  WHERE gmp."userId"=p_user_id AND gmp."familyId"=p_family_id
    AND (SELECT COUNT(*) FROM "game_match_players" o
         WHERE o."matchId"=gmp."matchId") >= 3;

  SELECT COUNT(*) INTO v_early
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id
    AND EXTRACT(HOUR FROM "finishedAt" AT TIME ZONE 'Asia/Kolkata') < 9;

  SELECT COUNT(*) INTO v_late
  FROM "game_match_players"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id
    AND EXTRACT(HOUR FROM "finishedAt" AT TIME ZONE 'Asia/Kolkata') >= 22;

  -- scheduled family game night participations
  SELECT COUNT(*) INTO v_night_reg
  FROM "game_match_players" gmp
  JOIN "scheduled_game_nights" sgn
    ON sgn."familyId" = gmp."familyId"
   AND gmp."finishedAt" BETWEEN COALESCE(sgn."startedAt", sgn."scheduledFor") AND COALESCE(sgn."startedAt", sgn."scheduledFor") + interval '4 hours'
  WHERE gmp."userId"=p_user_id AND gmp."familyId"=p_family_id;

  SELECT COUNT(*) INTO v_night_win
  FROM "game_match_players" gmp
  JOIN "scheduled_game_nights" sgn
    ON sgn."familyId" = gmp."familyId"
   AND gmp."finishedAt" BETWEEN COALESCE(sgn."startedAt", sgn."scheduledFor") AND COALESCE(sgn."startedAt", sgn."scheduledFor") + interval '4 hours'
  WHERE gmp."userId"=p_user_id AND gmp."familyId"=p_family_id AND gmp."result"='win';

  SELECT COUNT(*) INTO v_cup_win
  FROM "game_season_winners"
  WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "rank"=1;

  -- ── Build the earned set ──
  IF v_wins >= 1        THEN v_earned := v_earned || ARRAY['first-game-win']; END IF;
  IF v_wins >= 5        THEN v_earned := v_earned || ARRAY['win-5-games']; END IF;
  IF v_wins >= 25       THEN v_earned := v_earned || ARRAY['win-25-games']; END IF;
  IF v_wins >= 100      THEN v_earned := v_earned || ARRAY['win-100-games']; END IF;
  IF v_wins >= 10       THEN v_earned := v_earned || ARRAY['family-champion']; END IF;
  IF v_best >= 3        THEN v_earned := v_earned || ARRAY['win-streak-3']; END IF;
  IF v_best >= 5        THEN v_earned := v_earned || ARRAY['undefeated-streak-5']; END IF;
  IF v_week >= 5        THEN v_earned := v_earned || ARRAY['played-5-games-week']; END IF;
  IF v_weekend >= 3     THEN v_earned := v_earned || ARRAY['weekend-gamer']; END IF;
  IF v_matches >= 50    THEN v_earned := v_earned || ARRAY['play-50-games']; END IF;
  IF v_matches >= 200   THEN v_earned := v_earned || ARRAY['play-200-games']; END IF;
  IF v_variety >= 8     THEN v_earned := v_earned || ARRAY['family-explorer']; END IF;
  IF v_spect >= 5       THEN v_earned := v_earned || ARRAY['spectator-supporter']; END IF;
  IF v_social >= 10     THEN v_earned := v_earned || ARRAY['social-gamer']; END IF;
  IF v_early >= 1       THEN v_earned := v_earned || ARRAY['early-bird']; END IF;
  IF v_late >= 1        THEN v_earned := v_earned || ARRAY['night-owl']; END IF;
  IF v_given >= 10      THEN v_earned := v_earned || ARRAY['cheering-champion']; END IF;
  IF v_received >= 10   THEN v_earned := v_earned || ARRAY['gracious-player']; END IF;
  IF v_night_reg >= 4   THEN v_earned := v_earned || ARRAY['family-game-night-regular']; END IF;
  IF v_night_win >= 25  THEN v_earned := v_earned || ARRAY['family-night-champion']; END IF;
  IF v_cup_win >= 1     THEN v_earned := v_earned || ARRAY['family-cup-champion']; END IF;

  -- Per-game champion badges (5 wins in that game)
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='bingo_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['bingo-master']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='sos_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['sos-strategist']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='ludo_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['ludo-champion']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='chess_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['chess-master']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='carrom_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['carrom-king']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='checkers_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['checkers-champ']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='tictactoe_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['tictactoe-tactician']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='dotsboxes_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['dots-boxer']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='nameplace_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['nameplace-scholar']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='antakshari_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['antakshari-star']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='twotruths_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['twotruths-mastermind']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='chitmatch_games' AND "wins">=5) THEN v_earned := v_earned || ARRAY['chitmatch-collector']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='redlight_rounds' AND "wins">=5) THEN v_earned := v_earned || ARRAY['freeze-dash-sprinter']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='truthordare_games' AND "matches">=10) THEN v_earned := v_earned || ARRAY['truthordare-fearless']; END IF;
  IF EXISTS (SELECT 1 FROM "game_user_stats" WHERE "userId"=p_user_id AND "familyId"=p_family_id AND "gameTable"='ghost_painter_rounds' AND "wins">=5) THEN v_earned := v_earned || ARRAY['ghost-painter-virtuoso']; END IF;

  IF v_earned = '{}' THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(MAX("userName"), 'Family Member') INTO v_user_name
  FROM "game_match_players" WHERE "userId" = p_user_id LIMIT 1;

  -- Insert only NEW badges; build the returned array from what was inserted
  FOR v_badge IN
    SELECT b."id", b."slug", b."name", b."icon", b."tier"
    FROM "Badge" b
    WHERE b."category" = 'games' AND b."slug" = ANY(v_earned)
      AND NOT EXISTS (
        SELECT 1 FROM "UserBadge" ub
        WHERE ub."badgeId" = b."id"
          AND ub."userId" = p_user_id
          AND COALESCE(ub."familyId", p_family_id) = p_family_id)
  LOOP
    INSERT INTO "UserBadge" ("id","userId","badgeId","familyId","earnedAt")
    VALUES (gen_random_uuid()::text, p_user_id, v_badge."id", p_family_id, now())
    ON CONFLICT DO NOTHING;

    v_new_badges := v_new_badges || jsonb_build_object(
      'slug', v_badge."slug",
      'name', v_badge."name",
      'icon', v_badge."icon",
      'tier', v_badge."tier");

    INSERT INTO "FamilyActivityLog"
      ("id","familyId","actorUserId","actorName","action","description","metadata")
    VALUES (
      gen_random_uuid()::text, p_family_id, p_user_id, v_user_name,
      'game_badge_earned',
      format('%s earned the %s badge', v_user_name, v_badge."name"),
      jsonb_build_object('badgeSlug', v_badge."slug", 'badgeName', v_badge."name",
                         'badgeIcon', v_badge."icon", 'badgeTier', v_badge."tier"));
  END LOOP;

  RETURN v_new_badges;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) Completion trigger — archive the round the moment it completes
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn__ghost_painter_on_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN
      PERFORM public.fn__archive_family_match('ghost_painter_rounds', NEW."id");
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ghost painter archive failed for %: %', NEW."id", SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ghost_painter_archive ON "ghost_painter_rounds";
CREATE TRIGGER trg_ghost_painter_archive
AFTER UPDATE ON "ghost_painter_rounds"
FOR EACH ROW EXECUTE FUNCTION public.fn__ghost_painter_on_complete();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) Cleanup — archive-then-delete finished rounds; retire stale ones
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_cleanup_completed_games()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
AS $$
DECLARE
    tbl text;
    completed_tables text[] := ARRAY[
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'dotsboxes_games', 'nameplace_games', 'truthordare_games',
        'twotruths_games', 'chess_games', 'tictactoe_games',
        'checkers_games', 'carrom_games'
    ];
    finished_tables text[] := ARRAY['sos_games', 'redlight_rounds'];
    gp_round record;
BEGIN
    FOREACH tbl IN ARRAY completed_tables LOOP
        BEGIN
            EXECUTE format(
                'DELETE FROM public.game_invites
                 WHERE "gameTable" = $1
                   AND "gameId" IN (
                     SELECT "id" FROM public.%I
                     WHERE public.fn_is_completed_status("status")
                       AND "completedAt" IS NOT NULL
                       AND "completedAt" < now() - interval ''1 hour''
                   );',
                tbl
            ) USING tbl;
            EXECUTE format(
                'DELETE FROM public.%I
                 WHERE public.fn_is_completed_status("status")
                   AND "completedAt" IS NOT NULL
                   AND "completedAt" < now() - interval ''1 hour'';',
                tbl
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'fn_cleanup_completed_games: skip %: %', tbl, SQLERRM;
        END;
    END LOOP;

    FOREACH tbl IN ARRAY finished_tables LOOP
        BEGIN
            EXECUTE format(
                'DELETE FROM public.game_invites
                 WHERE "gameTable" = $1
                   AND "gameId" IN (
                     SELECT "id" FROM public.%I
                     WHERE public.fn_is_completed_status("status")
                       AND "finishedAt" IS NOT NULL
                       AND "finishedAt" < now() - interval ''1 hour''
                   );',
                tbl
            ) USING tbl;
            EXECUTE format(
                'DELETE FROM public.%I
                 WHERE public.fn_is_completed_status("status")
                   AND "finishedAt" IS NOT NULL
                   AND "finishedAt" < now() - interval ''1 hour'';',
                tbl
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'fn_cleanup_completed_games: skip %: %', tbl, SQLERRM;
        END;
    END LOOP;

    -- ── Ghost Painter rounds ──
    -- (a) Retire stale abandoned rounds (stuck in drawing/guessing for > 2h):
    --     flip to completed; the archive trigger then runs (rounds without
    --     any guesses are skipped by the archive guard).
    BEGIN
        UPDATE public.ghost_painter_rounds
           SET "status" = 'completed',
               "endsAt" = COALESCE("endsAt", now())
         WHERE "status" IN ('drawing','guessing')
           AND "startedAt" < now() - interval '2 hours';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'fn_cleanup_completed_games: gp retire failed: %', SQLERRM;
    END;

    -- (b) Delete completed rounds older than 1 hour. The completion trigger
    --     archived them already; strokes + guesses cascade via FK.
    BEGIN
        DELETE FROM public.game_invites
         WHERE "gameTable" = 'ghost_painter_rounds'
           AND "gameId" IN (
             SELECT "id" FROM public.ghost_painter_rounds
              WHERE "status" = 'completed'
                AND "endsAt" < now() - interval '1 hour'
           );
        DELETE FROM public.ghost_painter_rounds
         WHERE "status" = 'completed'
           AND "endsAt" < now() - interval '1 hour';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'fn_cleanup_completed_games: gp delete failed: %', SQLERRM;
    END;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8) Sportsmanship permissions already cover all whitelisted tables (matchId
--    is a plain text key) — no extra grants needed. Keep function grants.
-- ─────────────────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION public.fn__ghost_painter_on_complete() TO authenticated;
