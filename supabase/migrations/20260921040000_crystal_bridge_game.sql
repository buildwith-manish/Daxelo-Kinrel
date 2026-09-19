-- 20260921040000_crystal_bridge_game.sql
-- Crystal Bridge — turn-based bridge-crossing survival game. 2–8 players.
--
-- Each row of the bridge has two crystals (left + right). Only one is
-- safe. Players take turns picking which crystal to step on. Wrong
-- choice = elimination. Last survivor or first to finish wins.
--
-- Bridge types: crystal (standard), ice (slide chance), lava (stun
-- nearby), shadow (safe hidden), storm (random lightning).
-- Powers: reveal, shield, leap, swap, scanner.
-- Team modes: solo, 2v2, 3v3, 4v4.

CREATE TABLE IF NOT EXISTS "crystal_bridge_games" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "hostUserId" TEXT NOT NULL,
  "hostUserName" TEXT NOT NULL DEFAULT 'Host',
  "roomName" TEXT,
  status TEXT NOT NULL DEFAULT 'waiting',
  "maxPlayers" INTEGER NOT NULL DEFAULT 8,
  "playerOrder" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "turnEndsAt" TIMESTAMPTZ,
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
  "bridgeType" TEXT NOT NULL DEFAULT 'crystal',
  "totalRows" INTEGER NOT NULL DEFAULT 20,
  "teamMode" TEXT NOT NULL DEFAULT 'solo',
  "turnSeconds" INTEGER NOT NULL DEFAULT 20
);
CREATE INDEX IF NOT EXISTS idx_cbg_family ON "crystal_bridge_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "crystal_bridge_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "crystal_bridge_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "userName" TEXT NOT NULL,
  "isReady" BOOLEAN NOT NULL DEFAULT false,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ,
  UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_cbp_game ON "crystal_bridge_players" ("gameId", "joinedAt");

ALTER TABLE "crystal_bridge_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "crystal_bridge_games_select_family" ON "crystal_bridge_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "crystal_bridge_games_insert_host" ON "crystal_bridge_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "crystal_bridge_games_update_family" ON "crystal_bridge_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "crystal_bridge_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "crystal_bridge_players_select_family" ON "crystal_bridge_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "crystal_bridge_games" g WHERE g.id = "crystal_bridge_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "crystal_bridge_players_insert_self_or_host" ON "crystal_bridge_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "crystal_bridge_games" g WHERE g.id = "crystal_bridge_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "crystal_bridge_players_update_self" ON "crystal_bridge_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "crystal_bridge_players_delete_self" ON "crystal_bridge_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "crystal_bridge_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "crystal_bridge_players";
ALTER TABLE "crystal_bridge_games" REPLICA IDENTITY FULL;
ALTER TABLE "crystal_bridge_players" REPLICA IDENTITY FULL;

