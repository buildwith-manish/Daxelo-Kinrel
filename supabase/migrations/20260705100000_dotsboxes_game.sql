-- Dots and Boxes — 2-4 players, classic pen-and-paper game
-- Players draw lines between dots. Complete a box = capture + bonus turn.
-- Most boxes wins. Supports ties for 3-4 player games.

CREATE TABLE IF NOT EXISTS "dotsboxes_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "hostUserId"            TEXT NOT NULL,
    "hostUserName"          TEXT NOT NULL DEFAULT 'Host',
    status                  TEXT NOT NULL DEFAULT 'waiting',
    "gridSize"              INTEGER NOT NULL DEFAULT 5, -- 5x5 boxes = 6x6 dots
    "currentTurnPlayerId"   TEXT,
    "bonusTurn"             BOOLEAN NOT NULL DEFAULT false,
    "winnerUserIds"         JSONB,
    "winnerNames"           JSONB,
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_db_games_family ON "dotsboxes_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_db_games_status ON "dotsboxes_games"("status");

CREATE TABLE IF NOT EXISTS "dotsboxes_players" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "dotsboxes_games"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    "turnOrder"     INTEGER NOT NULL,
    "playerColor"   INTEGER NOT NULL, -- 0=orange, 1=blue, 2=teal, 3=gold
    "boxesCaptured" INTEGER NOT NULL DEFAULT 0,
    "joinedAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_db_players_game ON "dotsboxes_players"("gameId");

CREATE TABLE IF NOT EXISTS "dotsboxes_lines" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"            TEXT NOT NULL REFERENCES "dotsboxes_games"(id) ON DELETE CASCADE,
    "lineType"          TEXT NOT NULL, -- horizontal | vertical
    "row"               INTEGER NOT NULL,
    "col"               INTEGER NOT NULL,
    "drawnByPlayerId"   TEXT NOT NULL,
    "drawnByPlayerName" TEXT NOT NULL DEFAULT 'Player',
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "lineType", "row", "col")
);

CREATE INDEX IF NOT EXISTS idx_db_lines_game ON "dotsboxes_lines"("gameId");

CREATE TABLE IF NOT EXISTS "dotsboxes_boxes" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"            TEXT NOT NULL REFERENCES "dotsboxes_games"(id) ON DELETE CASCADE,
    "boxRow"            INTEGER NOT NULL,
    "boxCol"            INTEGER NOT NULL,
    "capturedByPlayerId" TEXT,
    "capturedByPlayerName" TEXT,
    "capturedAt"        TIMESTAMPTZ,
    UNIQUE("gameId", "boxRow", "boxCol")
);

CREATE INDEX IF NOT EXISTS idx_db_boxes_game ON "dotsboxes_boxes"("gameId");

ALTER TABLE "dotsboxes_games"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "dotsboxes_players" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "dotsboxes_lines"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "dotsboxes_boxes"   ENABLE ROW LEVEL SECURITY;

CREATE POLICY "db_games_select" ON "dotsboxes_games"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "dotsboxes_games"."familyId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "db_games_insert" ON "dotsboxes_games"
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "dotsboxes_games"."familyId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "db_games_update" ON "dotsboxes_games"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "dotsboxes_games"."familyId" AND fm."userId" = auth.uid()::text));

CREATE POLICY "db_players_select" ON "dotsboxes_players"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "dotsboxes_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "dotsboxes_players"."gameId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "db_players_insert" ON "dotsboxes_players"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "db_players_update" ON "dotsboxes_players"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "dotsboxes_games" WHERE id = "dotsboxes_players"."gameId") AND fm."userId" = auth.uid()::text));

CREATE POLICY "db_lines_select" ON "dotsboxes_lines"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "dotsboxes_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "dotsboxes_lines"."gameId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "db_lines_insert" ON "dotsboxes_lines"
    FOR INSERT WITH CHECK ("drawnByPlayerId" = auth.uid()::text);

CREATE POLICY "db_boxes_select" ON "dotsboxes_boxes"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "dotsboxes_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "dotsboxes_boxes"."gameId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "db_boxes_insert" ON "dotsboxes_boxes"
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "dotsboxes_games" WHERE id = "dotsboxes_boxes"."gameId") AND fm."userId" = auth.uid()::text));
CREATE POLICY "db_boxes_update" ON "dotsboxes_boxes"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "dotsboxes_games" WHERE id = "dotsboxes_boxes"."gameId") AND fm."userId" = auth.uid()::text));

ALTER PUBLICATION supabase_realtime ADD TABLE "dotsboxes_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "dotsboxes_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "dotsboxes_lines";
ALTER PUBLICATION supabase_realtime ADD TABLE "dotsboxes_boxes";
