-- Bingo — gameplay & synchronization repair.
--
-- Fixes (diagnosed live 2026-09-19):
--   1. bingo_games had REPLICA IDENTITY DEFAULT → realtime UPDATE payloads
--      only carried changed columns → the client parsed status=null→'waiting'
--      and the board flipped back to the waiting room on EVERY called number.
--      (bingo_cards was already FULL; games + claims now follow.)
--   2. Number calling relied on a once-per-minute cron hitting the
--      bingo-caller Edge Function while games expect one call every
--      callIntervalSeconds (3-15s). Numbers trickled at 1/12 speed.
--      → fn_bingo_tick is now driven by any live client (1s watchdog,
--        same pattern as fn_memorymatch_tick), with a */15s SQL safety
--        net for rooms whose clients all vanished mid-game.
--   3. Games where all 75 numbers get called with no claim used to linger
--      in_progress forever (zombie rooms). → auto-complete as a draw.
--   4. fn__archive_family_match had NO participants fallback for bingo
--      (chess/tod/tugofwar/memorymatch have one) and the provider never
--      recorded participants → bingo matches archived NOTHING (0 players
--      → RETURN NULL). → fallback derives participants from bingo_cards.
--   5. Claiming required a round-trip through the bingo-verify-claim Edge
--      Function. → fn_bingo_claim does verify + audit + completion in one
--      authenticated RPC (auth.uid()-based, no spoofable playerId).
--   6. startGame wrote client-clock timestamps with no server-side host /
--      min-players validation. → fn_bingo_start.
--   7. bingo_cards had no DELETE policy → leaveGame's own-row delete was
--      silently rejected by RLS. → bingo_cards_delete policy.

-- ═══════════════════════════════════════════════════════════════════
-- 1. Realtime completeness
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE "bingo_games"  REPLICA IDENTITY FULL;
ALTER TABLE "bingo_claims" REPLICA IDENTITY FULL;

-- ═══════════════════════════════════════════════════════════════════
-- 2. RLS — players may delete their own card (leaving a game)
-- ═══════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "bingo_cards_delete" ON "bingo_cards";
CREATE POLICY "bingo_cards_delete" ON "bingo_cards"
    FOR DELETE USING (
        "playerId" = auth.uid()::text
        OR EXISTS (SELECT 1 FROM "bingo_games" g
                   WHERE g.id = "bingo_cards"."gameId"
                   AND g."hostUserId" = auth.uid()::text)
    );

-- ═══════════════════════════════════════════════════════════════════
-- 3. fn_bingo_start — host-only, ≥2 cards, server timestamps
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_bingo_start(p_game_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    g record;
    v_cards int;
BEGIN
    SELECT * INTO g FROM "bingo_games" WHERE "id" = p_game_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
    END IF;
    IF g."hostUserId" <> auth.uid()::text THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_host');
    END IF;
    IF g.status <> 'waiting' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'already_started');
    END IF;

    SELECT COUNT(*) INTO v_cards FROM "bingo_cards" WHERE "gameId" = p_game_id;
    IF v_cards < 2 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'need_two_players');
    END IF;

    -- lastCallAt stays NULL → the first number drops the moment any
    -- client ticks (no dead air after the start whistle).
    UPDATE "bingo_games"
       SET "status" = 'in_progress',
           "startedAt" = now(),
           "lastActivityAt" = now()
     WHERE "id" = p_game_id;

    RETURN jsonb_build_object('ok', true);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 4. fn_bingo_tick — client-driven, interval-gated number calling.
