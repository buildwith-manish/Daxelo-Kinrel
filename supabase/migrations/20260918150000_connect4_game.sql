-- =============================================================================
-- 20260918150000_connect4_game.sql
--
-- Connect 4 — classic strategy game on a 7×6 grid.
--
-- Mirrors the memorymatch_games / ashta_chamma_games schema + RPC pattern.
-- The game table stores the full serializable board state as JSONB (6×7
-- grid, current player, move history, winner). RPCs enforce
-- server-authoritative disc drops; clients render from the realtime row.
--
-- The pure game logic lives client-side in connect4_engine.dart. The
-- server applies moves via fn_connect4_drop which mirrors the engine's
-- dropDisc() logic in PL/pgSQL (deterministic).
--
-- Tables:
--   connect4_games   — the game row (status, boardState, turn)
--   connect4_players — the roster (userId, isReady, joinedAt, leftAt)
--
-- RPCs:
--   fn_connect4_start  — host starts; validates 2 players; inits boardState
--   fn_connect4_drop   — current player drops a disc in a column
--   fn_connect4_tick   — 2s watchdog: expires turns, refreshes heartbeat
--   fn_connect4_leave  — mid-game departure
--   fn__connect4_on_complete — TRIGGER fn: fires fn__archive_family_match
-- =============================================================================

-- =============================================================================
-- SECTION 1: Game table
-- =============================================================================

