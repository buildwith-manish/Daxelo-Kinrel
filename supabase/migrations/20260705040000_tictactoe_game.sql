-- Tic-Tac-Toe — 2-player, best-of-N rounds
-- Pure game logic written from scratch (no external package needed).

CREATE TABLE IF NOT EXISTS "tictactoe_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "playerXId"             TEXT NOT NULL,
    "playerXName"           TEXT NOT NULL DEFAULT 'Player 1',
    "playerOId"             TEXT NOT NULL,
    "playerOName"           TEXT NOT NULL DEFAULT 'Player 2',
    "currentTurnPlayerId"   TEXT NOT NULL,
    "bestOf"                INTEGER NOT NULL DEFAULT 1,
    "roundsWonX"            INTEGER NOT NULL DEFAULT 0,
    "roundsWonO"            INTEGER NOT NULL DEFAULT 0,
    "currentRound"          INTEGER NOT NULL DEFAULT 1,
    status                  TEXT NOT NULL DEFAULT 'waiting', -- waiting | in_progress | completed
    "overallWinnerId"       TEXT,
    "overallWinnerName"     TEXT,
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tictactoe_games_family ON "tictactoe_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_tictactoe_games_status ON "tictactoe_games"("status");

CREATE TABLE IF NOT EXISTS "tictactoe_rounds" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "tictactoe_games"(id) ON DELETE CASCADE,
    "roundNumber"   INTEGER NOT NULL,
    "boardState"    JSONB NOT NULL DEFAULT '[null,null,null,null,null,null,null,null,null]',
    result          TEXT, -- x_win | o_win | draw | null
    "completedAt"   TIMESTAMPTZ,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tictactoe_rounds_game ON "tictactoe_rounds"("gameId", "roundNumber");

CREATE TABLE IF NOT EXISTS "tictactoe_moves" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "roundId"       TEXT NOT NULL REFERENCES "tictactoe_rounds"(id) ON DELETE CASCADE,
    "playerId"      TEXT NOT NULL,
    "playerName"    TEXT NOT NULL DEFAULT 'Player',
    "cellIndex"     INTEGER NOT NULL, -- 0-8
    mark            TEXT NOT NULL,    -- X | O
    "moveNumber"    INTEGER NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tictactoe_moves_round ON "tictactoe_moves"("roundId", "moveNumber");

ALTER TABLE "tictactoe_games"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tictactoe_rounds" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "tictactoe_moves"  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tictactoe_games_select" ON "tictactoe_games"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "tictactoe_games"."familyId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tictactoe_games_insert" ON "tictactoe_games"
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "tictactoe_games"."familyId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tictactoe_games_update" ON "tictactoe_games"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "tictactoe_games"."familyId" AND fm."userId" = auth.uid()::text));

CREATE POLICY "tictactoe_rounds_select" ON "tictactoe_rounds"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "tictactoe_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "tictactoe_rounds"."gameId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tictactoe_rounds_insert" ON "tictactoe_rounds"
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "tictactoe_games" WHERE id = "tictactoe_rounds"."gameId") AND fm."userId" = auth.uid()::text));
CREATE POLICY "tictactoe_rounds_update" ON "tictactoe_rounds"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "tictactoe_games" WHERE id = "tictactoe_rounds"."gameId") AND fm."userId" = auth.uid()::text));

CREATE POLICY "tictactoe_moves_select" ON "tictactoe_moves"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "tictactoe_rounds" r JOIN "tictactoe_games" g ON g.id = r."gameId" JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE r.id = "tictactoe_moves"."roundId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tictactoe_moves_insert" ON "tictactoe_moves"
    FOR INSERT WITH CHECK ("playerId" = auth.uid()::text);

ALTER PUBLICATION supabase_realtime ADD TABLE "tictactoe_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "tictactoe_rounds";
ALTER PUBLICATION supabase_realtime ADD TABLE "tictactoe_moves";
