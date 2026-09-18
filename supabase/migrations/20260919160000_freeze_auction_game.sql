-- 20260919160000_freeze_auction_game.sql
-- Freeze Auction — mystery crate bidding game. 2–8 players.

CREATE TABLE IF NOT EXISTS "freeze_auction_games" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL, "hostUserId" TEXT NOT NULL, "hostUserName" TEXT NOT NULL DEFAULT 'Host',
  "roomName" TEXT, status TEXT NOT NULL DEFAULT 'waiting', "maxPlayers" INTEGER NOT NULL DEFAULT 8,
  "playerOrder" JSONB NOT NULL DEFAULT '[]'::jsonb, "currentPlayerId" TEXT, "currentTurnIndex" INTEGER NOT NULL DEFAULT 0,
  "turnEndsAt" TIMESTAMPTZ, "boardState" JSONB, "winnerUserIds" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "endReason" TEXT, "startedAt" TIMESTAMPTZ, "completedAt" TIMESTAMPTZ, "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "autoCloseDeadline" TIMESTAMPTZ, "cancelledAt" TIMESTAMPTZ, "closedAt" TIMESTAMPTZ,
  "hostReady" BOOLEAN DEFAULT true, "spectatorsEnabled" BOOLEAN DEFAULT true, "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "totalRounds" INTEGER NOT NULL DEFAULT 5, "startingCoins" INTEGER NOT NULL DEFAULT 100, "itemPoolId" TEXT NOT NULL DEFAULT 'normal'
);
CREATE INDEX IF NOT EXISTS idx_fag_family ON "freeze_auction_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "freeze_auction_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "freeze_auction_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL, "userName" TEXT NOT NULL,
  "isReady" BOOLEAN NOT NULL DEFAULT false, "readyAt" TIMESTAMPTZ,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(), "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ, UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_fap_game ON "freeze_auction_players" ("gameId", "joinedAt");

ALTER TABLE "freeze_auction_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "freeze_auction_games_select_family" ON "freeze_auction_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "freeze_auction_games_insert_host" ON "freeze_auction_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "freeze_auction_games_update_family" ON "freeze_auction_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "freeze_auction_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "freeze_auction_players_select_family" ON "freeze_auction_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "freeze_auction_games" g WHERE g.id = "freeze_auction_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "freeze_auction_players_insert_self_or_host" ON "freeze_auction_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "freeze_auction_games" g WHERE g.id = "freeze_auction_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "freeze_auction_players_update_self" ON "freeze_auction_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "freeze_auction_players_delete_self" ON "freeze_auction_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "freeze_auction_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "freeze_auction_players";
ALTER TABLE "freeze_auction_games" REPLICA IDENTITY FULL;
ALTER TABLE "freeze_auction_players" REPLICA IDENTITY FULL;

