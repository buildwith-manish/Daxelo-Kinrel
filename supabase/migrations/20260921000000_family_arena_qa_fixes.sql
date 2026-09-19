-- ═══════════════════════════════════════════════════════════════════════
-- Family Arena QA Critical Fixes — 2026-09-21
-- ═══════════════════════════════════════════════════════════════════════
-- Comprehensive fix migration from the full E2E QA review of the Family
-- Arena. Fixes are grouped:
--
--   PART 1  Ecosystem whitelist extensions (12 newer games)
--           - fn_touch_game_activity (+3 dropped by the word_forge
--             migration's stale snapshot: code_clues, night_falls,
--             sketch_telephone)
--           - fn__game_meta (+3 same)
--           - fn_set_player_ready (+11 player tables / +12 game tables)
--           - fn__archive_family_match (+12 game tables → stats, badges,
--             Family Cup points, match history and activity finally
--             update for the newer games)
--           - fn_end_game / fn__hard_delete_room / fn_close_expired_rooms
--             / fn_get_match_ecosystem (+12 game tables → zombie rooms
--             can finally be cleaned up)
--
--   PART 2  Mind Match — jsonb `?` operator never matches numeric array
--           elements → every round awarded 0 points and every match ended
--           0-0 with no winner. Fixed with @> containment.
--
--   PART 3  Freeze Auction — v_coins / v_shield never initialized in the
--           revealing branch → jsonb_set(..., NULL) nulled the entire
--           boardState on every reveal. Fixed by reading the winner's
--           current coins/shield from the players JSON first, plus the
--           missing steal/freeze/multiplier effect application.
--
--   PART 4  Color Trap — the phase machine had no driver for
--           arenaShown → colorAnnounced → countdown (game stuck forever
--           on "Arena ready"). The tick now drives ALL phases on a
--           time-authoritative schedule (phaseAt timestamps, so N
--           clients ticking do NOT accelerate the countdown), and spawn
--           positions are clamped on-grid for 5+ players.
--
--   PART 5  Night Falls — dead players could still submit night actions,
--           the night could never auto-resolve after the seer/doctor
--           died (expected locks never shrank), and a disconnected
--           hunter blocked the game forever (revenge now times out).
--
--   PART 6  Secret Heist — resolve had no phase guard → tick-driven and
--           submit-driven resolutions could double-apply coin effects.
--
--   PART 7  Ashta Chamma — captures were never applied server-side (the
--           engine's capture code was never synced), and no-move rolls
--           burned the full 30s turn timer (~80% of opening rolls).
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- PART 1a: fn_touch_game_activity — restore the 3 tables dropped by the
-- word_forge migration's stale redefinition.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(p_game_table text, p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games','sos_games',
    'dotsboxes_games','nameplace_games','truthordare_games','twotruths_games',
    'redlight_rounds','chess_games','tictactoe_games','checkers_games','carrom_games',
    'tugofwar_games','memorymatch_games','ashta_chamma_games','ghost_painter_rounds',
    'connect4_games','impostor_games','color_trap_games','freeze_auction_games',
    'flick_arena_games','secret_heist_games','mind_match_games','word_forge_games',
    'code_clues_games','night_falls_games','sketch_telephone_games'
  ) THEN
    RAISE EXCEPTION 'Unknown game table: %', p_game_table;
  END IF;
  EXECUTE format('UPDATE public.%I SET "lastActivityAt" = now() WHERE "id" = $1;', p_game_table) USING p_game_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- PART 1b: fn__game_meta — restore code_clues / night_falls /
-- sketch_telephone entries.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn__game_meta() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'tictactoe_games', jsonb_build_object('id','tictactoe','name','Tic-Tac-Toe','icon','#️⃣','accent','#8B5CF6'),
    'chess_games', jsonb_build_object('id','chess','name','Chess','icon','♟️','accent','#64748B'),
    'checkers_games', jsonb_build_object('id','checkers','name','Checkers','icon','🔴','accent','#6366F1'),
    'carrom_games', jsonb_build_object('id','carrom','name','Carrom','icon','⚪','accent','#F59E0B'),
    'ludo_games', jsonb_build_object('id','ludo','name','Ludo','icon','🎲','accent','#E11D48'),
    'bingo_games', jsonb_build_object('id','bingo','name','Bingo','icon','🎰','accent','#06B6D4'),
    'dotsboxes_games', jsonb_build_object('id','dotsboxes','name','Dots and Boxes','icon','📐','accent','#06B6D4'),
    'truthordare_games', jsonb_build_object('id','truthordare','name','Truth or Dare','icon','🎲','accent','#EF4444'),
    'twotruths_games', jsonb_build_object('id','twotruths','name','Two Truths and a Lie','icon','🤥','accent','#D946EF'),
    'chitmatch_games', jsonb_build_object('id','chitmatch','name','TripleMatch','icon','🎫','accent','#EC4899'),
    'redlight_rounds', jsonb_build_object('id','freeze-dash','name','Freeze & Dash','icon','🚦','accent','#10B981'),
    'ghost_painter_rounds', jsonb_build_object('id','ghost-painter','name','Ghost Painter','icon','👻','accent','#EC4899'),
    'antakshari_games', jsonb_build_object('id','antakshari','name','Antakshari','icon','🎵','accent','#8B5CF6'),
    'nameplace_games', jsonb_build_object('id','nameplace','name','Name, Place, Animal, Thing','icon','📝','accent','#10B981'),
    'sos_games', jsonb_build_object('id','sos','name','SOS','icon','🔤','accent','#F59E0B'),
    'tugofwar_games', jsonb_build_object('id','tug-of-war','name','Tug of War','icon','💪','accent','#E8612A'),
    'memorymatch_games', jsonb_build_object('id','memory-match','name','Memory Match','icon','🧠','accent','#A855F7'),
    'ashta_chamma_games', jsonb_build_object('id','ashta-chamma','name','Ashta Chamma','icon','🐚','accent','#E11D48'),
    'connect4_games', jsonb_build_object('id','connect4','name','Connect 4','icon','🔴','accent','#0EA5E9'),
    'impostor_games', jsonb_build_object('id','impostor','name','Who''s the Impostor?','icon','🕵️','accent','#8B5CF6'),
    'color_trap_games', jsonb_build_object('id','color-trap','name','Color Trap','icon','🎨','accent','#F59E0B'),
    'freeze_auction_games', jsonb_build_object('id','freeze-auction','name','Freeze Auction','icon','📦','accent','#F59E0B'),
    'flick_arena_games', jsonb_build_object('id','flick-arena','name','Flick Arena','icon','🎯','accent','#22D3EE'),
    'secret_heist_games', jsonb_build_object('id','secret-heist','name','Secret Heist','icon','💰','accent','#10B981'),
    'mind_match_games', jsonb_build_object('id','mind-match','name','Mind Match','icon','🧠','accent','#F472B6'),
    'word_forge_games', jsonb_build_object('id','word-forge','name','Word Forge','icon','📖','accent','#8B5CF6'),
    'code_clues_games', jsonb_build_object('id','code-clues','name','Code Clues','icon','🔐','accent','#F59E0B'),
    'night_falls_games', jsonb_build_object('id','night-falls','name','Night Falls','icon','🌙','accent','#6366F1'),
    'sketch_telephone_games', jsonb_build_object('id','sketch-telephone','name','Sketch Telephone','icon','✏️','accent','#EC4899')
  );
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- PART 1c: code_clues_players lacks the readyAt column the generic ready
-- UPDATE writes — add it before whitelisting the table.
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE "code_clues_players" ADD COLUMN IF NOT EXISTS "readyAt" TIMESTAMPTZ;

-- ═══════════════════════════════════════════════════════════════════════
-- PART 1d: fn_set_player_ready — extend whitelists to every game with a
-- player table. Without this, the lobby Ready toggle was a silent no-op
-- for the 12 newer games (client optimistically toggles, server rejects
-- the unknown table, ready state never syncs — "0 of 2 Ready" forever).
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_set_player_ready(p_player_table text, p_game_table text, p_game_id text, p_user_id text, p_is_ready boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF p_player_table NOT IN (
        'antakshari_players', 'chitmatch_players', 'ludo_players',
        'sos_players', 'dotsboxes_players', 'nameplace_players',
        'truthordare_players', 'twotruths_players', 'redlight_players',
        'bingo_players', 'tugofwar_players', 'memorymatch_players',
        'connect4_players', 'impostor_players', 'ashta_chamma_players',
        'color_trap_players', 'freeze_auction_players', 'secret_heist_players',
        'mind_match_players', 'code_clues_players', 'night_falls_players',
        'sketch_telephone_players', 'word_forge_players'
    ) THEN
        RAISE EXCEPTION 'Unknown player table: %', p_player_table;
    END IF;
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'tugofwar_games', 'memorymatch_games', 'connect4_games',
        'impostor_games', 'ashta_chamma_games', 'color_trap_games',
        'freeze_auction_games', 'secret_heist_games', 'mind_match_games',
        'code_clues_games', 'night_falls_games', 'sketch_telephone_games',
        'word_forge_games'
    ) THEN
        RAISE EXCEPTION 'Unknown game table: %', p_game_table;
    END IF;

    IF p_player_table = 'redlight_players' THEN
        EXECUTE format(
            'UPDATE public.%I SET "isReady" = $1, "readyAt" = CASE WHEN $1 THEN now() ELSE NULL END
             WHERE "roundId" = $2 AND "userId" = $3;',
            p_player_table
        ) USING p_is_ready, p_game_id, p_user_id;
    ELSE
        EXECUTE format(
            'UPDATE public.%I SET "isReady" = $1, "readyAt" = CASE WHEN $1 THEN now() ELSE NULL END
             WHERE "gameId" = $2 AND "userId" = $3;',
            p_player_table
        ) USING p_is_ready, p_game_id, p_user_id;
    END IF;

    PERFORM public.fn_touch_game_activity(p_game_table, p_game_id);
