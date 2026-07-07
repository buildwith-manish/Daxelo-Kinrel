-- Bingo Game — 2-30 players, server-authoritative number calling
--
-- Classic Bingo: each player gets a 5x5 card with numbers 1-75 (free
-- center space). A server-side Edge Function calls one random unclaimed
-- number at a time on an interval. Players mark matching numbers.
-- First to complete a row/column/diagonal (or full card) taps BINGO.
-- The claim is verified server-side before being accepted.
--
-- Pattern mirrors ghost_painter / redlight / sos / antakshari.

-- ─────────────────────────────────────────────────────────────────
-- bingo_games — one row per game session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "bingo_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "hostUserId"            TEXT NOT NULL,
    "hostUserName"          TEXT NOT NULL DEFAULT 'Host',
    status                  TEXT NOT NULL DEFAULT 'waiting',  -- waiting | in_progress | completed
    "winPattern"            TEXT NOT NULL DEFAULT 'line',     -- line | full_card
    "callIntervalSeconds"   INTEGER NOT NULL DEFAULT 5,
    "numbersCalled"         INTEGER[] NOT NULL DEFAULT '{}',  -- ordered array of called numbers
    "winnerPlayerId"        TEXT,
    "winnerPlayerName"      TEXT,
    "maxPlayers"            INTEGER NOT NULL DEFAULT 30,
    "lastCallAt"            TIMESTAMPTZ,                      -- when the last number was called
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bingo_games_family ON "bingo_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_bingo_games_status ON "bingo_games"("status");

-- ─────────────────────────────────────────────────────────────────
-- bingo_cards — one row per player per game
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "bingo_cards" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"            TEXT NOT NULL REFERENCES "bingo_games"(id) ON DELETE CASCADE,
    "playerId"          TEXT NOT NULL,
    "playerName"        TEXT NOT NULL DEFAULT 'Player',
    "cardNumbers"       JSONB NOT NULL,                      -- 5x5 grid [[1-15,16-30,...],...] with null at center
    "markedNumbers"     INTEGER[] NOT NULL DEFAULT '{}',     -- numbers the player has marked
    "hasClaimed"        BOOLEAN NOT NULL DEFAULT false,
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "playerId")
);

CREATE INDEX IF NOT EXISTS idx_bingo_cards_game ON "bingo_cards"("gameId");
CREATE INDEX IF NOT EXISTS idx_bingo_cards_player ON "bingo_cards"("playerId");

-- ─────────────────────────────────────────────────────────────────
-- bingo_claims — one row per BINGO claim (for audit + win verification)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "bingo_claims" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "bingo_games"(id) ON DELETE CASCADE,
    "playerId"      TEXT NOT NULL,
    "playerName"    TEXT NOT NULL DEFAULT 'Player',
    "claimedAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
    "isValid"       BOOLEAN,                                 -- null until verified, then true/false
    "invalidReason" TEXT,                                    -- why the claim was invalid (if false)
    "verifiedAt"    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_bingo_claims_game ON "bingo_claims"("gameId");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped (same pattern as prior games)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "bingo_games"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "bingo_cards"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "bingo_claims"  ENABLE ROW LEVEL SECURITY;

-- bingo_games: family members can read/insert/update
CREATE POLICY "bingo_games_select" ON "bingo_games"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "bingo_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "bingo_games_insert" ON "bingo_games"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "bingo_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "bingo_games_update" ON "bingo_games"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "bingo_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

-- bingo_cards: family-scoped read; players insert/update their own card
CREATE POLICY "bingo_cards_select" ON "bingo_cards"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "bingo_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "bingo_cards"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "bingo_cards_insert" ON "bingo_cards"
    FOR INSERT WITH CHECK ("playerId" = auth.uid()::text);
CREATE POLICY "bingo_cards_update" ON "bingo_cards"
    FOR UPDATE USING ("playerId" = auth.uid()::text);

