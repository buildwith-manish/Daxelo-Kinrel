-- 20260920140000_secret_heist_game.sql
-- Secret Heist — hidden-role / social deduction heist game. 3–8 players.
--
-- Every player is a thief attempting to steal the most treasure from a
-- shared vault. Each round players secretly choose one action (Steal,
-- Protect, Spy, Trap, Hack). Choices are revealed only after all players
-- lock. The resolution engine determines outcomes (successful steals,
-- blocked steals, triggered traps, hack results). After N rounds the
-- player with the most coins wins.
--
-- Mirrors impostor_games + freeze_auction_games schema + RPC pattern.
-- Hidden information: actions are stored per-player in a separate
-- `secret_heist_actions` table with RLS that hides other players' rows
-- until the round is resolved. The boardState JSONB on the games row
-- contains only the *resolved* history + aggregate counters — never the
-- pending actions.

CREATE TABLE IF NOT EXISTS "secret_heist_games" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "hostUserId" TEXT NOT NULL,
  "hostUserName" TEXT NOT NULL DEFAULT 'Host',
  "roomName" TEXT,
  status TEXT NOT NULL DEFAULT 'waiting',
  "maxPlayers" INTEGER NOT NULL DEFAULT 8,
  "playerOrder" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "currentPlayerId" TEXT,
  "currentTurnIndex" INTEGER NOT NULL DEFAULT 0,
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
  -- Game-specific config
  "totalRounds" INTEGER NOT NULL DEFAULT 5,
  "startingCoins" INTEGER NOT NULL DEFAULT 100,
  "vaultSize" INTEGER NOT NULL DEFAULT 500,
  "chaosMode" BOOLEAN NOT NULL DEFAULT false,
  "actionSeconds" INTEGER NOT NULL DEFAULT 30
);
CREATE INDEX IF NOT EXISTS idx_shg_family ON "secret_heist_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "secret_heist_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "secret_heist_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "userName" TEXT NOT NULL,
  "isReady" BOOLEAN NOT NULL DEFAULT false,
  "readyAt" TIMESTAMPTZ,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ,
  UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_shp_game ON "secret_heist_players" ("gameId", "joinedAt");

-- Hidden-action table. RLS exposes ONLY the caller's own row to each
-- player; the resolution RPC reads all rows for the round and updates
-- the games.boardState with the *resolved* outcome.
CREATE TABLE IF NOT EXISTS "secret_heist_actions" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "secret_heist_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "roundNumber" INTEGER NOT NULL,
  "action" TEXT NOT NULL,           -- steal | protect | spy | trap | hack | double_steal | alarm_bait
  "amount" INTEGER NOT NULL DEFAULT 0,  -- coins targeted (for steal/hack)
  "submittedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("gameId", "userId", "roundNumber")
);
CREATE INDEX IF NOT EXISTS idx_sha_game_round ON "secret_heist_actions" ("gameId", "roundNumber");