CREATE TABLE IF NOT EXISTS "connect4_games" (
  id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"          TEXT NOT NULL,
  "hostUserId"        TEXT NOT NULL,
  "hostUserName"      TEXT NOT NULL DEFAULT 'Host',
  "roomName"          TEXT,
  status              TEXT NOT NULL DEFAULT 'waiting',
  "maxPlayers"        INTEGER NOT NULL DEFAULT 2,
  "playerOrder"       JSONB NOT NULL DEFAULT '[]'::jsonb,
  "currentPlayerId"   TEXT,
  "currentTurnIndex"  INTEGER NOT NULL DEFAULT 0,
  "turnEndsAt"        TIMESTAMPTZ,
  "boardState"        JSONB,
  "placements"        JSONB NOT NULL DEFAULT '[]'::jsonb,
  "winnerUserIds"     JSONB NOT NULL DEFAULT '[]'::jsonb,
  "endReason"         TEXT,
  "startedAt"         TIMESTAMPTZ,
  "completedAt"       TIMESTAMPTZ,
  "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now(),
  "autoCloseDeadline" TIMESTAMPTZ,
  "cancelledAt"       TIMESTAMPTZ,
  "closedAt"          TIMESTAMPTZ,
  "hostReady"         BOOLEAN DEFAULT true,
  "spectatorsEnabled" BOOLEAN DEFAULT true,
  "lastActivityAt"    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_c4g_family ON "connect4_games" ("familyId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS idx_c4g_status ON "connect4_games" ("status", "lastActivityAt");

CREATE TABLE IF NOT EXISTS "connect4_players" (
  id                TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId"          TEXT NOT NULL REFERENCES "connect4_games"(id) ON DELETE CASCADE,
  "userId"          TEXT NOT NULL,
  "userName"        TEXT NOT NULL,
  "isReady"         BOOLEAN NOT NULL DEFAULT false,
  "readyAt"         TIMESTAMPTZ,
  "joinedAt"        TIMESTAMPTZ NOT NULL DEFAULT now(),
  "lastActivityAt"  TIMESTAMPTZ DEFAULT now(),
  "leftAt"          TIMESTAMPTZ,
  UNIQUE ("gameId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_c4p_game ON "connect4_players" ("gameId", "joinedAt");

-- =============================================================================
-- SECTION 2: RLS policies
-- =============================================================================

ALTER TABLE "connect4_games" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "connect4_games_select_family" ON "connect4_games"
  FOR SELECT TO authenticated
  USING (public.fn_user_is_family_member("familyId"));

CREATE POLICY "connect4_games_insert_host" ON "connect4_games"
  FOR INSERT TO authenticated
  WITH CHECK (
    "hostUserId" = auth.uid()::text
    AND public.fn_user_is_family_member("familyId")
  );

CREATE POLICY "connect4_games_update_family" ON "connect4_games"
  FOR UPDATE TO authenticated
  USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "connect4_players" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "connect4_players_select_family" ON "connect4_players"
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM "connect4_games" g
    WHERE g.id = "connect4_players"."gameId"
      AND public.fn_user_is_family_member(g."familyId")
  ));

CREATE POLICY "connect4_players_insert_self_or_host" ON "connect4_players"
  FOR INSERT TO authenticated
  WITH CHECK (
    "userId" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM "connect4_games" g
      WHERE g.id = "connect4_players"."gameId"
        AND g."hostUserId" = auth.uid()::text
    )
  );

CREATE POLICY "connect4_players_update_self" ON "connect4_players"
  FOR UPDATE TO authenticated
  USING ("userId" = auth.uid()::text);

CREATE POLICY "connect4_players_delete_self" ON "connect4_players"
  FOR DELETE TO authenticated
  USING ("userId" = auth.uid()::text);

-- =============================================================================
-- SECTION 3: Realtime publication
-- =============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE "connect4_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "connect4_players";
ALTER TABLE "connect4_games" REPLICA IDENTITY FULL;
ALTER TABLE "connect4_players" REPLICA IDENTITY FULL;

-- =============================================================================
-- SECTION 4: RPCs
-- =============================================================================

-- fn_connect4_start — host starts the match
CREATE OR REPLACE FUNCTION public.fn_connect4_start(p_game_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game record;
  v_players jsonb;
  v_player_count int;
  v_player_order text[] := ARRAY[]::text[];
  v_board_state jsonb;
  v_empty_board jsonb;
  v_i int;
BEGIN
  SELECT * INTO v_game FROM "connect4_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;

  IF v_game."hostUserId" <> auth.uid()::text THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_host');
  END IF;

  IF v_game.status <> 'waiting' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_started');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('userId', p."userId", 'userName', p."userName")
    ORDER BY p."joinedAt"
  ), '[]'::jsonb) INTO v_players
  FROM "connect4_players" p
  WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;

  v_player_count := jsonb_array_length(v_players);
  IF v_player_count < 2 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players');
  END IF;

  FOR v_i IN 0..v_player_count - 1 LOOP
    v_player_order := array_append(v_player_order, v_players->v_i->>'userId');
  END LOOP;

  -- Build empty 6×7 board (all -1)
  v_empty_board := '[]'::jsonb;
  FOR v_i IN 0..5 LOOP
    v_empty_board := v_empty_board || jsonb_build_array(-1, -1, -1, -1, -1, -1, -1);
  END LOOP;

  v_board_state := jsonb_build_object(
    'board', v_empty_board,
    'currentPlayer', 0,
    'moves', '[]'::jsonb,
    'winner', -1,
    'isDraw', false,
    'winningCells', '[]'::jsonb,
    'status', 'in_progress'
  );

  UPDATE "connect4_games" SET
    status = 'in_progress',
    "playerOrder" = to_jsonb(v_player_order),
    "currentPlayerId" = v_player_order[1],
    "currentTurnIndex" = 0,
    "boardState" = v_board_state,
    "startedAt" = now(),
    "turnEndsAt" = now() + interval '30 seconds',
    "lastActivityAt" = now()
  WHERE id = p_game_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_connect4_start(text) TO authenticated;