-- fn_crystalbridge_start
CREATE OR REPLACE FUNCTION public.fn_crystalbridge_start(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_players jsonb; v_count int; v_order text[]; v_i int;
  v_board jsonb; v_players_arr jsonb; v_rows jsonb; v_row jsonb;
  v_safe int; v_powers text[]; v_power text;
BEGIN
  SELECT * INTO v_game FROM "crystal_bridge_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "crystal_bridge_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_count := jsonb_array_length(v_players);
  IF v_count < 2 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;
  FOR v_i IN 0..v_count - 1 LOOP v_order := array_append(v_order, v_players->v_i->>'userId'); END LOOP;

  -- Generate bridge rows (safe side: 0=left, 1=right)
  v_rows := '[]'::jsonb;
  FOR v_i IN 1..v_game."totalRows" LOOP
    v_safe := floor(random() * 2)::int;
    v_rows := v_rows || jsonb_build_object(
      'rowNumber', v_i,
      'safeSide', v_safe,
      'revealed', false,
      'leftBroke', false,
      'rightBroke', false
    );
  END LOOP;

  -- Assign random powers
  v_powers := ARRAY['reveal','shield','leap','swap','scanner'];
  v_players_arr := '[]'::jsonb;
  FOR v_i IN 0..v_count - 1 LOOP
    v_power := v_powers[floor(random() * array_length(v_powers, 1) + 1)::int];
    v_players_arr := v_players_arr || jsonb_build_object(
      'idx', v_i,
      'userId', v_players->v_i->>'userId',
      'name', v_players->v_i->>'userName',
      'position', 0,
      'isAlive', true,
      'power', v_power,
      'powerUsed', false,
      'shieldActive', false,
      'isStunned', false,
      'crystalsCrossed', 0
    );
  END LOOP;

  v_board := jsonb_build_object(
    'playerCount', v_count,
    'bridgeType', v_game."bridgeType",
    'totalRows', v_game."totalRows",
    'teamMode', v_game."teamMode",
    'turnSeconds', v_game."turnSeconds",
    'currentPlayerIdx', 0,
    'currentRow', 1,
    'phase', 'choosing',
    'rows', v_rows,
    'players', v_players_arr,
    'events', '[]'::jsonb,
    'status', 'in_progress',
    'winnerIdx', -1,
    'winningTeam', -1,
    'matchStartTime', extract(epoch from now())::bigint
  );

  UPDATE "crystal_bridge_games" SET status = 'in_progress', "playerOrder" = to_jsonb(v_order),
    "boardState" = v_board, "startedAt" = now(),
    "turnEndsAt" = now() + (v_game."turnSeconds" || ' seconds')::interval,
    "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_crystalbridge_start(text) TO authenticated;

-- fn_crystalbridge_choose — player picks left (0) or right (1)
CREATE OR REPLACE FUNCTION public.fn_crystalbridge_choose(p_game_id text, p_side int) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_board jsonb; v_rows jsonb; v_row jsonb; v_players jsonb;
  v_current_idx int; v_current_row int; v_safe_side int;
  v_player jsonb; v_user_id text; v_bridge_type text; v_team_mode text;
  v_is_safe boolean; v_events jsonb; v_alive_count int;
  v_next_idx int; v_i int; v_team int; v_winning_team int;
  v_ice_slide boolean; v_lava_stun boolean; v_storm_strike boolean;
BEGIN
  SELECT * INTO v_game FROM "crystal_bridge_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  IF v_board->>'phase' <> 'choosing' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_choosing_phase'); END IF;
  v_current_idx := (v_board->>'currentPlayerIdx')::int;
  v_user_id := v_game."playerOrder"->>v_current_idx;
  IF v_user_id IS NULL OR v_user_id <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_your_turn'); END IF;
  IF p_side < 0 OR p_side > 1 THEN RETURN jsonb_build_object('ok', false, 'reason', 'invalid_side'); END IF;

  v_current_row := (v_board->>'currentRow')::int;
  v_rows := v_board->'rows';
  v_row := v_rows->(v_current_row - 1);
  v_safe_side := (v_row->>'safeSide')::int;
  v_players := v_board->'players';
  v_player := v_players->v_current_idx;
  v_bridge_type := v_board->>'bridgeType';
  v_team_mode := v_board->>'teamMode';
  v_events := v_board->'events';

  -- Check if player is shielded (survives one fall)
  IF (v_player->>'shieldActive')::boolean AND p_side <> v_safe_side THEN
    -- Shield saves them — consume shield, but they don't advance
    v_player := jsonb_set(v_player, '{shieldActive}', 'false');
    v_player := jsonb_set(v_player, '{powerUsed}', 'true');
    -- Reveal the row
    v_row := jsonb_set(v_row, '{revealed}', 'true');
    v_row := jsonb_set(v_row, CASE WHEN v_safe_side = 0 THEN '{rightBroke}' ELSE '{leftBroke}' END, 'true');
    v_rows := jsonb_set(v_rows, ARRAY[(v_current_row - 1)::text], v_row);
    v_events := v_events || jsonb_build_object('type','shield_saved','playerIdx',v_current_idx,'row',v_current_row);
    v_players := jsonb_set(v_players, ARRAY[v_current_idx::text], v_player);
    v_board := jsonb_set(v_board, '{rows}', v_rows);
    v_board := jsonb_set(v_board, '{players}', v_players);
    v_board := jsonb_set(v_board, '{events}', v_events);
    -- Next player's turn
    PERFORM public.fn_crystalbridge_advance_turn(v_board, v_game, p_game_id);
    RETURN jsonb_build_object('ok', true, 'shielded', true);
  END IF;

  v_is_safe := (p_side = v_safe_side);

  -- Reveal the row
  v_row := jsonb_set(v_row, '{revealed}', 'true');
  IF NOT v_is_safe THEN
    v_row := jsonb_set(v_row, CASE WHEN p_side = 0 THEN '{leftBroke}' ELSE '{rightBroke}' END, 'true');
  ELSE
    v_row := jsonb_set(v_row, CASE WHEN p_side = 0 THEN '{rightBroke}' ELSE '{leftBroke}' END, 'true');
  END IF;
  v_rows := jsonb_set(v_rows, ARRAY[(v_current_row - 1)::text], v_row);

  IF v_is_safe THEN
    -- Player advances
    v_player := jsonb_set(v_player, '{position}', v_current_row::text::jsonb);
    v_player := jsonb_set(v_player, '{crystalsCrossed}', ((v_player->>'crystalsCrossed')::int + 1)::text::jsonb);
    v_players := jsonb_set(v_players, ARRAY[v_current_idx::text], v_player);
    v_events := v_events || jsonb_build_object('type','safe','playerIdx',v_current_idx,'row',v_current_row,'side',p_side);

    -- Check win: reached the end
    IF v_current_row >= (v_board->>'totalRows')::int THEN
      v_board := jsonb_set(v_board, '{rows}', v_rows);
      v_board := jsonb_set(v_board, '{players}', v_players);
      v_board := jsonb_set(v_board, '{events}', v_events);
      v_board := jsonb_set(v_board, '{phase}', '"completed"');
      v_board := jsonb_set(v_board, '{status}', '"completed"');
      v_board := jsonb_set(v_board, '{winnerIdx}', v_current_idx::text::jsonb);
      IF v_team_mode <> 'solo' THEN
        v_team := CASE WHEN v_team_mode = '2v2' THEN (v_current_idx % 2) + 1
                       WHEN v_team_mode = '3v3' THEN (v_current_idx % 3) + 1
                       WHEN v_team_mode = '4v4' THEN (v_current_idx % 4) + 1 ELSE 1 END;
        v_board := jsonb_set(v_board, '{winningTeam}', v_team::text::jsonb);
      END IF;
      UPDATE "crystal_bridge_games" SET "boardState" = v_board, status = 'completed', "completedAt" = now(),
        "winnerUserIds" = jsonb_build_array(v_user_id),
        "endReason" = 'finish_reached', "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true, 'won', true);
    END IF;

    -- Bridge-type effects on safe step
    IF v_bridge_type = 'ice' THEN
      v_ice_slide := (random() < 0.25);
      IF v_ice_slide THEN
        v_events := v_events || jsonb_build_object('type','ice_slide','playerIdx',v_current_idx);
      END IF;
    ELSIF v_bridge_type = 'storm' THEN
      v_storm_strike := (random() < 0.15);
      IF v_storm_strike THEN
        v_events := v_events || jsonb_build_object('type','storm_strike','row',v_current_row);
      END IF;
    END IF;
  ELSE
    -- Player eliminated
    v_player := jsonb_set(v_player, '{isAlive}', 'false');
    v_players := jsonb_set(v_players, ARRAY[v_current_idx::text], v_player);
    v_events := v_events || jsonb_build_object('type','eliminated','playerIdx',v_current_idx,'row',v_current_row,'side',p_side);

    -- Lava bridge: stun nearby alive players
    IF v_bridge_type = 'lava' THEN
      FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP
        IF v_i <> v_current_idx AND (v_players->v_i->>'isAlive')::boolean THEN
          IF random() < 0.3 THEN
            v_players := jsonb_set(v_players, ARRAY[v_i::text, 'isStunned'], 'true');
            v_events := v_events || jsonb_build_object('type','lava_stun','playerIdx',v_i);
          END IF;
        END IF;
      END LOOP;
    END IF;
  END IF;

  v_board := jsonb_set(v_board, '{rows}', v_rows);
  v_board := jsonb_set(v_board, '{players}', v_players);
  v_board := jsonb_set(v_board, '{events}', v_events);

  -- Check if all but one eliminated
  v_alive_count := 0;
  FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP
    IF (v_players->v_i->>'isAlive')::boolean THEN v_alive_count := v_alive_count + 1; END IF;
  END LOOP;

  IF v_alive_count <= 1 AND v_team_mode = 'solo' THEN
    -- Last survivor wins
    v_board := jsonb_set(v_board, '{phase}', '"completed"');
    v_board := jsonb_set(v_board, '{status}', '"completed"');
    FOR v_i IN 0..jsonb_array_length(v_players) - 1 LOOP
      IF (v_players->v_i->>'isAlive')::boolean THEN
        v_board := jsonb_set(v_board, '{winnerIdx}', v_i::text::jsonb);
        UPDATE "crystal_bridge_games" SET "boardState" = v_board, status = 'completed', "completedAt" = now(),
          "winnerUserIds" = jsonb_build_array(v_game."playerOrder"->>v_i::text),
          "endReason" = 'last_survivor', "lastActivityAt" = now() WHERE id = p_game_id;
        RETURN jsonb_build_object('ok', true, 'won', true);
      END IF;
    END LOOP;
    -- Everyone dead — draw
    UPDATE "crystal_bridge_games" SET "boardState" = v_board, status = 'completed', "completedAt" = now(),
      "endReason" = 'all_eliminated', "lastActivityAt" = now() WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true, 'draw', true);
  END IF;

  -- Advance to next player's turn
  PERFORM public.fn_crystalbridge_advance_turn(v_board, v_game, p_game_id);
  RETURN jsonb_build_object('ok', true, 'safe', v_is_safe);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_crystalbridge_choose(text, int) TO authenticated;