-- ─────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "secret_heist_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "secret_heist_games_select_family" ON "secret_heist_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "secret_heist_games_insert_host" ON "secret_heist_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "secret_heist_games_update_family" ON "secret_heist_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "secret_heist_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "secret_heist_players_select_family" ON "secret_heist_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "secret_heist_games" g WHERE g.id = "secret_heist_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "secret_heist_players_insert_self_or_host" ON "secret_heist_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "secret_heist_games" g WHERE g.id = "secret_heist_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "secret_heist_players_update_self" ON "secret_heist_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "secret_heist_players_delete_self" ON "secret_heist_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- Hidden-action RLS: a player can see / insert / update only their OWN
-- action for the current round. The resolution RPC runs as SECURITY
-- DEFINER so it bypasses RLS to read everyone's action.
ALTER TABLE "secret_heist_actions" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "secret_heist_actions_select_own" ON "secret_heist_actions" FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "secret_heist_actions_insert_own" ON "secret_heist_actions" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "secret_heist_actions_update_own" ON "secret_heist_actions" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "secret_heist_actions_delete_own" ON "secret_heist_actions" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "secret_heist_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "secret_heist_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "secret_heist_actions";
ALTER TABLE "secret_heist_games" REPLICA IDENTITY FULL;
ALTER TABLE "secret_heist_players" REPLICA IDENTITY FULL;
ALTER TABLE "secret_heist_actions" REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────
-- fn_secretheist_start — host starts the match. Initializes boardState
-- with N players, vaultSize coins, and round 1 in 'choosing' phase.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_secretheist_start(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_players jsonb;
  v_count int;
  v_order text[];
  v_i int;
  v_board jsonb;
  v_players_arr jsonb;
  v_action_seconds int;
BEGIN
  SELECT * INTO v_game FROM "secret_heist_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "secret_heist_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_count := jsonb_array_length(v_players);
  IF v_count < 3 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;
  FOR v_i IN 0..v_count - 1 LOOP v_order := array_append(v_order, v_players->v_i->>'userId'); END LOOP;
  -- Build players array with startingCoins each
  v_players_arr := '[]'::jsonb;
  FOR v_i IN 0..v_count - 1 LOOP
    v_players_arr := v_players_arr || jsonb_build_object(
      'idx', v_i,
      'userId', v_players->v_i->>'userId',
      'name', v_players->v_i->>'userName',
      'coins', v_game."startingCoins",
      'suspicion', 0,
      'missesNextRound', false
    );
  END LOOP;
  v_action_seconds := v_game."actionSeconds";
  v_board := jsonb_build_object(
    'playerCount', v_count,
    'totalRounds', v_game."totalRounds",
    'startingCoins', v_game."startingCoins",
    'vaultSize', v_game."vaultSize",
    'vaultCoins', v_game."vaultSize",
    'chaosMode', v_game."chaosMode",
    'actionSeconds', v_action_seconds,
    'currentRound', 1,
    'rounds', jsonb_build_array(jsonb_build_object(
      'roundNumber', 1,
      'phase', 'choosing',
      'lockedCount', 0,
      'vaultLost', 0,
      'stealsSuccessful', 0,
      'stealsBlocked', 0,
      'trapsTriggered', 0,
      'hacksSucceeded', 0,
      'hacksBackfired', 0,
      'alarmsTriggered', 0,
      'events', '[]'::jsonb,
      'revealedActions', '[]'::jsonb
    )),
    'players', v_players_arr,
    'status', 'in_progress',
    'winner', -1
  );
  UPDATE "secret_heist_games" SET
    status = 'in_progress',
    "playerOrder" = to_jsonb(v_order),
    "currentPlayerId" = v_order[1],
    "boardState" = v_board,
    "startedAt" = now(),
    "turnEndsAt" = now() + (v_action_seconds || ' seconds')::interval,
    "lastActivityAt" = now()
  WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_secretheist_start(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_secretheist_submit_action — a player secretly chooses their action.
-- The action is recorded in secret_heist_actions (RLS hides it from
-- other players). The boardState's lockedCount is incremented so all
-- clients can see "5/6 players locked" without seeing *who* locked.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_secretheist_submit_action(
  p_game_id text,
  p_action text,
  p_amount int DEFAULT 0
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_idx int;
  v_player_count int;
  v_existing record;
  v_action_seconds int;
  v_locked_count int;
  v_chaos boolean;
  v_valid_actions text[] := ARRAY['steal','protect','spy','trap','hack'];
BEGIN
  SELECT * INTO v_game FROM "secret_heist_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_player_idx := (SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = auth.uid()::text);
  IF v_player_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_current := (v_board->>'currentRound')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'choosing' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_choosing_phase'); END IF;

  -- Chaos mode adds extra actions
  v_chaos := (v_board->>'chaosMode')::boolean;
  IF v_chaos THEN
    v_valid_actions := ARRAY['steal','protect','spy','trap','hack','double_steal','alarm_bait'];
  END IF;
  IF NOT (p_action = ANY(v_valid_actions)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_action');
  END IF;

  -- Amount validation for steal/hack/double_steal
  IF p_action IN ('steal','hack','double_steal') THEN
    IF p_amount < 10 THEN RETURN jsonb_build_object('ok', false, 'reason', 'amount_too_small'); END IF;
    IF p_amount > 50 THEN RETURN jsonb_build_object('ok', false, 'reason', 'amount_too_large'); END IF;
  END IF;

  -- Insert or update the action (player can change their mind during choosing phase)
  SELECT * INTO v_existing FROM "secret_heist_actions"
    WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text AND "roundNumber" = v_current LIMIT 1;
  IF v_existing.id IS NULL THEN
    INSERT INTO "secret_heist_actions" ("gameId","userId","roundNumber","action","amount")
    VALUES (p_game_id, auth.uid()::text, v_current, p_action, p_amount);
  ELSE
    UPDATE "secret_heist_actions" SET "action" = p_action, "amount" = p_amount, "submittedAt" = now()
    WHERE "id" = v_existing.id;
  END IF;

  -- Recompute lockedCount (number of distinct players with an action this round)
  SELECT count(*) INTO v_locked_count FROM "secret_heist_actions"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current;

  v_round := jsonb_set(v_round, '{lockedCount}', v_locked_count::text::jsonb);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  v_player_count := (v_board->>'playerCount')::int;
  v_action_seconds := (v_board->>'actionSeconds')::int;

  -- Auto-resolve when all players have locked
  IF v_locked_count >= v_player_count THEN
    v_round := jsonb_set(v_round, '{phase}', '"resolving"');
    v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
    v_board := jsonb_set(v_board, '{rounds}', v_rounds);
    UPDATE "secret_heist_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
    -- Trigger resolution
    PERFORM public.fn_secretheist_resolve(p_game_id);
    RETURN jsonb_build_object('ok', true, 'resolved', true);
  END IF;

  UPDATE "secret_heist_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_secretheist_submit_action(text, text, int) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_secretheist_resolve — the resolution engine. Runs as SECURITY
-- DEFINER so it can read all players' actions for the round.
--
-- Resolution order (matches the engine spec):
--   1. Traps apply first: any thief who chose Steal and was target of a
--      Trap has their steal converted to a failure + loses 10 coins.
--   2. Protect blocks the next steal that targets the vault: every
--      Protect reduces the vault's exposure by 30 coins for this round.
--   3. Steals process in random order. Each steal takes `amount` from
--      the vault UNLESS the vault's protected buffer covers it. If a
--      trap was set by a *specific* player, the steal is also blocked.
--   4. Hacks roll for outcome: 50% double_steal (extra coins), 30%
--      backfire (-coins to hacker), 20% alarm (vault locks, no steals
--      this round).
--   5. Spies learn info — recorded in events but no coin effect.
-- ─────────────────────────────────────────────────────────────────
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
  v_actions record;
  v_steals record;
  v_traps record;
  v_protects record;
  v_spies record;
  v_hacks record;
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
  v_action text;
  v_user_id text;
  v_user_name text;
  v_suspicion int;
  v_rolls float;
  v_steam_idx int;
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
  v_total_rounds := (v_board->>'totalRounds')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_vault_coins := (v_board->>'vaultCoins')::int;
  v_players := v_board->'players';
  v_action_seconds := (v_board->>'actionSeconds')::int;
  v_chaos := (v_board->>'chaosMode')::boolean;

  -- ── Process Protects: each Protect adds 30 to the protected buffer ──
  FOR v_protects IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'protect' LOOP
    v_protected_buffer := v_protected_buffer + 30;
    v_revealed := v_revealed || jsonb_build_object('userId', v_protects."userId", 'action', 'protect', 'amount', 30, 'outcome', 'active');
  END LOOP;

  -- ── Process Traps: collect trap-userIds. Each trap increases suspicion. ──
  v_trap_user_ids := ARRAY[]::text[];
  FOR v_traps IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'trap' LOOP
    v_trap_user_ids := array_append(v_trap_user_ids, v_traps."userId");
    v_revealed := v_revealed || jsonb_build_object('userId', v_traps."userId", 'action', 'trap', 'outcome', 'set');
  END LOOP;

  -- ── Process Hacks first — alarm may lock the vault ──
  FOR v_hacks IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" IN ('hack','double_steal','alarm_bait') LOOP
    v_user_id := v_hacks."userId";
    v_amount := v_hacks."amount";
    -- 50% success (double coins), 30% backfire (-amount), 20% alarm
    v_rolls := random();
    IF v_hacks."action" = 'double_steal' THEN
      -- Chaos-mode action: stronger success
      IF v_rolls < 0.65 THEN
        v_hacks_success := v_hacks_success + 1;
        v_steals_success := v_steals_success + 1;
        v_vault_lost := v_vault_lost + v_amount * 2;
        v_coins := (v_players->((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)->>'coins')::int + v_amount * 2;
        v_players := jsonb_set(v_players, ARRAY[((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)::text, 'coins'], v_coins::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'double_steal', 'amount', v_amount * 2, 'outcome', 'success');
        v_events := v_events || jsonb_build_object('type', 'hack_success', 'userId', v_user_id, 'amount', v_amount * 2);
      ELSE
        v_hacks_backfire := v_hacks_backfire + 1;
        v_coins := GREATEST((v_players->((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)->>'coins')::int - v_amount, 0);
        v_players := jsonb_set(v_players, ARRAY[((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)::text, 'coins'], v_coins::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'double_steal', 'outcome', 'backfire');
        v_events := v_events || jsonb_build_object('type', 'hack_backfire', 'userId', v_user_id, 'amount', v_amount);
      END IF;
    ELSIF v_hacks."action" = 'alarm_bait' THEN
      -- Chaos-mode: 50% chance to trigger alarm (no steals this round), 50% bait (gain 15)
      IF v_rolls < 0.5 THEN
        v_alarm_triggered := true;
        v_alarms := v_alarms + 1;
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'alarm_bait', 'outcome', 'alarm_triggered');
        v_events := v_events || jsonb_build_object('type', 'alarm_triggered', 'userId', v_user_id);
      ELSE
        v_coins := (v_players->((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)->>'coins')::int + 15;
        v_players := jsonb_set(v_players, ARRAY[((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)::text, 'coins'], v_coins::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'alarm_bait', 'outcome', 'bait_success', 'amount', 15);
      END IF;
    ELSE -- 'hack'
      IF v_rolls < 0.5 THEN
        v_hacks_success := v_hacks_success + 1;
        v_steals_success := v_steals_success + 1;
        v_vault_lost := v_vault_lost + v_amount * 2;
        v_coins := (v_players->((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)->>'coins')::int + v_amount * 2;
        v_players := jsonb_set(v_players, ARRAY[((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)::text, 'coins'], v_coins::text::jsonb);
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'hack', 'amount', v_amount * 2, 'outcome', 'success');
        v_events := v_events || jsonb_build_object('type', 'hack_success', 'userId', v_user_id, 'amount', v_amount * 2);
      ELSIF v_rolls < 0.8 THEN
        v_hacks_backfire := v_hacks_backfire + 1;
        v_coins := GREATEST((v_players->((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)->>'coins')::int - v_amount, 0);
        v_players := jsonb_set(v_players, ARRAY[((SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id) - 1)::text, 'coins'], v_coins::text::jsonb);
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

  -- ── Process Steals (skip if alarm triggered) ──
  IF NOT v_alarm_triggered THEN
    FOR v_steals IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'steal' ORDER BY random() LOOP
      v_user_id := v_steals."userId";
      v_amount := v_steals."amount";
      v_player_idx := (SELECT idx - 1 FROM unnest(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = v_user_id);

      -- Trap check: did anyone trap this round?
      IF array_length(v_trap_user_ids, 1) > 0 THEN
        -- 50% chance per trap that this steal gets caught
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

      -- Protect buffer check
      IF v_protected_buffer >= v_amount THEN
        v_protected_buffer := v_protected_buffer - v_amount;
        v_steals_blocked := v_steals_blocked + 1;
        v_revealed := v_revealed || jsonb_build_object('userId', v_user_id, 'action', 'steal', 'amount', v_amount, 'outcome', 'blocked');
        v_events := v_events || jsonb_build_object('type', 'steal_blocked', 'userId', v_user_id, 'amount', v_amount);
      ELSE
        -- Steal succeeds
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
    -- Alarm triggered — mark all steals as blocked
    FOR v_steals IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'steal' LOOP
      v_steals_blocked := v_steals_blocked + 1;
      v_revealed := v_revealed || jsonb_build_object('userId', v_steals."userId", 'action', 'steal', 'amount', v_steals."amount", 'outcome', 'alarm_blocked');
    END LOOP;
  END IF;

  -- ── Spies: just record events (info revealed to spy via separate query) ──
  FOR v_spies IN SELECT * FROM "secret_heist_actions" WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "action" = 'spy' LOOP
    v_revealed := v_revealed || jsonb_build_object('userId', v_spies."userId", 'action', 'spy', 'outcome', ' intel_gathered');
    v_events := v_events || jsonb_build_object('type', 'spy_used', 'userId', v_spies."userId");
  END LOOP;

  -- ── Update vault ──
  v_vault_coins := GREATEST(v_vault_coins - v_vault_lost, 0);

  -- ── Decay suspicion by 1 for players who didn't act aggressively ──
  FOR v_i IN 0..v_player_count - 1 LOOP
    v_s := (v_players->v_i->>'suspicion')::int;
    IF v_s > 0 THEN
      v_players := jsonb_set(v_players, ARRAY[v_i::text, 'suspicion'], GREATEST(v_s - 1, 0)::text::jsonb);
    END IF;
  END LOOP;

  -- ── Update round with resolved state ──
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
GRANT EXECUTE ON FUNCTION public.fn_secretheist_resolve(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_secretheist_advance — advance phase (revealing → next round or
-- finish match)
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_secretheist_advance(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_board jsonb; v_round jsonb; v_rounds jsonb;
  v_current int; v_player_count int; v_total_rounds int; v_action_seconds int;
  v_new_round jsonb; v_max_coins int; v_winner_idx int; v_tie boolean; v_s int; v_i int;
BEGIN
  SELECT * INTO v_game FROM "secret_heist_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  v_total_rounds := (v_board->>'totalRounds')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_action_seconds := (v_board->>'actionSeconds')::int;
  v_round := v_board->'rounds'->(v_current - 1);

  IF v_round->>'phase' = 'choosing' THEN
    -- Timer expired during choosing — auto-resolve with whoever has locked
    PERFORM public.fn_secretheist_resolve(p_game_id);
    RETURN jsonb_build_object('ok', true, 'auto_resolved', true);
  ELSIF v_round->>'phase' = 'revealing' THEN
    -- Advance to next round, or finish
    IF v_current >= v_total_rounds THEN
      v_board := jsonb_set(v_board, '{status}', '"completed"');
      v_max_coins := -1; v_winner_idx := -1; v_tie := false;
      FOR v_i IN 0..v_player_count - 1 LOOP
        v_s := (v_board->'players'->v_i->>'coins')::int;
        IF v_s > v_max_coins THEN v_max_coins := v_s; v_winner_idx := v_i; v_tie := false;
        ELSIF v_s = v_max_coins THEN v_tie := true; END IF;
      END LOOP;
      v_board := jsonb_set(v_board, '{winner}', v_winner_idx::text::jsonb);
      UPDATE "secret_heist_games" SET "boardState" = v_board, status = 'completed', "completedAt" = now(),
        "winnerUserIds" = CASE WHEN NOT v_tie AND v_winner_idx >= 0 THEN jsonb_build_array(v_game."playerOrder"->>v_winner_idx::text) ELSE '[]'::jsonb END,
        "endReason" = 'most_coins', "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true, 'finished', true);
    ELSE
      v_new_round := jsonb_build_object(
        'roundNumber', v_current + 1,
        'phase', 'choosing',
        'lockedCount', 0,
        'vaultLost', 0,
        'stealsSuccessful', 0,
        'stealsBlocked', 0,
        'trapsTriggered', 0,
        'hacksSucceeded', 0,
        'hacksBackfired', 0,
        'alarmsTriggered', 0,
        'events', '[]'::jsonb,
        'revealedActions', '[]'::jsonb
      );
      v_rounds := v_board->'rounds' || v_new_round;
      v_board := jsonb_set(v_board, '{rounds}', v_rounds);
      v_board := jsonb_set(v_board, '{currentRound}', (v_current + 1)::text::jsonb);
      UPDATE "secret_heist_games" SET "boardState" = v_board,
        "turnEndsAt" = now() + (v_action_seconds || ' seconds')::interval,
        "lastActivityAt" = now() WHERE id = p_game_id;
      RETURN jsonb_build_object('ok', true);
    END IF;
  ELSIF v_round->>'phase' = 'resolving' THEN
    -- Resolution in progress — no-op
    RETURN jsonb_build_object('ok', true);
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_phase');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_secretheist_advance(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_secretheist_tick — 2s watchdog. Auto-advances on timer expiry.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_secretheist_tick(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record;
BEGIN
  SELECT * INTO v_game FROM "secret_heist_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "secret_heist_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_game."turnEndsAt" IS NOT NULL AND v_game."turnEndsAt" < now() THEN
    PERFORM public.fn_secretheist_advance(p_game_id);
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_secretheist_tick(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_secretheist_leave
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_secretheist_leave(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_active int;
BEGIN
  SELECT * INTO v_game FROM "secret_heist_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "secret_heist_players" SET "leftAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  SELECT count(*) INTO v_active FROM "secret_heist_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
  IF v_active < 3 AND v_game.status = 'in_progress' THEN
    UPDATE "secret_heist_games" SET status = 'completed', "completedAt" = now(), "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((SELECT jsonb_agg("userId") FROM "secret_heist_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL), '[]'::jsonb),
      "lastActivityAt" = now() WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_secretheist_leave(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_secretheist_intel — let a Spy see one player's previous action.
-- SECURITY DEFINER so the spy can read another player's action row.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_secretheist_intel(
  p_game_id text,
  p_target_user_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record; v_board jsonb; v_current int; v_spy record;
BEGIN
  SELECT * INTO v_game FROM "secret_heist_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRound')::int;
  -- Verify the caller is a Spy this round
  SELECT * INTO v_spy FROM "secret_heist_actions"
    WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text AND "roundNumber" = v_current AND "action" = 'spy' LIMIT 1;
  IF v_spy.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_a_spy'); END IF;
  -- Return the target's previous-round action (if any)
  SELECT "action", "amount" FROM "secret_heist_actions"
    WHERE "gameId" = p_game_id AND "userId" = p_target_user_id AND "roundNumber" = v_current - 1
    LIMIT 1
  INTO v_spy."action", v_spy."amount";
  RETURN jsonb_build_object('ok', true, 'targetUserId', p_target_user_id, 'action', v_spy."action", 'amount', v_spy."amount");
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_secretheist_intel(text, text) TO authenticated;

-- Archive trigger
CREATE OR REPLACE FUNCTION public.fn__secretheist_on_complete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('secret_heist_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'secretheist archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_secretheist_archive ON "secret_heist_games";
CREATE TRIGGER trg_secretheist_archive AFTER UPDATE ON "secret_heist_games"
  FOR EACH ROW EXECUTE FUNCTION public.fn__secretheist_on_complete();

-- ─────────────────────────────────────────────────────────────────
-- Whitelists + metadata
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_touch_game_activity(p_game_table text, p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_game_table NOT IN (
    'antakshari_games','chitmatch_games','bingo_games','ludo_games','sos_games',
    'dotsboxes_games','nameplace_games','truthordare_games','twotruths_games',
    'redlight_rounds','chess_games','tictactoe_games','checkers_games','carrom_games',
    'tugofwar_games','memorymatch_games','ashta_chamma_games','ghost_painter_rounds',
    'connect4_games','impostor_games','color_trap_games','freeze_auction_games',
    'flick_arena_games','secret_heist_games'
  ) THEN
    RAISE EXCEPTION 'Unknown game table: %', p_game_table;
  END IF;
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
    'secret_heist_games', jsonb_build_object('id','secret-heist','name','Secret Heist','icon','💰','accent','#10B981')
  );
$$;

-- Achievement — Master Thief
INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'master-thief','Master Thief','मास्टर थीफ','Win 5 Secret Heist games','💰','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;
-- Patch the fn_secretheist_submit_action and fn_secretheist_resolve
-- functions to use jsonb_array_elements_text instead of unnest(jsonb).
-- The original migration used unnest(playerOrder) but playerOrder is a
-- JSONB array, and PostgreSQL doesn't have unnest(jsonb).

-- Helper: get a player's index in playerOrder from their userId.
CREATE OR REPLACE FUNCTION public.fn__sh_player_idx(p_player_order jsonb, p_user_id text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT (idx - 1)::int
  FROM jsonb_array_elements_text(p_player_order) WITH ORDINALITY AS t(uid, idx)
  WHERE uid = p_user_id
  LIMIT 1
$$;

-- Rewrite fn_secretheist_submit_action to use the helper.
CREATE OR REPLACE FUNCTION public.fn_secretheist_submit_action(
  p_game_id text,
  p_action text,
  p_amount int DEFAULT 0
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_idx int;
  v_player_count int;
  v_existing record;
  v_action_seconds int;
  v_locked_count int;
  v_chaos boolean;
  v_valid_actions text[] := ARRAY['steal','protect','spy','trap','hack'];
BEGIN
  SELECT * INTO v_game FROM "secret_heist_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_player_idx := public.fn__sh_player_idx(v_game."playerOrder", auth.uid()::text);
  IF v_player_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_current := (v_board->>'currentRound')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'choosing' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_choosing_phase'); END IF;

  v_chaos := (v_board->>'chaosMode')::boolean;
  IF v_chaos THEN
    v_valid_actions := ARRAY['steal','protect','spy','trap','hack','double_steal','alarm_bait'];
  END IF;
  IF NOT (p_action = ANY(v_valid_actions)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_action');
  END IF;

  IF p_action IN ('steal','hack','double_steal') THEN
    IF p_amount < 10 THEN RETURN jsonb_build_object('ok', false, 'reason', 'amount_too_small'); END IF;
    IF p_amount > 50 THEN RETURN jsonb_build_object('ok', false, 'reason', 'amount_too_large'); END IF;
  END IF;

  SELECT * INTO v_existing FROM "secret_heist_actions"
    WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text AND "roundNumber" = v_current LIMIT 1;
  IF v_existing.id IS NULL THEN
    INSERT INTO "secret_heist_actions" ("gameId","userId","roundNumber","action","amount")
    VALUES (p_game_id, auth.uid()::text, v_current, p_action, p_amount);
  ELSE
    UPDATE "secret_heist_actions" SET "action" = p_action, "amount" = p_amount, "submittedAt" = now()
    WHERE "id" = v_existing.id;
  END IF;

  SELECT count(*) INTO v_locked_count FROM "secret_heist_actions"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current;

  v_round := jsonb_set(v_round, '{lockedCount}', v_locked_count::text::jsonb);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  v_player_count := (v_board->>'playerCount')::int;
  v_action_seconds := (v_board->>'actionSeconds')::int;

  IF v_locked_count >= v_player_count THEN
    v_round := jsonb_set(v_round, '{phase}', '"resolving"');
    v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
    v_board := jsonb_set(v_board, '{rounds}', v_rounds);
    UPDATE "secret_heist_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
    PERFORM public.fn_secretheist_resolve(p_game_id);
    RETURN jsonb_build_object('ok', true, 'resolved', true);
  END IF;

  UPDATE "secret_heist_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_secretheist_submit_action(text, text, int) TO authenticated;

-- Rewrite fn_secretheist_resolve to use the helper for player index lookups.
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
GRANT EXECUTE ON FUNCTION public.fn_secretheist_resolve(text) TO authenticated;

-- Also patch fn_secretheist_intel to use the helper (it doesn't use unnest
-- but let's leave it as-is — it's fine).
