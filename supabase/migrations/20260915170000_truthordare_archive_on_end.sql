-- =============================================================================
-- Truth or Dare matches now archive when the host closes the table
-- =============================================================================
-- BUG: Truth or Dare is an open-ended party game — it has no natural finish
-- (rounds continue until the host closes the table). When that happened,
-- fn_end_game called fn__archive_family_match while the row was still
-- 'in_progress' (non-terminal, no winners) → the archive processor correctly
-- skipped it → fn__hard_delete_room then deleted the row. Result: ZERO Truth
-- or Dare matches were ever archived — no history, stats, badges
-- ('truthordare-fearless' was unreachable), challenges, milestones,
-- activity entries or Cup points.
--
-- FIX:
--   1. fn_end_game marks an in_progress Truth or Dare game as completed
--      BEFORE archiving, so closing the table becomes the natural match end
--      (result: played, everyone participates — same party semantics as
--      Ghost Painter).
--   2. fn__archive_family_match: 2-player Truth or Dare rounds record
--      'played' instead of 'draw' (party game — nobody "draws").
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_end_game(
    p_game_table text,
    p_game_id text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games'
    ) THEN
        RAISE EXCEPTION 'Unknown game table: %', p_game_table;
    END IF;

    -- ── Truth or Dare is an open-ended party game: the match ends when the
    --    host closes the table. Mark it completed FIRST so the archive
    --    records the family moment (participation for everyone) instead of
    --    discarding an "in-progress" row that the hard delete then erases.
    IF p_game_table = 'truthordare_games' THEN
        UPDATE public.truthordare_games
           SET "status" = 'completed',
               "completedAt" = now(),
               "lastActivityAt" = now()
         WHERE "id" = p_game_id
           AND "status" = 'in_progress';
    END IF;

    -- ── Family Gaming Ecosystem: archive completed matches BEFORE the
    --    hard delete (idempotent no-op for cancelled/abandoned rooms).
    BEGIN
        PERFORM public.fn__archive_family_match(p_game_table, p_game_id);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'ecosystem archive failed for %/%: %', p_game_table, p_game_id, SQLERRM;
    END;

    PERFORM public.fn__hard_delete_room(p_game_table, p_game_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_end_game(text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Party-game result semantics for Truth or Dare (mirrors Ghost Painter):
-- with no winners, every player records 'played' (2-player games would
-- otherwise be recorded as 'draw').
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

    -- Result derivation. Party games (Ghost Painter, Truth or Dare): the
    -- correct guesser wins (GP) or nobody wins (ToD); everyone else —
    -- including the drawer/host — is recorded as 'played', never 'loss'.
    IF v_winner_ids @> ARRAY[v_uid] THEN
      v_res := 'win';
    ELSIF array_length(v_winner_ids, 1) IS NULL THEN
      v_res := CASE WHEN p_game_table IN ('ghost_painter_rounds','truthordare_games') THEN 'played'
                    WHEN v_player_count <= 2 THEN 'draw' ELSE 'played' END;
    ELSE
      v_res := CASE WHEN p_game_table IN ('ghost_painter_rounds','truthordare_games') THEN 'played'
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
      ELSIF array_length(v_winner_ids,1) IS NULL THEN v_res := CASE WHEN p_game_table IN ('ghost_painter_rounds','truthordare_games') THEN 'played' WHEN v_player_count <= 2 THEN 'draw' ELSE 'played' END;
      ELSE v_res := CASE WHEN p_game_table IN ('ghost_painter_rounds','truthordare_games') THEN 'played' WHEN v_player_count <= 2 THEN 'loss' ELSE 'played' END;
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
