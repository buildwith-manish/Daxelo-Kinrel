-- Ludo Game — 2-4 players, classic Ludo (derived from Pachisi)
--
-- Players roll a die, move tokens around a 52-square shared track,
-- capture opponents, and race to get all 4 tokens to the center.
-- Dice rolls are server-authoritative (Edge Function) to prevent
-- client-side manipulation.
--
-- Token position encoding:
--   -1  = in home base (not yet on board)
--   0-50 = relative position on shared track (51 squares traveled)
--   51-56 = home column (6 private squares)
--   57  = finished (reached center)
--
-- Pattern mirrors prior games.

-- ─────────────────────────────────────────────────────────────────
-- ludo_games — one row per game session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "ludo_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "hostUserId"            TEXT NOT NULL,
    "hostUserName"          TEXT NOT NULL DEFAULT 'Host',
    status                  TEXT NOT NULL DEFAULT 'waiting',  -- waiting | in_progress | completed
    "playerCount"           INTEGER NOT NULL DEFAULT 2,       -- 2-4
    "currentTurnPlayerId"   TEXT,                             -- whose turn
    "lastDiceRoll"          INTEGER,                          -- 1-6 or null
    "consecutiveSixes"      INTEGER NOT NULL DEFAULT 0,       -- 3 = forfeit
    "extraTurnPending"      BOOLEAN NOT NULL DEFAULT false,   -- rolled 6, go again
    "winnerId"              TEXT,
    "winnerName"            TEXT,
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ludo_games_family ON "ludo_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_ludo_games_status ON "ludo_games"("status");

-- ─────────────────────────────────────────────────────────────────
-- ludo_players — one row per player per game
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "ludo_players" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "ludo_games"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    color           TEXT NOT NULL,                    -- red | blue | green | yellow
    "turnOrder"     INTEGER NOT NULL,                 -- 0-3
    "tokensFinished" INTEGER NOT NULL DEFAULT 0,     -- count of tokens at center
    "joinedAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_ludo_players_game ON "ludo_players"("gameId");

-- ─────────────────────────────────────────────────────────────────
-- ludo_tokens — one row per token (4 per player)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "ludo_tokens" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "ludo_games"(id) ON DELETE CASCADE,
    "playerId"      TEXT NOT NULL,                    -- userId of owner
    "tokenIndex"    INTEGER NOT NULL,                 -- 0-3
    position        INTEGER NOT NULL DEFAULT -1,      -- see encoding above
    "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "playerId", "tokenIndex")
);

CREATE INDEX IF NOT EXISTS idx_ludo_tokens_game ON "ludo_tokens"("gameId");
CREATE INDEX IF NOT EXISTS idx_ludo_tokens_player ON "ludo_tokens"("playerId");

-- ─────────────────────────────────────────────────────────────────
-- ludo_moves — one row per move (for history + replay)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "ludo_moves" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"            TEXT NOT NULL REFERENCES "ludo_games"(id) ON DELETE CASCADE,
    "playerId"          TEXT NOT NULL,
    "playerName"        TEXT NOT NULL DEFAULT 'Player',
    "tokenId"           TEXT,                           -- which token moved (null if just a roll)
    "tokenIndex"        INTEGER,                        -- 0-3
    "diceValue"         INTEGER NOT NULL,               -- 1-6
    "fromPosition"      INTEGER NOT NULL DEFAULT -1,
    "toPosition"        INTEGER NOT NULL DEFAULT -1,
    "capturedTokenId"   TEXT,                           -- opponent token sent home (if any)
    "capturedPlayerName" TEXT,
    "moveNumber"        INTEGER NOT NULL,
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ludo_moves_game ON "ludo_moves"("gameId", "moveNumber");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped (same pattern as prior games)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "ludo_games"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ludo_players" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ludo_tokens"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ludo_moves"   ENABLE ROW LEVEL SECURITY;

-- ludo_games: family members can read/insert/update
CREATE POLICY "ludo_games_select" ON "ludo_games"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "ludo_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "ludo_games_insert" ON "ludo_games"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "ludo_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "ludo_games_update" ON "ludo_games"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "ludo_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

-- ludo_players: family-scoped read; users insert their own row
CREATE POLICY "ludo_players_select" ON "ludo_players"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "ludo_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "ludo_players"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "ludo_players_insert" ON "ludo_players"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "ludo_players_update" ON "ludo_players"
    FOR UPDATE USING ("userId" = auth.uid()::text);

-- ludo_tokens: family-scoped read; any player in the game can update
-- (the current turn player moves tokens, including opponent's on capture)
CREATE POLICY "ludo_tokens_select" ON "ludo_tokens"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "ludo_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "ludo_tokens"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "ludo_tokens_insert" ON "ludo_tokens"
    FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "ludo_tokens_update" ON "ludo_tokens"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "ludo_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "ludo_tokens"."gameId"
                AND fm."userId" = auth.uid()::text)
    );

-- ludo_moves: family-scoped read; players insert their own moves
CREATE POLICY "ludo_moves_select" ON "ludo_moves"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "ludo_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "ludo_moves"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "ludo_moves_insert" ON "ludo_moves"
    FOR INSERT WITH CHECK ("playerId" = auth.uid()::text);

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication — all 4 tables for live game sync
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "ludo_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "ludo_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "ludo_tokens";
ALTER PUBLICATION supabase_realtime ADD TABLE "ludo_moves";
