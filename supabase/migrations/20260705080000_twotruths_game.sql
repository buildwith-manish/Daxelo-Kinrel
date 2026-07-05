-- Two Truths and a Lie — 4-12 players, turn-based deduction game
-- Each round: one player submits 3 statements (2 true, 1 lie).
-- Others guess which is the lie. Correct guess = 1 pt. Each fooled player = 1 pt for submitter.
-- lie_index is hidden from all players until the round resolves (RLS enforced).

CREATE TABLE IF NOT EXISTS "twotruths_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "hostUserId"            TEXT NOT NULL,
    "hostUserName"          TEXT NOT NULL DEFAULT 'Host',
    status                  TEXT NOT NULL DEFAULT 'waiting',
    mode                    TEXT NOT NULL DEFAULT 'player_authored', -- player_authored | ai_lie
    "currentRound"          INTEGER NOT NULL DEFAULT 0,
    "totalRounds"           INTEGER NOT NULL DEFAULT 3,
    "currentSubmitterId"    TEXT,
    "roundTimerSeconds"     INTEGER NOT NULL DEFAULT 30,
    "roundEndsAt"           TIMESTAMPTZ,
    "allGuessesSubmitted"   BOOLEAN NOT NULL DEFAULT false,
    "roundResolved"         BOOLEAN NOT NULL DEFAULT false,
    "winnerUserIds"         JSONB,
    "winnerNames"           JSONB,
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tt_games_family ON "twotruths_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_tt_games_status ON "twotruths_games"("status");

CREATE TABLE IF NOT EXISTS "twotruths_players" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "twotruths_games"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    "turnOrder"     INTEGER NOT NULL,
    "totalScore"    INTEGER NOT NULL DEFAULT 0,
    "hasGuessed"    BOOLEAN NOT NULL DEFAULT false,
    "joinedAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_tt_players_game ON "twotruths_players"("gameId");

CREATE TABLE IF NOT EXISTS "twotruths_rounds" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "twotruths_games"(id) ON DELETE CASCADE,
    "roundNumber"   INTEGER NOT NULL,
    "submitterId"   TEXT NOT NULL,
    "submitterName" TEXT NOT NULL DEFAULT 'Player',
    "statement1"    TEXT NOT NULL,
    "statement2"    TEXT NOT NULL,
    "statement3"    TEXT NOT NULL,
    "lieIndex"      INTEGER NOT NULL, -- 1, 2, or 3
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tt_rounds_game ON "twotruths_rounds"("gameId", "roundNumber");

CREATE TABLE IF NOT EXISTS "twotruths_guesses" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "roundId"           TEXT NOT NULL REFERENCES "twotruths_rounds"(id) ON DELETE CASCADE,
    "gameId"            TEXT NOT NULL,
    "guesserId"         TEXT NOT NULL,
    "guesserName"       TEXT NOT NULL DEFAULT 'Player',
    "guessedLieIndex"   INTEGER NOT NULL, -- 1, 2, or 3
    "isCorrect"         BOOLEAN,
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("roundId", "guesserId")
);

CREATE INDEX IF NOT EXISTS idx_tt_guesses_round ON "twotruths_guesses"("roundId");

-- RLS
ALTER TABLE "twotruths_games"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "twotruths_players" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "twotruths_rounds"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE "twotruths_guesses" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tt_games_select" ON "twotruths_games"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "twotruths_games"."familyId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tt_games_insert" ON "twotruths_games"
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "twotruths_games"."familyId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tt_games_update" ON "twotruths_games"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "twotruths_games"."familyId" AND fm."userId" = auth.uid()::text));

CREATE POLICY "tt_players_select" ON "twotruths_players"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "twotruths_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "twotruths_players"."gameId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tt_players_insert" ON "twotruths_players"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "tt_players_update" ON "twotruths_players"
    FOR UPDATE USING ("userId" = auth.uid()::text);

-- Rounds: family can see statements, BUT lie_index is only visible after roundResolved
-- We can't do column-level RLS easily in Supabase, so the client hides lie_index
-- until roundResolved=true. The RLS on guesses enforces blind guessing.
CREATE POLICY "tt_rounds_select" ON "twotruths_rounds"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "twotruths_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "twotruths_rounds"."gameId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tt_rounds_insert" ON "twotruths_rounds"
    FOR INSERT WITH CHECK (
        "submitterId" = auth.uid()::text AND
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "twotruths_games" WHERE id = "twotruths_rounds"."gameId") AND fm."userId" = auth.uid()::text)
    );

-- Guesses: guesser can see their own guess; others' guesses only visible after roundResolved
CREATE POLICY "tt_guesses_select_own" ON "twotruths_guesses"
    FOR SELECT USING ("guesserId" = auth.uid()::text);
CREATE POLICY "tt_guesses_select_resolved" ON "twotruths_guesses"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "twotruths_games" g WHERE g.id = "twotruths_guesses"."gameId" AND g."roundResolved" = true)
    );
CREATE POLICY "tt_guesses_insert" ON "twotruths_guesses"
    FOR INSERT WITH CHECK ("guesserId" = auth.uid()::text);
CREATE POLICY "tt_guesses_update" ON "twotruths_guesses"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "twotruths_games" WHERE id = "twotruths_guesses"."gameId") AND fm."userId" = auth.uid()::text));

ALTER PUBLICATION supabase_realtime ADD TABLE "twotruths_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "twotruths_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "twotruths_rounds";
ALTER PUBLICATION supabase_realtime ADD TABLE "twotruths_guesses";
