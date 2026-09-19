-- 20260921020000_stickman_heist_game.sql
-- Stickman Heist — real-time 2D multiplayer treasure-hunt shooter.
--
-- Uses a host-authoritative model: the host's client runs the Forge2D
-- physics simulation and broadcasts the full game state (~10Hz) via
-- Supabase Realtime. Other clients send their inputs to the host via
-- a separate table, and render the state they receive.
--
-- Match flow: lobby → searching → carrierActive → escapePhase → completed
-- One treasure spawns randomly. Player who collects it becomes the
-- carrier (revealed to all). Carrier must reach an escape zone to win.
-- If carrier is eliminated, treasure drops and anyone can pick it up.

CREATE TABLE IF NOT EXISTS "stickman_heist_games" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "hostUserId" TEXT NOT NULL,
  "hostUserName" TEXT NOT NULL DEFAULT 'Host',
  "roomName" TEXT,
  status TEXT NOT NULL DEFAULT 'waiting',
  "maxPlayers" INTEGER NOT NULL DEFAULT 8,
  "playerOrder" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "boardState" JSONB,
  "winnerUserIds" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "endReason" TEXT,
  "startedAt" TIMESTAMPTZ,
  "completedAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "autoCloseDeadline" TIMESTAMPTZ,
  "cancelledAt" TIMESTAMPTZ,
  "closedAt" TIMESTAMPTZ,
  "hostReady" BOOLEAN DEFAULT true,
  "spectatorsEnabled" BOOLEAN NOT NULL DEFAULT true,
  "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  -- Game-specific config
  "mapId" TEXT NOT NULL DEFAULT 'bank',
  "respawnsEnabled" BOOLEAN NOT NULL DEFAULT true,
  "matchSeconds" INTEGER NOT NULL DEFAULT 180,
  "lastStateBroadcast" TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_shg_family ON "stickman_heist_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "stickman_heist_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "stickman_heist_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "userName" TEXT NOT NULL,
  "isReady" BOOLEAN NOT NULL DEFAULT false,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ,
  UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_shp_game ON "stickman_heist_players" ("gameId", "joinedAt");

-- Real-time input table: non-host players write their inputs here.
-- The host reads them and applies to the simulation. RLS: each player
-- can only write their own input row.
CREATE TABLE IF NOT EXISTS "stickman_heist_inputs" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "stickman_heist_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "moveX" REAL NOT NULL DEFAULT 0,
  "moveY" REAL NOT NULL DEFAULT 0,
  "aimAngle" REAL NOT NULL DEFAULT 0,
  "shooting" BOOLEAN NOT NULL DEFAULT false,
  "reloadRequested" BOOLEAN NOT NULL DEFAULT false,
  "swapWeaponRequested" BOOLEAN NOT NULL DEFAULT false,
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_shi_game ON "stickman_heist_inputs" ("gameId");

ALTER TABLE "stickman_heist_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "stickman_heist_games_select_family" ON "stickman_heist_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "stickman_heist_games_insert_host" ON "stickman_heist_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "stickman_heist_games_update_family" ON "stickman_heist_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "stickman_heist_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "stickman_heist_players_select_family" ON "stickman_heist_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "stickman_heist_games" g WHERE g.id = "stickman_heist_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "stickman_heist_players_insert_self_or_host" ON "stickman_heist_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "stickman_heist_games" g WHERE g.id = "stickman_heist_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "stickman_heist_players_update_self" ON "stickman_heist_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "stickman_heist_players_delete_self" ON "stickman_heist_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER TABLE "stickman_heist_inputs" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "stickman_heist_inputs_select_all" ON "stickman_heist_inputs" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "stickman_heist_games" g WHERE g.id = "stickman_heist_inputs"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "stickman_heist_inputs_upsert_own" ON "stickman_heist_inputs" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "stickman_heist_inputs_update_own" ON "stickman_heist_inputs" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "stickman_heist_inputs_delete_own" ON "stickman_heist_inputs" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "stickman_heist_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "stickman_heist_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "stickman_heist_inputs";
ALTER TABLE "stickman_heist_games" REPLICA IDENTITY FULL;
ALTER TABLE "stickman_heist_players" REPLICA IDENTITY FULL;
ALTER TABLE "stickman_heist_inputs" REPLICA IDENTITY FULL;

