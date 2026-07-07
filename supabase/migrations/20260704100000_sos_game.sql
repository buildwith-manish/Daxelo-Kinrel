-- SOS Game — 2-player and 4-player team mode
--
-- Classic SOS game where players place S or O letters on a grid to
-- complete SOS sequences. Two modes:
--   • two_player: 2 players, free letter choice, alternating turns
--   • four_player_teams: 4 players in 2 teams (Team S / Team O),
--     fixed letters per team, rotating turn order S1→O1→S2→O2
--
-- Pattern mirrors ghost_painter / redlight (camelCase columns,
-- FamilyMember join for RLS, Realtime publication).

-- ─────────────────────────────────────────────────────────────────
-- sos_games — one row per game session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "sos_games" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"      TEXT NOT NULL,
    "hostUserId"    TEXT NOT NULL,
    "hostUserName"  TEXT NOT NULL DEFAULT 'Host',
    mode            TEXT NOT NULL DEFAULT 'two_player',  -- two_player | four_player_teams
    "gridSize"      INTEGER NOT NULL DEFAULT 7,           -- 7x7 grid
    status          TEXT NOT NULL DEFAULT 'lobby',       -- lobby | active | finished
    "currentTurnOrder" INTEGER NOT NULL DEFAULT 0,       -- index into turn rotation
    "winnerTeam"    TEXT,                                 -- S | O | NULL (tie or 2-player)
    "winnerUserId"  TEXT,                                 -- for 2-player mode
    "startedAt"     TIMESTAMPTZ,
    "finishedAt"    TIMESTAMPTZ,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sos_games_family ON "sos_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_sos_games_status ON "sos_games"("status");

-- ─────────────────────────────────────────────────────────────────
-- sos_players — one row per player per game
-- In 2-player mode: team is NULL, turnOrder is 0 or 1
-- In 4-player team mode: team is S or O, turnOrder is 0-3
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "sos_players" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "sos_games"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    team            TEXT,                                 -- S | O | NULL (NULL in 2-player mode)
    "turnOrder"     INTEGER NOT NULL,                    -- 0,1,2,3
    score           INTEGER NOT NULL DEFAULT 0,          -- per-player score (2-player mode)
    "joinedAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_sos_players_game ON "sos_players"("gameId");
CREATE INDEX IF NOT EXISTS idx_sos_players_user ON "sos_players"("userId");

-- ─────────────────────────────────────────────────────────────────
-- sos_moves — one row per letter placement
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "sos_moves" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "sos_games"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    "rowIdx"        INTEGER NOT NULL,
    "colIdx"        INTEGER NOT NULL,
    letter          TEXT NOT NULL,                       -- S | O
    team            TEXT,                                 -- S | O | NULL (which team scored, team mode)
    sequenced       BOOLEAN NOT NULL DEFAULT false,      -- did this move complete SOS sequences?
    "sequenceCount" INTEGER NOT NULL DEFAULT 0,          -- how many sequences this move completed
    "playedAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "rowIdx", "colIdx")
);

CREATE INDEX IF NOT EXISTS idx_sos_moves_game ON "sos_moves"("gameId", "playedAt");

-- ─────────────────────────────────────────────────────────────────
-- sos_scores — denormalized standings (one row per player OR per team)
-- In 2-player mode: one row per player (team is NULL)
-- In 4-player team mode: one row per team (userId is NULL)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "sos_scores" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "sos_games"(id) ON DELETE CASCADE,
    "userId"        TEXT,                                 -- NULL in team mode
    team            TEXT,                                 -- S | O | NULL in 2-player
    score           INTEGER NOT NULL DEFAULT 0,
    "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sos_scores_game ON "sos_scores"("gameId");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped (same pattern as ghost_painter / redlight)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "sos_games"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "sos_players" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "sos_moves"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "sos_scores"  ENABLE ROW LEVEL SECURITY;

-- sos_games: family members can read/insert/update
CREATE POLICY "sos_games_select" ON "sos_games"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "sos_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "sos_games_insert" ON "sos_games"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "sos_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "sos_games_update" ON "sos_games"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "sos_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

-- sos_players: family-scoped read; users insert/update their own row
CREATE POLICY "sos_players_select" ON "sos_players"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "sos_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "sos_players"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "sos_players_insert" ON "sos_players"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "sos_players_update" ON "sos_players"
    FOR UPDATE USING ("userId" = auth.uid()::text);

-- sos_moves: family-scoped read; users insert their own moves
CREATE POLICY "sos_moves_select" ON "sos_moves"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "sos_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "sos_moves"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "sos_moves_insert" ON "sos_moves"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);

-- sos_scores: family-scoped read; users insert/update their own/team's score
CREATE POLICY "sos_scores_select" ON "sos_scores"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "sos_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "sos_scores"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "sos_scores_insert" ON "sos_scores"
    FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "sos_scores_update" ON "sos_scores"
    FOR UPDATE USING (TRUE);

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication — moves + players for live game sync
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "sos_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "sos_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "sos_moves";
