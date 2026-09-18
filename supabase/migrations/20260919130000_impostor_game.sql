-- 20260919130000_impostor_game.sql
-- Who's the Impostor? — social deduction party game. 3–10 players.
-- Mirrors connect4_games / memorymatch_games schema + RPC pattern.

CREATE TABLE IF NOT EXISTS "impostor_games" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL, "hostUserId" TEXT NOT NULL, "hostUserName" TEXT NOT NULL DEFAULT 'Host',
  "roomName" TEXT, status TEXT NOT NULL DEFAULT 'waiting', "maxPlayers" INTEGER NOT NULL DEFAULT 10,
  "playerOrder" JSONB NOT NULL DEFAULT '[]'::jsonb, "currentPlayerId" TEXT, "currentTurnIndex" INTEGER NOT NULL DEFAULT 0,
  "turnEndsAt" TIMESTAMPTZ, "boardState" JSONB, "winnerUserIds" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "endReason" TEXT, "startedAt" TIMESTAMPTZ, "completedAt" TIMESTAMPTZ, "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "autoCloseDeadline" TIMESTAMPTZ, "cancelledAt" TIMESTAMPTZ, "closedAt" TIMESTAMPTZ,
  "hostReady" BOOLEAN DEFAULT true, "spectatorsEnabled" BOOLEAN DEFAULT true, "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "totalRounds" INTEGER NOT NULL DEFAULT 3, "wordPackId" TEXT NOT NULL DEFAULT 'food',
  "clueSeconds" INTEGER NOT NULL DEFAULT 30, "voteSeconds" INTEGER NOT NULL DEFAULT 30
);
CREATE INDEX IF NOT EXISTS idx_ig_family ON "impostor_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "impostor_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "impostor_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL, "userName" TEXT NOT NULL,
  "isReady" BOOLEAN NOT NULL DEFAULT false, "readyAt" TIMESTAMPTZ,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(), "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ, UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_ip_game ON "impostor_players" ("gameId", "joinedAt");

ALTER TABLE "impostor_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "impostor_games_select_family" ON "impostor_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "impostor_games_insert_host" ON "impostor_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "impostor_games_update_family" ON "impostor_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "impostor_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "impostor_players_select_family" ON "impostor_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "impostor_games" g WHERE g.id = "impostor_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "impostor_players_insert_self_or_host" ON "impostor_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "impostor_games" g WHERE g.id = "impostor_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "impostor_players_update_self" ON "impostor_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "impostor_players_delete_self" ON "impostor_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "impostor_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "impostor_players";
ALTER TABLE "impostor_games" REPLICA IDENTITY FULL;
ALTER TABLE "impostor_players" REPLICA IDENTITY FULL;

