-- Chess Game — 2-player standard chess using chess.dart (MIT+BSD) logic engine
--
-- Players: white and black. Board state stored as FEN. Moves recorded
-- with algebraic notation. All logic (move validation, check/checkmate/
-- stalemate, castling, en passant, promotion) handled client-side by
-- the chess package — Supabase stores state + broadcasts via Realtime.
--
-- Pattern mirrors prior games.

-- ─────────────────────────────────────────────────────────────────
-- chess_games — one row per game session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "chess_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "playerWhiteId"         TEXT NOT NULL,
    "playerWhiteName"       TEXT NOT NULL DEFAULT 'Player 1',
    "playerBlackId"         TEXT NOT NULL,
    "playerBlackName"       TEXT NOT NULL DEFAULT 'Player 2',
    "currentTurnColor"      TEXT NOT NULL DEFAULT 'white',  -- white | black
    "boardState"            TEXT NOT NULL,                  -- FEN string
    status                  TEXT NOT NULL DEFAULT 'waiting', -- waiting | in_progress | completed
    result                  TEXT,                           -- white_win | black_win | draw | stalemate
    "winnerId"              TEXT,
    "winnerName"            TEXT,
    "lastMoveAt"            TIMESTAMPTZ,
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chess_games_family ON "chess_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_chess_games_status ON "chess_games"("status");

-- ─────────────────────────────────────────────────────────────────
-- chess_moves — one row per move (for history + replay)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "chess_moves" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"            TEXT NOT NULL REFERENCES "chess_games"(id) ON DELETE CASCADE,
    "playerId"          TEXT NOT NULL,
    "playerName"        TEXT NOT NULL DEFAULT 'Player',
    "fromSquare"        TEXT NOT NULL,            -- e.g. 'e2'
    "toSquare"          TEXT NOT NULL,            -- e.g. 'e4'
    "pieceMoved"        TEXT NOT NULL,            -- e.g. 'P', 'N', 'B', 'R', 'Q', 'K'
    "capturedPiece"     TEXT,                     -- e.g. 'p' (lowercase if black)
    "specialMove"       TEXT,                     -- castle_kingside | castle_queenside | en_passant | promotion
    "promotedTo"        TEXT,                     -- Q | R | B | N (if promotion)
    "moveNumber"        INTEGER NOT NULL,
    notation            TEXT NOT NULL,            -- algebraic notation, e.g. 'e4', 'Nf3', 'O-O', 'exd5'
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chess_moves_game ON "chess_moves"("gameId", "moveNumber");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped (same pattern as prior games)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "chess_games" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "chess_moves" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chess_games_select" ON "chess_games"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "chess_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "chess_games_insert" ON "chess_games"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "chess_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "chess_games_update" ON "chess_games"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "chess_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

CREATE POLICY "chess_moves_select" ON "chess_moves"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "chess_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "chess_moves"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "chess_moves_insert" ON "chess_moves"
    FOR INSERT WITH CHECK ("playerId" = auth.uid()::text);

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "chess_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "chess_moves";
