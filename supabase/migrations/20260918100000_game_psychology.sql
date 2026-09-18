-- Migration: 20260918100000_game_psychology.sql
-- Family Gaming Ecosystem — Psychology Layer.
--
-- Applies evidence-based engagement principles across ALL 17 games:
--   • Competence (Self-Determination Theory): per-game personal bests —
--     score / accuracy / fastest win — recorded server-side when a match
--     archives, so every results screen can celebrate improvement, not
--     just victory (growth-mindset framing).
--   • Goal-Setting Theory (ritual, not outcome): family play streak —
--     consecutive days the family played TOGETHER. Rewards showing up,
--     never punishes losing (loss aversion avoided by design).
--   • Benign social comparison: per-player scores persisted on
--     game_match_players so results screens can award superlatives
--     ("top score of the match") to non-winners too.
--
-- Server-authoritative throughout: all bests are computed from game
-- tables by SECURITY DEFINER functions during archiving — clients never
-- submit scores.
--
-- Contents:
--   1. game_match_players += score / accuracyPct
--   2. game_personal_bests table (+ RLS: family select only)
--   3. fn__game_score_rows      — per-game score extraction (internal)
--   4. fn__record_match_highlights — bests + weekly participation (internal)
--   5. fn__archive_family_match v3 — calls (4), merges payload
--   6. fn_get_match_ecosystem v3  — carries highlights + scores
--   7. fn_get_family_play_streak  — hub streak banner data (public)

-- ═══════════════════════════════════════════════════════════════════
-- 1. game_match_players: per-player score columns
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE "game_match_players"
  ADD COLUMN IF NOT EXISTS "score" int,
  ADD COLUMN IF NOT EXISTS "accuracyPct" int;

-- ═══════════════════════════════════════════════════════════════════
-- 2. game_personal_bests
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "game_personal_bests" (
  "id"         text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId"     text NOT NULL,
  "familyId"   text NOT NULL,
  "gameTable"  text NOT NULL,
  "metric"     text NOT NULL,          -- score | accuracy_pct | fastest_win
  "value"      numeric NOT NULL,       -- higher better, except fastest_win (seconds, lower better)
  "matchId"    text,
  "achievedAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt"  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_game_personal_bests
  ON "game_personal_bests" ("userId", "familyId", "gameTable", "metric");

CREATE INDEX IF NOT EXISTS idx_gpb_family_game
  ON "game_personal_bests" ("familyId", "gameTable");

ALTER TABLE "game_personal_bests" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "game_personal_bests_select_family" ON "game_personal_bests";
CREATE POLICY "game_personal_bests_select_family" ON "game_personal_bests"
  FOR SELECT TO authenticated USING (fn_user_is_family_member("familyId"));
-- Writes happen exclusively inside SECURITY DEFINER archive functions.

-- ═══════════════════════════════════════════════════════════════════
-- 3. fn__game_score_rows — per-game score extraction (internal)
--    Returns [{userId, userName, score, accuracyPct}]. Tables without a
--    meaningful per-player numeric score return '[]' (their winners can
--    still earn fastest_win bests).
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn__game_score_rows(
  p_game_table text,
  p_game_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_rows jsonb := '[]'::jsonb;
BEGIN
  IF p_game_table = 'sos_games' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'userId', p."userId", 'userName', p."userName", 'score', p.score)), '[]'::jsonb)
      INTO v_rows
      FROM "sos_players" p WHERE p."gameId" = p_game_id;

  ELSIF p_game_table = 'dotsboxes_games' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'userId', p."userId", 'userName', p."userName", 'score', p."boxesCaptured")), '[]'::jsonb)
      INTO v_rows
      FROM "dotsboxes_players" p WHERE p."gameId" = p_game_id;

  ELSIF p_game_table = 'nameplace_games' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'userId', p."userId", 'userName', p."userName", 'score', p."totalScore")), '[]'::jsonb)
      INTO v_rows
      FROM "nameplace_players" p WHERE p."gameId" = p_game_id;

  ELSIF p_game_table = 'tugofwar_games' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'userId', p."userId", 'userName', p."userName", 'score', p."pullCount")), '[]'::jsonb)
      INTO v_rows
      FROM "tugofwar_players" p WHERE p."gameId" = p_game_id;

  ELSIF p_game_table = 'ludo_games' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'userId', p."userId", 'userName', p."userName", 'score', p."tokensFinished")), '[]'::jsonb)
      INTO v_rows
      FROM "ludo_players" p WHERE p."gameId" = p_game_id;

  ELSIF p_game_table = 'redlight_rounds' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'userId', r."userId", 'userName', r."userName",
             'score', ROUND(r."finalProgress")::int)), '[]'::jsonb)
      INTO v_rows
      FROM "redlight_results" r WHERE r."roundId" = p_game_id;

  ELSIF p_game_table = 'memorymatch_games' THEN
    SELECT COALESCE((SELECT m."placements" FROM "memorymatch_games" m WHERE m."id" = p_game_id), '[]'::jsonb)
      INTO v_rows;
    -- normalize: pairs → score, accuracy → accuracyPct
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'userId', x->>'userId', 'userName', COALESCE(x->>'userName','Player'),
             'score', COALESCE(x->>'pairs','0')::int,
             'accuracyPct', LEAST(100, ROUND(COALESCE(x->>'accuracy','0')::numeric))::int)), '[]'::jsonb)
      INTO v_rows
      FROM jsonb_array_elements(COALESCE(v_rows, '[]'::jsonb)) AS x;

  ELSIF p_game_table = 'twotruths_games' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'userId', t."userId", 'userName', t."userName", 'score', t.correct)), '[]'::jsonb)
      INTO v_rows
      FROM (
        SELECT g."guesserId" AS "userId", MAX(g."guesserName") AS "userName",
               COUNT(*)::int AS correct
        FROM "twotruths_guesses" g
        WHERE g."gameId" = p_game_id AND g."isCorrect"
        GROUP BY g."guesserId"
      ) t;

  ELSIF p_game_table = 'ghost_painter_rounds' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'userId', t."userId", 'userName', t."userName", 'score', t.correct)), '[]'::jsonb)
      INTO v_rows
      FROM (
        SELECT g."userId", MAX(g."userName") AS "userName", COUNT(*)::int AS correct
        FROM "ghost_painter_guesses" g
        WHERE g."roundId" = p_game_id AND g."isCorrect"
        GROUP BY g."userId"
      ) t;
  END IF;

  RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 4. fn__record_match_highlights — scores onto player rows, personal