-- fn_connect4_drop — current player drops a disc in a column
CREATE OR REPLACE FUNCTION public.fn_connect4_drop(p_game_id text, p_column int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_moves jsonb;
  v_current_player int;
  v_col int := p_column;
  v_row int := -1;
  v_r int;
  v_winner int := -1;
  v_winning_cells jsonb := '[]'::jsonb;
  v_is_draw boolean := false;
  v_next_player int;
  v_cell_val int;
  v_count int;
  v_dr int;
  v_dc int;
  v_rr int;
  v_cc int;
BEGIN
  SELECT * INTO v_game FROM "connect4_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;

  IF v_game.status <> 'in_progress' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress');
  END IF;

  IF v_game."currentPlayerId" <> auth.uid()::text THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_your_turn');
  END IF;

  IF v_col < 0 OR v_col >= 7 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_column');
  END IF;

  v_board := v_game."boardState";
  v_current_player := (v_board->>'currentPlayer')::int;

  -- Find the drop row (lowest empty in this column)
  FOR v_r IN 5..0 LOOP
    IF (v_board->'board'->v_r->v_col)::int = -1 THEN
      v_row := v_r;
      EXIT;
    END IF;
  END LOOP;

  IF v_row < 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'column_full');
  END IF;

  -- Place the disc
  v_board := jsonb_set(v_board, ARRAY['board', v_row::text, v_col::text],
    to_jsonb(v_current_player));

  -- Record the move
  v_moves := v_board->'moves';
  v_moves := v_moves || jsonb_build_object('player', v_current_player, 'col', v_col);
  v_board := jsonb_set(v_board, '{moves}', v_moves);

  -- Check for a winner (4 directions from the placed disc)
  -- Direction vectors: (0,1) horizontal, (1,0) vertical, (1,1) diag ↘, (1,-1) diag ↙
  FOR v_dr IN 0..1 LOOP
    FOR v_dc IN -1..1 LOOP
      IF v_dr = 0 AND v_dc = 0 THEN CONTINUE; END IF;
      IF v_dr = 0 AND v_dc < 0 THEN CONTINUE; END IF; -- skip duplicate horizontal

      v_count := 1;

      -- Positive direction
      v_rr := v_row + v_dr;
      v_cc := v_col + v_dc;
      WHILE v_rr >= 0 AND v_rr < 6 AND v_cc >= 0 AND v_cc < 7 LOOP
        v_cell_val := (v_board->'board'->v_rr->v_cc)::int;
        IF v_cell_val = v_current_player THEN
          v_count := v_count + 1;
          v_rr := v_rr + v_dr;
          v_cc := v_cc + v_dc;
        ELSE
          EXIT;
        END IF;
      END LOOP;

      -- Negative direction
      v_rr := v_row - v_dr;
      v_cc := v_col - v_dc;
      WHILE v_rr >= 0 AND v_rr < 6 AND v_cc >= 0 AND v_cc < 7 LOOP
        v_cell_val := (v_board->'board'->v_rr->v_cc)::int;
        IF v_cell_val = v_current_player THEN
          v_count := v_count + 1;
          v_rr := v_rr - v_dr;
          v_cc := v_cc - v_dc;
        ELSE
          EXIT;
        END IF;
      END LOOP;

      IF v_count >= 4 THEN
        v_winner := v_current_player;
        EXIT;
      END IF;
    END LOOP;
    IF v_winner >= 0 THEN EXIT; END IF;
  END LOOP;

  -- Check for draw (board full = 42 discs)
  IF v_winner < 0 AND jsonb_array_length(v_moves) >= 42 THEN
    v_is_draw := true;
  END IF;

  IF v_winner >= 0 THEN
    -- Game over — winner found
    v_board := jsonb_set(v_board, '{winner}', v_winner);
    v_board := jsonb_set(v_board, '{status}', '"completed"');
    UPDATE "connect4_games" SET
      "boardState" = v_board,
      status = 'completed',
      "completedAt" = now(),
      "winnerUserIds" = jsonb_build_array(
        v_game."playerOrder" #>> ARRAY[v_winner::text]
      ),
      "endReason" = 'four_in_a_row',
      "lastActivityAt" = now()
    WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true, 'winner', v_winner);
  END IF;

  IF v_is_draw THEN
    v_board := jsonb_set(v_board, '{isDraw}', 'true');
    v_board := jsonb_set(v_board, '{status}', '"completed"');
    UPDATE "connect4_games" SET
      "boardState" = v_board,
      status = 'completed',
      "completedAt" = now(),
      "endReason" = 'draw',
      "lastActivityAt" = now()
    WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true, 'draw', true);
  END IF;

  -- Switch turns
  v_next_player := (v_current_player + 1) % 2;
  v_board := jsonb_set(v_board, '{currentPlayer}', v_next_player);
  UPDATE "connect4_games" SET
    "boardState" = v_board,
    "currentPlayerId" = "playerOrder"->>v_next_player,
    "currentTurnIndex" = v_next_player,
    "turnEndsAt" = now() + interval '30 seconds',
    "lastActivityAt" = now()
  WHERE id = p_game_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_connect4_drop(text, int) TO authenticated;

