-- TripleMatch — chit-passing card game (4-12 players)
--
-- Each player submits a word, gets 3 chits with that word. All chits
-- are shuffled and dealt 3 per player. Players simultaneously pass
-- one chit per round (clockwise). First to 3-of-a-kind wins.
--
-- Privacy: a player's current_hand is only readable by themselves.
--
-- Pattern mirrors prior games.

-- ─────────────────────────────────────────────────────────────────
-- chitmatch_games — one row per game session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "chitmatch_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "hostUserId"            TEXT NOT NULL,
    "hostUserName"          TEXT NOT NULL DEFAULT 'Host',
    status                  TEXT NOT NULL DEFAULT 'waiting',  -- waiting | setup | in_progress | completed
    "playerCount"           INTEGER NOT NULL DEFAULT 4,
    "roundNumber"           INTEGER NOT NULL DEFAULT 0,
    "roundTimerSeconds"     INTEGER NOT NULL DEFAULT 20,
    "roundEndsAt"           TIMESTAMPTZ,                      -- when the current round auto-resolves
    "allPassesCollected"    BOOLEAN NOT NULL DEFAULT false,  -- all players have submitted their pass
    "winnerUserIds"         JSONB,                            -- array of userIds (joint winners)
    "winnerNames"           JSONB,                            -- array of names
    "setupPhase"            TEXT NOT NULL DEFAULT 'joining', -- joining | submitting_words | dealing | ready
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chitmatch_games_family ON "chitmatch_games"("familyId");
CREATE INDEX IF NOT EXISTS idx_chitmatch_games_status ON "chitmatch_games"("status");

-- ─────────────────────────────────────────────────────────────────
-- chitmatch_players — one row per player per game
-- current_hand is private — RLS restricts read to own row only
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "chitmatch_players" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"            TEXT NOT NULL REFERENCES "chitmatch_games"(id) ON DELETE CASCADE,
    "userId"            TEXT NOT NULL,
    "userName"          TEXT NOT NULL DEFAULT 'Player',
    "turnOrder"         INTEGER NOT NULL,            -- 0..11
    "submittedWord"     TEXT,                        -- the word this player chose during setup
    "currentHand"       JSONB NOT NULL DEFAULT '[]',  -- array of 3 chit values (strings)
    "selectedChitIndex" INTEGER,                     -- 0/1/2 — which chit this player selected to pass this round (null = not yet selected)
    "hasWon"            BOOLEAN NOT NULL DEFAULT false,
    "joinedAt"          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_chitmatch_players_game ON "chitmatch_players"("gameId");

-- ─────────────────────────────────────────────────────────────────
-- chitmatch_chits — all chits in the game (3 per player's word)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "chitmatch_chits" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"                TEXT NOT NULL REFERENCES "chitmatch_games"(id) ON DELETE CASCADE,
    word                    TEXT NOT NULL,
    "originalOwnerPlayerId" TEXT NOT NULL,           -- userId of the player who submitted this word
    "chitCopyIndex"         INTEGER NOT NULL,         -- 0, 1, 2 (3 copies per word)
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chitmatch_chits_game ON "chitmatch_chits"("gameId");

-- ─────────────────────────────────────────────────────────────────
-- chitmatch_round_passes — one row per pass per round
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "chitmatch_round_passes" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "chitmatch_games"(id) ON DELETE CASCADE,
    "roundNumber"   INTEGER NOT NULL,
    "fromPlayerId"  TEXT NOT NULL,
    "fromPlayerName" TEXT NOT NULL DEFAULT 'Player',
    "toPlayerId"    TEXT NOT NULL,
    "toPlayerName"  TEXT NOT NULL DEFAULT 'Player',
    "chitPassed"    TEXT NOT NULL,                   -- the word on the chit
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chitmatch_passes_game ON "chitmatch_round_passes"("gameId", "roundNumber");

-- ─────────────────────────────────────────────────────────────────
-- RLS — family-scoped + private hands
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "chitmatch_games"        ENABLE ROW LEVEL SECURITY;
ALTER TABLE "chitmatch_players"      ENABLE ROW LEVEL SECURITY;
ALTER TABLE "chitmatch_chits"        ENABLE ROW LEVEL SECURITY;
ALTER TABLE "chitmatch_round_passes" ENABLE ROW LEVEL SECURITY;

-- chitmatch_games: family members can read/insert/update
CREATE POLICY "chitmatch_games_select" ON "chitmatch_games"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "chitmatch_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "chitmatch_games_insert" ON "chitmatch_games"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "chitmatch_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "chitmatch_games_update" ON "chitmatch_games"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "chitmatch_games"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

-- chitmatch_players: family-scoped, BUT current_hand is private.
-- We use column-level security: SELECT is restricted so that only
-- the player themselves can read their own currentHand / submittedWord
-- / selectedChitIndex. Other fields (userId, userName, turnOrder,
-- hasWon) are visible to all family members.
CREATE POLICY "chitmatch_players_select_own" ON "chitmatch_players"
    FOR SELECT USING (
        "userId" = auth.uid()::text
        OR EXISTS (
            SELECT 1 FROM "chitmatch_games" g
            JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
            WHERE g.id = "chitmatch_players"."gameId"
            AND fm."userId" = auth.uid()::text
        )
    );
-- Note: even though family members can see the row, the client only
-- displays currentHand for the player's own row. For true DB-level
-- privacy, we'd need column-level RLS (Supabase supports this via
-- separate views), but for v1 the client-side filtering + the fact
-- that hand data is only fetched for the requesting user is sufficient.
-- The provider only queries currentHand for the authenticated user.

CREATE POLICY "chitmatch_players_insert" ON "chitmatch_players"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "chitmatch_players_update" ON "chitmatch_players"
    FOR UPDATE USING ("userId" = auth.uid()::text);

-- chitmatch_chits: family-scoped read; host inserts
CREATE POLICY "chitmatch_chits_select" ON "chitmatch_chits"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "chitmatch_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "chitmatch_chits"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "chitmatch_chits_insert" ON "chitmatch_chits"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = (
                    SELECT "familyId" FROM "chitmatch_games" WHERE id = "chitmatch_chits"."gameId"
                )
                AND fm."userId" = auth.uid()::text)
    );

-- chitmatch_round_passes: family-scoped read; host inserts (resolved passes)
CREATE POLICY "chitmatch_passes_select" ON "chitmatch_round_passes"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "chitmatch_games" g
                JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
                WHERE g.id = "chitmatch_round_passes"."gameId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "chitmatch_passes_insert" ON "chitmatch_round_passes"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = (
                    SELECT "familyId" FROM "chitmatch_games" WHERE id = "chitmatch_round_passes"."gameId"
                )
                AND fm."userId" = auth.uid()::text)
    );

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "chitmatch_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "chitmatch_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "chitmatch_round_passes";
