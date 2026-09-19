-- 20260920220000_sketch_telephone_game.sql
-- Sketch Telephone — Gartic Phone-style drawing chain. 4–8 players.
--
-- Each player writes a secret prompt. That prompt rotates to the next
-- player, who draws it. Their drawing rotates to the next player, who
-- describes it. Their description rotates to the next player, who draws
-- it. And so on. After N rounds (one per player), every chain has been
-- touched by every player exactly once. The chains are then revealed
-- step-by-step — the "telephone" degradation creates the comedy.
--
-- Architecture reuses the hidden-submission + parallel-step pattern
-- from mind_match: the games row carries boardState (currentStep, phase,
-- chains metadata) and the chains table stores the actual content rows
-- (prompt text, drawing stroke JSON, description text). RLS lets any
-- family member read the chains table so the reveal screen can render
-- every chain — but during the active writing/drawing phase the UI
-- only surfaces the player's assigned chain (the previous step in the
-- chain they're currently working on).
--
-- Step rotation:
--   At step k (0-indexed), player at index j works on the chain owned
--   by player at index (j + k) mod N. At step 0, each player writes
--   the prompt on their own chain. After N steps, all chains are done.
--
-- Step type:
--   step 0         → prompt (text)
--   step odd       → drawing (stroke JSON)
--   step even > 0  → description (text)

CREATE TABLE IF NOT EXISTS "sketch_telephone_games" (
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
  "drawingSeconds" INTEGER NOT NULL DEFAULT 90
);
CREATE INDEX IF NOT EXISTS idx_stg_family ON "sketch_telephone_games" ("familyId", "createdAt" DESC);

CREATE TABLE IF NOT EXISTS "sketch_telephone_players" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "sketch_telephone_games"(id) ON DELETE CASCADE,
  "userId" TEXT NOT NULL,
  "userName" TEXT NOT NULL,
  "isReady" BOOLEAN NOT NULL DEFAULT false,
  "readyAt" TIMESTAMPTZ,
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "lastActivityAt" TIMESTAMPTZ DEFAULT now(),
  "leftAt" TIMESTAMPTZ,
  UNIQUE ("gameId", "userId")
);
CREATE INDEX IF NOT EXISTS idx_stp_game ON "sketch_telephone_players" ("gameId", "joinedAt");

-- Each row is a single step in a single chain. stepType is
-- 'prompt' | 'drawing' | 'description'. content is text (prompt /
-- description) or stroke JSON (drawing). RLS: family-readable so the
-- reveal phase can show every chain; only the author can insert /
-- update their own row.
CREATE TABLE IF NOT EXISTS "sketch_telephone_chains" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "gameId" TEXT NOT NULL REFERENCES "sketch_telephone_games"(id) ON DELETE CASCADE,
  "chainIndex" INTEGER NOT NULL,
  "stepIndex" INTEGER NOT NULL,
  "stepType" TEXT NOT NULL,
  "content" TEXT,
  "authorUserId" TEXT NOT NULL,
  "authorUserName" TEXT NOT NULL DEFAULT 'Player',
  "submittedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("gameId", "chainIndex", "stepIndex")
);
CREATE INDEX IF NOT EXISTS idx_stc_game_chain_step ON "sketch_telephone_chains" ("gameId", "chainIndex", "stepIndex");
CREATE INDEX IF NOT EXISTS idx_stc_game_step ON "sketch_telephone_chains" ("gameId", "stepIndex");