-- fn_connect4_tick — 2s watchdog
CREATE OR REPLACE FUNCTION public.fn_connect4_tick(p_game_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_next_player int;
BEGIN
  SELECT * INTO v_game FROM "connect4_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_game.status <> 'in_progress' THEN RETURN; END IF;

  UPDATE "connect4_players" SET "lastActivityAt" = now()
  WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;

  IF v_game."turnEndsAt" IS NOT NULL AND v_game."turnEndsAt" < now() THEN
    v_board := v_game."boardState";
    v_next_player := ((v_board->>'currentPlayer')::int + 1) % 2;
    v_board := jsonb_set(v_board, '{currentPlayer}', v_next_player);
    UPDATE "connect4_games" SET
      "boardState" = v_board,
      "currentPlayerId" = "playerOrder"->>v_next_player,
      "currentTurnIndex" = v_next_player,
      "turnEndsAt" = now() + interval '30 seconds',
      "lastActivityAt" = now()
    WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_connect4_tick(text) TO authenticated;

-- fn_connect4_leave — mid-game departure
CREATE OR REPLACE FUNCTION public.fn_connect4_leave(p_game_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game record;
  v_active_count int;
BEGIN
  SELECT * INTO v_game FROM "connect4_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;

  UPDATE "connect4_players" SET "leftAt" = now()
  WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;

  SELECT count(*) INTO v_active_count
  FROM "connect4_players"
  WHERE "gameId" = p_game_id AND "leftAt" IS NULL;

  IF v_active_count < 2 AND v_game.status = 'in_progress' THEN
    UPDATE "connect4_games" SET
      status = 'completed',
      "completedAt" = now(),
      "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((
        SELECT jsonb_agg("userId")
        FROM "connect4_players"
        WHERE "gameId" = p_game_id AND "leftAt" IS NULL
      ), '[]'::jsonb),
      "lastActivityAt" = now()
    WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_connect4_leave(text) TO authenticated;

-- =============================================================================
-- SECTION 5: Archive trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn__connect4_on_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN
      PERFORM public.fn__archive_family_match('connect4_games', NEW."id");
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'connect4 archive failed for %: %', NEW."id", SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_connect4_archive ON "connect4_games";
CREATE TRIGGER trg_connect4_archive
  AFTER UPDATE ON "connect4_games"
  FOR EACH ROW
  EXECUTE FUNCTION public.fn__connect4_on_complete();