--    bests upserts, weekly participation counts (internal)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn__record_match_highlights(
  p_game_table text,
  p_game_id text,
  p_family_id text,
  p_duration int,
  p_winner_ids text[]
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_rows jsonb;
  v_r jsonb;
  v_uid text;
  v_uname text;
  v_score int;
  v_acc int;
  v_pbs jsonb := '[]'::jsonb;
  v_prev numeric;
  v_first boolean;
  v_participation jsonb := '{}'::jsonb;
  v_w text;
BEGIN
  v_rows := public.fn__game_score_rows(p_game_table, p_game_id);

  -- ── Persist per-player scores onto the archived rows ──
  FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(v_rows,'[]'::jsonb)) LOOP
    v_uid := v_r ->> 'userId';
    v_score := NULLIF(v_r ->> 'score','')::int;
    v_acc := NULLIF(v_r ->> 'accuracyPct','')::int;
    UPDATE "game_match_players"
       SET "score" = COALESCE(v_score, "score"),
           "accuracyPct" = COALESCE(v_acc, "accuracyPct")
     WHERE "matchId" = p_game_id AND "userId" = v_uid;
  END LOOP;

  -- ── Weekly participation (this match included — counts post-archive) ──
  SELECT COALESCE(jsonb_object_agg("userId", cnt), '{}'::jsonb)
    INTO v_participation
    FROM (
      SELECT "userId", COUNT(*)::int AS cnt
      FROM "game_match_players"
      WHERE "familyId" = p_family_id
        AND "finishedAt" > now() - interval '7 days'
      GROUP BY "userId"
    ) t;

  -- ── Personal bests: score / accuracy (higher is better) ──
  FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(v_rows,'[]'::jsonb)) LOOP
    v_uid := v_r ->> 'userId';
    v_uname := COALESCE(v_r ->> 'userName', 'Player');

    v_score := NULLIF(v_r ->> 'score','')::int;
    IF v_score IS NOT NULL AND v_score > 0 THEN
      SELECT "value" INTO v_prev FROM "game_personal_bests"
      WHERE "userId"=v_uid AND "familyId"=p_family_id
        AND "gameTable"=p_game_table AND "metric"='score';
      v_first := v_prev IS NULL;
      IF v_first OR v_score > v_prev THEN
        INSERT INTO "game_personal_bests"
          ("userId","familyId","gameTable","metric","value","matchId")
        VALUES (v_uid, p_family_id, p_game_table, 'score', v_score, p_game_id)
        ON CONFLICT ("userId","familyId","gameTable","metric") DO UPDATE SET
          "value" = EXCLUDED."value", "matchId" = EXCLUDED."matchId",
          "achievedAt" = now(), "updatedAt" = now();
        v_pbs := v_pbs || jsonb_build_object(
          'userId', v_uid, 'userName', v_uname, 'metric', 'score',
          'value', v_score, 'previousValue', v_prev, 'firstEver', v_first);
      END IF;
    END IF;

    v_acc := NULLIF(v_r ->> 'accuracyPct','')::int;
    IF v_acc IS NOT NULL AND v_acc > 0 THEN
      SELECT "value" INTO v_prev FROM "game_personal_bests"
      WHERE "userId"=v_uid AND "familyId"=p_family_id
        AND "gameTable"=p_game_table AND "metric"='accuracy_pct';
      v_first := v_prev IS NULL;
      IF v_first OR v_acc > v_prev THEN
        INSERT INTO "game_personal_bests"
          ("userId","familyId","gameTable","metric","value","matchId")
        VALUES (v_uid, p_family_id, p_game_table, 'accuracy_pct', v_acc, p_game_id)
        ON CONFLICT ("userId","familyId","gameTable","metric") DO UPDATE SET
          "value" = EXCLUDED."value", "matchId" = EXCLUDED."matchId",
          "achievedAt" = now(), "updatedAt" = now();
        v_pbs := v_pbs || jsonb_build_object(
          'userId', v_uid, 'userName', v_uname, 'metric', 'accuracy_pct',
          'value', v_acc, 'previousValue', v_prev, 'firstEver', v_first);
      END IF;
    END IF;
  END LOOP;

  -- ── Personal best: fastest win (lower is better; >= 60s so walkovers
  --    and instant resignations never pollute the record) ──
  IF p_duration >= 60 AND array_length(p_winner_ids, 1) IS NOT NULL THEN
    FOREACH v_w IN ARRAY p_winner_ids LOOP
      IF v_w IS NULL OR v_w = '' THEN CONTINUE; END IF;
      SELECT "value" INTO v_prev FROM "game_personal_bests"
      WHERE "userId"=v_w AND "familyId"=p_family_id
        AND "gameTable"=p_game_table AND "metric"='fastest_win';
      v_first := v_prev IS NULL;
      IF v_first OR p_duration < v_prev THEN
        INSERT INTO "game_personal_bests"
          ("userId","familyId","gameTable","metric","value","matchId")
        VALUES (v_w, p_family_id, p_game_table, 'fastest_win', p_duration, p_game_id)
        ON CONFLICT ("userId","familyId","gameTable","metric") DO UPDATE SET
          "value" = EXCLUDED."value", "matchId" = EXCLUDED."matchId",
          "achievedAt" = now(), "updatedAt" = now();
        SELECT COALESCE(MAX("userName"), 'Player') INTO v_uname
        FROM "game_match_players" WHERE "matchId"=p_game_id AND "userId"=v_w;
        v_pbs := v_pbs || jsonb_build_object(
          'userId', v_w, 'userName', v_uname, 'metric', 'fastest_win',
          'value', p_duration, 'previousValue', v_prev, 'firstEver', v_first);
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'personalBests', v_pbs,
    'participation', v_participation);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 5. fn__archive_family_match v3 — full latest body (memorymatch-era)