-- bingo_claims: family-scoped read; players insert their own claim
CREATE POLICY "bingo_claims_select" ON "bingo_claims"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "bingo_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "bingo_claims"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "bingo_claims_insert" ON "bingo_claims"
    FOR INSERT WITH CHECK ("playerId" = auth.uid()::text);

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication — all 3 tables for live game sync
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "bingo_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "bingo_cards";
ALTER PUBLICATION supabase_realtime ADD TABLE "bingo_claims";

-- ─────────────────────────────────────────────────────────────────
-- RPC: bingo_call_next_number — server-authoritative number calling
-- Picks the next random unclaimed number and appends it to numbersCalled.
-- Returns the newly called number, or null if all 75 have been called.
-- Idempotent — if called multiple times within the same interval, only
-- the first call advances the sequence (subsequent calls return the
-- same number).
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.bingo_call_next_number(game_id TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    game_record RECORD;
    all_numbers INTEGER[] := ARRAY(
        SELECT generate_series(1, 75)
    );
    available_numbers INTEGER[];
    next_number INTEGER;
    call_interval INTEGER;
BEGIN
    SELECT "numbersCalled", "callIntervalSeconds", "lastCallAt", status
    INTO game_record
    FROM "bingo_games"
    WHERE id = game_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF game_record.status != 'in_progress' THEN
        RETURN NULL;
    END IF;

    -- Check if enough time has passed since the last call
    call_interval := COALESCE(game_record."callIntervalSeconds", 5);
    IF game_record."lastCallAt" IS NOT NULL THEN
        IF NOW() - game_record."lastCallAt" < make_interval(secs => call_interval) THEN
            -- Too soon — return the last called number
            IF array_length(game_record."numbersCalled", 1) > 0 THEN
                RETURN game_record."numbersCalled"[array_length(game_record."numbersCalled", 1)];
            END IF;
            RETURN NULL;
        END IF;
    END IF;

    -- Compute available (uncalled) numbers using array difference
    SELECT array_agg(n) INTO available_numbers
    FROM unnest(all_numbers) AS n
    WHERE NOT (n = ANY(game_record."numbersCalled"));

    IF array_length(available_numbers, 1) IS NULL OR array_length(available_numbers, 1) = 0 THEN
        -- All numbers called — no more to call
        RETURN NULL;
    END IF;

    -- Pick a random available number
    SELECT available_numbers[floor(random() * array_length(available_numbers, 1)) + 1]
    INTO next_number;

    -- Append and update timestamp
    UPDATE "bingo_games"
    SET "numbersCalled" = array_append("numbersCalled", next_number),
        "lastCallAt" = NOW()
    WHERE id = game_id;

    RETURN next_number;
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- RPC: bingo_verify_claim — server-side win verification
-- Validates that a player's marked numbers actually complete the win
-- pattern against their card + the called numbers. Returns JSON with
-- {valid: bool, reason: string?}.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.bingo_verify_claim(claim_game_id TEXT, claim_player_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    game_record RECORD;
    card_record RECORD;
    card_grid JSONB;
    marked INTEGER[];
    called INTEGER[];
    valid_marked INTEGER[];
    row_idx INTEGER;
    col_idx INTEGER;
    cell_value INTEGER;
    win_pattern TEXT;
    -- For line checks
    row_complete BOOLEAN;
    col_complete BOOLEAN;
    diag1_complete BOOLEAN;
    diag2_complete BOOLEAN;
    -- For full card
    all_marked BOOLEAN;
BEGIN
    SELECT "numbersCalled", "winPattern"
    INTO game_record
    FROM "bingo_games"
    WHERE id = claim_game_id;

    IF NOT FOUND THEN
        RETURN json_build_object('valid', false, 'reason', 'Game not found');
    END IF;

    SELECT "cardNumbers", "markedNumbers"
    INTO card_record
    FROM "bingo_cards"
    WHERE "gameId" = claim_game_id AND "playerId" = claim_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('valid', false, 'reason', 'Card not found');
    END IF;

    card_grid := card_record."cardNumbers";
    marked := card_record."markedNumbers";
    called := game_record."numbersCalled";

    -- Filter marked to only those that were actually called
    -- (player can't win by marking numbers that weren't called)
    SELECT array_agg(m) INTO valid_marked
    FROM unnest(marked) AS m
    WHERE m = ANY(called);

    IF valid_marked IS NULL THEN
        valid_marked := ARRAY[]::INTEGER[];
    END IF;

    win_pattern := COALESCE(game_record."winPattern", 'line');

    IF win_pattern = 'full_card' THEN
        -- Check every cell (except center which is free) is marked
        all_marked := true;
        FOR row_idx IN 0..4 LOOP
            FOR col_idx IN 0..4 LOOP
                -- Skip the center cell (free space)
                IF row_idx = 2 AND col_idx = 2 THEN
                    CONTINUE;
                END IF;
                cell_value := (card_grid -> row_idx -> col_idx)::INTEGER;
                IF cell_value IS NOT NULL AND NOT (cell_value = ANY(valid_marked)) THEN
                    all_marked := false;
                    EXIT;
                END IF;
            END LOOP;
            IF NOT all_marked THEN EXIT; END IF;
        END LOOP;

        IF all_marked THEN
            RETURN json_build_object('valid', true);
        ELSE
            RETURN json_build_object('valid', false, 'reason', 'Card not fully marked');
        END IF;
    END IF;

    -- Line pattern: check rows, columns, diagonals
    -- Rows
    FOR row_idx IN 0..4 LOOP
        row_complete := true;
        FOR col_idx IN 0..4 LOOP
            IF row_idx = 2 AND col_idx = 2 THEN
                CONTINUE; -- free space
            END IF;
            cell_value := (card_grid -> row_idx -> col_idx)::INTEGER;
            IF cell_value IS NOT NULL AND NOT (cell_value = ANY(valid_marked)) THEN
                row_complete := false;
                EXIT;
            END IF;
        END LOOP;
        IF row_complete THEN
            RETURN json_build_object('valid', true);
        END IF;
    END LOOP;

    -- Columns
    FOR col_idx IN 0..4 LOOP
        col_complete := true;
        FOR row_idx IN 0..4 LOOP
            IF row_idx = 2 AND col_idx = 2 THEN
                CONTINUE;
            END IF;
            cell_value := (card_grid -> row_idx -> col_idx)::INTEGER;
            IF cell_value IS NOT NULL AND NOT (cell_value = ANY(valid_marked)) THEN
                col_complete := false;
                EXIT;
            END IF;
        END LOOP;
        IF col_complete THEN
            RETURN json_build_object('valid', true);
        END IF;
    END LOOP;

    -- Diagonal 1 (top-left to bottom-right)
    diag1_complete := true;
    FOR row_idx IN 0..4 LOOP
        IF row_idx = 2 THEN
            CONTINUE; -- center free space
        END IF;
        cell_value := (card_grid -> row_idx -> row_idx)::INTEGER;
        IF cell_value IS NOT NULL AND NOT (cell_value = ANY(valid_marked)) THEN
            diag1_complete := false;
            EXIT;
        END IF;
    END LOOP;
    IF diag1_complete THEN
        RETURN json_build_object('valid', true);
    END IF;

    -- Diagonal 2 (top-right to bottom-left)
    diag2_complete := true;
    FOR row_idx IN 0..4 LOOP
        IF row_idx = 2 THEN
            CONTINUE;
        END IF;
        cell_value := (card_grid -> row_idx -> (4 - row_idx))::INTEGER;
        IF cell_value IS NOT NULL AND NOT (cell_value = ANY(valid_marked)) THEN
            diag2_complete := false;
            EXIT;
        END IF;
    END LOOP;
    IF diag2_complete THEN
        RETURN json_build_object('valid', true);
    END IF;

    RETURN json_build_object('valid', false, 'reason', 'No completed line/diagonal');
END;
$$;