-- Prompt suggestions for the seed prompt button (50 prompts).
CREATE TABLE IF NOT EXISTS "sketch_telephone_prompts" (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  prompt TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  active BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX IF NOT EXISTS idx_stp_active ON "sketch_telephone_prompts" (active);

-- ─────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "sketch_telephone_games" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sketch_telephone_games_select_family" ON "sketch_telephone_games" FOR SELECT TO authenticated USING (public.fn_user_is_family_member("familyId"));
CREATE POLICY "sketch_telephone_games_insert_host" ON "sketch_telephone_games" FOR INSERT TO authenticated WITH CHECK ("hostUserId" = auth.uid()::text AND public.fn_user_is_family_member("familyId"));
CREATE POLICY "sketch_telephone_games_update_family" ON "sketch_telephone_games" FOR UPDATE TO authenticated USING (public.fn_user_is_family_member("familyId"));

ALTER TABLE "sketch_telephone_players" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sketch_telephone_players_select_family" ON "sketch_telephone_players" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "sketch_telephone_games" g WHERE g.id = "sketch_telephone_players"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "sketch_telephone_players_insert_self_or_host" ON "sketch_telephone_players" FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text OR EXISTS (SELECT 1 FROM "sketch_telephone_games" g WHERE g.id = "sketch_telephone_players"."gameId" AND g."hostUserId" = auth.uid()::text));
CREATE POLICY "sketch_telephone_players_update_self" ON "sketch_telephone_players" FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "sketch_telephone_players_delete_self" ON "sketch_telephone_players" FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER TABLE "sketch_telephone_chains" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sketch_telephone_chains_select_family" ON "sketch_telephone_chains" FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM "sketch_telephone_games" g WHERE g.id = "sketch_telephone_chains"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "sketch_telephone_chains_insert_author" ON "sketch_telephone_chains" FOR INSERT TO authenticated WITH CHECK ("authorUserId" = auth.uid()::text AND EXISTS (SELECT 1 FROM "sketch_telephone_games" g WHERE g.id = "sketch_telephone_chains"."gameId" AND public.fn_user_is_family_member(g."familyId")));
CREATE POLICY "sketch_telephone_chains_update_author" ON "sketch_telephone_chains" FOR UPDATE TO authenticated USING ("authorUserId" = auth.uid()::text);
CREATE POLICY "sketch_telephone_chains_delete_author" ON "sketch_telephone_chains" FOR DELETE TO authenticated USING ("authorUserId" = auth.uid()::text);

ALTER TABLE "sketch_telephone_prompts" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sketch_telephone_prompts_select_all" ON "sketch_telephone_prompts" FOR SELECT TO authenticated USING (active = true);

ALTER PUBLICATION supabase_realtime ADD TABLE "sketch_telephone_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "sketch_telephone_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "sketch_telephone_chains";
ALTER TABLE "sketch_telephone_games" REPLICA IDENTITY FULL;
ALTER TABLE "sketch_telephone_players" REPLICA IDENTITY FULL;
ALTER TABLE "sketch_telephone_chains" REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────
-- fn_sketchtelephone_step_type — returns 'prompt' | 'drawing' | 'description'
-- for a given 0-indexed step. Mirrors the Dart helper.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sketchtelephone_step_type(p_step int) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_step = 0 THEN 'prompt'
    WHEN mod(p_step, 2) = 1 THEN 'drawing'
    ELSE 'description'
  END
$$;

-- ─────────────────────────────────────────────────────────────────
-- fn_sketchtelephone_start — host starts the match.
-- Initializes boardState with N players, N empty chains, step 0 (writing).
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sketchtelephone_start(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_players jsonb;
  v_count int;
  v_order text[];
  v_i int;
  v_board jsonb;
  v_players_arr jsonb;
  v_chains_arr jsonb;
  v_drawing_seconds int;
BEGIN
  SELECT * INTO v_game FROM "sketch_telephone_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_game."hostUserId" <> auth.uid()::text THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_host'); END IF;
  IF v_game.status <> 'waiting' THEN RETURN jsonb_build_object('ok', false, 'reason', 'already_started'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId', p."userId", 'userName', p."userName") ORDER BY p."joinedAt"), '[]'::jsonb) INTO v_players
  FROM "sketch_telephone_players" p WHERE p."gameId" = p_game_id AND p."leftAt" IS NULL;
  v_count := jsonb_array_length(v_players);
  IF v_count < 4 THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_enough_players'); END IF;
  FOR v_i IN 0..v_count - 1 LOOP v_order := array_append(v_order, v_players->v_i->>'userId'); END LOOP;
  -- Build players array
  v_players_arr := '[]'::jsonb;
  FOR v_i IN 0..v_count - 1 LOOP
    v_players_arr := v_players_arr || jsonb_build_object(
      'idx', v_i,
      'userId', v_players->v_i->>'userId',
      'name', v_players->v_i->>'userName'
    );
  END LOOP;
  -- Build N empty chains (one per player, owned by that player)
  v_chains_arr := '[]'::jsonb;
  FOR v_i IN 0..v_count - 1 LOOP
    v_chains_arr := v_chains_arr || jsonb_build_object(
      'chainIndex', v_i,
      'ownerUserId', v_players->v_i->>'userId',
      'ownerName', v_players->v_i->>'userName',
      'steps', '[]'::jsonb
    );
  END LOOP;
  v_drawing_seconds := v_game."drawingSeconds";
  v_board := jsonb_build_object(
    'playerCount', v_count,
    'drawingSeconds', v_drawing_seconds,
    'currentStep', 0,
    'phase', 'writing',
    'chains', v_chains_arr,
    'players', v_players_arr,
    'status', 'in_progress',
    'winnerIndex', -1
  );
  UPDATE "sketch_telephone_games" SET
    status = 'in_progress',
    "playerOrder" = to_jsonb(v_order),
    "currentPlayerId" = v_order[1],
    "boardState" = v_board,
    "startedAt" = now(),
    "turnEndsAt" = now() + (v_drawing_seconds || ' seconds')::interval,
    "lastActivityAt" = now()
  WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_sketchtelephone_start(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_sketchtelephone_submit_step — a player submits the content for
-- the current step on the chain they're assigned to.
--
-- Chain assignment: at step k, player at index j works on chain
-- owned by player at index (j + k) mod N. Equivalently: chainIndex
-- of the chain they're working on equals (j + k) mod N.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sketchtelephone_submit_step(
  p_game_id text,
  p_content text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_player_idx int;
  v_player_count int;
  v_current_step int;
  v_chain_idx int;
  v_step_type text;
  v_existing record;
  v_submitted_count int;
  v_drawing_seconds int;
  v_player_name text;
BEGIN
  SELECT * INTO v_game FROM "sketch_telephone_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  IF v_board->>'phase' = 'revealing' OR v_board->>'phase' = 'finished' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_active_phase');
  END IF;
  v_player_idx := (SELECT idx - 1 FROM jsonb_array_elements_text(v_game."playerOrder") WITH ORDINALITY AS t(uid, idx) WHERE uid = auth.uid()::text);
  IF v_player_idx IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_game'); END IF;
  v_current_step := (v_board->>'currentStep')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_drawing_seconds := (v_board->>'drawingSeconds')::int;
  -- Chain this player is working on at this step
  v_chain_idx := mod(v_player_idx + v_current_step, v_player_count);
  v_step_type := public.fn_sketchtelephone_step_type(v_current_step);
  -- Validate content
  IF p_content IS NULL OR btrim(p_content) = '' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'empty_content');
  END IF;
  -- For prompt / description, cap length
  IF v_step_type <> 'drawing' AND length(p_content) > 200 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'content_too_long');
  END IF;
  -- Get player name
  SELECT name INTO v_player_name FROM jsonb_array_elements(v_board->'players') AS p WHERE (p->>'idx')::int = v_player_idx LIMIT 1;
  IF v_player_name IS NULL THEN v_player_name := 'Player'; END IF;

  -- Insert or update the chain step
  SELECT * INTO v_existing FROM "sketch_telephone_chains"
    WHERE "gameId" = p_game_id AND "chainIndex" = v_chain_idx AND "stepIndex" = v_current_step LIMIT 1;
  IF v_existing.id IS NULL THEN
    INSERT INTO "sketch_telephone_chains" ("gameId","chainIndex","stepIndex","stepType","content","authorUserId","authorUserName")
    VALUES (p_game_id, v_chain_idx, v_current_step, v_step_type, p_content, auth.uid()::text, v_player_name);
  ELSE
    UPDATE "sketch_telephone_chains"
      SET "content" = p_content, "authorUserId" = auth.uid()::text, "authorUserName" = v_player_name, "submittedAt" = now()
    WHERE "id" = v_existing.id;
  END IF;

  -- Count submissions for this step
  SELECT count(*) INTO v_submitted_count FROM "sketch_telephone_chains"
    WHERE "gameId" = p_game_id AND "stepIndex" = v_current_step;

  -- Auto-advance when all players have submitted
  IF v_submitted_count >= v_player_count THEN
    PERFORM public.fn_sketchtelephone_advance(p_game_id);
    RETURN jsonb_build_object('ok', true, 'advanced', true);
  END IF;

  UPDATE "sketch_telephone_games" SET "lastActivityAt" = now() WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_sketchtelephone_submit_step(text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_sketchtelephone_advance — move to the next step, or to reveal.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sketchtelephone_advance(p_game_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_current int;
  v_player_count int;
  v_drawing_seconds int;
  v_next_step int;
  v_next_phase text;
  v_next_step_type text;
BEGIN
  SELECT * INTO v_game FROM "sketch_telephone_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_in_progress'); END IF;
  v_board := v_game."boardState";
  IF v_board->>'phase' = 'revealing' THEN
    -- Host ends the reveal → finish
    v_board := jsonb_set(v_board, '{phase}', '"finished"');
    v_board := jsonb_set(v_board, '{status}', '"completed"');
    UPDATE "sketch_telephone_games" SET
      "boardState" = v_board,
      status = 'completed',
      "completedAt" = now(),
      "endReason" = 'completed',
      "winnerUserIds" = (
        SELECT COALESCE(jsonb_agg("userId"), '[]'::jsonb)
        FROM "sketch_telephone_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL
      ),
      "lastActivityAt" = now()
    WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true, 'finished', true);
  END IF;
  v_current := (v_board->>'currentStep')::int;
  v_player_count := (v_board->>'playerCount')::int;
  v_drawing_seconds := (v_board->>'drawingSeconds')::int;
  v_next_step := v_current + 1;
  IF v_next_step >= v_player_count THEN
    -- All steps done — enter reveal
    v_board := jsonb_set(v_board, '{phase}', '"revealing"');
    UPDATE "sketch_telephone_games" SET "boardState" = v_board, "turnEndsAt" = NULL, "lastActivityAt" = now() WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true, 'revealing', true);
  END IF;
  -- Advance to the next step
  v_next_step_type := public.fn_sketchtelephone_step_type(v_next_step);
  IF v_next_step_type = 'drawing' THEN
    v_next_phase := 'drawing';
  ELSE
    v_next_phase := 'writing';
  END IF;
  v_board := jsonb_set(v_board, '{currentStep}', v_next_step::text::jsonb);
  v_board := jsonb_set(v_board, '{phase}', to_jsonb(v_next_phase));
  UPDATE "sketch_telephone_games" SET
    "boardState" = v_board,
    "turnEndsAt" = now() + (v_drawing_seconds || ' seconds')::interval,
    "lastActivityAt" = now()
  WHERE id = p_game_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_sketchtelephone_advance(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_sketchtelephone_tick — 2s watchdog. Auto-advances on timer expiry.
-- Only advances when ALL players have submitted OR the timer expired
-- (in which case missing submissions are left blank).
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sketchtelephone_tick(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game record;
  v_board jsonb;
  v_current int;
  v_submitted int;
  v_player_count int;
BEGIN
  SELECT * INTO v_game FROM "sketch_telephone_games" WHERE id = p_game_id;
  IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;
  UPDATE "sketch_telephone_players" SET "lastActivityAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  v_board := v_game."boardState";
  IF v_board->>'phase' = 'revealing' OR v_board->>'phase' = 'finished' THEN RETURN; END IF;
  IF v_game."turnEndsAt" IS NULL THEN RETURN; END IF;
  IF v_game."turnEndsAt" >= now() THEN RETURN; END IF;
  -- Timer expired — advance (missing submissions are simply absent)
  PERFORM public.fn_sketchtelephone_advance(p_game_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_sketchtelephone_tick(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- fn_sketchtelephone_leave
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sketchtelephone_leave(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_game record; v_active int;
BEGIN
  SELECT * INTO v_game FROM "sketch_telephone_games" WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE "sketch_telephone_players" SET "leftAt" = now() WHERE "gameId" = p_game_id AND "userId" = auth.uid()::text;
  SELECT count(*) INTO v_active FROM "sketch_telephone_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL;
  IF v_active < 4 AND v_game.status = 'in_progress' THEN
    UPDATE "sketch_telephone_games" SET status = 'completed', "completedAt" = now(), "endReason" = 'walkover',
      "winnerUserIds" = COALESCE((SELECT jsonb_agg("userId") FROM "sketch_telephone_players" WHERE "gameId" = p_game_id AND "leftAt" IS NULL), '[]'::jsonb),
      "lastActivityAt" = now() WHERE id = p_game_id;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_sketchtelephone_leave(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- Archive trigger — when status flips to 'completed', archive the row.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn__sketchtelephone_on_complete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
    BEGIN PERFORM public.fn__archive_family_match('sketch_telephone_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'sketchtelephone archive failed: %', SQLERRM; END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sketchtelephone_archive ON "sketch_telephone_games";
CREATE TRIGGER trg_sketchtelephone_archive AFTER UPDATE ON "sketch_telephone_games"
  FOR EACH ROW EXECUTE FUNCTION public.fn__sketchtelephone_on_complete();

-- ─────────────────────────────────────────────────────────────────
-- Whitelists + metadata — extend the shared helpers with our table.
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
    'sketch_telephone_games'
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
    'secret_heist_games', jsonb_build_object('id','secret-heist','name','Secret Heist','icon','💰','accent','#10B981'),
    'mind_match_games', jsonb_build_object('id','mind-match','name','Mind Match','icon','🧠','accent','#F472B6'),
    'code_clues_games', jsonb_build_object('id','code-clues','name','Code Clues','icon','🔐','accent','#F59E0B'),
    'sketch_telephone_games', jsonb_build_object('id','sketch-telephone','name','Sketch Telephone','icon','🎨','accent','#EC4899')
  );
$$;

-- Achievement — Chain Master
INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
  (gen_random_uuid()::text,'chain-master','Chain Master','चेन मास्टर','Complete 5 Sketch Telephone games','🎨','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- Seed the prompt pool — 50 family-friendly drawable prompts.
-- ─────────────────────────────────────────────────────────────────
INSERT INTO "sketch_telephone_prompts" (prompt) VALUES
  ('A cat riding a skateboard'),
  ('A dragon eating pizza'),
  ('A robot dancing at a wedding'),
  ('A shark wearing sunglasses'),
  ('A penguin on vacation'),
  ('A ghost trying to use a smartphone'),
  ('A dinosaur at a coffee shop'),
  ('An astronaut planting flowers on Mars'),
  ('A unicorn delivering mail'),
  ('A wizard cooking breakfast'),
  ('A frog playing the violin'),
  ('A pirate cat searching for treasure'),
  ('A ninja turtle on a picnic'),
  ('A vampire taking a selfie'),
  ('A superhero saving a cat from a tree'),
  ('A cow jumping over the moon'),
  ('A bear riding a bicycle'),
  ('A octopus playing eight instruments at once'),
  ('A snail in a race car'),
  ('A chicken crossing the road (with a reason)'),
  ('A dog surfing a giant wave'),
  ('A monster hiding under a bed'),
  ('A snowman in the desert'),
  ('A wizard fighting a dragon with a wand'),
  ('A fish driving a submarine'),
  ('A bee selling honey at a market'),
  ('A panda doing yoga'),
  ('A turtle wearing a top hat'),
  ('A ghost reading a book in a library'),
  ('A alien tasting ice cream for the first time'),
  ('A knight fighting a dragon with a rubber chicken'),
  ('A princess rescuing a prince from a tower'),
  ('A fox running a bakery'),
  ('A pig flying an airplane'),
  ('A elephant balancing on a tightrope'),
  ('A monkey DJing a party'),
  ('A penguin building an igloo mansion'),
  ('A duck detective solving a mystery'),
  ('A werewolf howling at a birthday cake'),
  ('A giraffe with a really long scarf'),
  ('A snail mail delivery service'),
  ('A vampire dentist at work'),
  ('A turtle racing a hare (rematch)'),
  ('A grandma ninja in training'),
  ('A UFO abducting a cow for tea'),
  ('A hedgehog with a balloon collection'),
  ('A cactus wearing a sombrero'),
  ('A llama attending a business meeting'),
  ('A toaster that came to life'),
  ('A mermaid using a smartphone underwater')
ON CONFLICT DO NOTHING;