--    + psychology hook. Only change vs v2: highlight recording + payload.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn__archive_family_match(p_game_table text, p_game_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_highlights     jsonb;
BEGIN
  -- Whitelist game tables (security: p_game_table is used in dynamic SQL)
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games',
    'sos_games','dotsboxes_games','nameplace_games','truthordare_games',
    'twotruths_games','redlight_rounds','chess_games','tictactoe_games',
    'checkers_games','carrom_games','ghost_painter_rounds','tugofwar_games',
    'memorymatch_games'
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
                          'nameplace_games','twotruths_games','tugofwar_games',
                          'memorymatch_games') THEN
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

  -- ── Truth or Dare: its lobby creates rooms via the game's own provider
  --    (todProvider.createGame → truthordare_players only), NOT via the
  --    RoomController — so game_participants stays empty. Derive participants
  --    from truthordare_players so these matches archive too.
  IF v_player_count = 0 AND p_game_table = 'truthordare_games' THEN
    SELECT jsonb_agg(jsonb_build_object(
             'userId', tp."userId",
             'userName', COALESCE(tp."userName", 'Family Member'),
             'role', CASE WHEN tp."userId" = (SELECT g."hostUserId" FROM public.truthordare_games g WHERE g."id" = p_game_id) THEN 'host' ELSE 'player' END))
    INTO v_participants
    FROM public.truthordare_players tp
    WHERE tp."gameId" = p_game_id;
    v_player_count := jsonb_array_length(COALESCE(v_participants, '[]'::jsonb));
  END IF;
  IF v_player_count = 0 AND p_game_table = 'tugofwar_games' THEN
    SELECT jsonb_agg(jsonb_build_object(
             'userId', tp."userId",
             'userName', COALESCE(tp."userName", 'Family Member'),
             'role', CASE WHEN tp."userId" = (SELECT g."hostUserId" FROM public.tugofwar_games g WHERE g."id" = p_game_id) THEN 'host' ELSE 'player' END))
    INTO v_participants
    FROM public.tugofwar_players tp
    WHERE tp."gameId" = p_game_id;
    v_player_count := jsonb_array_length(COALESCE(v_participants, '[]'::jsonb));
  END IF;
  IF v_player_count = 0 AND p_game_table = 'memorymatch_games' THEN
    SELECT jsonb_agg(jsonb_build_object(
             'userId', tp."userId",
             'userName', COALESCE(tp."userName", 'Family Member'),
             'role', CASE WHEN tp."userId" = (SELECT g."hostUserId" FROM public.memorymatch_games g WHERE g."id" = p_game_id) THEN 'host' ELSE 'player' END))
    INTO v_participants
    FROM public.memorymatch_players tp
    WHERE tp."gameId" = p_game_id;
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
      v_res := CASE WHEN p_game_table IN ('tugofwar_games','memorymatch_games') THEN 'draw'
                    WHEN p_game_table IN ('ghost_painter_rounds','truthordare_games') THEN 'played'
                    WHEN v_player_count <= 2 THEN 'draw' ELSE 'played' END;
    ELSE
      v_res := CASE WHEN p_game_table IN ('tugofwar_games','memorymatch_games') THEN 'loss'
                    WHEN p_game_table IN ('ghost_painter_rounds','truthordare_games') THEN 'played'
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

  -- ── 3.5 Psychology layer: per-game scores + personal bests + weekly
  --       participation (SECURITY DEFINER, server-computed) ──
  v_highlights := public.fn__record_match_highlights(
    p_game_table, p_game_id, v_family_id, v_duration, v_winner_ids);

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
      ELSIF array_length(v_winner_ids,1) IS NULL THEN v_res := CASE WHEN p_game_table IN ('tugofwar_games','memorymatch_games') THEN 'draw' WHEN p_game_table IN ('ghost_painter_rounds','truthordare_games') THEN 'played' WHEN v_player_count <= 2 THEN 'draw' ELSE 'played' END;
      ELSE v_res := CASE WHEN p_game_table IN ('tugofwar_games','memorymatch_games') THEN 'loss' WHEN p_game_table IN ('ghost_painter_rounds','truthordare_games') THEN 'played' WHEN v_player_count <= 2 THEN 'loss' ELSE 'played' END;
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
    'personalBests', COALESCE(v_highlights->'personalBests', '[]'::jsonb),
    'participation', COALESCE(v_highlights->'participation', '{}'::jsonb),
    'players', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', p."userId", 'userName', p."userName", 'result', p."result",
        'score', p."score", 'accuracyPct', p."accuracyPct"))
      FROM "game_match_players" p WHERE p."matchId" = p_game_id
    ), '[]'::jsonb)
  );

  UPDATE "game_match_history"
    SET "rewardsJson" = v_summary
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

  IF p_game_table = 'memorymatch_games' THEN
    UPDATE "game_match_history" h
       SET "rewardsJson" = h."rewardsJson" || jsonb_build_object(
             'placements', COALESCE((SELECT m."placements" FROM public.memorymatch_games m WHERE m."id" = p_game_id), '[]'::jsonb),
             'cardPack', (SELECT m."cardPack" FROM public.memorymatch_games m WHERE m."id" = p_game_id))
     WHERE h."gameTable" = 'memorymatch_games' AND h."gameId" = p_game_id;
  END IF;

  RETURN v_summary;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 6. fn_get_match_ecosystem v3 — carries highlights + player scores
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_get_match_ecosystem(p_game_table text, p_game_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_summary jsonb;
  v_meta jsonb;
BEGIN
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games',
    'sos_games','dotsboxes_games','nameplace_games','truthordare_games',
    'twotruths_games','redlight_rounds','chess_games','tictactoe_games',
    'checkers_games','carrom_games','ghost_painter_rounds','tugofwar_games',
    'memorymatch_games'
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
    'personalBests', COALESCE(h."rewardsJson"->'personalBests', '[]'::jsonb),
    'participation', COALESCE(h."rewardsJson"->'participation', '{}'::jsonb),
    'players', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', p."userId", 'userName', p."userName", 'result', p."result",
        'score', p."score", 'accuracyPct', p."accuracyPct"))
      FROM "game_match_players" p WHERE p."matchId" = h."id"
    ), '[]'::jsonb)
  )
  INTO v_summary
  FROM "game_match_history" h
  WHERE h."gameTable" = p_game_table AND h."gameId" = p_game_id;

  RETURN v_summary;  -- NULL when the room was cancelled (never archived)
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 7. fn_get_family_play_streak — "family game night" ritual data.
--    Streak = consecutive days with ≥1 archived family match (IST day
--    boundary — matches the product's primary audience). A gap of today
--    is tolerated: the streak is alive until the day fully passes.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_get_family_play_streak(
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_dates date[];
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_cursor date;
  v_prev date;
  v_current int := 0;
  v_best int := 0;
  v_run int := 0;
  v_matches_week int;
  v_players_week int;
  v_last timestamptz;
BEGIN
  SELECT ARRAY(
    SELECT DISTINCT (h."finishedAt" AT TIME ZONE 'Asia/Kolkata')::date AS d
    FROM "game_match_history" h
    WHERE h."familyId" = p_family_id
    ORDER BY d
  ) INTO v_dates;

  -- Best streak across all history
  FOREACH v_cursor IN ARRAY v_dates LOOP
    IF v_prev IS NULL OR v_cursor = v_prev + 1 THEN
      v_run := v_run + 1;
    ELSE
      v_run := 1;
    END IF;
    v_best := GREATEST(v_best, v_run);
    v_prev := v_cursor;
  END LOOP;

  -- Current streak counts back from today; if nothing today yet, from
  -- yesterday (the night is still young — "tonight keeps it alive").
  v_cursor := CASE WHEN v_dates @> ARRAY[v_today] THEN v_today ELSE v_today - 1 END;
  WHILE v_dates @> ARRAY[v_cursor] LOOP
    v_current := v_current + 1;
    v_cursor := v_cursor - 1;
  END LOOP;

  SELECT COUNT(*)::int INTO v_matches_week
  FROM "game_match_history"
  WHERE "familyId" = p_family_id AND "finishedAt" > now() - interval '7 days';

  SELECT COUNT(DISTINCT "userId")::int INTO v_players_week
  FROM "game_match_players"
  WHERE "familyId" = p_family_id AND "finishedAt" > now() - interval '7 days';

  SELECT MAX("finishedAt") INTO v_last
  FROM "game_match_history" WHERE "familyId" = p_family_id;

  RETURN jsonb_build_object(
    'currentStreakDays', v_current,
    'bestStreakDays', v_best,
    'matchesThisWeek', v_matches_week,
    'playersThisWeek', v_players_week,
    'playedToday', v_dates @> ARRAY[v_today],
    'lastPlayedAt', v_last);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_family_play_streak(text) TO authenticated;
