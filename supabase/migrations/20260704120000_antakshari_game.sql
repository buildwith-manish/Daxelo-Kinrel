-- Antakshari Game — 2-20 players, turn-based singing game
--
-- Players take turns singing a song line (via external voice/video call)
-- starting with the last letter of the previous player's song. The app
-- tracks turns and validates the letter-chain rule via self-reporting
-- + a 3-challenge threshold mechanic. NO song lyrics or audio are
-- stored — pure turn tracking.
--
-- Pattern mirrors ghost_painter / redlight / sos (camelCase columns,
-- FamilyMember join for RLS, Realtime publication).

-- ─────────────────────────────────────────────────────────────────
-- antakshari_games — one row per game session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "antakshari_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "hostUserId"            TEXT NOT NULL,
    "hostUserName"          TEXT NOT NULL DEFAULT 'Host',
    status                  TEXT NOT NULL DEFAULT 'waiting',  -- waiting | in_progress | completed
    "gameMode"              TEXT NOT NULL DEFAULT 'standard', -- standard | round_limited
    "currentTurnPlayerId"   TEXT,                             -- userId of active player
    "currentRequiredLetter" TEXT,                             -- single char A-Z
    "turnTimerSeconds"      INTEGER NOT NULL DEFAULT 30,
    "turnStartedAt"         TIMESTAMPTZ,                      -- when current turn began
    "maxPlayers"            INTEGER NOT NULL DEFAULT 12,      -- cap 20
    "roundLimit"            INTEGER,                          -- nullable; for round_limited mode
    "currentTurnNumber"     INTEGER NOT NULL DEFAULT 0,
    "currentRound"          INTEGER NOT NULL DEFAULT 0,
    "winnerUserIds"         JSONB,                            -- array of userIds (multi-winner for round_limited)
    "winnerNames"           JSONB,                            -- array of names
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_antakshari_games_family ON "antakshari_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_antakshari_games_status ON "antakshari_games"("status");

-- ─────────────────────────────────────────────────────────────────
-- antakshari_players — one row per player per game
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "antakshari_players" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "antakshari_games"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    "turnOrder"     INTEGER NOT NULL,            -- 0..19
    "isEliminated"  BOOLEAN NOT NULL DEFAULT false,
    "eliminatedAt"  TIMESTAMPTZ,
    "joinedAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_antakshari_players_game ON "antakshari_players"("gameId");
CREATE INDEX IF NOT EXISTS idx_antakshari_players_user ON "antakshari_players"("userId");

-- ─────────────────────────────────────────────────────────────────
-- antakshari_turns — one row per turn (player sings + reports letter)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "antakshari_turns" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"                TEXT NOT NULL REFERENCES "antakshari_games"(id) ON DELETE CASCADE,
    "playerId"              TEXT NOT NULL,                    -- userId
    "playerName"            TEXT NOT NULL DEFAULT 'Player',
    "letterStartedWith"     TEXT NOT NULL,                    -- single char A-Z
    "letterEndedWith"       TEXT,                             -- single char A-Z (null if timed out)
    "turnNumber"            INTEGER NOT NULL,
    "wasChallenged"         BOOLEAN NOT NULL DEFAULT false,
    "challengeResult"       TEXT NOT NULL DEFAULT 'pending',  -- pending | valid | invalid | timed_out
    "challengeWindowEndsAt" TIMESTAMPTZ,                      -- 10s after turn submitted
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_antakshari_turns_game ON "antakshari_turns"("gameId", "turnNumber");

-- ─────────────────────────────────────────────────────────────────
-- antakshari_challenges — one row per challenge (3+ = auto-eliminate)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "antakshari_challenges" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "turnId"        TEXT NOT NULL REFERENCES "antakshari_turns"(id) ON DELETE CASCADE,
    "challengerId"  TEXT NOT NULL,                            -- userId
    "challengerName" TEXT NOT NULL DEFAULT 'Player',
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("turnId", "challengerId")                          -- one challenge per player per turn
);

CREATE INDEX IF NOT EXISTS idx_antakshari_challenges_turn ON "antakshari_challenges"("turnId");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped (same pattern as ghost_painter / redlight / sos)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "antakshari_games"     ENABLE ROW LEVEL SECURITY;
ALTER TABLE "antakshari_players"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "antakshari_turns"     ENABLE ROW LEVEL SECURITY;
ALTER TABLE "antakshari_challenges" ENABLE ROW LEVEL SECURITY;

-- antakshari_games: family members can read/insert/update
CREATE POLICY "antakshari_games_select" ON "antakshari_games"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "antakshari_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "antakshari_games_insert" ON "antakshari_games"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "antakshari_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "antakshari_games_update" ON "antakshari_games"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "antakshari_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

-- antakshari_players: family-scoped read; users insert/update their own row
CREATE POLICY "antakshari_players_select" ON "antakshari_players"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "antakshari_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "antakshari_players"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "antakshari_players_insert" ON "antakshari_players"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "antakshari_players_update" ON "antakshari_players"
    FOR UPDATE USING ("userId" = auth.uid()::text);

-- antakshari_turns: family-scoped read; active player inserts their own turn
CREATE POLICY "antakshari_turns_select" ON "antakshari_turns"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "antakshari_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "antakshari_turns"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "antakshari_turns_insert" ON "antakshari_turns"
    FOR INSERT WITH CHECK ("playerId" = auth.uid()::text);

-- antakshari_challenges: family-scoped read; users insert their own challenge
CREATE POLICY "antakshari_challenges_select" ON "antakshari_challenges"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "antakshari_turns" t
                JOIN "antakshari_games" g ON g.id = t."gameId"
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE t.id = "antakshari_challenges"."turnId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "antakshari_challenges_insert" ON "antakshari_challenges"
    FOR INSERT WITH CHECK ("challengerId" = auth.uid()::text);

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication — all 4 tables for live game sync
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "antakshari_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "antakshari_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "antakshari_turns";
ALTER PUBLICATION supabase_realtime ADD TABLE "antakshari_challenges";
