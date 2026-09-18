-- 20260919150000_color_trap_game.sql
-- Color Trap — last-player-standing on colored tile grid. 2–8 players.

CREATE TABLE IF NOT EXISTS "color_trap_games" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL, "hostUserId" TEXT NOT NULL, "hostUserName" TEXT NOT NULL DEFAULT 'Host',
  "roomName" TEXT, status TEXT NOT NULL DEFAULT 'waiting', "maxPlayers" INTEGER NOT NULL DEFAULT 8,
  "playerOrder" JSONB NOT NULL DEFAULT '[]'::jsonb, "currentPlayerId" TEXT, "currentTurnIndex" INTEGER NOT NULL DEFAULT 0,
  "turnEndsAt" TIMESTAMPTZ, "boardState" JSONB, "winnerUserIds" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "endReason" TEXT, "startedAt" TIMESTAMPTZ, "completedAt" TIMESTAMPTZ, "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "autoCloseDeadline" TIMESTAMPTZ, "cancelledAt" TIMESTAMPTZ, "closedAt" TIMESTAMPTZ,
  "hostReady" BOOLEAN DEFAULT true, "spectatorsEnabled" BOOLEAN DEFAULT true, "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  difficulty TEXT NOT NULL DEFAULT 'medium'
);
CREATE INDEX IF NOT EXISTS idx_ctg_family ON "color_trap_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "color_trap_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "color_trap_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL, "userName" TEXT NOT NULL,
  "isReady" BOOLEAN NOT NULL DEFAULT false, "readyAt" TIMESTAMPTZ,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(), "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ, UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_ctp_game ON "color_trap_players" ("gameId", "joinedAt");

ALTER TABLE "color_trap_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "color_trap_games_select_family" ON "color_trap_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "color_trap_games_insert_host" ON "color_trap_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "color_trap_games_update_family" ON "color_trap_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "color_trap_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "color_trap_players_select_family" ON "color_trap_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "color_trap_games" g WHERE g.id = "color_trap_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "color_trap_players_insert_self_or_host" ON "color_trap_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "color_trap_games" g WHERE g.id = "color_trap_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "color_trap_players_update_self" ON "color_trap_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "color_trap_players_delete_self" ON "color_trap_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "color_trap_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "color_trap_players";
ALTER TABLE "color_trap_games" REPLICA IDENTITY FULL;
ALTER TABLE "color_trap_players" REPLICA IDENTITY FULL;

-- fn_colortrap_start
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
      v_players_arr := v_players_arr || jsonb_build_object('idx', v_i, 'userId', v_players->v_i->>'userId', 'name', v_players->v_i->>'userName', 'r', (v_i // 2) * (v_size // 2), 'c', (v_i % 2) * (v_size - 1), 'alive', true, 'elim', -1);
    END LOOP;
    v_board := jsonb_build_object('playerCount', v_count, 'difficulty', v_difficulty, 'currentRound', 1,
      'rounds', jsonb_build_array(jsonb_build_object('round', 1, 'target', v_target, 'tiles', v_tiles, 'size', v_size, 'phase', 'arenaShown', 'countdown', 0)),
      'players', v_players_arr, 'status', 'in_progress', 'winner', -1);
  END;
  UPDATE "color_trap_games" SET status = 'in_progress', "playerOrder" = to_jsonb(v_order), "boardState" = v_board, "startedAt" = now(), "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_colortrap_start(text) TO authenticated;

-- fn_colortrap_move — player moves to a tile
CREATE OR REPLACE FUNCTION public.fn_colortrap_move(p_game_id text, p_row int, p_col int) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb; v_player_idx int; v_size int; v_players jsonb; v_phase text;
BEGIN
  SELECT * INTO v_game FROM "color_trap_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_player_idx := (SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = auth.uid()::text);
  IF v_player_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_round := v_board->'rounds'->((v_board->>'currentRound')::int - 1);
  v_phase := v_round->>'phase';
  IF v_phase = 'elimination' OR v_phase = 'roundEnd' THEN RETURN jsonb_build_object('ok', false, 'reason', 'wrong_phase'); END IF;
  v_size := (v_round->>'size')::int;
  IF p_row < 0 OR p_row >= v_size OR p_col < 0 OR p_col >= v_size THEN RETURN jsonb_build_object('ok', false, 'reason', 'out_of_bounds'); END IF;
  v_players := v_board->'players';
  v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'r'], p_row::text::jsonb);
  v_players := jsonb_set(v_players, ARRAY[v_player_idx::text, 'c'], p_col::text::jsonb);
  v_board := jsonb_set(v_board, '{players}', v_players);
  UPDATE "color_trap_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_colortrap_move(text, int, int) TO authenticated;