END;
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- PART 1e: fn__archive_family_match — extend whitelist + winner extraction
-- to the 12 newer games (all use the winnerUserIds jsonb pattern). This
-- makes match history, game_user_stats, Family Cup points, activity feed,
-- challenges and badges finally update for these games.
-- ═══════════════════════════════════════════════════════════════════════
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
    'memorymatch_games','connect4_games','impostor_games','ashta_chamma_games',
    'color_trap_games','freeze_auction_games','flick_arena_games',
    'secret_heist_games','mind_match_games','code_clues_games',
    'night_falls_games','sketch_telephone_games','word_forge_games'
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
                          'memorymatch_games','connect4_games','impostor_games',
                          'ashta_chamma_games','color_trap_games','freeze_auction_games',
                          'flick_arena_games','secret_heist_games','mind_match_games',
                          'code_clues_games','night_falls_games','sketch_telephone_games',
                          'word_forge_games') THEN
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
  IF p_game_table = 'bingo_games' THEN
    -- Cards are the authoritative roster; participant rows fill any gaps
    -- (e.g. legacy rooms). UNION dedupes, and card-holders win over
    -- participant rows so nobody is counted twice.
    SELECT jsonb_agg(jsonb_build_object(
             'userId', x."userId",
             'userName', COALESCE(x."userName", 'Family Member'),
             'role', CASE WHEN x."userId" = (SELECT g."hostUserId" FROM public.bingo_games g WHERE g."id" = p_game_id) THEN 'host' ELSE 'player' END))
    INTO v_participants
    FROM (
      SELECT bc."playerId" AS "userId", bc."playerName" AS "userName"
        FROM public.bingo_cards bc
       WHERE bc."gameId" = p_game_id
      UNION
      SELECT gp."userId", gp."userName"
        FROM "game_participants" gp
       WHERE gp."gameTable" = 'bingo_games'
         AND gp."gameId" = p_game_id
         AND gp."leftAt" IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.bingo_cards bc2
                          WHERE bc2."gameId" = p_game_id
                            AND bc2."playerId" = gp."userId")
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


-- ═══════════════════════════════════════════════════════════════════════
-- PART 1f: fn_end_game + fn__hard_delete_room — extend whitelists to the
-- 12 newer games so rooms can actually be cleaned up (no more zombie
-- rooms that no RPC and no cron can delete).
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_end_game(p_game_table text, p_game_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games',
        'tugofwar_games', 'memorymatch_games', 'connect4_games',
        'impostor_games', 'ashta_chamma_games', 'color_trap_games',
        'freeze_auction_games', 'flick_arena_games', 'secret_heist_games',
        'mind_match_games', 'code_clues_games', 'night_falls_games',
        'sketch_telephone_games', 'word_forge_games'
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
$function$;

CREATE OR REPLACE FUNCTION public.fn__hard_delete_room(p_game_table text, p_game_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games',
        'tugofwar_games', 'memorymatch_games', 'connect4_games',
        'impostor_games', 'ashta_chamma_games', 'color_trap_games',
        'freeze_auction_games', 'flick_arena_games', 'secret_heist_games',
        'mind_match_games', 'code_clues_games', 'night_falls_games',
        'sketch_telephone_games', 'word_forge_games'
    ) THEN
        RAISE EXCEPTION 'Unknown game table: %', p_game_table;
    END IF;

    -- 1. Delete pending invites for this room (stale invites must never
    --    re-open a closed room).
    DELETE FROM public.game_invites
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

    -- 2. Delete all participant rows (realtime fans these DELETEs out to
    --    every connected lobby — player lists empty immediately).
    DELETE FROM public.game_participants
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

    -- 3. Delete all spectator rows.
    DELETE FROM public.game_spectators
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

    -- 4. Delete the room event log (the 'cancel' event inserted by the
    --    caller has already been delivered via realtime WAL).
    DELETE FROM public.game_room_events
    WHERE "gameTable" = p_game_table AND "gameId" = p_game_id;

    -- 5. DELETE the game row itself — all game-specific child tables
    --    (players / moves / cards / turns / tokens / rounds / claims)
    --    cascade via FK ON DELETE CASCADE. After this returns, the room
    --    no longer exists anywhere in the database.
    EXECUTE format('DELETE FROM public.%I WHERE "id" = $1;', p_game_table)
    USING p_game_id;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════
-- PART 1g: fn_close_expired_rooms + fn_get_match_ecosystem — extend to
-- every game table (auto-close cron + ecosystem summary).
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_close_expired_rooms()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
    DECLARE
        v_closed_count integer := 0;
        t text;
        r record;
    BEGIN
        FOREACH t IN ARRAY ARRAY[
            'bingo_games', 'ludo_games', 'checkers_games', 'carrom_games',
            'chess_games', 'sos_games', 'antakshari_games', 'tictactoe_games',
            'truthordare_games', 'twotruths_games', 'dotsboxes_games',
            'nameplace_games', 'chitmatch_games', 'redlight_rounds',
            'tugofwar_games', 'memorymatch_games', 'ghost_painter_rounds',
            'connect4_games', 'impostor_games', 'ashta_chamma_games',
            'color_trap_games', 'freeze_auction_games', 'flick_arena_games',
            'secret_heist_games', 'mind_match_games', 'code_clues_games',
            'night_falls_games', 'sketch_telephone_games', 'word_forge_games'
        ] LOOP
            FOR r IN EXECUTE format(
                'SELECT "id" AS game_id, "familyId" AS family_id
                 FROM %I
                 WHERE "autoCloseDeadline" IS NOT NULL
                   AND "autoCloseDeadline" <= now()
                   AND "cancelledAt" IS NULL
                   AND "closedAt" IS NULL
                   AND (
                       "status" IN (''lobby'', ''waiting'')
                       OR "status" IS NULL
                   )',
                t
            ) LOOP
                -- Post the auto_close event FIRST so realtime clients
                -- (waiting rooms, boards) receive it via WAL before the
                -- rows vanish.
                INSERT INTO "game_room_events"
                    ("gameTable", "gameId", "familyId", "userId", "userName", "eventType", "payload")
                VALUES
                    (t, r.game_id, r.family_id, NULL, 'System', 'auto_close',
                     jsonb_build_object('reason', 'auto_close_deadline_passed'));

                -- Remove the room entirely (invites, participants,
                -- spectators, events + game row; children cascade).
                BEGIN
                    PERFORM public.fn__hard_delete_room(t, r.game_id);
                EXCEPTION WHEN OTHERS THEN
                    -- Unknown table whitelist miss — fall back to soft close.
                    EXECUTE format(
                        'UPDATE %I SET "closedAt" = now(), "cancelledAt" = COALESCE("cancelledAt", now()) WHERE "id" = $1',
                        t
                    ) USING r.game_id;
                    DELETE FROM "game_participants"
                    WHERE "gameTable" = t AND "gameId" = r.game_id;
                    DELETE FROM "game_spectators"
                    WHERE "gameTable" = t AND "gameId" = r.game_id;
                END;

                v_closed_count := v_closed_count + 1;
            END LOOP;
        END LOOP;

        RETURN v_closed_count;
    END;
$$;

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
    'memorymatch_games','connect4_games','impostor_games','ashta_chamma_games',
    'color_trap_games','freeze_auction_games','flick_arena_games',
    'secret_heist_games','mind_match_games','code_clues_games',
    'night_falls_games','sketch_telephone_games','word_forge_games'
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
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- PART 2: Mind Match — the jsonb `?` operator only matches STRING array
-- elements, but playerIndices is built with jsonb_agg(idx - 1) = NUMBERS.
-- No player was ever matched to their group → every round awarded 0
-- points → every match ended 0-0 with no winner. Fixed with @> containment
-- against to_jsonb(int) which matches numeric elements.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_mindmatch_resolve(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_count int;
  v_total_rounds int;
  v_players jsonb;
  v_answer_seconds int;
  v_answer_groups jsonb := '[]'::jsonb;
  v_group_obj jsonb;
  v_group_size int;
  v_max_group_size int := 0;
  v_crowd_favorite text;
  v_perfect_match boolean := false;
  v_points_arr jsonb := '[]'::jsonb;
  v_points int;
  v_player_idx int;
  v_player_score int;
  v_player_streak int;
  v_player_perfect int;
  v_matched_this_round boolean;
  v_i int;
  v_crowd_bonus boolean;
  v_perfect_bonus boolean;
  v_my_group_size int;
  v_my_crowd_bonus boolean;
  v_my_perfect_bonus boolean;
  v_group_idx int;
BEGIN
  SELECT * INTO v_game FROM "mind_match_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  v_total_rounds := (v_board->>'totalRounds')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_players := v_board->'players';
  v_answer_seconds := (v_board->>'answerSeconds')::int;

  -- ── Group answers by normalized form using a CTE ──
  -- We build the groups as a JSONB array, sorted by size desc, then alpha.
  WITH grouped AS (
    SELECT
      a."normalizedAnswer",
      min(a."answer") AS display_answer,  -- shortest display form
      jsonb_agg(a."userId") AS user_ids,
      jsonb_agg(
        (SELECT name FROM jsonb_array_elements(v_players) WITH ORDINALITY AS t(p, i)
         WHERE i - 1 = (SELECT idx - 1 FROM jsonb_array_elements_text(v_game."playerOrder") WITH ORDINALITY AS o(uid, idx) WHERE uid = a."userId"))
      ) AS user_names,
      jsonb_agg(
        (SELECT idx - 1 FROM jsonb_array_elements_text(v_game."playerOrder") WITH ORDINALITY AS o(uid, idx) WHERE uid = a."userId")
      ) AS player_indices,
      count(*) AS group_size
    FROM "mind_match_answers" a
    WHERE a."gameId" = p_game_id AND a."roundNumber" = v_current
    GROUP BY a."normalizedAnswer"
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'answer', g.display_answer,
      'normalizedAnswer', g."normalizedAnswer",
      'userIds', g.user_ids,
      'userNames', g.user_names,
      'playerIndices', g.player_indices,
      'size', g.group_size
    ) ORDER BY g.group_size DESC, g.display_answer ASC
  )
  INTO v_answer_groups
  FROM grouped g;

  IF v_answer_groups IS NULL THEN
    v_answer_groups := '[]'::jsonb;
  END IF;

  -- ── Find max group size ──
  v_max_group_size := 0;
  FOR v_i IN 0..jsonb_array_length(v_answer_groups) - 1 LOOP
    v_group_size := (v_answer_groups->v_i->>'size')::int;
    IF v_group_size > v_max_group_size THEN
      v_max_group_size := v_group_size;
    END IF;
  END LOOP;

  -- ── Perfect Match: everyone gave the same answer ──
  v_perfect_match := (v_max_group_size = v_player_count AND v_player_count > 1);

  -- ── Crowd Favorite: the largest group (first one if tie) ──
  IF v_max_group_size >= 2 THEN
    v_crowd_favorite := v_answer_groups->0->>'answer';
  ELSE
    v_crowd_favorite := null;
  END IF;

  -- ── Award points ──
  v_points_arr := '[]'::jsonb;
  FOR v_i IN 0..v_player_count - 1 LOOP
    v_matched_this_round := false;
    v_points := 0;
    v_crowd_bonus := false;
    v_perfect_bonus := false;
    v_my_group_size := 0;

    -- Find the group this player is in
    FOR v_group_idx IN 0..jsonb_array_length(v_answer_groups) - 1 LOOP
      v_group_obj := v_answer_groups->v_group_idx;
      IF (v_group_obj->'playerIndices') @> to_jsonb(v_i) THEN
        v_my_group_size := (v_group_obj->>'size')::int;
        v_matched_this_round := v_my_group_size >= 2;
        IF v_my_group_size >= 2 THEN
          v_points := v_my_group_size * 5;
        ELSE
          v_points := 2;
        END IF;
        -- Crowd favorite bonus
        IF v_crowd_favorite IS NOT NULL AND v_my_group_size = v_max_group_size AND v_max_group_size >= 2 THEN
          v_points := v_points + 5;
          v_crowd_bonus := true;
        END IF;
        -- Perfect match bonus
        IF v_perfect_match THEN
          v_points := v_points + 20;
          v_perfect_bonus := true;
        END IF;
        EXIT;
      END IF;
    END LOOP;

    -- Streak bonus
    v_player_streak := (v_players->v_i->>'streak')::int;
    IF v_matched_this_round THEN
      v_player_streak := v_player_streak + 1;
      IF v_player_streak >= 2 THEN
        v_points := v_points + (v_player_streak - 1) * 5;
      END IF;
    ELSE
      v_player_streak := 0;
    END IF;

    -- Update player score
    v_player_score := (v_players->v_i->>'score')::int + v_points;
    v_player_perfect := (v_players->v_i->>'perfectMatches')::int + (CASE WHEN v_perfect_bonus THEN 1 ELSE 0 END);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'score'], v_player_score::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'lastRoundPoints'], v_points::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'streak'], v_player_streak::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_i::text, 'perfectMatches'], v_player_perfect::text::jsonb);

    v_points_arr := v_points_arr || jsonb_build_object(
      'playerIndex', v_i,
      'points', v_points,
      'matched', v_matched_this_round,
      'groupSize', v_my_group_size,
      'crowdBonus', v_crowd_bonus,
      'perfectBonus', v_perfect_bonus,
      'streak', v_player_streak
    );
  END LOOP;

  -- ── Update round with resolved state ──
  v_round := v_board->'rounds'->(v_current - 1);
  v_round := jsonb_set(v_round, '{phase}', '"revealing"');
  v_round := jsonb_set(v_round, '{answerGroups}', v_answer_groups);
  v_round := jsonb_set(v_round, '{crowdFavorite}', to_jsonb(v_crowd_favorite));
  v_round := jsonb_set(v_round, '{perfectMatch}', to_jsonb(v_perfect_match));
  v_round := jsonb_set(v_round, '{pointsAwarded}', v_points_arr);

  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  v_board := jsonb_set(v_board, '{players}', v_players);

  UPDATE "mind_match_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mindmatch_resolve(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- PART 3: Freeze Auction — initialize v_coins / v_shield from the