-- =============================================================================
-- SECTION 6: Whitelist connect4_games in shared functions
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(p_game_table text, p_game_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_game_table NOT IN (
        'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
        'sos_games', 'dotsboxes_games', 'nameplace_games',
        'truthordare_games', 'twotruths_games', 'redlight_rounds',
        'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games',
        'tugofwar_games', 'memorymatch_games', 'ashta_chamma_games',
        'ghost_painter_rounds', 'connect4_games'
    ) THEN
        RAISE EXCEPTION 'Unknown game table: %', p_game_table;
    END IF;
    EXECUTE format(
        'UPDATE public.%I SET "lastActivityAt" = now() WHERE "id" = $1;',
        p_game_table
    ) USING p_game_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_touch_game_activity(text, text) TO authenticated;

-- =============================================================================
-- SECTION 7: Game metadata
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn__game_meta()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'tictactoe_games', jsonb_build_object('id', 'tictactoe', 'name', 'Tic-Tac-Toe', 'icon', '#️⃣', 'accent', '#8B5CF6'),
    'chess_games', jsonb_build_object('id', 'chess', 'name', 'Chess', 'icon', '♟️', 'accent', '#64748B'),
    'checkers_games', jsonb_build_object('id', 'checkers', 'name', 'Checkers', 'icon', '🔴', 'accent', '#6366F1'),
    'carrom_games', jsonb_build_object('id', 'carrom', 'name', 'Carrom', 'icon', '⚪', 'accent', '#F59E0B'),
    'ludo_games', jsonb_build_object('id', 'ludo', 'name', 'Ludo', 'icon', '🎲', 'accent', '#E11D48'),
    'bingo_games', jsonb_build_object('id', 'bingo', 'name', 'Bingo', 'icon', '🎰', 'accent', '#06B6D4'),
    'dotsboxes_games', jsonb_build_object('id', 'dotsboxes', 'name', 'Dots and Boxes', 'icon', '📐', 'accent', '#06B6D4'),
    'truthordare_games', jsonb_build_object('id', 'truthordare', 'name', 'Truth or Dare', 'icon', '🎲', 'accent', '#EF4444'),
    'twotruths_games', jsonb_build_object('id', 'twotruths', 'name', 'Two Truths and a Lie', 'icon', '🤥', 'accent', '#D946EF'),
    'chitmatch_games', jsonb_build_object('id', 'chitmatch', 'name', 'TripleMatch', 'icon', '🎫', 'accent', '#EC4899'),
    'redlight_rounds', jsonb_build_object('id', 'freeze-dash', 'name', 'Freeze & Dash', 'icon', '🚦', 'accent', '#10B981'),
    'ghost_painter_rounds', jsonb_build_object('id', 'ghost-painter', 'name', 'Ghost Painter', 'icon', '👻', 'accent', '#EC4899'),
    'antakshari_games', jsonb_build_object('id', 'antakshari', 'name', 'Antakshari', 'icon', '🎵', 'accent', '#8B5CF6'),
    'nameplace_games', jsonb_build_object('id', 'nameplace', 'name', 'Name, Place, Animal, Thing', 'icon', '📝', 'accent', '#10B981'),
    'sos_games', jsonb_build_object('id', 'sos', 'name', 'SOS', 'icon', '🔤', 'accent', '#F59E0B'),
    'tugofwar_games', jsonb_build_object('id', 'tug-of-war', 'name', 'Tug of War', 'icon', '💪', 'accent', '#E8612A'),
    'memorymatch_games', jsonb_build_object('id', 'memory-match', 'name', 'Memory Match', 'icon', '🧠', 'accent', '#A855F7'),
    'ashta_chamma_games', jsonb_build_object('id', 'ashta-chamma', 'name', 'Ashta Chamma', 'icon', '🐚', 'accent', '#E11D48'),
    'connect4_games', jsonb_build_object('id', 'connect4', 'name', 'Connect 4', 'icon', '🔴', 'accent', '#0EA5E9')
  );
$$;

-- =============================================================================
-- SECTION 8: Champion badge seed
-- =============================================================================

INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt")
VALUES
  (gen_random_uuid()::text,'connect4-master','Connect 4 Master','कनेक्ट 4 मास्टर','Win 5 Connect 4 games','🔴','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;
