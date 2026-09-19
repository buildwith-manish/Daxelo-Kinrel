-- 20260920200000_night_falls_game.sql
-- Night Falls — classic Werewolf / social deduction game. 5–12 players.
--
-- Roles: Werewolf (2–3), Seer (1), Doctor (1), Hunter (1), Villager (rest).
-- Night phase: Werewolves choose a victim, Seer investigates a player,
-- Doctor protects a player. Day phase: Village debates + votes to
-- eliminate a player. Werewolves win if they equal/outnumber villagers;
-- Villagers win if all werewolves are eliminated.
--
-- Mirrors impostor_games + secret_heist_games schema + RPC pattern.
-- Hidden information: night actions are stored per-player in a separate
-- `night_falls_actions` table with RLS that hides other players' rows
-- until the round is resolved. Roles are stored in `night_falls_players`
-- but the `role` column is hidden via column-level GRANT — only the
-- caller's own role is accessible (via fn_nightfalls_my_role RPC).
-- At game end all roles are published into boardState.roles.

CREATE TABLE IF NOT EXISTS "night_falls_games" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "hostUserId" TEXT NOT NULL,
  "hostUserName" TEXT NOT NULL DEFAULT 'Host',
  "roomName" TEXT,
  status TEXT NOT NULL DEFAULT 'waiting',
  "maxPlayers" INTEGER NOT NULL DEFAULT 12,
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
  "nightSeconds" INTEGER NOT NULL DEFAULT 30,
  "daySeconds" INTEGER NOT NULL DEFAULT 60,
  "voteSeconds" INTEGER NOT NULL DEFAULT 30,
  "roleRevealSeconds" INTEGER NOT NULL DEFAULT 15
);
CREATE INDEX IF NOT EXISTS idx_nfg_family ON "night_falls_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "night_falls_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "night_falls_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "userName" TEXT NOT NULL,
  "role" TEXT,                     -- werewolf | seer | doctor | hunter | villager — NULL until game starts
  "isAlive" BOOLEAN NOT NULL DEFAULT true,
  "isReady" BOOLEAN NOT NULL DEFAULT false,
  "readyAt" TIMESTAMPTZ,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ,
  UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_nfp_game ON "night_falls_players" ("gameId", "joinedAt");

-- Hidden-action table. RLS exposes ONLY the caller's own rows to each
-- player; the resolution RPCs read all rows for the round (as SECURITY
-- DEFINER) and update the games.boardState with the *resolved* outcome.
CREATE TABLE IF NOT EXISTS "night_falls_actions" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "night_falls_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "roundNumber" INTEGER NOT NULL,
  "actionType" TEXT NOT NULL,      -- wolf_kill | seer_investigate | doctor_protect | vote | hunter_revenge
  "targetUserId" TEXT,
  "result" TEXT,                   -- for seer_investigate: 'werewolf' | 'villager'
  "submittedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("gameId", "userId", "roundNumber", "actionType")
);
CREATE INDEX IF NOT EXISTS idx_nfa_game_round ON "night_falls_actions" ("gameId", "roundNumber");