-- fn_colortrap_advance — advance phase (arenaShown→colorAnnounced→countdown→elimination→nextRound)
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
  ELSIF v_phase = 'colorAnnounced' THEN
    v_round := jsonb_set(v_round, '{phase}', '"countdown"');
  ELSIF v_phase = 'countdown' THEN
    -- Eliminate
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
    v_new_round := jsonb_build_object('round', v_current + 1, 'target', v_target, 'tiles', v_tiles, 'size', v_size, 'phase', 'arenaShown', 'countdown', 0);
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
GRANT EXECUTE ON FUNCTION public.fn_colortrap_advance(text) TO authenticated;

-- fn_colortrap_tick — 2s watchdog (auto-advance countdown)
CREATE OR REPLACE FUNCTION public.fn_colortrap_tick(p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_board jsonb; v_round jsonb; v_phase text; v_countdown int;
BEGIN
  SELECT * INTO v_game FROM "color_trap_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "color_trap_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  v_board := v_game."boardState";
  v_round := v_board->'rounds'->((v_board->>'currentRound')::int - 1);
  v_phase := v_round->>'phase';
  v_countdown := (v_round->>'countdown')::int;
  IF v_phase = 'countdown' AND v_countdown > 0 THEN
    v_countdown := v_countdown - 1;
    v_round := jsonb_set(v_round, '{countdown}', v_countdown::text::jsonb);
    DECLARE v_rounds jsonb := jsonb_set(v_board->'rounds', ARRAY[((v_board->>'currentRound')::int - 1)::text], v_round);
    BEGIN
      v_board := jsonb_set(v_board, '{rounds}', v_rounds);
      UPDATE "color_trap_games" SET "boardState" = v_board WHERE id = p_game_id;
    END;
    IF v_countdown <= 0 THEN PERFORM public.fn_colortrap_advance(p_game_id); END IF;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_colortrap_tick(text) TO authenticated;

-- fn_colortrap_leave
CREATE OR REPLACE FUNCTION public.fn_colortrap_leave(p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_active int;
BEGIN
  SELECT * INTO v_game FROM "color_trap_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "color_trap_players" SET "leftAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  SELECT count(*) INTO v_active FROM "color_trap_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
  IF v_active < 2 AND v_game.status = 'in_progress' THEN
    UPDATE "color_trap_games" SET status = 'completed', "completedAt" = now(), "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((SELECT jsonb_agg("userId") FROM "color_trap_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL), '[]'::jsonb),
      "lastActivityAt" = now() WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_colortrap_leave(text) TO authenticated;

-- Archive trigger
CREATE OR REPLACE FUNCTION public.fn__colortrap_on_complete() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('color_trap_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'colortrap archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_colortrap_archive ON "color_trap_games";
CREATE TRIGGER trg_colortrap_archive AFTER UPDATE ON "color_trap_games" FOR EACH ROW EXECUTE FUNCTION public.fn__colortrap_on_complete();

-- Whitelists
CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(p_game_table text, p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_game_table NOT IN ('antakshari_games','chitmatch_games','bingo_games','ludo_games','sos_games','dotsboxes_games','nameplace_games','truthordare_games','twotruths_games','redlight_rounds','chess_games','tictactoe_games','checkers_games','carrom_games','tugofwar_games','memorymatch_games','ashta_chamma_games','ghost_painter_rounds','connect4_games','impostor_games','color_trap_games') THEN
    RAISE EXCEPTION 'Unknown game table: %', p_game_table; END IF;
  EXECUTE format('UPDATE public.%I SET "lastActivityAt" = now() WHERE "id" = $1;', p_game_table) USING p_game_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_touch_game_activity(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn__game_meta() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
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
    'impostor_games', jsonb_build_object('id','impostor','name','Impostor','icon','🕵️','accent','#8B5CF6'),
    'color_trap_games', jsonb_build_object('id','color-trap','name','Color Trap','icon','🎨','accent','#F59E0B')
  );
$$;

INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'colortrap-master','Color Trap Master','कलर ट्रैप मास्टर','Win 5 Color Trap games','🎨','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;
