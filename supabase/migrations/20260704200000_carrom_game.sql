-- Carrom Game — 2-player physics-based board game using Forge2D
--
-- Players flick a striker to pot coins (white/black + queen) into
-- 4 corner pockets. Server stores game state + turn history; physics
-- runs client-side via Forge2D, only settled state is broadcast.
--
-- Pattern mirrors prior games.

-- ─────────────────────────────────────────────────────────────────
-- carrom_games — one row per game session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "carrom_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "playerOneId"           TEXT NOT NULL,
    "playerOneName"         TEXT NOT NULL DEFAULT 'Player 1',
    "playerTwoId"           TEXT NOT NULL,
    "playerTwoName"         TEXT NOT NULL DEFAULT 'Player 2',
    "currentTurnPlayerId"   TEXT NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'waiting',  -- waiting | in_progress | completed
    "playerOneColor"        TEXT NOT NULL DEFAULT 'white',   -- white | black
    "playerTwoColor"        TEXT NOT NULL DEFAULT 'black',
    "boardState"            JSONB NOT NULL,                   -- array of {type, x, y, isPotted}
    "strikerX"              NUMERIC(10,4) NOT NULL DEFAULT 0,
    "strikerY"              NUMERIC(10,4) NOT NULL DEFAULT 0,
    "playerOneScore"        INTEGER NOT NULL DEFAULT 0,      -- coins potted by player 1
    "playerTwoScore"        INTEGER NOT NULL DEFAULT 0,
    "queenStatus"           TEXT NOT NULL DEFAULT 'on_board', -- on_board | potted_uncovered | potted_covered
    "queenPottedBy"         TEXT,                             -- playerId who potted queen
    "winnerId"              TEXT,
    "winnerName"            TEXT,
    "lastTurnSummary"       JSONB,                            -- {potted: [], foul: bool, extraTurn: bool, reason}
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_carrom_games_family ON "carrom_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_carrom_games_status ON "carrom_games"("status");

-- ─────────────────────────────────────────────────────────────────
-- carrom_turns — one row per turn (for history + replay)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "carrom_turns" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"            TEXT NOT NULL REFERENCES "carrom_games"(id) ON DELETE CASCADE,
    "playerId"          TEXT NOT NULL,
    "playerName"        TEXT NOT NULL DEFAULT 'Player',
    "strikerStartX"     NUMERIC(10,4) NOT NULL,
    "strikerStartY"     NUMERIC(10,4) NOT NULL,
    "angle"             NUMERIC(8,4) NOT NULL,              -- radians
    "force"             NUMERIC(8,4) NOT NULL,              -- 0.0 to 1.0
    "pottedCoins"       JSONB NOT NULL DEFAULT '[]',        -- array of coin types potted
    "wasFoul"           BOOLEAN NOT NULL DEFAULT false,
    "foulReason"        TEXT,
    "extraTurn"         BOOLEAN NOT NULL DEFAULT false,
    "queenPotted"       BOOLEAN NOT NULL DEFAULT false,
    "queenCovered"      BOOLEAN NOT NULL DEFAULT false,
    "turnNumber"        INTEGER NOT NULL,
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_carrom_turns_game ON "carrom_turns"("gameId", "turnNumber");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped (same pattern as prior games)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "carrom_games" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "carrom_turns" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "carrom_games_select" ON "carrom_games"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "carrom_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "carrom_games_insert" ON "carrom_games"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "carrom_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "carrom_games_update" ON "carrom_games"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "carrom_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

CREATE POLICY "carrom_turns_select" ON "carrom_turns"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "carrom_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "carrom_turns"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "carrom_turns_insert" ON "carrom_turns"
    FOR INSERT WITH CHECK ("playerId" = auth.uid()::text);

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "carrom_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "carrom_turns";