-- fn_crystalbridge_advance_turn — helper to move to next alive player
CREATE OR REPLACE FUNCTION public.fn_crystalbridge_advance_turn(p_board jsonb, p_game record, p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_board jsonb := p_board;
  v_players jsonb; v_count int; v_current_idx int; v_next_idx int;
  v_i int; v_found boolean := false; v_turn_seconds int;
BEGIN
  v_players := v_board->'players';
  v_count := jsonb_array_length(v_players);
  v_current_idx := (v_board->>'currentPlayerIdx')::int;
  v_turn_seconds := (v_board->>'turnSeconds')::int;

  -- Find next alive, non-stunned player
  FOR v_i IN 1..v_count LOOP
    v_next_idx := (v_current_idx + v_i) % v_count;
    IF (v_players->v_next_idx->>'isAlive')::boolean AND NOT (v_players->v_next_idx->>'isStunned')::boolean THEN
      v_found := true;
      EXIT;
    END IF;
  END LOOP;

  IF NOT v_found THEN
    -- All remaining players are stunned — unstun them and try again
    FOR v_i IN 0..v_count - 1 LOOP
      v_players := jsonb_set(v_players, ARRAY[v_i::text, 'isStunned'], 'false');
    END LOOP;
    v_board := jsonb_set(v_board, '{players}', v_players);
    FOR v_i IN 1..v_count LOOP
      v_next_idx := (v_current_idx + v_i) % v_count;
      IF (v_players->v_next_idx->>'isAlive')::boolean THEN
        v_found := true;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  IF v_found THEN
    v_board := jsonb_set(v_board, '{currentPlayerIdx}', v_next_idx::text::jsonb);
    -- Advance row if we wrapped around
    IF v_next_idx <= v_current_idx THEN
      v_board := jsonb_set(v_board, '{currentRow}', ((v_board->>'currentRow')::int + 1)::text::jsonb);
    END IF;
    v_board := jsonb_set(v_board, '{phase}', '"choosing"');
  ELSE
    v_board := jsonb_set(v_board, '{phase}', '"completed"');
    v_board := jsonb_set(v_board, '{status}', '"completed"');
  END IF;

  UPDATE "crystal_bridge_games" SET "boardState" = v_board,
    "turnEndsAt" = CASE WHEN v_found THEN now() + (v_turn_seconds || ' seconds')::interval ELSE null END,
    "lastActivityAt" = now() WHERE id = p_game_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_crystalbridge_advance_turn(jsonb, record, text) TO authenticated;

-- fn_crystalbridge_use_power
CREATE OR REPLACE FUNCTION public.fn_crystalbridge_use_power(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_board jsonb; v_players jsonb; v_player jsonb;
  v_current_idx int; v_power text; v_rows jsonb; v_row jsonb;
  v_current_row int; v_i int; v_events jsonb;
BEGIN
  SELECT * INTO v_game FROM "crystal_bridge_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  IF v_board->>'phase' <> 'choosing' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_choosing_phase'); END IF;
  v_current_idx := (v_board->>'currentPlayerIdx')::int;
  v_user_id := v_game."playerOrder"->>v_current_idx;
  IF v_user_id IS NULL OR v_user_id <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_your_turn'); END IF;
  v_players := v_board->'players';
  v_player := v_players->v_current_idx;
  IF (v_player->>'powerUsed')::boolean THEN RETURN jsonb_build_object('ok', false, 'reason', 'power_already_used'); END IF;
  v_power := v_player->>'power';
  v_current_row := (v_board->>'currentRow')::int;
  v_rows := v_board->'rows';
  v_events := v_board->'events';

  CASE v_power
    WHEN 'reveal' THEN
      -- Reveal safe side of current row
      v_row := v_rows->(v_current_row - 1);
      v_row := jsonb_set(v_row, '{revealed}', 'true');
      v_rows := jsonb_set(v_rows, ARRAY[(v_current_row - 1)::text], v_row);
      v_board := jsonb_set(v_board, '{rows}', v_rows);
      v_events := v_events || jsonb_build_object('type','power_reveal','playerIdx',v_current_idx,'row',v_current_row);
    WHEN 'shield' THEN
      v_player := jsonb_set(v_player, '{shieldActive}', 'true');
      v_players := jsonb_set(v_players, ARRAY[v_current_idx::text], v_player);
      v_board := jsonb_set(v_board, '{players}', v_players);
      v_events := v_events || jsonb_build_object('type','power_shield','playerIdx',v_current_idx);
    WHEN 'leap' THEN
      -- Skip current row (auto-safe advance)
      v_player := jsonb_set(v_player, '{position}', v_current_row::text::jsonb);
      v_player := jsonb_set(v_player, '{crystalsCrossed}', ((v_player->>'crystalsCrossed')::int + 1)::text::jsonb);
      v_players := jsonb_set(v_players, ARRAY[v_current_idx::text], v_player);
      v_board := jsonb_set(v_board, '{players}', v_players);
      v_events := v_events || jsonb_build_object('type','power_leap','playerIdx',v_current_idx,'row',v_current_row);
    WHEN 'scanner' THEN
      -- Reveal next 2 rows
      FOR v_i IN 0..1 LOOP
        IF v_current_row + v_i <= jsonb_array_length(v_rows) THEN
          v_row := v_rows->(v_current_row + v_i - 1);
          v_row := jsonb_set(v_row, '{revealed}', 'true');
          v_rows := jsonb_set(v_rows, ARRAY[(v_current_row + v_i - 1)::text], v_row);
        END IF;
      END LOOP;
      v_board := jsonb_set(v_board, '{rows}', v_rows);
      v_events := v_events || jsonb_build_object('type','power_scanner','playerIdx',v_current_idx);
    WHEN 'swap' THEN
      -- Swap turn order (just skip to next player's turn — effectively swaps)
      v_events := v_events || jsonb_build_object('type','power_swap','playerIdx',v_current_idx);
    ELSE
      RETURN jsonb_build_object('ok', false, 'reason', 'invalid_power');
  END CASE;

  v_player := jsonb_set(v_player, '{powerUsed}', 'true');
  v_players := jsonb_set(v_players, ARRAY[v_current_idx::text], v_player);
  v_board := jsonb_set(v_board, '{players}', v_players);
  v_board := jsonb_set(v_board, '{events}', v_events);

  UPDATE "crystal_bridge_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;

  -- If leap was used, advance turn (player already moved)
  IF v_power = 'leap' THEN
    PERFORM public.fn_crystalbridge_advance_turn(v_board, v_game, p_game_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'power', v_power);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_crystalbridge_use_power(text) TO authenticated;

-- fn_crystalbridge_tick
CREATE OR REPLACE FUNCTION public.fn_crystalbridge_tick(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_board jsonb; v_players jsonb; v_current_idx int; v_i int;
  v_next_idx int; v_count int; v_turn_seconds int; v_found boolean;
BEGIN
  SELECT * INTO v_game FROM "crystal_bridge_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "crystal_bridge_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_game."turnEndsAt" IS NULL OR v_game."turnEndsAt" > now() THEN RETURN; END IF;

  -- Timer expired — auto-eliminate current player
  v_board := v_game."boardState";
  v_current_idx := (v_board->>'currentPlayerIdx')::int;
  v_players := v_board->'players';
  v_players := jsonb_set(v_players, ARRAY[v_current_idx::text, 'isAlive'], 'false');
  v_board := jsonb_set(v_board, '{players}', v_players);
  v_board := jsonb_set(v_board, '{events}', (v_board->'events') || jsonb_build_object('type','timeout','playerIdx',v_current_idx));
  PERFORM public.fn_crystalbridge_advance_turn(v_board, v_game, p_game_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_crystalbridge_tick(text) TO authenticated;

-- fn_crystalbridge_leave
CREATE OR REPLACE FUNCTION public.fn_crystalbridge_leave(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_active int;
BEGIN
  SELECT * INTO v_game FROM "crystal_bridge_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "crystal_bridge_players" SET "leftAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  SELECT count(*) INTO v_active FROM "crystal_bridge_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
  IF v_active < 2 AND v_game.status = 'in_progress' THEN
    UPDATE "crystal_bridge_games" SET status = 'completed', "completedAt" = now(), "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((SELECT jsonb_agg("userId") FROM "crystal_bridge_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL), '[]'::jsonb),
      "lastActivityAt" = now() WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_crystalbridge_leave(text) TO authenticated;

-- Archive trigger
CREATE OR REPLACE FUNCTION public.fn__crystalbridge_on_complete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('crystal_bridge_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'crystalbridge archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_crystalbridge_archive ON "crystal_bridge_games";
CREATE TRIGGER trg_crystalbridge_archive AFTER UPDATE ON "crystal_bridge_games"
  FOR EACH ROW EXECUTE FUNCTION public.fn__crystalbridge_on_complete();

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
    'night_falls_games','sketch_telephone_games','word_forge_games','stickman_heist_games',
    'crystal_bridge_games'
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
    'stickman_heist_games', jsonb_build_object('id','stickman-heist','name','Stickman Heist','icon','💎','accent','#EF4444'),
    'crystal_bridge_games', jsonb_build_object('id','crystal-bridge','name','Crystal Bridge','icon','🔮','accent','#06B6D4')
  );
$$;

INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'crystal-legend','Crystal Legend','क्रिस्टल लीजेंड','Win 5 Crystal Bridge games','🔮','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;