-- winner's player JSON (previously NULL → jsonb_set(..., NULL) nulled the
-- entire boardState on every reveal) + implement the steal / freeze /
-- multiplier effects that were previously no-ops.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_freezeauction_advance(p_game_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb; v_current int; v_phase text;
  v_bids jsonb; v_winner_idx int; v_win_bid int; v_players jsonb; v_item jsonb; v_effect text; v_value int;
  v_pool jsonb; v_pool_id text; v_idx int; v_new_round jsonb; v_total int; v_alive int; v_max_coins int; v_winner_player int;
  v_i int; v_count int; v_bid_amt int; v_bid_ts text; v_max_bid int; v_earliest_ts text; v_desc text; v_coins int; v_shield boolean; v_is_final boolean;
BEGIN
  SELECT * INTO v_game FROM "freeze_auction_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  v_phase := v_round->>'phase';
  v_players := v_board->'players';

  IF v_phase = 'bidding' THEN
    -- Lock bids + determine winner (highest bid, ties by earliest)
    v_bids := v_round->'bids';
    v_count := jsonb_array_length(v_bids);
    v_winner_idx := -1; v_max_bid := -1; v_earliest_ts := '9999';
    FOR v_i IN 0..v_count - 1 LOOP
      v_bid_amt := (v_bids->v_i->>'amt')::int;
      v_bid_ts := v_bids->v_i->>'ts';
      IF v_bid_amt > v_max_bid OR (v_bid_amt = v_max_bid AND v_bid_ts < v_earliest_ts) THEN
        v_max_bid := v_bid_amt; v_winner_idx := (v_bids->v_i->>'p')::int; v_earliest_ts := v_bid_ts;
      END IF;
    END LOOP;
    IF v_winner_idx >= 0 AND v_max_bid > 0 THEN
      -- Deduct bid
      v_players := jsonb_set(v_players, ARRAY[v_winner_idx::text, 'coins'], ((v_players->v_winner_idx->>'coins')::int - v_max_bid)::text::jsonb);
      v_round := jsonb_set(v_round, '{winner}', v_winner_idx::text::jsonb);
      v_round := jsonb_set(v_round, '{winBid}', v_max_bid::text::jsonb);
    END IF;
    v_round := jsonb_set(v_round, '{phase}', '"revealing"');
    v_board := jsonb_set(v_board, '{players}', v_players);
  ELSIF v_phase = 'revealing' THEN
    -- Apply effect (simplified — server picks effect based on item id)
    v_item := v_round->'item';
    v_effect := 'nothing'; v_value := 0; v_desc := 'Nothing inside';
    v_winner_idx := COALESCE((v_round->>'winner')::int, -1);
    IF v_winner_idx >= 0 THEN
      -- Simple effect mapping based on item id
      DECLARE v_item_id text := v_item->>'id';
      BEGIN
        v_effect := CASE v_item_id
          WHEN 'i-add10' THEN 'addCoins' WHEN 'i-add20' THEN 'addCoins' WHEN 'i-add30' THEN 'addCoins'
          WHEN 'i-add50' THEN 'addCoins' WHEN 'i-add75' THEN 'addCoins' WHEN 'i-jackpot' THEN 'jackpot'
          WHEN 'i-double' THEN 'doubleCoins' WHEN 'i-triple' THEN 'tripleCoins'
          WHEN 'i-steal25' THEN 'stealCoins' WHEN 'i-shield' THEN 'shield'
          WHEN 'i-mult' THEN 'multiplier' WHEN 'i-freeze' THEN 'freeze'
          WHEN 'i-nothing' THEN 'nothing' WHEN 'i-lose25' THEN 'loseCoins'
          WHEN 'i-lose50' THEN 'loseCoins' WHEN 'i-bankrupt' THEN 'bankruptcy'
          ELSE 'nothing' END;
        v_value := CASE v_item_id
          WHEN 'i-add10' THEN 10 WHEN 'i-add20' THEN 20 WHEN 'i-add30' THEN 30
          WHEN 'i-add50' THEN 50 WHEN 'i-add75' THEN 75 WHEN 'i-jackpot' THEN 100
          WHEN 'i-steal25' THEN 25 WHEN 'i-lose25' THEN 25 WHEN 'i-lose50' THEN 50
          ELSE 0 END;
        -- Read the winner's CURRENT coins/shield first (they were never
        -- initialized in the original version — v_coins stayed NULL, and
        -- jsonb_set(..., NULL) nulled the whole boardState).
        v_coins := COALESCE((v_players->v_winner_idx->>'coins')::int, 0);
        v_shield := COALESCE((v_players->v_winner_idx->>'shield')::boolean, false);
        -- Apply effect to winner's coins
        IF v_effect = 'addCoins' THEN v_coins := v_coins + v_value; v_desc := '+' || v_value || ' coins';
        ELSIF v_effect = 'jackpot' THEN v_coins := v_coins + v_value; v_desc := 'JACKPOT! +' || v_value || ' coins';
        ELSIF v_effect = 'doubleCoins' THEN v_coins := v_coins * 2; v_desc := 'Coins doubled!';
        ELSIF v_effect = 'tripleCoins' THEN v_coins := v_coins * 3; v_desc := 'Coins tripled!';
        ELSIF v_effect = 'stealCoins' THEN
          DECLARE v_victim int := -1; v_max_coins int := -1;
          BEGIN
            FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP
              IF v_i <> v_winner_idx AND (v_players->v_i->>'alive')::boolean THEN
                IF COALESCE((v_players->v_i->>'coins')::int, 0) > v_max_coins THEN
                  v_max_coins := COALESCE((v_players->v_i->>'coins')::int, 0);
                  v_victim := v_i;
                END IF;
              END IF;
            END LOOP;
            IF v_victim >= 0 THEN
              v_players := jsonb_set(v_players, ARRAY[v_victim::text, 'coins'], GREATEST(v_max_coins - v_value, 0)::text::jsonb);
              v_coins := v_coins + v_value;
              v_desc := 'Stole ' || v_value || ' coins';
            ELSE
              v_desc := 'No one to steal from';
            END IF;
          END;
        ELSIF v_effect = 'shield' THEN v_shield := true; v_desc := 'Shield activated!';
        ELSIF v_effect = 'multiplier' THEN
          v_players := jsonb_set(v_players, ARRAY[v_winner_idx::text, 'multiplier'], to_jsonb(true));
          v_desc := 'Next reward x2!';
        ELSIF v_effect = 'freeze' THEN
          DECLARE v_frozen boolean := false;
          BEGIN
            FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP
              IF v_i <> v_winner_idx AND (v_players->v_i->>'alive')::boolean
                 AND NOT COALESCE((v_players->v_i->>'frozen')::boolean, false) THEN
                v_players := jsonb_set(v_players, ARRAY[v_i::text, 'frozen'], to_jsonb(true));
                v_frozen := true;
                v_desc := 'Froze a player for next round';
                EXIT;
              END IF;
            END LOOP;
            IF NOT v_frozen THEN v_desc := 'No one to freeze'; END IF;
          END;
        ELSIF v_effect = 'nothing' THEN v_desc := 'Empty crate';
        ELSIF v_effect = 'loseCoins' THEN
          IF v_shield THEN v_shield := false; v_desc := 'Shield blocked the trap!';
          ELSE v_coins := GREATEST(v_coins - v_value, 0); v_desc := '-' || v_value || ' coins'; END IF;
        ELSIF v_effect = 'bankruptcy' THEN
          IF v_shield THEN v_shield := false; v_desc := 'Shield blocked bankruptcy!';
          ELSE v_coins := 0; v_desc := 'BANKRUPTCY!'; END IF;
        ELSE v_desc := 'Nothing'; END IF;
          v_players := jsonb_set(v_players, ARRAY[v_winner_idx::text, 'coins'], v_coins::text::jsonb);
          v_players := jsonb_set(v_players, ARRAY[v_winner_idx::text, 'shield'], to_jsonb(v_shield));
          IF v_coins <= 0 THEN v_players := jsonb_set(v_players, ARRAY[v_winner_idx::text, 'alive'], 'false'); END IF;
      END;
      -- Clear freeze for all
      FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP
        v_players := jsonb_set(v_players, ARRAY[v_i::text, 'frozen'], 'false');
      END LOOP;
    END IF;
    v_round := jsonb_set(v_round, '{effect}', to_jsonb(v_desc));
    v_round := jsonb_set(v_round, '{phase}', '"roundResult"');
    v_board := jsonb_set(v_board, '{players}', v_players);
  ELSIF v_phase = 'roundResult' THEN
    -- Next round or finish
    v_total := (v_board->>'totalRounds')::int;
    v_alive := 0;
    FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP IF (v_players->v_i->>'alive')::boolean THEN v_alive := v_alive + 1; END IF; END LOOP;
    IF v_current >= v_total OR v_alive <= 1 THEN
      -- Finish
      v_max_coins := -1; v_winner_player := -1;
      FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP
        v_value := (v_players->v_i->>'coins')::int;
        IF v_value > v_max_coins THEN v_max_coins := v_value; v_winner_player := v_i; END IF;
      END LOOP;
      v_board := jsonb_set(v_board, '{status}', '"completed"');
      v_board := jsonb_set(v_board, '{winner}', v_winner_player::text::jsonb);
      v_round := jsonb_set(v_round, '{phase}', '"finished"');
      v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
      v_board := jsonb_set(v_board, '{rounds}', v_rounds);
      UPDATE "freeze_auction_games" SET "boardState" = v_board, status = 'completed', "completedAt" = now(),
        "winnerUserIds" = CASE WHEN v_winner_player >= 0 THEN jsonb_build_array(v_game."playerOrder"->>v_winner_player::text) ELSE '[]'::jsonb END,
        "endReason" = 'most_coins', "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true, 'finished', true);
    ELSE
      -- Next round
      v_pool_id := v_board->>'itemPoolId';
      v_is_final := (v_current + 1) >= v_total;
      v_pool := CASE WHEN v_is_final THEN '["i-add50","i-add75","i-double","i-triple","i-jackpot","i-shield","i-mult"]'::jsonb
        WHEN v_pool_id = 'chaos' THEN '["i-add10","i-add50","i-double","i-steal25","i-freeze","i-nothing","i-lose50","i-bankrupt"]'::jsonb
        ELSE '["i-add10","i-add20","i-add30","i-add50","i-add75","i-double","i-steal25","i-shield","i-mult","i-nothing","i-lose25","i-lose50","i-bankrupt"]'::jsonb END;
      v_idx := floor(random() * jsonb_array_length(v_pool))::int;
      v_new_round := jsonb_build_object('round', v_current + 1, 'item', jsonb_build_object('id', v_pool->v_idx, 'name', 'Mystery Crate', 'rarity', 'common', 'effect', 'addCoins', 'value', 25, 'desc', '?'), 'final', v_is_final, 'phase', 'bidding', 'bids', '[]'::jsonb, 'winner', -1, 'winBid', 0);
      v_rounds := v_board->'rounds' || v_new_round;
      v_board := jsonb_set(v_board, '{rounds}', v_rounds);
      v_board := jsonb_set(v_board, '{currentRound}', (v_current + 1)::text::jsonb);
      UPDATE "freeze_auction_games" SET "boardState" = v_board, "turnEndsAt" = now() + interval '30 seconds', "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true);
    END IF;
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_phase');
  END IF;

  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  UPDATE "freeze_auction_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════
