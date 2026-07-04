-- Checkers Game — 2-player classic checkers on 8x8 board
--
-- Standard checkers rules: 12 pieces each, diagonal movement, mandatory
-- captures, multi-jumps, king promotion. Pure logic runs client-side
-- (validated identically on both players' devices); Supabase stores
-- game state + move history + broadcasts via Realtime.
--
-- Pattern mirrors ghost_painter / redlight / sos / antakshari / bingo.

-- ─────────────────────────────────────────────────────────────────
-- checkers_games — one row per game session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "checkers_games" (
    id                          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"                  TEXT NOT NULL,
    "playerOneId"               TEXT NOT NULL,             -- red player (bottom)
    "playerOneName"             TEXT NOT NULL DEFAULT 'Player 1',
    "playerTwoId"               TEXT NOT NULL,             -- black player (top)
    "playerTwoName"             TEXT NOT NULL DEFAULT 'Player 2',
    "currentTurnPlayerId"       TEXT NOT NULL,             -- whose turn
    "boardState"                JSONB NOT NULL,            -- 8x8 grid of pieces
    status                      TEXT NOT NULL DEFAULT 'waiting',  -- waiting | in_progress | completed
    "winnerId"                  TEXT,
    "winnerName"                TEXT,
    "mandatoryCapturePending"   BOOLEAN NOT NULL DEFAULT false,  -- mid-multi-jump?
    "multiJumpPieceRow"         INTEGER,                   -- if multi-jump in progress, the row of the piece
    "multiJumpPieceCol"         INTEGER,                   -- if multi-jump in progress, the col of the piece
    "playerOneCaptured"         INTEGER NOT NULL DEFAULT 0, -- count of pieces captured BY player one
    "playerTwoCaptured"         INTEGER NOT NULL DEFAULT 0,
    "startedAt"                 TIMESTAMPTZ,
    "completedAt"               TIMESTAMPTZ,
    "createdAt"                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_checkers_games_family ON "checkers_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_checkers_games_status ON "checkers_games"("status");
CREATE INDEX IF NOT EXISTS idx_checkers_games_player1 ON "checkers_games"("playerOneId");
CREATE INDEX IF NOT EXISTS idx_checkers_games_player2 ON "checkers_games"("playerTwoId");

-- ─────────────────────────────────────────────────────────────────
-- checkers_moves — one row per move (for history + replay)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "checkers_moves" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "checkers_games"(id) ON DELETE CASCADE,
    "playerId"      TEXT NOT NULL,
    "playerName"    TEXT NOT NULL DEFAULT 'Player',
    "fromRow"       INTEGER NOT NULL,
    "fromCol"       INTEGER NOT NULL,
    "toRow"         INTEGER NOT NULL,
    "toCol"         INTEGER NOT NULL,
    "wasCapture"    BOOLEAN NOT NULL DEFAULT false,
    "capturedRow"   INTEGER,                                -- the row of the captured piece (if any)
    "capturedCol"   INTEGER,                                -- the col of the captured piece (if any)
    "becameKing"    BOOLEAN NOT NULL DEFAULT false,
    "moveNumber"    INTEGER NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_checkers_moves_game ON "checkers_moves"("gameId", "moveNumber");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped (same pattern as prior games)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "checkers_games" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "checkers_moves" ENABLE ROW LEVEL SECURITY;

-- checkers_games: family members can read/insert/update
CREATE POLICY "checkers_games_select" ON "checkers_games"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "checkers_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "checkers_games_insert" ON "checkers_games"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "checkers_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "checkers_games_update" ON "checkers_games"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "checkers_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

-- checkers_moves: family-scoped read; players insert their own moves
CREATE POLICY "checkers_moves_select" ON "checkers_moves"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "checkers_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "checkers_moves"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "checkers_moves_insert" ON "checkers_moves"
    FOR INSERT WITH CHECK ("playerId" = auth.uid()::text);

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication — both tables for live game sync
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "checkers_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "checkers_moves";