-- fn_stickmanheist_start
CREATE OR REPLACE FUNCTION public.fn_stickmanheist_start(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_players jsonb; v_count int; v_order text[]; v_i int;
  v_board jsonb; v_players_arr jsonb;
  v_treasure_x real; v_treasure_y real;
  v_spawn_x real; v_spawn_y real;
BEGIN
  SELECT * INTO v_game FROM "stickman_heist_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "stickman_heist_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_count := jsonb_array_length(v_players);
  IF v_count < 2 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;
  FOR v_i IN 0..v_count - 1 LOOP v_order := array_append(v_order, v_players->v_i->>'userId'); END LOOP;
  -- Random treasure position (center area of map)
  v_treasure_x := (random() - 0.5) * 4.0;
  v_treasure_y := (random() - 0.5) * 4.0;
  v_players_arr := '[]'::jsonb;
  FOR v_i IN 0..v_count - 1 LOOP
    v_spawn_x := (random() - 0.5) * 8.0;
    v_spawn_y := (random() - 0.5) * 8.0;
    v_players_arr := v_players_arr || jsonb_build_object(
      'idx', v_i,
      'userId', v_players->v_i->>'userId',
      'name', v_players->v_i->>'userName',
      'x', v_spawn_x,
      'y', v_spawn_y,
      'angle', 0.0,
      'health', 100,
      'maxHealth', 100,
      'isAlive', true,
      'weapon', 'pistol',
      'ammo', 12,
      'maxAmmo', 12,
      'isReloading', false,
      'hasTreasure', false,
      'kills', 0,
      'deaths', 0,
      'respawnAt', null
    );
  END LOOP;
  v_board := jsonb_build_object(
    'playerCount', v_count,
    'mapId', v_game."mapId",
    'respawnsEnabled', v_game."respawnsEnabled",
    'matchSeconds', v_game."matchSeconds",
    'matchTimeRemaining', v_game."matchSeconds",
    'phase', 'searching',
    'treasure', jsonb_build_object('x', v_treasure_x, 'y', v_treasure_y, 'carrierIdx', -1, 'collected', false),
    'escapeZones', jsonb_build_array(
      jsonb_build_object('x', -9.0, 'y', -9.0, 'radius', 1.5, 'active', false, 'label', 'SW'),
      jsonb_build_object('x', 9.0, 'y', -9.0, 'radius', 1.5, 'active', false, 'label', 'SE'),
      jsonb_build_object('x', -9.0, 'y', 9.0, 'radius', 1.5, 'active', false, 'label', 'NW'),
      jsonb_build_object('x', 9.0, 'y', 9.0, 'radius', 1.5, 'active', false, 'label', 'NE')
    ),
    'weaponSpawns', jsonb_build_array(
      jsonb_build_object('x', -4.0, 'y', 0.0, 'weapon', 'shotgun', 'taken', false),
      jsonb_build_object('x', 4.0, 'y', 0.0, 'weapon', 'smg', 'taken', false),
      jsonb_build_object('x', 0.0, 'y', -4.0, 'weapon', 'sniper', 'taken', false),
      jsonb_build_object('x', 0.0, 'y', 4.0, 'weapon', 'shotgun', 'taken', false),
      jsonb_build_object('x', -5.0, 'y', -5.0, 'weapon', 'smg', 'taken', false),
      jsonb_build_object('x', 5.0, 'y', 5.0, 'weapon', 'sniper', 'taken', false)
    ),
    'powerupSpawns', jsonb_build_array(
      jsonb_build_object('x', -3.0, 'y', 3.0, 'type', 'health', 'taken', false),
      jsonb_build_object('x', 3.0, 'y', -3.0, 'type', 'ammo', 'taken', false),
      jsonb_build_object('x', -3.0, 'y', -3.0, 'type', 'shield', 'taken', false),
      jsonb_build_object('x', 3.0, 'y', 3.0, 'type', 'speed', 'taken', false)
    ),
    'projectiles', '[]'::jsonb,
    'events', '[]'::jsonb,
    'players', v_players_arr,
    'status', 'in_progress',
    'winnerIdx', -1,
    'matchStartTime', extract(epoch from now())::bigint
  );
  UPDATE "stickman_heist_games" SET status = 'in_progress', "playerOrder" = to_jsonb(v_order),
    "boardState" = v_board, "startedAt" = now(),
    "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_stickmanheist_start(text) TO authenticated;

-- fn_stickmanheist_broadcast_state — host broadcasts the current sim state
CREATE OR REPLACE FUNCTION public.fn_stickmanheist_broadcast_state(p_game_id text, p_state jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record;
BEGIN
  SELECT * INTO v_game FROM "stickman_heist_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  UPDATE "stickman_heist_games" SET "boardState" = p_state,
    "lastStateBroadcast" = now(),
    "lastActivityAt" = now(),
    status = CASE WHEN (p_state->>'status') = 'completed' THEN 'completed' ELSE status END,
    "completedAt" = CASE WHEN (p_state->>'status') = 'completed' THEN now() ELSE "completedAt" END,
    "winnerUserIds" = CASE
      WHEN (p_state->>'status') = 'completed' AND (p_state->>'winnerIdx')::int >= 0
      THEN jsonb_build_array(v_game."playerOrder"->>((p_state->>'winnerIdx')::int))
      ELSE "winnerUserIds" END,
    "endReason" = CASE WHEN (p_state->>'status') = 'completed' THEN 'escape' ELSE "endReason" END
  WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_stickmanheist_broadcast_state(text, jsonb) TO authenticated;

-- fn_stickmanheist_leave
CREATE OR REPLACE FUNCTION public.fn_stickmanheist_leave(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_active int;
BEGIN
  SELECT * INTO v_game FROM "stickman_heist_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "stickman_heist_players" SET "leftAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  SELECT count(*) INTO v_active FROM "stickman_heist_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
  IF v_active < 2 AND v_game.status = 'in_progress' THEN
    UPDATE "stickman_heist_games" SET status = 'completed', "completedAt" = now(), "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((SELECT jsonb_agg("userId") FROM "stickman_heist_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL), '[]'::jsonb),
      "lastActivityAt" = now() WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_stickmanheist_leave(text) TO authenticated;

-- Archive trigger
CREATE OR REPLACE FUNCTION public.fn__stickmanheist_on_complete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('stickman_heist_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'stickmanheist archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_stickmanheist_archive ON "stickman_heist_games";
CREATE TRIGGER trg_stickmanheist_archive AFTER UPDATE ON "stickman_heist_games"
  FOR EACH ROW EXECUTE FUNCTION public.fn__stickmanheist_on_complete();

CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(p_game_table text, p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games','sos_games',
    'dotsboxes_games','nameplace_games','truthordare_games','twotruths_games',
    'redlight_rounds','chess_games','tictactoe_games','checkers_games','carrom_games',
    'tugofwar_games','memorymatch_games','ashta_chamma_games','ghost_painter_rounds',
    'connect4_games','impostor_games','color_trap_games','freeze_auction_games',
    'flick_arena_games','secret_heist_games','mind_match_games','code_clues_games',
    'night_falls_games','sketch_telephone_games','word_forge_games','stickman_heist_games'
  ) THEN RAISE EXCEPTION 'Unknown game table: %', p_game_table; END IF;
  EXECUTE format('UPDATE public.%I SET "lastActivityAt" = now() WHERE "id" = $1;', p_game_table) USING p_game_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_touch_game_activity(text, text) TO authenticated;

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
    'code_clues_games', jsonb_build_object('id','code-clues','name','Code Clues','icon','🔐','accent','#F59E0B'),
    'night_falls_games', jsonb_build_object('id','night-falls','name','Night Falls','icon','🌙','accent','#6366F1'),
    'sketch_telephone_games', jsonb_build_object('id','sketch-telephone','name','Sketch Telephone','icon','🎨','accent','#EC4899'),
    'word_forge_games', jsonb_build_object('id','word-forge','name','Word Forge','icon','📖','accent','#8B5CF6'),
    'stickman_heist_games', jsonb_build_object('id','stickman-heist','name','Stickman Heist','icon','💎','accent','#EF4444')
  );
$$;

INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'legendary-heister','Legendary Heister','लेजेंडरी हाइस्टर','Win 5 Stickman Heist games','💎','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;