-- ─────────────────────────────────────────────────────────────────
-- RLS — games + players
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "night_falls_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "night_falls_games_select_family" ON "night_falls_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "night_falls_games_insert_host" ON "night_falls_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "night_falls_games_update_family" ON "night_falls_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "night_falls_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "night_falls_players_select_family" ON "night_falls_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "night_falls_games" g WHERE g.id = "night_falls_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "night_falls_players_insert_self_or_host" ON "night_falls_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "night_falls_games" g WHERE g.id = "night_falls_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "night_falls_players_update_self" ON "night_falls_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "night_falls_players_delete_self" ON "night_falls_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- Column-level GRANT: hide the `role` column from authenticated users.
-- Roles are only accessible via the SECURITY DEFINER RPC fn_nightfalls_my_role
-- (for the caller's own role) or published into boardState.roles at game end.
REVOKE ALL ON "night_falls_players" FROM authenticated;
GRANT SELECT (id, "gameId", "userId", "userName", "isAlive", "isReady", "readyAt", "joinedAt", "lastActivityAt", "leftAt") ON "night_falls_players" TO authenticated;
GRANT INSERT (id, "gameId", "userId", "userName", "isReady", "joinedAt") ON "night_falls_players" TO authenticated;
GRANT UPDATE ("isReady", "readyAt", "lastActivityAt", "leftAt", "isAlive") ON "night_falls_players" TO authenticated;

-- Hidden-action RLS: a player can see / insert / update only their OWN
-- actions. The resolution RPCs run as SECURITY DEFINER so they bypass
-- RLS to read everyone's actions.
ALTER TABLE "night_falls_actions" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "night_falls_actions_select_own" ON "night_falls_actions" FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "night_falls_actions_insert_own" ON "night_falls_actions" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "night_falls_actions_update_own" ON "night_falls_actions" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "night_falls_actions_delete_own" ON "night_falls_actions" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "night_falls_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "night_falls_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "night_falls_actions";
ALTER TABLE "night_falls_games" REPLICA IDENTITY FULL;
ALTER TABLE "night_falls_players" REPLICA IDENTITY FULL;
ALTER TABLE "night_falls_actions" REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_start — host starts the match. Assigns roles randomly,
-- initializes boardState with round 1 in 'role_reveal' phase.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nightfalls_start(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_players jsonb;
  v_count int;
  v_order text[];
  v_i int;
  v_wolf_count int;
  v_roles text[];
  v_shuffled text[];
  v_board jsonb;
  v_players_arr jsonb;
  v_role text;
  v_night_seconds int;
  v_day_seconds int;
  v_vote_seconds int;
  v_role_reveal_seconds int;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "night_falls_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_count := jsonb_array_length(v_players);
  IF v_count < 5 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;

  FOR v_i IN 0..v_count - 1 LOOP v_order := array_append(v_order, v_players->v_i->>'userId'); END LOOP;

  -- Role distribution: 2 wolves for 5–8 players, 3 wolves for 9–12.
  v_wolf_count := CASE WHEN v_count >= 9 THEN 3 ELSE 2 END;

  -- Build the role pool: wolves + 1 seer + 1 doctor + 1 hunter + rest villagers
  v_roles := ARRAY[]::text[];
  FOR v_i IN 1..v_wolf_count LOOP v_roles := array_append(v_roles, 'werewolf'); END LOOP;
  v_roles := array_append(v_roles, 'seer');
  v_roles := array_append(v_roles, 'doctor');
  v_roles := array_append(v_roles, 'hunter');
  FOR v_i IN 1..(v_count - v_wolf_count - 3) LOOP v_roles := array_append(v_roles, 'villager'); END LOOP;

  -- Fisher–Yates shuffle
  v_shuffled := v_roles;
  FOR v_i IN REVERSE v_count..2 LOOP
    DECLARE v_j int; v_tmp text; BEGIN
      v_j := floor(random() * v_i)::int + 1;
      v_tmp := v_shuffled[v_j];
      v_shuffled[v_j] := v_shuffled[v_i];
      v_shuffled[v_i] := v_tmp;
    END;
  END LOOP;

  -- Assign roles to players + build players array
  v_players_arr := '[]'::jsonb;
  FOR v_i IN 1..v_count LOOP
    v_role := v_shuffled[v_i];
    UPDATE "night_falls_players" SET "role" = v_role, "isAlive" = true
      WHERE "gameId" = p_game_id AND "userId" = v_order[v_i];
    v_players_arr := v_players_arr || jsonb_build_object(
      'idx', v_i - 1,
      'userId', v_order[v_i],
      'name', v_players->(v_i - 1)->>'userName',
      'isAlive', true
    );
  END LOOP;

  v_night_seconds := v_game."nightSeconds";
  v_day_seconds := v_game."daySeconds";
  v_vote_seconds := v_game."voteSeconds";
  v_role_reveal_seconds := v_game."roleRevealSeconds";

  v_board := jsonb_build_object(
    'playerCount', v_count,
    'nightSeconds', v_night_seconds,
    'daySeconds', v_day_seconds,
    'voteSeconds', v_vote_seconds,
    'roleRevealSeconds', v_role_reveal_seconds,
    'currentRoundNumber', 1,
    'rounds', jsonb_build_array(jsonb_build_object(
      'roundNumber', 1,
      'phase', 'role_reveal',
      'nightActions', jsonb_build_object('lockedCount', 0, 'killedUserId', null, 'killedUserName', null, 'noKill', false),
      'dayVotes', '[]'::jsonb,
      'voteLockedCount', 0,
      'eliminatedUserId', null,
      'eliminatedUserName', null,
      'eliminatedRole', null,
      'hunterRevengePending', false,
      'hunterRevengeTargetId', null,
      'hunterRevengeTargetName', null,
      'hunterRevengeRole', null
    )),
    'players', v_players_arr,
    'status', 'in_progress',
    'winnerTeam', null,
    'rolesRevealed', false,
    'roles', '{}'::jsonb
  );

  UPDATE "night_falls_games" SET
    status = 'in_progress',
    "playerOrder" = to_jsonb(v_order),
    "currentPlayerId" = v_order[1],
    "boardState" = v_board,
    "startedAt" = now(),
    "turnEndsAt" = now() + (v_role_reveal_seconds || ' seconds')::interval,
    "lastActivityAt" = now()
  WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_start(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_my_role — returns the caller's role + fellow werewolves
-- (if the caller is a werewolf) as a jsonb object. Roles are hidden via
-- column-level GRANT on night_falls_players; this RPC is the only way
-- for a client to learn their own role.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nightfalls_my_role(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text;
  v_fellow_wolves jsonb;
BEGIN
  SELECT "role" INTO v_role FROM "night_falls_players"
    WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_role IS NULL THEN RETURN jsonb_build_object('role', null, 'fellowWolves', '[]'::jsonb); END IF;
  IF v_role = 'werewolf' THEN
    SELECT COALESCE(jsonb_agg("userId"), '[]'::jsonb) INTO v_fellow_wolves
      FROM "night_falls_players"
      WHERE "gameId" = p_game_id AND "role" = 'werewolf' AND "userId" <> auth.uid()::text;
  ELSE
    v_fellow_wolves := '[]'::jsonb;
  END IF;
  RETURN jsonb_build_object('role', v_role, 'fellowWolves', v_fellow_wolves);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_my_role(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_submit_night_action — a player secretly submits their
-- night action (wolf_kill / seer_investigate / doctor_protect). The
-- action is recorded in night_falls_actions (RLS hides it from other
-- players). boardState.rounds[i].nightActions.lockedCount is
-- incremented so all clients can see "X/N locked" without seeing WHO
-- locked. When all role-players have locked, fn_nightfalls_resolve_night
-- is called automatically.
-- ─────────────────────────────────────────────────────────────────
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

  SELECT "role" INTO v_my_role FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_my_role IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;

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

  -- Auto-resolve when all role-players have locked
  v_wolf_count := CASE WHEN (v_board->>'playerCount')::int >= 9 THEN 3 ELSE 2 END;
  v_expected_locks := v_wolf_count + 2;  -- wolves + seer + doctor
  IF v_locked_count >= v_expected_locks THEN
    UPDATE "night_falls_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
    PERFORM public.fn_nightfalls_resolve_night(p_game_id);
    RETURN jsonb_build_object('ok', true, 'resolved', true);
  END IF;

  UPDATE "night_falls_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_submit_night_action(text, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_resolve_night — resolves all night actions. Runs as
-- SECURITY DEFINER so it can read all players' actions for the round.
--
-- Resolution:
--   1. Tally wolf_kill targets — pick the most-voted (ties: most recent).
--   2. Read doctor_protect target.
--   3. If doctor's target == wolf kill target → noKill = true.
--      Else → killedUserId = wolf kill target, mark dead.
--   4. Read seer_investigate target. Look up target's role. Update the
--      seer's action row with result = 'werewolf' or 'villager'.
--   5. Check win condition. Advance phase to 'day'.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nightfalls_resolve_night(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_count int;
  v_night_seconds int;
  v_day_seconds int;
  v_wolf_action record;
  v_wolf_target text;
  v_doctor_target text;
  v_seer_target text;
  v_seer_action record;
  v_target_role text;
  v_killed_name text;
  v_max_votes int;
  v_count int;
  v_i int;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRoundNumber')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'night' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_night_phase'); END IF;
  v_player_count := (v_board->>'playerCount')::int;
  v_night_seconds := (v_board->>'nightSeconds')::int;
  v_day_seconds := (v_board->>'daySeconds')::int;

  -- 1. Tally wolf_kill targets — pick most-voted (ties: most recent submission)
  v_max_votes := 0; v_wolf_target := null;
  FOR v_wolf_action IN
    SELECT "targetUserId", count(*) AS cnt, max("submittedAt") AS latest
    FROM "night_falls_actions"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "actionType" = 'wolf_kill'
    GROUP BY "targetUserId"
    ORDER BY cnt DESC, latest DESC
  LOOP
    IF v_wolf_target IS NULL THEN v_wolf_target := v_wolf_action."targetUserId"; v_max_votes := v_wolf_action.cnt; END IF;
  END LOOP;

  -- 2. Read doctor's protect target
  SELECT "targetUserId" INTO v_doctor_target FROM "night_falls_actions"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "actionType" = 'doctor_protect' LIMIT 1;

  -- 3. Determine kill
  IF v_wolf_target IS NOT NULL AND v_wolf_target <> v_doctor_target THEN
    -- Kill the target
    SELECT "userName" INTO v_killed_name FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = v_wolf_target;
    UPDATE "night_falls_players" SET "isAlive" = false WHERE "gameId" = p_game_id AND "userId" = v_wolf_target;
    -- Mark killed in boardState players array
    FOR v_i IN 0..v_player_count - 1 LOOP
      IF v_board->'players'->v_i->>'userId' = v_wolf_target THEN
        v_board := jsonb_set(v_board, ARRAY['players', v_i::text, 'isAlive'], 'false'::jsonb);
      END IF;
    END LOOP;
    v_round := jsonb_set(v_round, '{nightActions,killedUserId}', to_jsonb(v_wolf_target));
    v_round := jsonb_set(v_round, '{nightActions,killedUserName}', to_jsonb(v_killed_name));
    v_round := jsonb_set(v_round, '{nightActions,noKill}', 'false'::jsonb);
  ELSE
    -- No kill (either no wolf submitted, or doctor saved the victim)
    v_round := jsonb_set(v_round, '{nightActions,killedUserId}', 'null'::jsonb);
    v_round := jsonb_set(v_round, '{nightActions,killedUserName}', 'null'::jsonb);
    v_round := jsonb_set(v_round, '{nightActions,noKill}', 'true'::jsonb);
  END IF;

  -- 4. Seer investigation — look up target's role, store result in seer's action row
  SELECT * INTO v_seer_action FROM "night_falls_actions"
    WHERE "gameId" = p_game_id AND "roundNumber" = v_current AND "actionType" = 'seer_investigate' LIMIT 1;
  IF v_seer_action.id IS NOT NULL THEN
    v_seer_target := v_seer_action."targetUserId";
    SELECT "role" INTO v_target_role FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = v_seer_target;
    IF v_target_role = 'werewolf' THEN
      UPDATE "night_falls_actions" SET "result" = 'werewolf' WHERE "id" = v_seer_action.id;
    ELSE
      UPDATE "night_falls_actions" SET "result" = 'villager' WHERE "id" = v_seer_action.id;
    END IF;
  END IF;

  -- 5. Advance phase to 'day'
  v_round := jsonb_set(v_round, '{phase}', '"day"');
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  UPDATE "night_falls_games" SET "boardState" = v_board, "turnEndsAt" = now() + (v_day_seconds || ' seconds')::interval, "lastActivityAt" = now() WHERE id = p_game_id;

  -- Check win condition (night kill could end the game)
  PERFORM public.fn__nightfalls_check_win(p_game_id);
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_resolve_night(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn__nightfalls_check_win — internal helper. Checks alive counts and
-- completes the game if a team has won. Publishes all roles into
-- boardState.roles when the game ends.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn__nightfalls_check_win(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_alive_wolves int;
  v_alive_villagers int;
  v_winner text;
  v_winner_ids jsonb;
  v_roles jsonb;
  v_r record;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;

  SELECT count(*) INTO v_alive_wolves FROM "night_falls_players"
    WHERE "gameId" = p_game_id AND "role" = 'werewolf' AND "isAlive" = true;
  SELECT count(*) INTO v_alive_villagers FROM "night_falls_players"
    WHERE "gameId" = p_game_id AND "role" <> 'werewolf' AND "isAlive" = true;

  IF v_alive_wolves = 0 THEN
    v_winner := 'village';
  ELSIF v_alive_wolves >= v_alive_villagers THEN
    v_winner := 'wolves';
  ELSE
    RETURN;  -- game continues
  END IF;

  -- Build winner user IDs + roles map
  SELECT COALESCE(jsonb_agg("userId"), '[]'::jsonb) INTO v_winner_ids
    FROM "night_falls_players"
    WHERE "gameId" = p_game_id AND "isAlive" = true
      AND ((v_winner = 'village' AND "role" <> 'werewolf')
        OR (v_winner = 'wolves' AND "role" = 'werewolf'));

  v_roles := '{}'::jsonb;
  FOR v_r IN SELECT "userId", "role" FROM "night_falls_players" WHERE "gameId" = p_game_id LOOP
    v_roles := v_roles || jsonb_build_object(v_r."userId", v_r."role");
  END LOOP;

  v_board := v_game."boardState";
  v_board := jsonb_set(v_board, '{status}', '"completed"');
  v_board := jsonb_set(v_board, '{winnerTeam}', to_jsonb(v_winner));
  v_board := jsonb_set(v_board, '{rolesRevealed}', 'true'::jsonb);
  v_board := jsonb_set(v_board, '{roles}', v_roles);

  UPDATE "night_falls_games" SET
    "boardState" = v_board,
    status = 'completed',
    "completedAt" = now(),
    "winnerUserIds" = v_winner_ids,
    "endReason" = CASE v_winner WHEN 'village' THEN 'village_wins' ELSE 'wolves_win' END,
    "lastActivityAt" = now()
  WHERE id = p_game_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_vote — a player votes to eliminate another player.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nightfalls_vote(p_game_id text, p_target_user_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_count int;
  v_existing record;
  v_locked_count int;
  v_alive_count int;
  v_target_alive boolean;
  v_my_alive boolean;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRoundNumber')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'vote' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_vote_phase'); END IF;

  -- Caller must be alive
  SELECT "isAlive" INTO v_my_alive FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF NOT v_my_alive THEN RETURN jsonb_build_object('ok', false, 'reason', 'voter_dead'); END IF;

  -- Target must be alive + in game
  SELECT "isAlive" INTO v_target_alive FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = p_target_user_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'invalid_target'); END IF;
  IF NOT v_target_alive THEN RETURN jsonb_build_object('ok', false, 'reason', 'target_dead'); END IF;
  IF p_target_user_id = auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'cant_vote_self'); END IF;

  -- Insert or update vote
  SELECT * INTO v_existing FROM "night_falls_actions"
    WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text AND "roundNumber" = v_current AND "actionType" = 'vote' LIMIT 1;
  IF v_existing.id IS NULL THEN
    INSERT INTO "night_falls_actions" ("gameId","userId","roundNumber","actionType","targetUserId")
    VALUES (p_game_id, auth.uid()::text, v_current, 'vote', p_target_user_id);
  ELSE
    UPDATE "night_falls_actions" SET "targetUserId" = p_target_user_id, "submittedAt" = now() WHERE "id" = v_existing.id;
  END IF;

  -- Recompute vote locked count (distinct alive voters)
  SELECT count(DISTINCT a."userId") INTO v_locked_count
    FROM "night_falls_actions" a
    JOIN "night_falls_players" p ON p."userId" = a."userId" AND p."gameId" = a."gameId"
    WHERE a."gameId" = p_game_id AND a."roundNumber" = v_current AND a."actionType" = 'vote' AND p."isAlive" = true;

  v_round := jsonb_set(v_round, '{voteLockedCount}', v_locked_count::text::jsonb);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  -- Count alive players
  SELECT count(*) INTO v_alive_count FROM "night_falls_players" WHERE "gameId" = p_game_id AND "isAlive" = true;

  -- Auto-resolve when all alive players have voted
  IF v_locked_count >= v_alive_count THEN
    UPDATE "night_falls_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
    PERFORM public.fn_nightfalls_resolve_vote(p_game_id);
    RETURN jsonb_build_object('ok', true, 'resolved', true);
  END IF;

  UPDATE "night_falls_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_vote(text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_resolve_vote — tallies votes, eliminates the most-voted
-- player (ties = no elimination). Reveals their role. If the eliminated
-- player is the hunter, sets hunterRevengePending = true.
-- ─────────────────────────────────────────────────────────────────
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
    -- If hunter was eliminated, set revenge pending
    IF v_eliminated_role = 'hunter' THEN
      v_round := jsonb_set(v_round, '{hunterRevengePending}', 'true'::jsonb);
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
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_resolve_vote(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_hunter_revenge — the hunter (when eliminated by vote)
-- picks one player to take down with them.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nightfalls_hunter_revenge(p_game_id text, p_target_user_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_count int;
  v_my_role text;
  v_target_alive boolean;
  v_target_name text;
  v_target_role text;
  v_i int;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRoundNumber')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  IF v_round->>'phase' <> 'result' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_result_phase'); END IF;
  IF (v_round->>'hunterRevengePending')::boolean <> true THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_revenge_pending'); END IF;

  -- Caller must be the eliminated hunter
  SELECT "role" INTO v_my_role FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  IF v_my_role <> 'hunter' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_hunter'); END IF;

  -- Target must be alive + in game
  SELECT "isAlive", "userName", "role" INTO v_target_alive, v_target_name, v_target_role FROM "night_falls_players" WHERE "gameId" = p_game_id AND "userId" = p_target_user_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'invalid_target'); END IF;
  IF NOT v_target_alive THEN RETURN jsonb_build_object('ok', false, 'reason', 'target_dead'); END IF;

  -- Record the revenge action
  INSERT INTO "night_falls_actions" ("gameId","userId","roundNumber","actionType","targetUserId")
  VALUES (p_game_id, auth.uid()::text, v_current, 'hunter_revenge', p_target_user_id)
  ON CONFLICT ("gameId","userId","roundNumber","actionType") DO UPDATE SET "targetUserId" = excluded."targetUserId", "submittedAt" = now();

  -- Kill the target
  UPDATE "night_falls_players" SET "isAlive" = false WHERE "gameId" = p_game_id AND "userId" = p_target_user_id;
  v_player_count := (v_board->>'playerCount')::int;
  FOR v_i IN 0..v_player_count - 1 LOOP
    IF v_board->'players'->v_i->>'userId' = p_target_user_id THEN
      v_board := jsonb_set(v_board, ARRAY['players', v_i::text, 'isAlive'], 'false'::jsonb);
    END IF;
  END LOOP;

  v_round := jsonb_set(v_round, '{hunterRevengeTargetId}', to_jsonb(p_target_user_id));
  v_round := jsonb_set(v_round, '{hunterRevengeTargetName}', to_jsonb(v_target_name));
  v_round := jsonb_set(v_round, '{hunterRevengeRole}', to_jsonb(v_target_role));
  v_round := jsonb_set(v_round, '{hunterRevengePending}', 'false'::jsonb);
  v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
  v_board := jsonb_set(v_board, '{rounds}', v_rounds);

  UPDATE "night_falls_games" SET "boardState" = v_board, "lastActivityAt" = now() WHERE id = p_game_id;

  -- Check win condition (hunter revenge could end the game)
  PERFORM public.fn__nightfalls_check_win(p_game_id);
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_hunter_revenge(text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_advance — advances the phase machine:
--   role_reveal → night
--   day → vote
--   result → night (next round) or finished
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nightfalls_advance(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
  v_rounds jsonb;
  v_current int;
  v_player_count int;
  v_night_seconds int;
  v_vote_seconds int;
  v_new_round jsonb;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  v_current := (v_board->>'currentRoundNumber')::int;
  v_round := v_board->'rounds'->(v_current - 1);
  v_player_count := (v_board->>'playerCount')::int;
  v_night_seconds := (v_board->>'nightSeconds')::int;
  v_vote_seconds := (v_board->>'voteSeconds')::int;

  IF v_round->>'phase' = 'role_reveal' THEN
    v_round := jsonb_set(v_round, '{phase}', '"night"');
    v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
    v_board := jsonb_set(v_board, '{rounds}', v_rounds);
    UPDATE "night_falls_games" SET "boardState" = v_board, "turnEndsAt" = now() + (v_night_seconds || ' seconds')::interval, "lastActivityAt" = now() WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true);
  ELSIF v_round->>'phase' = 'day' THEN
    v_round := jsonb_set(v_round, '{phase}', '"vote"');
    v_rounds := jsonb_set(v_board->'rounds', ARRAY[(v_current - 1)::text], v_round);
    v_board := jsonb_set(v_board, '{rounds}', v_rounds);
    UPDATE "night_falls_games" SET "boardState" = v_board, "turnEndsAt" = now() + (v_vote_seconds || ' seconds')::interval, "lastActivityAt" = now() WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true);
  ELSIF v_round->>'phase' = 'result' THEN
    -- If hunter revenge is still pending, can't advance yet
    IF (v_round->>'hunterRevengePending')::boolean = true THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'hunter_revenge_pending');
    END IF;
    -- Start next round
    v_new_round := jsonb_build_object(
      'roundNumber', v_current + 1,
      'phase', 'night',
      'nightActions', jsonb_build_object('lockedCount', 0, 'killedUserId', null, 'killedUserName', null, 'noKill', false),
      'dayVotes', '[]'::jsonb,
      'voteLockedCount', 0,
      'eliminatedUserId', null,
      'eliminatedUserName', null,
      'eliminatedRole', null,
      'hunterRevengePending', false,
      'hunterRevengeTargetId', null,
      'hunterRevengeTargetName', null,
      'hunterRevengeRole', null
    );
    v_rounds := v_board->'rounds' || v_new_round;
    v_board := jsonb_set(v_board, '{rounds}', v_rounds);
    v_board := jsonb_set(v_board, '{currentRoundNumber}', (v_current + 1)::text::jsonb);
    UPDATE "night_falls_games" SET "boardState" = v_board, "turnEndsAt" = now() + (v_night_seconds || ' seconds')::interval, "lastActivityAt" = now() WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true);
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_phase');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_advance(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_tick — 2s watchdog. Advances phases on timer expiry.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nightfalls_tick(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_round jsonb;
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
    -- Only auto-advance if hunter revenge is not pending
    IF (v_round->>'hunterRevengePending')::boolean <> true THEN
      PERFORM public.fn_nightfalls_advance(p_game_id);
    END IF;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_tick(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_nightfalls_leave — a player leaves. If too few remain, the game
-- ends as a walkover (survivors win).
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nightfalls_leave(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_active int;
  v_alive_wolves int;
  v_alive_villagers int;
  v_winner text;
  v_board jsonb;
  v_player_count int;
  v_i int;
BEGIN
  SELECT * INTO v_game FROM "night_falls_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "night_falls_players" SET "leftAt" = now(), "isAlive" = false WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  -- Update boardState players array to reflect departure
  IF v_game."boardState" IS NOT NULL THEN
    v_board := v_game."boardState";
    v_player_count := COALESCE(jsonb_array_length(v_board->'players'), 0);
    FOR v_i IN 0..v_player_count - 1 LOOP
      IF v_board->'players'->v_i->>'userId' = auth.uid()::text THEN
        v_board := jsonb_set(v_board, ARRAY['players', v_i::text, 'isAlive'], 'false'::jsonb);
      END IF;
    END LOOP;
    UPDATE "night_falls_games" SET "boardState" = v_board WHERE id = p_game_id;
  END IF;

  IF v_game.status = 'in_progress' THEN
    SELECT count(*) INTO v_active FROM "night_falls_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
    SELECT count(*) INTO v_alive_wolves FROM "night_falls_players" WHERE "gameId" = p_game_id AND "role" = 'werewolf' AND "isAlive" = true;
    SELECT count(*) INTO v_alive_villagers FROM "night_falls_players" WHERE "gameId" = p_game_id AND "role" <> 'werewolf' AND "isAlive" = true;
    -- Walkover if fewer than 3 active players, or one side is empty
    IF v_active < 3 OR v_alive_wolves = 0 OR v_alive_villagers = 0 THEN
      IF v_alive_wolves = 0 AND v_alive_villagers > 0 THEN v_winner := 'village';
      ELSIF v_alive_wolves > 0 AND v_alive_villagers = 0 THEN v_winner := 'wolves';
      ELSE v_winner := null; END IF;
      PERFORM public.fn__nightfalls_finalize_walkover(p_game_id, v_winner);
    END IF;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_nightfalls_leave(text) TO authenticated;

-- Helper to finalize a walkover
CREATE OR REPLACE FUNCTION public.fn__nightfalls_finalize_walkover(p_game_id text, p_winner text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_board jsonb;
  v_winner_ids jsonb;
  v_roles jsonb;
  v_r record;
BEGIN
  SELECT "boardState" INTO v_board FROM "night_falls_games" WHERE id = p_game_id;
  v_roles := '{}'::jsonb;
  FOR v_r IN SELECT "userId", "role" FROM "night_falls_players" WHERE "gameId" = p_game_id LOOP
    v_roles := v_roles || jsonb_build_object(v_r."userId", v_r."role");
  END LOOP;
  SELECT COALESCE(jsonb_agg("userId"), '[]'::jsonb) INTO v_winner_ids
    FROM "night_falls_players"
    WHERE "gameId" = p_game_id AND "isAlive" = true
      AND ((p_winner = 'village' AND "role" <> 'werewolf')
        OR (p_winner = 'wolves' AND "role" = 'werewolf'));
  v_board := jsonb_set(v_board, '{status}', '"completed"');
  v_board := jsonb_set(v_board, '{winnerTeam}', to_jsonb(COALESCE(p_winner, 'abandoned')));
  v_board := jsonb_set(v_board, '{rolesRevealed}', 'true'::jsonb);
  v_board := jsonb_set(v_board, '{roles}', v_roles);
  UPDATE "night_falls_games" SET
    "boardState" = v_board,
    status = 'completed',
    "completedAt" = now(),
    "winnerUserIds" = v_winner_ids,
    "endReason" = 'walkover',
    "lastActivityAt" = now()
  WHERE id = p_game_id;
END;
$$;

-- Archive trigger
CREATE OR REPLACE FUNCTION public.fn__nightfalls_on_complete() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('night_falls_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'nightfalls archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_nightfalls_archive ON "night_falls_games";
CREATE TRIGGER trg_nightfalls_archive AFTER UPDATE ON "night_falls_games" FOR EACH ROW EXECUTE FUNCTION public.fn__nightfalls_on_complete();

-- ─────────────────────────────────────────────────────────────────
-- Whitelist + metadata (extend fn_touch_game_activity + fn__game_meta)
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
    'flick_arena_games','secret_heist_games','mind_match_games','code_clues_games',
    'night_falls_games'
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
    'night_falls_games', jsonb_build_object('id','night-falls','name','Night Falls','icon','🌙','accent','#6366F1')
  );
$$;

INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'night-hunter','Night Hunter','नाइट हंटर','Win 5 Night Falls games','🌙','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;