--    Any connected player/spectator may call it every second; the server
--    serializes (FOR UPDATE) and only advances when the interval elapsed.
--    Also: participant heartbeat (reaper protection) + draw auto-complete
--    when all 75 numbers are called with no valid claim.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_bingo_tick(p_game_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    g record;
    v_available int[];
    v_next int;
    v_interval int;
BEGIN
    SELECT * INTO g FROM "bingo_games" WHERE "id" = p_game_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
    END IF;

    -- Heartbeat: keep the caller's participant row fresh so the shared
    -- reaper never kills a live room (pure refresh — no insert).
    UPDATE "game_participants"
       SET "lastSeenAt" = now(), "connectionState" = 'online'
     WHERE "gameTable" = 'bingo_games' AND "gameId" = p_game_id
       AND "userId" = auth.uid()::text;

    IF g.status <> 'in_progress' THEN
        RETURN jsonb_build_object('ok', true, 'status', g.status,
                                  'numbersCalled', g."numbersCalled");
    END IF;

    -- Keep the room's activity stamp fresh.
    UPDATE "bingo_games" SET "lastActivityAt" = now() WHERE "id" = p_game_id;

    -- Interval gate (server clock — clients can agree on when the next
    -- number is due via lastCallAt + callIntervalSeconds).
    v_interval := COALESCE(g."callIntervalSeconds", 5);
    IF g."lastCallAt" IS NOT NULL
       AND now() - g."lastCallAt" < make_interval(secs => v_interval) THEN
        RETURN jsonb_build_object(
            'ok', true, 'status', 'in_progress',
            'called', NULL,
            'numbersCalled', g."numbersCalled",
            'nextDueMs',
            GREATEST(0, (EXTRACT(EPOCH FROM (g."lastCallAt" + make_interval(secs => v_interval) - now())) * 1000)::int));
    END IF;

    -- All numbers called and nobody claimed → complete as a draw.
    IF COALESCE(array_length(g."numbersCalled", 1), 0) >= 75 THEN
        UPDATE "bingo_games"
           SET "status" = 'completed',
               "completedAt" = now(),
               "lastActivityAt" = now()
         WHERE "id" = p_game_id;
        RETURN jsonb_build_object('ok', true, 'status', 'completed',
                                  'draw', true, 'numbersCalled', g."numbersCalled");
    END IF;

    -- Serialize concurrent ticks, then re-read under lock.
    SELECT * INTO g FROM "bingo_games" WHERE "id" = p_game_id FOR UPDATE;
    v_interval := COALESCE(g."callIntervalSeconds", 5);
    IF g."lastCallAt" IS NOT NULL
       AND now() - g."lastCallAt" < make_interval(secs => v_interval) THEN
        RETURN jsonb_build_object(
            'ok', true, 'status', 'in_progress',
            'called', NULL,
            'numbersCalled', g."numbersCalled",
            'nextDueMs',
            GREATEST(0, (EXTRACT(EPOCH FROM (g."lastCallAt" + make_interval(secs => v_interval) - now())) * 1000)::int));
    END IF;

    -- Pick a random unclaimed number.
    SELECT array_agg(n) INTO v_available
    FROM generate_series(1, 75) AS n
    WHERE NOT (n = ANY(g."numbersCalled"));

    IF v_available IS NULL THEN
        UPDATE "bingo_games"
           SET "status" = 'completed', "completedAt" = now(), "lastActivityAt" = now()
         WHERE "id" = p_game_id;
        RETURN jsonb_build_object('ok', true, 'status', 'completed',
                                  'draw', true, 'numbersCalled', g."numbersCalled");
    END IF;

    SELECT v_available[floor(random() * array_length(v_available, 1)) + 1]
      INTO v_next;

    UPDATE "bingo_games"
       SET "numbersCalled" = array_append("numbersCalled", v_next),
           "lastCallAt" = now(),
           "lastActivityAt" = now()
     WHERE "id" = p_game_id;

    RETURN jsonb_build_object(
        'ok', true, 'status', 'in_progress',
        'called', v_next,
        'numbersCalled', g."numbersCalled" || v_next,
        'nextDueMs', v_interval * 1000);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 5. fn_bingo_call_all_due — cron safety net. Ticks every in-progress
--    game at most once per interval. Covers rooms whose clients all
--    closed (numbers keep advancing → draw auto-complete → the hourly
--    cleanup archives + deletes the finished room).
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_bingo_call_all_due()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    r record;
    v_called int := 0;
BEGIN
    FOR r IN SELECT "id" FROM "bingo_games" WHERE "status" = 'in_progress' FOR UPDATE SKIP LOCKED
    LOOP
        IF (SELECT public.fn_bingo_tick(r."id")) ->> 'called' IS NOT NULL THEN
            v_called := v_called + 1;
        END IF;
    END LOOP;
    RETURN v_called;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 6. Cron — replace the once-per-minute HTTP hop with a */15s SQL tick.
--    (The bingo-caller Edge Function stays deployed but is no longer the
--    driver; clients advance numbers in real time via fn_bingo_tick.)
-- ═══════════════════════════════════════════════════════════════════

SELECT cron.unschedule('bingo-caller-every-minute')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bingo-caller-every-minute');

SELECT cron.schedule(
    'bingo-caller-safety-net',
    '15 seconds',
    $$SELECT public.fn_bingo_call_all_due();$$
);

-- ═══════════════════════════════════════════════════════════════════
-- 7. fn_bingo_claim — verify + audit + complete in one RPC.
--    Player identity comes from auth.uid() — never from the payload.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_bingo_claim(p_game_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_player text := auth.uid()::text;
    v_game record;
    v_card record;
    v_verify jsonb;
    v_name text;
BEGIN
    SELECT * INTO v_game FROM "bingo_games" WHERE "id" = p_game_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', false, 'reason', 'Game not found');
    END IF;
    IF v_game.status <> 'in_progress' THEN
        RETURN jsonb_build_object('valid', false, 'reason', 'Game is not in progress');
    END IF;
    IF v_game."winnerPlayerId" IS NOT NULL THEN
        RETURN jsonb_build_object('valid', false, 'reason', 'A winner has already been declared');
    END IF;

    SELECT * INTO v_card FROM "bingo_cards"
     WHERE "gameId" = p_game_id AND "playerId" = v_player;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', false, 'reason', 'You have no card in this game');
    END IF;
    v_name := COALESCE(v_card."playerName", 'Player');

    -- Server-side pattern verification (marked numbers vs called).
    v_verify := public.bingo_verify_claim(p_game_id, v_player);

    -- Audit trail — one row per claim, valid or not.
    INSERT INTO "bingo_claims"
        ("gameId", "playerId", "playerName", "isValid", "invalidReason", "verifiedAt")
    VALUES
        (p_game_id, v_player, v_name,
         (v_verify ->> 'valid')::boolean,
         CASE WHEN (v_verify ->> 'valid')::boolean THEN NULL
              ELSE v_verify ->> 'reason' END,
         now());

    IF (v_verify ->> 'valid')::boolean THEN
        UPDATE "bingo_games"
           SET "status" = 'completed',
               "winnerPlayerId" = v_player,
               "winnerPlayerName" = v_name,
               "completedAt" = now(),
               "lastActivityAt" = now()
         WHERE "id" = p_game_id;
        UPDATE "bingo_cards"
           SET "hasClaimed" = true
         WHERE "gameId" = p_game_id AND "playerId" = v_player;
        RETURN jsonb_build_object('valid', true,
                                  'winnerPlayerId', v_player,
                                  'winnerPlayerName', v_name);
    ELSE
        RETURN jsonb_build_object('valid', false,
                                  'reason', COALESCE(v_verify ->> 'reason', 'Claim is not valid'));
    END IF;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 8. Grants
-- ═══════════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION public.fn_bingo_start(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_bingo_tick(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_bingo_claim(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- 9. fn__archive_family_match — bingo participants fallback (patched
--    function body is appended by the builder script; see
--    scripts/bingo/build_migration.py).
-- ═══════════════════════════════════════════════════════════════════

-- ── patched fn__archive_family_match (bingo fallback) ──

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

  -- ── Bingo: no dedicated player table — participants are the players
  --    holding cards (bingo_cards). The provider records joins via
  --    fn_record_room_join, but re-joining clients or legacy rooms can
  --    miss it, so derive the roster from the cards themselves.
  IF v_player_count = 0 AND p_game_table = 'bingo_games' THEN
    SELECT jsonb_agg(jsonb_build_object(
             'userId', bc."playerId",
             'userName', COALESCE(bc."playerName", 'Family Member'),
             'role', CASE WHEN bc."playerId" = (SELECT g."hostUserId" FROM public.bingo_games g WHERE g."id" = p_game_id) THEN 'host' ELSE 'player' END))
    INTO v_participants
    FROM public.bingo_cards bc
    WHERE bc."gameId" = p_game_id;
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
$function$