-- fn_freezeauction_start
CREATE OR REPLACE FUNCTION public.fn_freezeauction_start(p_game_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_players jsonb; v_count int; v_order text[]; v_board jsonb; v_item jsonb; v_pool jsonb; v_idx int; v_players_arr jsonb;
BEGIN
  SELECT * INTO v_game FROM "freeze_auction_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "freeze_auction_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_count := jsonb_array_length(v_players);
  IF v_count < 2 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;
  FOR v_idx IN 0..v_count - 1 LOOP v_order := array_append(v_order, v_players->v_idx->>'userId'); END LOOP;
  -- Pick random item from pool
  v_pool := CASE v_game."itemPoolId" WHEN 'chaos' THEN '["i-add10","i-add50","i-double","i-steal25","i-freeze","i-nothing","i-lose50","i-bankrupt"]'::jsonb WHEN 'legendary' THEN '["i-add50","i-add75","i-double","i-triple","i-jackpot","i-shield","i-mult"]'::jsonb ELSE '["i-add10","i-add20","i-add30","i-add50","i-add75","i-double","i-steal25","i-shield","i-mult","i-nothing","i-lose25","i-lose50","i-bankrupt"]'::jsonb END;
  v_idx := floor(random() * jsonb_array_length(v_pool))::int;
  -- Build a simplified item jsonb
  v_item := jsonb_build_object('id', v_pool->v_idx, 'name', 'Mystery Crate', 'rarity', 'common', 'effect', 'addCoins', 'value', 25, 'desc', '?');
  -- Build players array
  v_players_arr := '[]'::jsonb;
  FOR v_idx IN 0..v_count - 1 LOOP
    v_players_arr := v_players_arr || jsonb_build_object('idx', v_idx, 'userId', v_players->v_idx->>'userId', 'name', v_players->v_idx->>'userName', 'coins', v_game."startingCoins", 'alive', true, 'shield', false, 'mult', false, 'frozen', false);
  END LOOP;
  v_board := jsonb_build_object('playerCount', v_count, 'totalRounds', v_game."totalRounds", 'startingCoins', v_game."startingCoins", 'itemPoolId', v_game."itemPoolId", 'currentRound', 1, 'rounds', jsonb_build_array(jsonb_build_object('round', 1, 'item', v_item, 'final', v_game."totalRounds" = 1, 'phase', 'bidding', 'bids', '[]'::jsonb, 'winner', -1, 'winBid', 0)), 'players', v_players_arr, 'status', 'in_progress', 'winner', -1);
  UPDATE "freeze_auction_games" SET status = 'in_progress', "playerOrder" = to_jsonb(v_order), "boardState" = v_board, "startedAt" = now(), "turnEndsAt" = now() + interval '30 seconds', "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_freezeauction_start(text) TO authenticated;

-- fn_freezeauction_bid
CREATE OR REPLACE FUNCTION public.fn_freezeauction_bid(p_game_id text, p_amount int) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb; v_player_idx int; v_players jsonb; v_coins int; v_frozen boolean;
BEGIN
  SELECT * INTO v_game FROM "freeze_auction_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_player_idx := (SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = auth.uid()::text);
  IF v_player_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_round := v_board->'rounds'->((v_board->>'currentRound')::int - 1);
  IF v_round->>'phase' <> 'bidding' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_bidding_phase'); END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_round->'bids') WHERE value->>'p' = v_player_idx::text) THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_bid'); END IF;
  v_players := v_board->'players';
  v_coins := (v_players->v_player_idx->>'coins')::int;
  v_frozen := (v_players->v_player_idx->>'frozen')::boolean;
  IF p_amount > v_coins THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_coins'); END IF;
  IF v_frozen AND p_amount > 25 THEN RETURN jsonb_build_object('ok', false, 'reason', 'frozen_max_25'); END IF;
  v_round := jsonb_set(v_round, '{bids}', (v_round->'bids') || jsonb_build_object('p', v_player_idx, 'amt', p_amount, 'ts', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[((v_board->>'currentRound')::int - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);
  UPDATE "freeze_auction_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_freezeauction_bid(text, int) TO authenticated;

-- fn_freezeauction_advance — lock bids, determine winner, reveal, advance
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
        -- Apply effect to winner's coins
        IF v_effect = 'addCoins' THEN v_coins := v_coins + v_value; v_desc := '+' || v_value || ' coins';
        ELSIF v_effect = 'jackpot' THEN v_coins := v_coins + v_value; v_desc := 'JACKPOT! +' || v_value || ' coins';
        ELSIF v_effect = 'doubleCoins' THEN v_coins := v_coins * 2; v_desc := 'Coins doubled!';
        ELSIF v_effect = 'tripleCoins' THEN v_coins := v_coins * 3; v_desc := 'Coins tripled!';
        ELSIF v_effect = 'stealCoins' THEN v_coins := v_coins + v_value; v_desc := 'Stole ' || v_value || ' coins';
        ELSIF v_effect = 'shield' THEN v_shield := true; v_desc := 'Shield activated!';
        ELSIF v_effect = 'multiplier' THEN v_desc := 'Next reward x2!';
        ELSIF v_effect = 'freeze' THEN v_desc := 'Froze a random player';
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
GRANT EXECUTE ON FUNCTION public.fn_freezeauction_advance(text) TO authenticated;

-- fn_freezeauction_tick
CREATE OR REPLACE FUNCTION public.fn_freezeauction_tick(p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record;
BEGIN
  SELECT * INTO v_game FROM "freeze_auction_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "freeze_auction_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_game."turnEndsAt" IS NOT NULL AND v_game."turnEndsAt" < now() THEN PERFORM public.fn_freezeauction_advance(p_game_id); END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_freezeauction_tick(text) TO authenticated;

-- fn_freezeauction_leave
CREATE OR REPLACE FUNCTION public.fn_freezeauction_leave(p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_active int;
BEGIN
  SELECT * INTO v_game FROM "freeze_auction_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "freeze_auction_players" SET "leftAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  SELECT count(*) INTO v_active FROM "freeze_auction_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
  IF v_active < 2 AND v_game.status = 'in_progress' THEN
    UPDATE "freeze_auction_games" SET status = 'completed', "completedAt" = now(), "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((SELECT jsonb_agg("userId") FROM "freeze_auction_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL), '[]'::jsonb),
      "lastActivityAt" = now() WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_freezeauction_leave(text) TO authenticated;

-- Archive trigger
CREATE OR REPLACE FUNCTION public.fn__freezeauction_on_complete() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('freeze_auction_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'freezeauction archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_freezeauction_archive ON "freeze_auction_games";
CREATE TRIGGER trg_freezeauction_archive AFTER UPDATE ON "freeze_auction_games" FOR EACH ROW EXECUTE FUNCTION public.fn__freezeauction_on_complete();

-- Whitelists
CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(p_game_table text, p_game_id text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_game_table NOT IN ('antakshari_games','chitmatch_games','bingo_games','ludo_games','sos_games','dotsboxes_games','nameplace_games','truthordare_games','twotruths_games','redlight_rounds','chess_games','tictactoe_games','checkers_games','carrom_games','tugofwar_games','memorymatch_games','ashta_chamma_games','ghost_painter_rounds','connect4_games','impostor_games','color_trap_games','freeze_auction_games') THEN
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
    'color_trap_games', jsonb_build_object('id','color-trap','name','Color Trap','icon','🎨','accent','#F59E0B'),
    'freeze_auction_games', jsonb_build_object('id','freeze-auction','name','Freeze Auction','icon','📦','accent','#F59E0B')
  );
$$;

INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'auction-master','Auction Master','नीलामी मास्टर','Win 5 Freeze Auction games','📦','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;