-- PART 4: Color Trap — the phase machine had no driver for the early
-- phases (the game was stuck on "Arena ready — move to position!"
-- forever) and the counter-based countdown accelerated with the number of
-- connected clients. The tick now drives ALL phases on a time-
-- authoritative schedule, and spawn positions are clamped on-grid for
-- 5+ players (previously off-arena → auto-eliminated).
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_colortrap_start(p_game_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_players jsonb; v_count int; v_order text[]; v_board jsonb; v_difficulty text; v_size int; v_colors int; v_tiles jsonb; v_target text; v_i int; v_r int; v_c int; v_avail text[];
BEGIN
  SELECT * INTO v_game FROM "color_trap_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "color_trap_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_count := jsonb_array_length(v_players);
  IF v_count < 2 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;
  FOR v_i IN 0..v_count - 1 LOOP v_order := array_append(v_order, v_players->v_i->>'userId'); END LOOP;
  v_difficulty := v_game.difficulty;
  v_size := CASE v_difficulty WHEN 'easy' THEN 6 WHEN 'hard' THEN 10 WHEN 'expert' THEN 12 ELSE 8 END;
  v_colors := CASE v_difficulty WHEN 'easy' THEN 4 WHEN 'hard' THEN 6 WHEN 'expert' THEN 8 ELSE 5 END;
  v_avail := CASE v_colors WHEN 4 THEN ARRAY['red','blue','green','yellow'] WHEN 5 THEN ARRAY['red','blue','green','yellow','purple'] WHEN 6 THEN ARRAY['red','blue','green','yellow','purple','orange'] WHEN 8 THEN ARRAY['red','blue','green','yellow','purple','orange','cyan','pink'] ELSE ARRAY['red','blue','green','yellow','purple'] END;
  -- Generate tiles
  v_tiles := '[]'::jsonb;
  FOR v_r IN 0..v_size - 1 LOOP FOR v_c IN 0..v_size - 1 LOOP
    v_tiles := v_tiles || jsonb_build_object('r', v_r, 'c', v_c, 'color', v_avail[1 + floor(random() * v_colors)::int], 'v', true);
  END LOOP; END LOOP;
  -- Pick target color
  v_target := v_avail[1 + floor(random() * v_colors)::int];
  -- Build initial player positions
  DECLARE v_players_arr jsonb := '[]'::jsonb;
  BEGIN
    FOR v_i IN 0..v_count - 1 LOOP
      -- Spawn positions clamped ON-GRID for any player count (the old
      -- (v_i // 2) * (v_size // 2) formula pushed players 5+ off the
      -- arena, where they were auto-eliminated at the first countdown).
      DECLARE v_half int := GREATEST((v_count + 1) / 2, 1); v_sr int := 1 + ((v_i / 2) * (v_size - 2)) / v_half; BEGIN
        v_players_arr := v_players_arr || jsonb_build_object('idx', v_i, 'userId', v_players->v_i->>'userId', 'name', v_players->v_i->>'userName', 'r', LEAST(v_sr, v_size - 2), 'c', CASE WHEN v_i % 2 = 0 THEN 1 ELSE v_size - 2 END, 'alive', true, 'elim', -1);
      END;
    END LOOP;
    v_board := jsonb_build_object('playerCount', v_count, 'difficulty', v_difficulty, 'currentRound', 1,
      'rounds', jsonb_build_array(jsonb_build_object('round', 1, 'target', v_target, 'tiles', v_tiles, 'size', v_size, 'phase', 'arenaShown', 'countdown', 0, 'phaseAt', to_jsonb(now()::text))),
      'players', v_players_arr, 'status', 'in_progress', 'winner', -1);
  END;
  UPDATE "color_trap_games" SET status = 'in_progress', "playerOrder" = to_jsonb(v_order), "boardState" = v_board, "startedAt" = now(), "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_colortrap_advance(p_game_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb; v_current int; v_phase text;
  v_size int; v_colors int; v_difficulty text; v_countdown int; v_avail text[];
  v_tiles jsonb; v_target text; v_r int; v_c int; v_players jsonb; v_alive int;
  v_winner_idx int; v_new_round jsonb; v_i int; v_tile_color text; v_eliminated boolean;
BEGIN
  SELECT * INTO v_game FROM "color_trap_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  v_phase := v_round->>'phase';
  v_difficulty := v_board->>'difficulty';
  v_countdown := CASE v_difficulty WHEN 'easy' THEN 5 WHEN 'hard' THEN 3 WHEN 'expert' THEN 2 ELSE 4 END;

  IF v_phase = 'arenaShown' THEN
    v_round := jsonb_set(v_round, '{phase}', '"colorAnnounced"');
    v_round := jsonb_set(v_round, '{countdown}', v_countdown::text::jsonb);
    v_round := jsonb_set(v_round, '{phaseAt}', to_jsonb(now()::text));
  ELSIF v_phase = 'colorAnnounced' THEN
    v_round := jsonb_set(v_round, '{phase}', '"countdown"');
    v_round := jsonb_set(v_round, '{phaseAt}', to_jsonb(now()::text));
    v_round := jsonb_set(v_round, '{countdownEndsAt}', to_jsonb((now() + make_interval(secs => v_countdown))::text));
  ELSIF v_phase = 'countdown' THEN
    -- Eliminate
    v_round := jsonb_set(v_round, '{phaseAt}', to_jsonb(now()::text));
    v_target := v_round->>'target';
    v_players := v_board->'players';
    v_alive := 0;
    FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP
      IF (v_players->v_i->>'alive')::boolean THEN
        v_tile_color := (SELECT t->>'color' FROM jsonb_array_elements(v_round->'tiles') t WHERE (t->>'r')::int = (v_players->v_i->>'r')::int AND (t->>'c')::int = (v_players->v_i->>'c')::int LIMIT 1);
        IF v_tile_color IS NULL OR v_tile_color <> v_target THEN
          v_players := jsonb_set(v_players, ARRAY[v_i::text, 'alive'], 'false');
          v_players := jsonb_set(v_players, ARRAY[v_i::text, 'elim'], v_current::text::jsonb);
        ELSE v_alive := v_alive + 1; END IF;
      END IF;
    END LOOP;
    -- Hide non-target tiles
    v_tiles := v_round->'tiles';
    FOR v_i IN 0..jsonb_array_length(v_tiles) - 1 LOOP
      IF v_tiles->v_i->>'color' <> v_target THEN
        v_tiles := jsonb_set(v_tiles, ARRAY[v_i::text, 'v'], 'false');
      END IF;
    END LOOP;
    v_round := jsonb_set(v_round, '{tiles}', v_tiles);
    v_round := jsonb_set(v_round, '{phase}', '"elimination"');
    v_board := jsonb_set(v_board, '{players}', v_players);
    -- Check winner
    IF v_alive <= 1 THEN
      v_winner_idx := -1;
      FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP
        IF (v_players->v_i->>'alive')::boolean THEN v_winner_idx := v_i; EXIT; END IF;
      END LOOP;
      v_board := jsonb_set(v_board, '{winner}', v_winner_idx::text::jsonb);
      v_board := jsonb_set(v_board, '{status}', '"completed"');
      v_round := jsonb_set(v_round, '{phase}', '"roundEnd"');
      v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
      v_board := jsonb_set(v_board, '{rounds}', v_rounds);
      UPDATE "color_trap_games" SET "boardState" = v_board, status = 'completed', "completedAt" = now(),
        "winnerUserIds" = CASE WHEN v_winner_idx >= 0 THEN jsonb_build_array(v_game."playerOrder"->>v_winner_idx::text) ELSE '[]'::jsonb END,
        "endReason" = 'last_standing', "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true, 'finished', true);
    END IF;
  ELSIF v_phase = 'elimination' THEN
    -- Next round
    v_size := (v_round->>'size')::int;
    v_colors := CASE v_difficulty WHEN 'easy' THEN 4 WHEN 'hard' THEN 6 WHEN 'expert' THEN 8 ELSE 5 END;
    v_avail := CASE v_colors WHEN 4 THEN ARRAY['red','blue','green','yellow'] WHEN 5 THEN ARRAY['red','blue','green','yellow','purple'] WHEN 6 THEN ARRAY['red','blue','green','yellow','purple','orange'] WHEN 8 THEN ARRAY['red','blue','green','yellow','purple','orange','cyan','pink'] ELSE ARRAY['red','blue','green','yellow','purple'] END;
    v_tiles := '[]'::jsonb;
    FOR v_r IN 0..v_size - 1 LOOP FOR v_c IN 0..v_size - 1 LOOP
      v_tiles := v_tiles || jsonb_build_object('r', v_r, 'c', v_c, 'color', v_avail[1 + floor(random() * v_colors)::int], 'v', true);
    END LOOP; END LOOP;
    v_target := v_avail[1 + floor(random() * v_colors)::int];
    v_new_round := jsonb_build_object('round', v_current + 1, 'target', v_target, 'tiles', v_tiles, 'size', v_size, 'phase', 'arenaShown', 'countdown', 0, 'phaseAt', to_jsonb(now()::text));
    v_rounds := v_board->'rounds' || v_new_round;
    v_board := jsonb_set(v_board, '{rounds}', v_rounds);
    v_board := jsonb_set(v_board, '{currentRound}', (v_current + 1)::text::jsonb);
    UPDATE "color_trap_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true);
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_phase');
  END IF;

  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  UPDATE "color_trap_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- fn_colortrap_tick — 2s watchdog. Drives the ENTIRE phase machine on a
-- time-authoritative schedule (phaseAt timestamps), so N connected
-- clients ticking every 2s cannot accelerate the countdown:
--   arenaShown (4s) → colorAnnounced (3s) → countdown (endsAt) →
--   elimination (5s) → next round's arenaShown.
CREATE OR REPLACE FUNCTION public.fn_colortrap_tick(p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_board jsonb; v_round jsonb; v_phase text; v_countdown int; v_phase_at timestamptz; v_ends_at timestamptz; v_remaining int;
BEGIN
  SELECT * INTO v_game FROM "color_trap_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "color_trap_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  v_board := v_game."boardState";
  v_round := v_board->'rounds'->((v_board->>'currentRound')::int - 1);
  v_phase := v_round->>'phase';

  -- Backfill phaseAt for rounds created before this fix (treat the
  -- backfill moment as the phase start).
  IF v_round ? 'phaseAt' THEN
    v_phase_at := (v_round->>'phaseAt')::timestamptz;
  ELSE
    v_phase_at := now();
    v_round := jsonb_set(v_round, '{phaseAt}', to_jsonb(now()::text));
    v_board := jsonb_set(v_board, '{rounds}', jsonb_set(v_board->'rounds', ARRAY[((v_board->>'currentRound')::int - 1)::text], v_round));
    UPDATE "color_trap_games" SET "boardState" = v_board WHERE id = p_game_id;
  END IF;

  IF v_phase = 'arenaShown' THEN
    IF now() - v_phase_at >= interval '4 seconds' THEN
      PERFORM public.fn_colortrap_advance(p_game_id);
    END IF;
  ELSIF v_phase = 'colorAnnounced' THEN
    IF now() - v_phase_at >= interval '3 seconds' THEN
      PERFORM public.fn_colortrap_advance(p_game_id);
    END IF;
  ELSIF v_phase = 'countdown' THEN
    v_countdown := COALESCE((v_round->>'countdown')::int, 0);
    IF v_round ? 'countdownEndsAt' THEN
      v_ends_at := (v_round->>'countdownEndsAt')::timestamptz;
    ELSE
      -- Backfill: the countdown value is seconds remaining.
      v_ends_at := now() + make_interval(secs => v_countdown);
      v_round := jsonb_set(v_round, '{countdownEndsAt}', to_jsonb(v_ends_at::text));
    END IF;
    v_remaining := GREATEST(ceil(extract(epoch FROM (v_ends_at - now())))::int, 0);
    IF v_remaining <> v_countdown THEN
      v_round := jsonb_set(v_round, '{countdown}', v_remaining::text::jsonb);
      v_board := jsonb_set(v_board, '{rounds}', jsonb_set(v_board->'rounds', ARRAY[((v_board->>'currentRound')::int - 1)::text], v_round));
      UPDATE "color_trap_games" SET "boardState" = v_board WHERE id = p_game_id;
    END IF;
    IF v_remaining <= 0 THEN
      PERFORM public.fn_colortrap_advance(p_game_id);
    END IF;
  ELSIF v_phase = 'elimination' THEN
    IF now() - v_phase_at >= interval '5 seconds' THEN
      PERFORM public.fn_colortrap_advance(p_game_id);
    END IF;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_colortrap_tick(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- PART 5: Night Falls — dead players can no longer submit night actions;
-- night auto-resolution now counts only ALIVE role-players (previously
-- the night could never auto-resolve after the seer/doctor died); hunter
-- revenge now expires after 45s so a disconnected hunter cannot block
-- the game forever.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_nightfalls_submit_night_action(
  p_game_id text, p_action_type text, p_target_user_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_my_role text;
  v_my_alive boolean;
  v_existing record;
  v_locked_count int;
  v_wolf_count int;
  v_expected_locks int;
  v_target_alive boolean;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRoundNumber')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'night' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_night_phase'); END IF;

  SELECT "role", "isAlive" INTO v_my_role, v_my_alive FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_my_role IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  -- Dead players cannot act (their kills/votes must not count).
  IF v_my_alive IS DISTINCT FROM true THEN RETURN jsonb_build_object('ok', false, 'reason', 'you_are_dead'); END IF;

  -- Validate action type matches role
  IF p_action_type = 'wolf_kill' AND v_my_role <> 'werewolf' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_werewolf'); END IF;
  IF p_action_type = 'seer_investigate' AND v_my_role <> 'seer' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_seer'); END IF;
  IF p_action_type = 'doctor_protect' AND v_my_role <> 'doctor' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_doctor'); END IF;
  IF p_action_type NOT IN ('wolf_kill','seer_investigate','doctor_protect') THEN RETURN jsonb_build_object('ok', false, 'reason', 'invalid_action'); END IF;

  -- Target must be alive + in game
  SELECT "isAlive" INTO v_target_alive FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = p_target_user_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'invalid_target'); END IF;
  IF NOT v_target_alive THEN RETURN jsonb_build_object('ok', false, 'reason', 'target_dead'); END IF;
  -- Wolves can't kill themselves
  IF p_action_type = 'wolf_kill' AND p_target_user_id = auth.uid()::text THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'cant_target_self');
  END IF;

  -- Insert or update (player can change their mind during night phase)
  SELECT * INTO v_existing FROM "night_falls_actions"
    WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text AND "roundNumber" = v_current AND "actionType" = p_action_type LIMIT 1;
  IF v_existing.id IS NULL THEN
    INSERT INTO "night_falls_actions" ("gameId","userId","roundNumber","actionType","targetUserId")
    VALUES (p_game_id, auth.uid()::text, v_current, p_action_type, p_target_user_id);
  ELSE
    UPDATE "night_falls_actions" SET "targetUserId" = p_target_user_id, "submittedAt" = now() WHERE "id" = v_existing.id;
  END IF;

  -- Recompute locked count (distinct users with any night action this round)
  SELECT count(DISTINCT "userId") INTO v_locked_count FROM "night_falls_actions"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "actionType" IN ('wolf_kill','seer_investigate','doctor_protect');

  v_round := jsonb_set(v_round, '{nightActions,lockedCount}', v_locked_count::text::jsonb);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  -- Auto-resolve when all ALIVE role-players have locked. Expected locks
  -- are computed from the LIVE roster (dead wolves/seer/doctor no longer
  -- block the night — previously the night could never auto-resolve after
  -- the seer or doctor died, burning the full timer every night).
  SELECT count(*) INTO v_expected_locks FROM "night_falls_players"
    WHERE "gameId" = p_game_id AND "isAlive" AND "role" IN ('werewolf','seer','doctor');
  IF v_expected_locks = 0 THEN v_expected_locks := 1; END IF; -- safety
  IF v_locked_count >= v_expected_locks THEN
    UPDATE "night_falls_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
    PERFORM public.fn_nightfalls_resolve_night(p_game_id);
    RETURN jsonb_build_object('ok', true, 'resolved', true);
  END IF;

  UPDATE "night_falls_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_nightfalls_tick(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_phase text;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "night_falls_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_game."turnEndsAt" IS NULL OR v_game."turnEndsAt" >= now() THEN RETURN; END IF;

  v_board := v_game."boardState";
  v_current := (v_board->>'currentRoundNumber')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  v_phase := v_round->>'phase';

  IF v_phase = 'role_reveal' THEN
    PERFORM public.fn_nightfalls_advance(p_game_id);
  ELSIF v_phase = 'night' THEN
    PERFORM public.fn_nightfalls_resolve_night(p_game_id);
  ELSIF v_phase = 'day' THEN
    PERFORM public.fn_nightfalls_advance(p_game_id);
  ELSIF v_phase = 'vote' THEN
    PERFORM public.fn_nightfalls_resolve_vote(p_game_id);
  ELSIF v_phase = 'result' THEN
    -- Only auto-advance if hunter revenge is not pending. A disconnected
    -- hunter used to block the game forever — revenge now expires after
    -- 45 seconds and the game moves on without it.
    IF (v_round->>'hunterRevengePending')::boolean <> true THEN
      PERFORM public.fn_nightfalls_advance(p_game_id);
    ELSE
      IF v_round ? 'revengePendingAt' THEN
        IF now() - (v_round->>'revengePendingAt')::timestamptz >= interval '45 seconds' THEN
          v_round := jsonb_set(v_round, '{hunterRevengePending}', 'false'::jsonb);
          v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
          v_board := jsonb_set(v_board, '{rounds}', v_rounds);
          UPDATE "night_falls_games" SET "boardState" = v_board WHERE id = p_game_id;
          PERFORM public.fn_nightfalls_advance(p_game_id);
        END IF;
      ELSE
        -- Stamp the pending time (first tick that sees it).
        v_round := jsonb_set(v_round, '{revengePendingAt}', to_jsonb(now()::text));
        v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
        v_board := jsonb_set(v_board, '{rounds}', v_rounds);
        UPDATE "night_falls_games" SET "boardState" = v_board WHERE id = p_game_id;
      END IF;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_nightfalls_resolve_vote(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_count int;
  v_vote_record record;
  v_eliminated_id text;
  v_eliminated_name text;
  v_eliminated_role text;
  v_max_votes int;
  v_tie boolean;
  v_count int;
  v_vote_seconds int;
  v_i int;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRoundNumber')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'vote' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_vote_phase'); END IF;
  v_player_count := (v_board->>'playerCount')::int;

  -- Tally votes
  v_max_votes := 0; v_eliminated_id := null; v_tie := false;
  FOR v_vote_record IN
    SELECT "targetUserId", count(*) AS cnt
    FROM "night_falls_actions"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "actionType" = 'vote'
    GROUP BY "targetUserId"
    ORDER BY cnt DESC
  LOOP
    IF v_vote_record.cnt > v_max_votes THEN
      v_max_votes := v_vote_record.cnt;
      v_eliminated_id := v_vote_record."targetUserId";
      v_tie := false;
    ELSIF v_vote_record.cnt = v_max_votes AND v_max_votes > 0 THEN
      v_tie := true;
    END IF;
  END LOOP;

  IF v_tie OR v_eliminated_id IS NULL THEN
    -- No elimination on tie
    v_round := jsonb_set(v_round, '{eliminatedUserId}', 'null'::jsonb);
    v_round := jsonb_set(v_round, '{eliminatedUserName}', to_jsonb('No one (tie)'::text));
    v_round := jsonb_set(v_round, '{eliminatedRole}', 'null'::jsonb);
    v_round := jsonb_set(v_round, '{hunterRevengePending}', 'false'::jsonb);
  ELSE
    -- Eliminate the player
    SELECT "userName", "role" INTO v_eliminated_name, v_eliminated_role FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = v_eliminated_id;
    UPDATE "night_falls_players" SET "isAlive" = false WHERE "gameId" = p_game_id AND "userId" = v_eliminated_id;
    FOR v_i IN 0..v_player_count - 1 LOOP
      IF v_board->'players'->v_i->>'userId' = v_eliminated_id THEN
        v_board := jsonb_set(v_board, ARRAY['players', v_i::text, 'isAlive'], 'false'::jsonb);
      END IF;
    END LOOP;
    v_round := jsonb_set(v_round, '{eliminatedUserId}', to_jsonb(v_eliminated_id));
    v_round := jsonb_set(v_round, '{eliminatedUserName}', to_jsonb(v_eliminated_name));
    v_round := jsonb_set(v_round, '{eliminatedRole}', to_jsonb(v_eliminated_role));
    -- If hunter was eliminated, set revenge pending (with a timestamp so
    -- the tick can expire it if the hunter never acts).
    IF v_eliminated_role = 'hunter' THEN
      v_round := jsonb_set(v_round, '{hunterRevengePending}', 'true'::jsonb);
      v_round := jsonb_set(v_round, '{revengePendingAt}', to_jsonb(now()::text));
    ELSE
      v_round := jsonb_set(v_round, '{hunterRevengePending}', 'false'::jsonb);
    END IF;
  END IF;

  v_round := jsonb_set(v_round, '{phase}', '"result"');
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  UPDATE "night_falls_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;

  -- Check win condition (vote elimination could end the game)
  PERFORM public.fn__nightfalls_check_win(p_game_id);
  RETURN jsonb_build_object('ok', true);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════
-- PART 6: Secret Heist — resolve now has a phase guard so the tick-driven
-- and submit-driven resolutions cannot double-apply coin effects.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_secretheist_resolve(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_count int;
  v_total_rounds int;
  v_players jsonb;
  v_vault_coins int;
  v_action_seconds int;
  v_action_rec record;
  v_chaos boolean;
  v_events jsonb := '[]'::jsonb;
  v_revealed jsonb := '[]'::jsonb;
  v_vault_lost int := 0;
  v_steals_success int := 0;
  v_steals_blocked int := 0;
  v_traps_triggered int := 0;
  v_hacks_success int := 0;
  v_hacks_backfire int := 0;
  v_alarms int := 0;
  v_protected_buffer int := 0;
  v_alarm_triggered boolean := false;
  v_player_idx int;
  v_coins int;
  v_amount int;
  v_user_id text;
  v_suspicion int;
  v_rolls float;
  v_trap_user_ids text[];
  v_new_round jsonb;
  v_max_coins int;
  v_winner_idx int;
  v_tie boolean;
  v_s int;
  v_i int;
BEGIN
  SELECT * INTO v_game FROM "secret_heist_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  -- Phase guard: only resolve a round still in its action phase. Without
  -- this, the tick-driven auto-resolve and the last submit-driven resolve
  -- could both run and double-apply steal/hack coin effects.
  DECLARE v_guard_round jsonb := v_board->'rounds'->(v_current - 1); BEGIN
    IF v_guard_round->>'phase' IS DISTINCT FROM 'action' THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'already_resolved');
    END IF;
  END;
  v_total_rounds := (v_board->>'totalRounds')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_vault_coins := (v_board->>'vaultCoins')::int;
  v_players := v_board->'players';
  v_action_seconds := (v_board->>'actionSeconds')::int;
  v_chaos := (v_board->>'chaosMode')::boolean;

  -- Protects
  FOR v_action_rec IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'protect' LOOP
    v_protected_buffer := v_protected_buffer + 30;
    v_revealed := v_revealed || jsonb_build_object('userId', v_action_rec."userId", 'action', 'protect', 'amount', 30, 'outcome', 'active');
  END LOOP;

  -- Traps
  v_trap_user_ids := ARRAY[]::text[];
  FOR v_action_rec IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'trap' LOOP
    v_trap_user_ids := array_append(v_trap_user_ids, v_action_rec."userId");
    v_revealed := v_revealed || jsonb_build_object('userId', v_action_rec."userId", 'action', 'trap', 'outcome', 'set');
  END LOOP;

  -- Hacks (and chaos variants)
  FOR v_action_rec IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" IN ('hack','double_steal','alarm_bait') LOOP
    v_user_id := v_action_rec."userId";
    v_amount := v_action_rec."amount";
    v_player_idx := public.fn__sh_player_idx(v_game."playerOrder", v_user_id);
    v_rolls := random();
    IF v_action_rec."action" = 'double_steal' THEN
      IF v_rolls < 0.65 THEN
        v_hacks_success := v_hacks_success + 1;
        v_steals_success := v_steals_success + 1;
        v_vault_lost := v_vault_lost + v_amount * 2;
        v_coins := (v_players->v_player_idx->>'coins')::int + v_amount * 2;
        v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'coins'], v_coins::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'double_steal', 'amount', v_amount * 2, 'outcome', 'success');
        v_events := v_events || jsonb_build_object('type', 'hack_success', 'userId', v_user_id, 'amount', v_amount * 2);
      ELSE
        v_hacks_backfire := v_hacks_backfire + 1;
        v_coins := GREATEST((v_players->v_player_idx->>'coins')::int - v_amount, 0);
        v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'coins'], v_coins::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'double_steal', 'outcome', 'backfire');
        v_events := v_events || jsonb_build_object('type', 'hack_backfire', 'userId', v_user_id, 'amount', v_amount);
      END IF;
    ELSIF v_action_rec."action" = 'alarm_bait' THEN
      IF v_rolls < 0.5 THEN
        v_alarm_triggered := true;
        v_alarms := v_alarms + 1;
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'alarm_bait', 'outcome', 'alarm_triggered');
        v_events := v_events || jsonb_build_object('type', 'alarm_triggered', 'userId', v_user_id);
      ELSE
        v_coins := (v_players->v_player_idx->>'coins')::int + 15;
        v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'coins'], v_coins::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'alarm_bait', 'outcome', 'bait_success', 'amount', 15);
      END IF;
    ELSE -- 'hack'
      IF v_rolls < 0.5 THEN
        v_hacks_success := v_hacks_success + 1;
        v_steals_success := v_steals_success + 1;
        v_vault_lost := v_vault_lost + v_amount * 2;
        v_coins := (v_players->v_player_idx->>'coins')::int + v_amount * 2;
        v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'coins'], v_coins::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'hack', 'amount', v_amount * 2, 'outcome', 'success');
        v_events := v_events || jsonb_build_object('type', 'hack_success', 'userId', v_user_id, 'amount', v_amount * 2);
      ELSIF v_rolls < 0.8 THEN
        v_hacks_backfire := v_hacks_backfire + 1;
        v_coins := GREATEST((v_players->v_player_idx->>'coins')::int - v_amount, 0);
        v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'coins'], v_coins::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'hack', 'outcome', 'backfire');
        v_events := v_events || jsonb_build_object('type', 'hack_backfire', 'userId', v_user_id, 'amount', v_amount);
      ELSE
        v_alarm_triggered := true;
        v_alarms := v_alarms + 1;
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'hack', 'outcome', 'alarm');
        v_events := v_events || jsonb_build_object('type', 'alarm_triggered', 'userId', v_user_id);
      END IF;
    END IF;
  END LOOP;

  -- Steals
  IF NOT v_alarm_triggered THEN
    FOR v_action_rec IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'steal' ORDER BY random() LOOP
      v_user_id := v_action_rec."userId";
      v_amount := v_action_rec."amount";
      v_player_idx := public.fn__sh_player_idx(v_game."playerOrder", v_user_id);

      IF array_length(v_trap_user_ids, 1) > 0 THEN
        IF random() < 0.4 THEN
          v_traps_triggered := v_traps_triggered + 1;
          v_steals_blocked := v_steals_blocked + 1;
          v_coins := GREATEST((v_players->v_player_idx->>'coins')::int - 10, 0);
          v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'coins'], v_coins::text::jsonb);
          v_suspicion := (v_players->v_player_idx->>'suspicion')::int + 1;
          v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'suspicion'], v_suspicion::text::jsonb);
          v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'steal', 'amount', v_amount, 'outcome', 'trapped');
          v_events := v_events || jsonb_build_object('type', 'trap_triggered', 'userId', v_user_id, 'penalty', 10);
          CONTINUE;
        END IF;
      END IF;

      IF v_protected_buffer >= v_amount THEN
        v_protected_buffer := v_protected_buffer - v_amount;
        v_steals_blocked := v_steals_blocked + 1;
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'steal', 'amount', v_amount, 'outcome', 'blocked');
        v_events := v_events || jsonb_build_object('type', 'steal_blocked', 'userId', v_user_id, 'amount', v_amount);
      ELSE
        v_steals_success := v_steals_success + 1;
        v_vault_lost := v_vault_lost + v_amount;
        v_coins := (v_players->v_player_idx->>'coins')::int + v_amount;
        v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'coins'], v_coins::text::jsonb);
        v_suspicion := (v_players->v_player_idx->>'suspicion')::int + 1;
        v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'suspicion'], v_suspicion::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'steal', 'amount', v_amount, 'outcome', 'success');
        v_events := v_events || jsonb_build_object('type', 'steal_success', 'userId', v_user_id, 'amount', v_amount);
      END IF;
    END LOOP;
  ELSE
    FOR v_action_rec IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'steal' LOOP
      v_steals_blocked := v_steals_blocked + 1;
      v_revealed := v_revealed || jsonb_build_object('userId', v_action_rec."userId", 'action', 'steal', 'amount', v_action_rec."amount", 'outcome', 'alarm_blocked');
    END LOOP;
  END IF;

  -- Spies
  FOR v_action_rec IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'spy' LOOP
    v_revealed := v_revealed || jsonb_build_object('userId', v_action_rec."userId", 'action', 'spy', 'outcome', 'intel_gathered');
    v_events := v_events || jsonb_build_object('type', 'spy_used', 'userId', v_action_rec."userId");
  END LOOP;

  v_vault_coins := GREATEST(v_vault_coins - v_vault_lost, 0);

  -- Decay suspicion
  FOR v_i IN 0..v_player_count - 1 LOOP
    v_s := (v_players->v_i->>'suspicion')::int;
    IF v_s > 0 THEN
      v_players := jsonb_set(v_players, ARRAY[v_i::text, 'suspicion'], GREATEST(v_s - 1, 0)::text::jsonb);
    END IF;
  END LOOP;

  v_round := v_board->'rounds'->(v_current - 1);
  v_round := jsonb_set(v_round, '{phase}', '"revealing"');
  v_round := jsonb_set(v_round, '{vaultLost}', v_vault_lost::text::jsonb);
  v_round := jsonb_set(v_round, '{stealsSuccessful}', v_steals_success::text::jsonb);
  v_round := jsonb_set(v_round, '{stealsBlocked}', v_steals_blocked::text::jsonb);
  v_round := jsonb_set(v_round, '{trapsTriggered}', v_traps_triggered::text::jsonb);
  v_round := jsonb_set(v_round, '{hacksSucceeded}', v_hacks_success::text::jsonb);
  v_round := jsonb_set(v_round, '{hacksBackfired}', v_hacks_backfire::text::jsonb);
  v_round := jsonb_set(v_round, '{alarmsTriggered}', v_alarms::text::jsonb);
  v_round := jsonb_set(v_round, '{events}', v_events);
  v_round := jsonb_set(v_round, '{revealedActions}', v_revealed);

  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  v_board := jsonb_set(v_board, '{vaultCoins}', v_vault_coins::text::jsonb);
  v_board := jsonb_set(v_board, '{players}', v_players);

  UPDATE "secret_heist_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════
