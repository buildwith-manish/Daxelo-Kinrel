-- 20260920120000_flick_arena_game.sql
-- Flick Arena — physics-based disc-flicking goal game (Forge2D). 2-4 players.
--
-- Match types:
--   • Solo Duel (1v1) — first to 3 goals wins
--   • Team Battle (2v2) — first team to 5 goals wins (shared score)
--
-- Physics runs client-side via Forge2D (deterministic); the server stores
-- settled disc + ball positions + scores, realtime broadcasts updates,
-- and a pg_cron-driven watchdog enforces the 15-second turn timer.
--
-- Pattern mirrors carrom_games + freeze_auction_games.

-- ─────────────────────────────────────────────────────────────────
-- flick_arena_games — one row per match session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "flick_arena_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "hostUserId"            TEXT,
    "hostUserName"          TEXT,
    "roomName"              TEXT,

    -- 'solo_duel' (1v1) or 'team_battle' (2v2)
    "matchType"             TEXT NOT NULL DEFAULT 'solo_duel',
    "maxPlayers"            INTEGER NOT NULL DEFAULT 2,

    -- Inline player slots (mirrors carrom pattern for 1v1; for 2v2 we
    -- use a separate players table for the 4 roster entries but still
    -- keep team ids here for quick reads).
    "playerOneId"           TEXT NOT NULL DEFAULT '',
    "playerOneName"         TEXT NOT NULL DEFAULT 'Player 1',
    "playerTwoId"           TEXT NOT NULL DEFAULT '',
    "playerTwoName"         TEXT NOT NULL DEFAULT 'Player 2',
    "playerThreeId"         TEXT NOT NULL DEFAULT '',
    "playerThreeName"       TEXT NOT NULL DEFAULT 'Player 3',
    "playerFourId"          TEXT NOT NULL DEFAULT '',
    "playerFourName"        TEXT NOT NULL DEFAULT 'Player 4',

    -- Player → team assignment (1 or 2). Indexed by slot number (1..4).
    "teamAssignment"        JSONB NOT NULL DEFAULT '{"1":1,"2":2,"3":1,"4":2}'::jsonb,

    -- Turn order: array of slot numbers [1,2] or [1,2,3,4]
    "turnOrder"             JSONB NOT NULL DEFAULT '[1,2]'::jsonb,
    "currentTurnSlot"       INTEGER NOT NULL DEFAULT 1,
    "currentTurnPlayerId"   TEXT NOT NULL DEFAULT '',
    "currentTurnPlayerName" TEXT NOT NULL DEFAULT '',
    "turnEndsAt"            TIMESTAMPTZ,

    status                  TEXT NOT NULL DEFAULT 'waiting',  -- waiting | in_progress | completed

    -- Goals scored per team (shared in team battle)
    "teamOneScore"          INTEGER NOT NULL DEFAULT 0,
    "teamTwoScore"          INTEGER NOT NULL DEFAULT 0,

    -- Winning team (1 or 2); for solo_duel maps to player slot
    "winningTeam"           INTEGER,
    "winnerUserIds"         JSONB NOT NULL DEFAULT '[]'::jsonb,
    "endReason"             TEXT,

    -- Board state: discs (id, ownerSlot, x, y, isPotted, isStriker) + ball (x, y, vx, vy) + last shooter
    "boardState"            JSONB NOT NULL,
    "lastTurnSummary"       JSONB,

    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now(),
    "lastActivityAt"        TIMESTAMPTZ DEFAULT now(),
    "autoCloseDeadline"     TIMESTAMPTZ,
    "cancelledAt"           TIMESTAMPTZ,
    "closedAt"              TIMESTAMPTZ,
    "spectatorsEnabled"     BOOLEAN NOT NULL DEFAULT true,
    "hostReady"             BOOLEAN DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_flick_arena_games_family ON "flick_arena_games"("familyId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS idx_flick_arena_games_status ON "flick_arena_games"("status");

-- ─────────────────────────────────────────────────────────────────
-- flick_arena_turns — one row per turn (for history + replay)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "flick_arena_turns" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"            TEXT NOT NULL REFERENCES "flick_arena_games"(id) ON DELETE CASCADE,
    "playerId"          TEXT NOT NULL,
    "playerName"        TEXT NOT NULL DEFAULT 'Player',
    "slotNumber"        INTEGER NOT NULL,
    "teamNumber"        INTEGER NOT NULL,
    "discId"            TEXT NOT NULL,
    "discStartX"        NUMERIC(10,4) NOT NULL,
    "discStartY"        NUMERIC(10,4) NOT NULL,
    "angle"             NUMERIC(8,4) NOT NULL,                -- radians
    "force"             NUMERIC(8,4) NOT NULL,                -- 0.0 to 1.0
    "shotDistance"      NUMERIC(10,4) NOT NULL DEFAULT 0,     -- physics units traveled
    "scoredGoal"        BOOLEAN NOT NULL DEFAULT false,
    "goalForTeam"       INTEGER,                               -- 1 or 2 if a goal was scored
    "wasAutoSkipped"    BOOLEAN NOT NULL DEFAULT false,
    "turnNumber"        INTEGER NOT NULL,
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_flick_arena_turns_game ON "flick_arena_turns"("gameId", "turnNumber");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "flick_arena_games" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "flick_arena_turns" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "flick_arena_games_select" ON "flick_arena_games"
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "flick_arena_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "flick_arena_games_insert" ON "flick_arena_games"
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "flick_arena_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "flick_arena_games_update" ON "flick_arena_games"
    FOR UPDATE TO authenticated USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "flick_arena_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

CREATE POLICY "flick_arena_turns_select" ON "flick_arena_turns"
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM "flick_arena_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "flick_arena_turns"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "flick_arena_turns_insert" ON "flick_arena_turns"
    FOR INSERT TO authenticated WITH CHECK ("playerId" = auth.uid()::text);

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "flick_arena_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "flick_arena_turns";
ALTER TABLE "flick_arena_games" REPLICA IDENTITY FULL;
ALTER TABLE "flick_arena_turns" REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────
-- Turn-timer watchdog — runs from client _tick RPC. If the turn timer
-- has expired, advances the turn (auto-skip with no goal).
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_flickarena_tick(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_game record;
    v_slots int[];
    v_current_slot int;
    v_idx int;
    v_next_slot int;
    v_next_player_id text;
    v_next_player_name text;
    v_team int;
    v_board jsonb;
BEGIN
    SELECT * INTO v_game FROM "flick_arena_games" WHERE id = p_game_id;
    IF NOT FOUND OR v_game.status <> 'in_progress' THEN RETURN; END IF;

    -- Heartbeat the caller's row (no-op for inline-player games)
    PERFORM public.fn_touch_game_activity('flick_arena_games', p_game_id);

    IF v_game."turnEndsAt" IS NULL OR v_game."turnEndsAt" > now() THEN RETURN; END IF;

    -- Timer expired — auto-skip
    v_slots := ARRAY(SELECT jsonb_array_elements_text(v_game."turnOrder")::int);
    v_current_slot := v_game."currentTurnSlot";
    v_idx := array_position(v_slots, v_current_slot);
    IF v_idx IS NULL THEN v_idx := 0; END IF;
    v_next_slot := v_slots[((v_idx) % array_length(v_slots, 1)) + 1];

    SELECT "playerId", "playerName" INTO v_next_player_id, v_next_player_name
    FROM (
        SELECT v_game."playerOneId" AS "playerId", v_game."playerOneName" AS "playerName", 1 AS slot
        UNION ALL SELECT v_game."playerTwoId", v_game."playerTwoName", 2
        UNION ALL SELECT v_game."playerThreeId", v_game."playerThreeName", 3
        UNION ALL SELECT v_game."playerFourId", v_game."playerFourName", 4
    ) p WHERE p.slot = v_next_slot;

    v_team := (v_game."teamAssignment" ->> v_next_slot::text)::int;

    UPDATE "flick_arena_games"
    SET "currentTurnSlot" = v_next_slot,
        "currentTurnPlayerId" = COALESCE(v_next_player_id, ''),
        "currentTurnPlayerName" = COALESCE(v_next_player_name, ''),
        "turnEndsAt" = now() + interval '15 seconds',
        "lastActivityAt" = now()
    WHERE id = p_game_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_flickarena_tick(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- Leave-match walkover — if fewer than the required player count remain,
-- declare the remaining team the winner.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_flickarena_leave(p_game_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_game record;
    v_match_type text;
    v_remaining_slots int[];
    v_team1_remaining int;
    v_team2_remaining int;
    v_winner_team int;
    v_winner_ids text[];
BEGIN
    SELECT * INTO v_game FROM "flick_arena_games" WHERE id = p_game_id;
    IF NOT FOUND THEN RETURN; END IF;

    -- Mark the leaving player's slot empty by zeroing their id.
    -- The caller's auth.uid() determines which slot to clear.
    UPDATE "flick_arena_games"
    SET "playerOneId"   = CASE WHEN "playerOneId"   = auth.uid()::text THEN '' ELSE "playerOneId" END,
        "playerTwoId"   = CASE WHEN "playerTwoId"   = auth.uid()::text THEN '' ELSE "playerTwoId" END,
        "playerThreeId" = CASE WHEN "playerThreeId" = auth.uid()::text THEN '' ELSE "playerThreeId" END,
        "playerFourId"  = CASE WHEN "playerFourId"  = auth.uid()::text THEN '' ELSE "playerFourId" END,
        "lastActivityAt" = now()
    WHERE id = p_game_id;

    SELECT * INTO v_game FROM "flick_arena_games" WHERE id = p_game_id;
    IF v_game.status <> 'in_progress' THEN RETURN; END IF;

    -- Count remaining players per team.
    v_team1_remaining := 0;
    v_team2_remaining := 0;
    IF v_game."playerOneId"   <> '' AND (v_game."teamAssignment"->>'1')::int = 1 THEN v_team1_remaining := v_team1_remaining + 1; END IF;
    IF v_game."playerTwoId"   <> '' AND (v_game."teamAssignment"->>'2')::int = 1 THEN v_team1_remaining := v_team1_remaining + 1; END IF;
    IF v_game."playerThreeId" <> '' AND (v_game."teamAssignment"->>'3')::int = 1 THEN v_team1_remaining := v_team1_remaining + 1; END IF;
    IF v_game."playerFourId"  <> '' AND (v_game."teamAssignment"->>'4')::int = 1 THEN v_team1_remaining := v_team1_remaining + 1; END IF;
    IF v_game."playerOneId"   <> '' AND (v_game."teamAssignment"->>'1')::int = 2 THEN v_team2_remaining := v_team2_remaining + 1; END IF;
    IF v_game."playerTwoId"   <> '' AND (v_game."teamAssignment"->>'2')::int = 2 THEN v_team2_remaining := v_team2_remaining + 1; END IF;
    IF v_game."playerThreeId" <> '' AND (v_game."teamAssignment"->>'3')::int = 2 THEN v_team2_remaining := v_team2_remaining + 1; END IF;
    IF v_game."playerFourId"  <> '' AND (v_game."teamAssignment"->>'4')::int = 2 THEN v_team2_remaining := v_team2_remaining + 1; END IF;

    v_match_type := v_game."matchType";

    IF v_match_type = 'solo_duel' THEN
        IF v_team1_remaining = 0 THEN v_winner_team := 2;
        ELSIF v_team2_remaining = 0 THEN v_winner_team := 1;
        ELSE RETURN; END IF;
    ELSE
        -- team battle: a team with zero remaining players forfeits
        IF v_team1_remaining = 0 THEN v_winner_team := 2;
        ELSIF v_team2_remaining = 0 THEN v_winner_team := 1;
        ELSE RETURN; END IF;
    END IF;

    -- Build winner user ids based on winning team
    v_winner_ids := ARRAY[]::text[];
    IF v_winner_team = 1 THEN
        IF v_game."playerOneId"   <> '' AND (v_game."teamAssignment"->>'1')::int = 1 THEN v_winner_ids := array_append(v_winner_ids, v_game."playerOneId"); END IF;
        IF v_game."playerTwoId"   <> '' AND (v_game."teamAssignment"->>'2')::int = 1 THEN v_winner_ids := array_append(v_winner_ids, v_game."playerTwoId"); END IF;
        IF v_game."playerThreeId" <> '' AND (v_game."teamAssignment"->>'3')::int = 1 THEN v_winner_ids := array_append(v_winner_ids, v_game."playerThreeId"); END IF;
        IF v_game."playerFourId"  <> '' AND (v_game."teamAssignment"->>'4')::int = 1 THEN v_winner_ids := array_append(v_winner_ids, v_game."playerFourId"); END IF;
    ELSE
        IF v_game."playerOneId"   <> '' AND (v_game."teamAssignment"->>'1')::int = 2 THEN v_winner_ids := array_append(v_winner_ids, v_game."playerOneId"); END IF;
        IF v_game."playerTwoId"   <> '' AND (v_game."teamAssignment"->>'2')::int = 2 THEN v_winner_ids := array_append(v_winner_ids, v_game."playerTwoId"); END IF;
        IF v_game."playerThreeId" <> '' AND (v_game."teamAssignment"->>'3')::int = 2 THEN v_winner_ids := array_append(v_winner_ids, v_game."playerThreeId"); END IF;
        IF v_game."playerFourId"  <> '' AND (v_game."teamAssignment"->>'4')::int = 2 THEN v_winner_ids := array_append(v_winner_ids, v_game."playerFourId"); END IF;
    END IF;

    UPDATE "flick_arena_games"
    SET status = 'completed',
        "completedAt" = now(),
        "winningTeam" = v_winner_team,
        "winnerUserIds" = to_jsonb(v_winner_ids),
        "endReason" = 'walkover',
        "lastActivityAt" = now()
    WHERE id = p_game_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_flickarena_leave(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────
-- Archive trigger (matches the pattern used by every other game)
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn__flickarena_on_complete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NEW."status" = 'completed' AND COALESCE(OLD."status", '') <> 'completed' THEN
        BEGIN PERFORM public.fn__archive_family_match('flick_arena_games', NEW."id"); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'flickarena archive failed: %', SQLERRM; END;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_flickarena_archive ON "flick_arena_games";
CREATE TRIGGER trg_flickarena_archive AFTER UPDATE ON "flick_arena_games"
    FOR EACH ROW EXECUTE FUNCTION public.fn__flickarena_on_complete();

-- ─────────────────────────────────────────────────────────────────
-- Whitelist flick_arena_games in the shared touch + game-meta helpers
-- (idempotent re-CREATE — keeps the table list in sync across all games)
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
        'flick_arena_games'
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
        'impostor_games', jsonb_build_object('id','impostor','name','Impostor','icon','🕵️','accent','#8B5CF6'),
        'color_trap_games', jsonb_build_object('id','color-trap','name','Color Trap','icon','🎨','accent','#F59E0B'),
        'freeze_auction_games', jsonb_build_object('id','freeze-auction','name','Freeze Auction','icon','📦','accent','#F59E0B'),
        'flick_arena_games', jsonb_build_object('id','flick-arena','name','Flick Arena','icon','🎯','accent','#22D3EE')
    );
$$;

-- Achievement — first flick-arena champion
INSERT INTO "Badge" ("id","slug","name","nameHi","description","icon","category","tier","threshold","isSecret","createdAt") VALUES
    (gen_random_uuid()::text,'flick-arena-ace','Flick Arena Ace','फ्लिक एरिना एस','Win 5 Flick Arena matches','🎯','games','gold',5,false,now())
ON CONFLICT ("slug") DO NOTHING;
