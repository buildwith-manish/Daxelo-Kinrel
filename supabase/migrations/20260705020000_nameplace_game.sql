-- Name, Place, Animal, Thing — letter-round scoring game (2-20 players)
--
-- Each round: a designated player picks a letter, all players write
-- one answer per category starting with that letter. Unique answers
-- get 10 pts, duplicates get 5 pts, dashes get 0. Game ends after
-- N rounds; highest total wins.
--
-- Privacy: answers are hidden from other players until the round
-- resolves (timer expires or all submitted).
--
-- Pattern mirrors prior games.

CREATE TABLE IF NOT EXISTS "nameplace_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "hostUserId"            TEXT NOT NULL,
    "hostUserName"          TEXT NOT NULL DEFAULT 'Host',
    status                  TEXT NOT NULL DEFAULT 'waiting',  -- waiting | in_progress | completed
    categories              JSONB NOT NULL DEFAULT '["Name","Place","Animal","Thing","Movie"]',
    "roundTimerSeconds"     INTEGER NOT NULL DEFAULT 60,
    "totalRounds"           INTEGER NOT NULL DEFAULT 5,
    "currentRound"          INTEGER NOT NULL DEFAULT 0,
    "currentLetterChooserId" TEXT,
    "currentLetter"         TEXT,
    "roundEndsAt"           TIMESTAMPTZ,
    "allAnswersSubmitted"   BOOLEAN NOT NULL DEFAULT false,
    "roundScoringDone"      BOOLEAN NOT NULL DEFAULT false,
    "winnerUserIds"         JSONB,
    "winnerNames"           JSONB,
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nameplace_games_family ON "nameplace_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_nameplace_games_status ON "nameplace_games"("status");

CREATE TABLE IF NOT EXISTS "nameplace_players" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "nameplace_games"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    "turnOrder"     INTEGER NOT NULL,
    "totalScore"    INTEGER NOT NULL DEFAULT 0,
    "hasSubmitted"  BOOLEAN NOT NULL DEFAULT false,
    "joinedAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_nameplace_players_game ON "nameplace_players"("gameId");

CREATE TABLE IF NOT EXISTS "nameplace_rounds" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"            TEXT NOT NULL REFERENCES "nameplace_games"(id) ON DELETE CASCADE,
    "roundNumber"       INTEGER NOT NULL,
    letter              TEXT NOT NULL,
    "letterChooserId"   TEXT NOT NULL,
    "letterChooserName" TEXT NOT NULL DEFAULT 'Player',
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nameplace_rounds_game ON "nameplace_rounds"("gameId", "roundNumber");

CREATE TABLE IF NOT EXISTS "nameplace_answers" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "roundId"       TEXT NOT NULL REFERENCES "nameplace_rounds"(id) ON DELETE CASCADE,
    "gameId"        TEXT NOT NULL,
    "playerId"      TEXT NOT NULL,
    "playerName"    TEXT NOT NULL DEFAULT 'Player',
    category        TEXT NOT NULL,
    "answerText"    TEXT NOT NULL,
    "pointsAwarded" INTEGER,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nameplace_answers_round ON "nameplace_answers"("roundId");
CREATE INDEX IF NOT EXISTS idx_nameplace_answers_game ON "nameplace_answers"("gameId");

-- RLS
ALTER TABLE "nameplace_games"    ENABLE ROW LEVEL SECURITY;
ALTER TABLE "nameplace_players"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE "nameplace_rounds"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "nameplace_answers"  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "nameplace_games_select" ON "nameplace_games"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "nameplace_games"."familyId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "nameplace_games_insert" ON "nameplace_games"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "nameplace_games"."familyId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "nameplace_games_update" ON "nameplace_games"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "nameplace_games"."familyId" AND fm."userId" = auth.uid()::text)
    );

CREATE POLICY "nameplace_players_select" ON "nameplace_players"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "nameplace_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "nameplace_players"."gameId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "nameplace_players_insert" ON "nameplace_players"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "nameplace_players_update" ON "nameplace_players"
    FOR UPDATE USING ("userId" = auth.uid()::text);

CREATE POLICY "nameplace_rounds_select" ON "nameplace_rounds"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "nameplace_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "nameplace_rounds"."gameId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "nameplace_rounds_insert" ON "nameplace_rounds"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "nameplace_games" WHERE id = "nameplace_rounds"."gameId") AND fm."userId" = auth.uid()::text)
    );

-- Answers: players can read their OWN answers always, but OTHER players'
-- answers only after roundScoringDone = true (privacy enforcement at DB level)
CREATE POLICY "nameplace_answers_select_own" ON "nameplace_answers"
    FOR SELECT USING ("playerId" = auth.uid()::text);
CREATE POLICY "nameplace_answers_select_resolved" ON "nameplace_answers"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "nameplace_games" g WHERE g.id = "nameplace_answers"."gameId" AND g."roundScoringDone" = true)
    );
CREATE POLICY "nameplace_answers_insert" ON "nameplace_answers"
    FOR INSERT WITH CHECK ("playerId" = auth.uid()::text);
CREATE POLICY "nameplace_answers_update" ON "nameplace_answers"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "nameplace_games" WHERE id = "nameplace_answers"."gameId") AND fm."userId" = auth.uid()::text)
    );

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE "nameplace_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "nameplace_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "nameplace_rounds";
ALTER PUBLICATION supabase_realtime ADD TABLE "nameplace_answers";