-- PART 7: Ashta Chamma — captures are now applied server-side (the SQL
-- previously skipped them with an "MVP" comment while the engine applied
-- them client-side, so the synced board never sent opponents home), the
-- 2+ opponent block rule is enforced, and no-move rolls pass the turn
-- immediately instead of burning the full 30s timer.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_ashtachamma_roll(p_game_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_up_shells int;
  v_dice int;
  v_available_moves boolean;
BEGIN
  SELECT * INTO v_game FROM "ashta_chamma_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;

  IF v_game.status <> 'in_progress' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress');
  END IF;

  IF v_game."currentPlayerId" <> auth.uid()::text THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_your_turn');
  END IF;

  IF v_game.phase <> 'roll' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_rolled');
  END IF;

  -- Generate cowrie shell throw (0-4 up shells → dice value)
  v_up_shells := floor(random() * 5)::int;  -- 0..4
  v_dice := CASE v_up_shells
    WHEN 0 THEN 8  -- Ashta
    WHEN 1 THEN 1
    WHEN 2 THEN 2
    WHEN 3 THEN 3
    WHEN 4 THEN 4  -- Chowka
  END;

  v_board := v_game."boardState";
  v_board := jsonb_set(v_board, '{lastDice}', v_dice);
  v_board := jsonb_set(v_board, '{hasRolled}', 'true');

  -- Auto-pass when the current player has NO legal move for this throw.
  -- (Previously every no-move roll burned the full 30s turn timer —
  -- with dice needing a 1 to enter from base, ~80% of opening rolls
  -- stalled. The engine auto-passes client-side; now the server does
  -- too, so both agree.)
  DECLARE
    v_current_player int := (v_board->>'currentPlayer')::int;
    v_player_count int := (v_board->>'playerCount')::int;
    v_pieces jsonb := v_board->'pieces';
    v_entry_indices int[] := CASE (v_board->>'playerCount')::int
      WHEN 2 THEN ARRAY[0, 28]
      WHEN 3 THEN ARRAY[0, 18, 36]
      ELSE ARRAY[0, 14, 28, 42]
    END;
    v_entry_index int := v_entry_indices[v_current_player + 1];
    v_has_legal boolean := false;
    v_i int;
    v_p jsonb;
    v_rel int; v_new_rel int; v_new_loop int; v_home int; v_new_home int;
    v_blockers int;
  BEGIN
    FOR v_i IN 0..jsonb_array_length(v_pieces) - 1 LOOP
      v_p := v_pieces->v_i;
      IF (v_p->>'owner')::int <> v_current_player THEN CONTINUE; END IF;
      IF v_p->>'zone' = 'base' THEN
        IF v_dice = 1 THEN
          -- Entry is legal unless the entry square is blocked by 2+ opponents.
          SELECT count(*) INTO v_blockers FROM jsonb_array_elements(v_pieces) AS o
          WHERE (o->>'owner')::int <> v_current_player
            AND o->>'zone' = 'loop' AND (o->>'loop')::int = v_entry_index;
          IF v_blockers < 2 THEN v_has_legal := true; EXIT; END IF;
        END IF;
      ELSIF v_p->>'zone' = 'loop' THEN
        v_rel := ((v_p->>'loop')::int - v_entry_index + 56) % 56;
        v_new_rel := v_rel + v_dice;
        IF v_new_rel <= 62 THEN
          IF v_new_rel < 56 THEN
            v_new_loop := (v_entry_index + v_new_rel) % 56;
            -- Destination with 2+ opponents on a non-safe square = blocked.
            IF (v_new_loop % 4) = 0 THEN
              v_has_legal := true; EXIT;
            END IF;
            SELECT count(*) INTO v_blockers FROM jsonb_array_elements(v_pieces) AS o
            WHERE (o->>'owner')::int <> v_current_player
              AND o->>'zone' = 'loop' AND (o->>'loop')::int = v_new_loop;
            IF v_blockers < 2 THEN v_has_legal := true; EXIT; END IF;
          ELSE
            v_has_legal := true; EXIT;
          END IF;
        END IF;
      ELSIF v_p->>'zone' = 'homeColumn' THEN
        v_home := COALESCE((v_p->>'home')::int, 0);
        v_new_home := v_home + v_dice;
        IF v_new_home <= 6 THEN v_has_legal := true; EXIT; END IF;
      END IF;
    END LOOP;

    IF NOT v_has_legal THEN
      -- No legal move: pass the turn to the next player immediately.
      v_board := jsonb_set(v_board, '{hasRolled}', 'false');
      v_board := jsonb_set(v_board, '{lastDice}', 0);
      DECLARE v_next int := (v_current_player + 1) % v_player_count; BEGIN
        v_board := jsonb_set(v_board, '{currentPlayer}', v_next);
        UPDATE "ashta_chamma_games" SET
          "boardState" = v_board,
          "lastDiceValue" = 0,
          phase = 'roll',
          "currentPlayerId" = "playerOrder"->>v_next,
          "currentTurnIndex" = v_next,
          "turnEndsAt" = now() + interval '30 seconds',
          "lastActivityAt" = now()
        WHERE id = p_game_id;
      END;
      RETURN jsonb_build_object('ok', true, 'dice', v_dice, 'upShells', v_up_shells, 'passed', true);
    END IF;
  END;

  UPDATE "ashta_chamma_games" SET
    "boardState" = v_board,
    "lastDiceValue" = v_dice,
    phase = 'move',
    "turnEndsAt" = now() + interval '30 seconds',
    "lastActivityAt" = now()
  WHERE id = p_game_id;

  RETURN jsonb_build_object('ok', true, 'dice', v_dice, 'upShells', v_up_shells);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_ashtachamma_move(p_game_id text, p_piece_index int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_pieces jsonb;
  v_piece jsonb;
  v_dice int;
  v_current_player int;
  v_player_count int;
  v_entry_indices int[];
  v_entry_index int;
  v_pieces_arr jsonb;
  v_piece_obj jsonb;
  v_zone text;
  v_loop_pos int;
  v_home_pos int;
  v_rel_pos int;
  v_new_rel int;
  v_new_loop int;
  v_new_home int;
  v_granted_extra boolean;
  v_captured_owner int := -1;
  v_captured_piece int := -1;
  v_winner int;
  v_moves jsonb;
  v_next_player int;
  v_i int;
  v_found boolean;
  v_arr_idx int;
BEGIN
  SELECT * INTO v_game FROM "ashta_chamma_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;

  IF v_game.status <> 'in_progress' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress');
  END IF;

  IF v_game."currentPlayerId" <> auth.uid()::text THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_your_turn');
  END IF;

  IF v_game.phase <> 'move' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'must_roll_first');
  END IF;

  v_board := v_game."boardState";
  v_dice := v_game."lastDiceValue";
  v_current_player := (v_board->>'currentPlayer')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_pieces := v_board->'pieces';

  v_entry_indices := CASE v_player_count
    WHEN 2 THEN ARRAY[0, 28]
    WHEN 3 THEN ARRAY[0, 18, 36]
    ELSE ARRAY[0, 14, 28, 42]
  END;
  v_entry_index := v_entry_indices[v_current_player + 1];

  -- Find the piece
  v_found := false;
  FOR v_i IN 0..jsonb_array_length(v_pieces) - 1 LOOP
    v_piece_obj := v_pieces->v_i;
    IF (v_piece_obj->>'owner')::int = v_current_player
       AND (v_piece_obj->>'index')::int = p_piece_index THEN
      v_piece_obj := jsonb_set(v_piece_obj, '{_arrIdx}', v_i);
      v_found := true;
      EXIT;
    END IF;
  END LOOP;

  IF NOT v_found THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'piece_not_found');
  END IF;

  v_zone := v_piece_obj->>'zone';

  -- Apply the move based on current zone
  IF v_zone = 'base' THEN
    -- Can only enter with dice = 1
    IF v_dice <> 1 THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'need_one_to_enter');
    END IF;
    -- Entry square must not be blocked by 2+ opponent pieces (mirrors
    -- the engine's block rule — the SQL previously skipped this check).
    DECLARE v_entry_blockers int := (
      SELECT count(*) FROM jsonb_array_elements(v_pieces) AS o
      WHERE (o->>'owner')::int <> v_current_player
        AND o->>'zone' = 'loop'
        AND (o->>'loop')::int = v_entry_index);
    BEGIN
      IF v_entry_blockers >= 2 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'entry_blocked');
      END IF;
    END;
    v_piece_obj := jsonb_set(v_piece_obj, '{zone}', '"loop"');
    v_piece_obj := jsonb_set(v_piece_obj, '{loop}', v_entry_index);
  ELSIF v_zone = 'loop' THEN
    v_loop_pos := (v_piece_obj->>'loop')::int;
    v_rel_pos := (v_loop_pos - v_entry_index + 56) % 56;
    v_new_rel := v_rel_pos + v_dice;

    IF v_new_rel < 56 THEN
      -- Still on the loop
      v_new_loop := (v_entry_index + v_new_rel) % 56;
      -- Landing validation + capture (mirrors the engine):
      --   • safe squares (every 4th) can never capture
      --   • 2+ opponent pieces on the destination = block → illegal move
      --   • exactly 1 opponent piece on a non-safe destination = capture
      --     (the opponent's piece is sent back to base)
      DECLARE
        v_occupants jsonb := (
          SELECT COALESCE(jsonb_agg(o), '[]'::jsonb) FROM jsonb_array_elements(v_pieces) AS o
          WHERE (o->>'owner')::int <> v_current_player
            AND o->>'zone' = 'loop'
            AND (o->>'loop')::int = v_new_loop);
        v_occupant_count int;
      BEGIN
        v_occupant_count := jsonb_array_length(v_occupants);
        -- Safe squares: every 4th loop square — no capture, no block.
        IF (v_new_loop % 4) = 0 THEN
          v_occupant_count := 0;
        END IF;
        IF v_occupant_count >= 2 THEN
          RETURN jsonb_build_object('ok', false, 'reason', 'blocked');
        END IF;
        IF v_occupant_count = 1 THEN
          -- Capture: send the opponent's piece back to base.
          DECLARE v_occ jsonb := v_occupants->0;
          BEGIN
            v_captured_owner := (v_occ->>'owner')::int;
            v_captured_piece := (v_occ->>'index')::int;
            FOR v_i IN 0..jsonb_array_length(v_pieces) - 1 LOOP
              IF (v_pieces->v_i->>'owner')::int = v_captured_owner
                 AND (v_pieces->v_i->>'index')::int = v_captured_piece THEN
                DECLARE v_captured jsonb := v_pieces->v_i; BEGIN
                  v_captured := jsonb_set(v_captured, '{zone}', '"base"');
                  v_captured := jsonb_set(v_captured, '{loop}', '(-1)'::text::jsonb);
                  v_captured := jsonb_set(v_captured, '{home}', '(-1)'::text::jsonb);
                  v_pieces := jsonb_set(v_pieces, ARRAY[v_i::text], v_captured);
                END;
                EXIT;
              END IF;
            END LOOP;
          END;
        END IF;
      END;
      v_piece_obj := jsonb_set(v_piece_obj, '{loop}', v_new_loop);
      v_piece_obj := jsonb_set(v_piece_obj, '{zone}', '"loop"');
    ELSIF v_new_rel < 62 THEN
      -- Entered home column
      v_new_home := v_new_rel - 56;
      v_piece_obj := jsonb_set(v_piece_obj, '{home}', v_new_home);
      v_piece_obj := jsonb_set(v_piece_obj, '{zone}', '"homeColumn"');
    ELSIF v_new_rel = 62 THEN
      -- Reached the finish
      v_piece_obj := jsonb_set(v_piece_obj, '{zone}', '"finished"');
      v_piece_obj := jsonb_set(v_piece_obj, '{home}', 6);
    ELSE
      -- Overshoot — illegal
      RETURN jsonb_build_object('ok', false, 'reason', 'overshoot');
    END IF;
  ELSIF v_zone = 'homeColumn' THEN
    v_home_pos := (v_piece_obj->>'home')::int;
    v_new_home := v_home_pos + v_dice;
    IF v_new_home < 6 THEN
      v_piece_obj := jsonb_set(v_piece_obj, '{home}', v_new_home);
    ELSIF v_new_home = 6 THEN
      v_piece_obj := jsonb_set(v_piece_obj, '{zone}', '"finished"');
      v_piece_obj := jsonb_set(v_piece_obj, '{home}', 6);
    ELSE
      RETURN jsonb_build_object('ok', false, 'reason', 'overshoot');
    END IF;
  END IF;

  -- Update the piece in the array
  v_arr_idx := (v_piece_obj->>'_arrIdx')::int;
  v_pieces := jsonb_set(v_pieces, ARRAY[v_arr_idx::text],
    v_piece_obj - '_arrIdx');
  v_board := jsonb_set(v_board, '{pieces}', v_pieces);

  -- Record the move
  v_granted_extra := (v_dice = 4 OR v_dice = 8);
  v_moves := v_board->'moves';
  v_moves := v_moves || jsonb_build_object(
    'player', v_current_player,
    'piece', p_piece_index,
    'dice', v_dice,
    'capturedOwner', v_captured_owner,
    'capturedPiece', v_captured_piece,
    'extra', v_granted_extra
  );
  v_board := jsonb_set(v_board, '{moves}', v_moves);

  -- Reset dice
  v_board := jsonb_set(v_board, '{lastDice}', 0);
  v_board := jsonb_set(v_board, '{hasRolled}', 'false');

  -- Check for a winner (all 4 pieces finished)
  v_winner := -1;
  FOR v_i IN 0..v_player_count - 1 LOOP
    DECLARE
      v_finished_count int;
    BEGIN
      SELECT count(*) INTO v_finished_count
      FROM jsonb_array_elements(v_pieces) AS elem
      WHERE (elem->>'owner')::int = v_i AND elem->>'zone' = 'finished';
      IF v_finished_count = 4 THEN
        v_winner := v_i;
        EXIT;
      END IF;
    END;
  END LOOP;

  IF v_winner >= 0 THEN
    v_board := jsonb_set(v_board, '{winner}', v_winner);
    v_board := jsonb_set(v_board, '{status}', '"completed"');
    UPDATE "ashta_chamma_games" SET
      "boardState" = v_board,
      "lastDiceValue" = 0,
      phase = 'roll',
      status = 'completed',
      "completedAt" = now(),
      "winnerUserIds" = jsonb_build_array(
        v_game."playerOrder" #>> ARRAY[v_winner::text]
      ),
      "endReason" = 'all_home',
      "lastActivityAt" = now()
    WHERE id = p_game_id;
    -- The trigger fn__ashtachamma_on_complete will fire the archive.
    RETURN jsonb_build_object('ok', true, 'winner', v_winner);
  END IF;

  -- Advance the turn (or retain if extra turn granted)
  IF NOT v_granted_extra THEN
    v_next_player := (v_current_player + 1) % v_player_count;
    v_board := jsonb_set(v_board, '{currentPlayer}', v_next_player);
    UPDATE "ashta_chamma_games" SET
      "boardState" = v_board,
      "lastDiceValue" = 0,
      phase = 'roll',
      "currentPlayerId" = "playerOrder"->>v_next_player,
      "currentTurnIndex" = v_next_player,
      "turnEndsAt" = now() + interval '30 seconds',
      "lastActivityAt" = now()
    WHERE id = p_game_id;
  ELSE
    -- Same player rolls again
    UPDATE "ashta_chamma_games" SET
      "boardState" = v_board,
      "lastDiceValue" = 0,
      phase = 'roll',
      "turnEndsAt" = now() + interval '30 seconds',
      "lastActivityAt" = now()
    WHERE id = p_game_id;
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;