-- fn_impostor_start
CREATE OR REPLACE FUNCTION public.fn_impostor_start(p_game_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_players jsonb; v_player_count int; v_order text[]; v_board jsonb; v_word text; v_impostor int; v_pack record; v_i int;
BEGIN
  SELECT * INTO v_game FROM "impostor_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "impostor_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_player_count := jsonb_array_length(v_players);
  IF v_player_count < 3 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;
  FOR v_i IN 0..v_player_count - 1 LOOP v_order := array_append(v_order, v_players->v_i->>'userId'); END LOOP;
  -- Pick word + impostor
  SELECT * INTO v_pack FROM (SELECT w FROM (VALUES ('food'),('animals'),('places'),('activities'),('family')) AS t(id), LATERAL (
    SELECT CASE t.id WHEN 'food' THEN 'Pizza' WHEN 'animals' THEN 'Tiger' WHEN 'places' THEN 'Beach' WHEN 'activities' THEN 'Cricket' WHEN 'family' THEN 'Birthday' ELSE 'Pizza' END
  ) AS w WHERE t.id = v_game."wordPackId" LIMIT 1) sub LIMIT 1;
  -- Simple word selection — use the first word as a fallback; the client engine handles the full pack
  v_word := COALESCE(v_pack.w, 'Pizza');
  v_impostor := floor(random() * v_player_count)::int;
  v_board := jsonb_build_object('playerCount', v_player_count, 'totalRounds', v_game."totalRounds", 'currentRound', 1,
    'rounds', jsonb_build_array(jsonb_build_object('roundNumber', 1, 'word', v_word, 'impostorIndex', v_impostor, 'wordPackId', v_game."wordPackId", 'phase', 'role_reveal', 'currentCluePlayer', 0, 'clues', '[]'::jsonb, 'votes', '[]'::jsonb, 'winner', null)),
    'scores', (SELECT jsonb_object_agg(i::text, 0) FROM generate_series(0, v_player_count - 1) AS i),
    'status', 'in_progress', 'wordPackId', v_game."wordPackId", 'clueSeconds', v_game."clueSeconds", 'voteSeconds', v_game."voteSeconds");
  UPDATE "impostor_games" SET status = 'in_progress', "playerOrder" = to_jsonb(v_order), "currentPlayerId" = v_order[1],
    "boardState" = v_board, "startedAt" = now(), "turnEndsAt" = now() + (v_game."clueSeconds" || ' seconds')::interval, "lastActivityAt" = now()
  WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_impostor_start(text) TO authenticated;

-- fn_impostor_clue — submit a clue
CREATE OR REPLACE FUNCTION public.fn_impostor_clue(p_game_id text, p_clue text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb; v_player_idx int; v_current_player int; v_clues jsonb; v_player_count int;
BEGIN
  SELECT * INTO v_game FROM "impostor_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_player_idx := (SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = auth.uid()::text);
  IF v_player_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_round := v_board->'rounds'->((v_board->>'currentRound')::int - 1);
  IF v_round->>'phase' <> 'clue' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_clue_phase'); END IF;
  v_current_player := (v_round->>'currentCluePlayer')::int;
  IF v_player_idx <> v_current_player THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_your_turn'); END IF;
  v_clues := v_round->'clues';
  -- Check not already submitted
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_clues) WHERE value->>'player' = v_player_idx::text) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_submitted');
  END IF;
  -- Add clue
  v_clues := v_clues || jsonb_build_object('player', v_player_idx, 'text', p_clue);
  v_round := jsonb_set(v_round, '{clues}', v_clues);
  v_player_count := (v_board->>'playerCount')::int;
  IF jsonb_array_length(v_clues) >= v_player_count THEN
    v_round := jsonb_set(v_round, '{phase}', '"voting"');
  ELSE
    v_round := jsonb_set(v_round, '{currentCluePlayer}', ((v_current_player + 1) % v_player_count)::text::jsonb);
  END IF;
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[((v_board->>'currentRound')::int - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  UPDATE "impostor_games" SET "boardState" = v_board, "turnEndsAt" = CASE WHEN v_round->>'phase' = 'voting' THEN now() + (v_game."voteSeconds" || ' seconds')::interval ELSE now() + (v_game."clueSeconds" || ' seconds')::interval END, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_impostor_clue(text, text) TO authenticated;

-- fn_impostor_vote — submit a vote
CREATE OR REPLACE FUNCTION public.fn_impostor_vote(p_game_id text, p_target_index int) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb; v_voter_idx int; v_votes jsonb; v_player_count int;
BEGIN
  SELECT * INTO v_game FROM "impostor_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_voter_idx := (SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = auth.uid()::text);
  IF v_voter_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_round := v_board->'rounds'->((v_board->>'currentRound')::int - 1);
  IF v_round->>'phase' <> 'voting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_voting_phase'); END IF;
  IF v_voter_idx = p_target_index THEN RETURN jsonb_build_object('ok', false, 'reason', 'cant_vote_self'); END IF;
  v_votes := v_round->'votes';
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_votes) WHERE value->>'voter' = v_voter_idx::text) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_voted');
  END IF;
  v_votes := v_votes || jsonb_build_object('voter', v_voter_idx, 'target', p_target_index);
  v_round := jsonb_set(v_round, '{votes}', v_votes);
  v_player_count := (v_board->>'playerCount')::int;
  -- If all votes in, auto-calculate result
  IF jsonb_array_length(v_votes) >= v_player_count THEN
    v_round := jsonb_set(v_round, '{phase}', '"result"');
    -- TODO: calculate winner (simplified — the advance RPC handles this)
  END IF;
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[((v_board->>'currentRound')::int - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  UPDATE "impostor_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_impostor_vote(text, int) TO authenticated;

-- fn_impostor_advance — advance phase (clue→voting→result→next round)
CREATE OR REPLACE FUNCTION public.fn_impostor_advance(p_game_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb;
  v_current_round int; v_player_count int; v_votes jsonb; v_impostor int;
  v_scores jsonb; v_max_votes int; v_most_voted int; v_is_tie boolean;
  v_winner text; v_total_rounds int; v_i int; v_count int;
  v_max_score int; v_winner_idx int; v_tie boolean; v_s int;
  v_new_word text; v_new_impostor int; v_new_round jsonb;
BEGIN
  SELECT * INTO v_game FROM "impostor_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current_round := (v_board->>'currentRound')::int;
  v_round := v_board->'rounds'->(v_current_round - 1);
  v_player_count := (v_board->>'playerCount')::int;
  v_total_rounds := (v_board->>'totalRounds')::int;

  IF v_round->>'phase' = 'role_reveal' THEN
    v_round := jsonb_set(v_round, '{phase}', '"clue"');
    v_round := jsonb_set(v_round, '{currentCluePlayer}', '0');
  ELSIF v_round->>'phase' = 'clue' THEN
    v_round := jsonb_set(v_round, '{phase}', '"voting"');
  ELSIF v_round->>'phase' = 'voting' THEN
    v_votes := v_round->'votes';
    v_impostor := (v_round->>'impostorIndex')::int;
    v_scores := v_board->'scores';
    v_max_votes := 0; v_most_voted := -1; v_is_tie := false;
    FOR v_i IN 0..v_player_count - 1 LOOP
      SELECT COUNT(*) INTO v_count FROM jsonb_array_elements(v_votes) WHERE (value->>'target')::int = v_i;
      IF v_count > v_max_votes THEN v_max_votes := v_count; v_most_voted := v_i; v_is_tie := false;
      ELSIF v_count = v_max_votes AND v_count > 0 THEN v_is_tie := true; END IF;
    END LOOP;
    IF v_is_tie OR v_most_voted = -1 THEN
      v_winner := 'impostor';
      v_scores := jsonb_set(v_scores, ARRAY[v_impostor::text], ((v_scores->>v_impostor::text)::int + 2)::text::jsonb);
    ELSIF v_most_voted = v_impostor THEN
      v_winner := 'crew';
      FOR v_i IN 0..v_player_count - 1 LOOP
        IF v_i <> v_impostor THEN v_scores := jsonb_set(v_scores, ARRAY[v_i::text], ((v_scores->>v_i::text)::int + 1)::text::jsonb); END IF;
      END LOOP;
    ELSE
      v_winner := 'impostor';
      v_scores := jsonb_set(v_scores, ARRAY[v_impostor::text], ((v_scores->>v_impostor::text)::int + 2)::text::jsonb);
    END IF;
    v_round := jsonb_set(v_round, '{phase}', '"result"');
    v_round := jsonb_set(v_round, '{winner}', to_jsonb(v_winner));
    v_board := jsonb_set(v_board, '{scores}', v_scores);
  ELSIF v_round->>'phase' = 'result' THEN
    IF v_current_round >= v_total_rounds THEN
      v_board := jsonb_set(v_board, '{status}', '"completed"');
      v_max_score := -1; v_winner_idx := -1; v_tie := false;
      FOR v_i IN 0..v_player_count - 1 LOOP
        v_s := (v_board->'scores'->>v_i::text)::int;
        IF v_s > v_max_score THEN v_max_score := v_s; v_winner_idx := v_i; v_tie := false;
        ELSIF v_s = v_max_score THEN v_tie := true; END IF;
      END LOOP;
      UPDATE "impostor_games" SET "boardState" = v_board, status = 'completed', "completedAt" = now(),
        "winnerUserIds" = CASE WHEN NOT v_tie AND v_winner_idx >= 0 THEN jsonb_build_array(v_game."playerOrder"->>v_winner_idx::text) ELSE '[]'::jsonb END,
        "endReason" = 'match_complete', "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true, 'finished', true);
    ELSE
      v_new_impostor := floor(random() * v_player_count)::int;
      v_new_word := CASE floor(random() * 5)::int WHEN 0 THEN 'Pizza' WHEN 1 THEN 'Tiger' WHEN 2 THEN 'Beach' WHEN 3 THEN 'Cricket' ELSE 'Birthday' END;
      v_new_round := jsonb_build_object('roundNumber', v_current_round + 1, 'word', v_new_word, 'impostorIndex', v_new_impostor, 'wordPackId', v_board->>'wordPackId', 'phase', 'role_reveal', 'currentCluePlayer', 0, 'clues', '[]'::jsonb, 'votes', '[]'::jsonb, 'winner', null);
      v_rounds := v_board->'rounds' || v_new_round;
      v_board := jsonb_set(v_board, '{rounds}', v_rounds);
      v_board := jsonb_set(v_board, '{currentRound}', (v_current_round + 1)::text::jsonb);
    END IF;
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_phase');
  END IF;

  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current_round - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  UPDATE "impostor_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_impostor_advance(text) TO authenticated;

-- fn_impostor_tick — 2s watchdog
CREATE OR REPLACE FUNCTION public.fn_impostor_tick(p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record;
BEGIN
  SELECT * INTO v_game FROM "impostor_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "impostor_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_game."turnEndsAt" IS NOT NULL AND v_game."turnEndsAt" < now() THEN
    PERFORM public.fn_impostor_advance(p_game_id);
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_impostor_tick(text) TO authenticated;

-- fn_impostor_leave
CREATE OR REPLACE FUNCTION public.fn_impostor_leave(p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_active int;
BEGIN
  SELECT * INTO v_game FROM "impostor_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "impostor_players" SET "leftAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  SELECT count(*) INTO v_active FROM "impostor_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
  IF v_active < 3 AND v_game.status = 'in_progress' THEN
    UPDATE "impostor_games" SET status = 'completed', "completedAt" = now(), "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((SELECT jsonb_agg("userId") FROM "impostor_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL), '[]'::jsonb),
      "lastActivityAt" = now() WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_impostor_leave(text) TO authenticated;

-- Archive trigger
CREATE OR REPLACE FUNCTION public.fn__impostor_on_complete() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('impostor_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'impostor archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_impostor_archive ON "impostor_games";
CREATE TRIGGER trg_impostor_archive AFTER UPDATE ON "impostor_games" FOR EACH ROW EXECUTE FUNCTION public.fn__impostor_on_complete();

-- Whitelist + metadata
CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(p_game_table text, p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_game_table NOT IN ('antakshari_games','chitmatch_games','bingo_games','ludo_games','sos_games','dotsboxes_games','nameplace_games','truthordare_games','twotruths_games','redlight_rounds','chess_games','tictactoe_games','checkers_games','carrom_games','tugofwar_games','memorymatch_games','ashta_chamma_games','ghost_painter_rounds','connect4_games','impostor_games') THEN
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
    'impostor_games', jsonb_build_object('id','impostor','name','Who''s the Impostor?','icon','🕵️','accent','#8B5CF6')
  );
$$;

INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'impostor-master','Impostor Master','इम्पोस्टर मास्टर','Win 5 Impostor games','🕵️','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;
