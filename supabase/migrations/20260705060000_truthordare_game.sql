-- Truth or Dare — spin-the-bottle with family-submitted, admin-approved prompts
-- 4-12 players. Bottle spins, lands on a player (never spinner). They pick
-- Truth or Dare, get a random approved prompt from the family's pool.
-- Prompts must be submitted and admin-approved before they're playable.

CREATE TABLE IF NOT EXISTS "truthordare_prompts" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"          TEXT NOT NULL,
    category            TEXT NOT NULL,            -- truth | dare
    "promptText"        TEXT NOT NULL,
    "submittedById"     TEXT NOT NULL,
    "submittedByName"   TEXT NOT NULL DEFAULT 'Member',
    status              TEXT NOT NULL DEFAULT 'pending', -- pending | approved | rejected
    "flaggedByFilter"   BOOLEAN NOT NULL DEFAULT false,
    "reviewedById"      TEXT,
    "reviewedByName"    TEXT,
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now(),
    "reviewedAt"        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_tod_prompts_family ON "truthordare_prompts"("familyId");
CREATE INDEX IF NOT EXISTS idx_tod_prompts_status ON "truthordare_prompts"(status);

CREATE TABLE IF NOT EXISTS "truthordare_games" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    "hostUserId"            TEXT NOT NULL,
    "hostUserName"          TEXT NOT NULL DEFAULT 'Host',
    status                  TEXT NOT NULL DEFAULT 'waiting',
    "currentSpinnerId"      TEXT,
    "roundNumber"           INTEGER NOT NULL DEFAULT 0,
    "startedAt"             TIMESTAMPTZ,
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tod_games_family ON "truthordare_games"("familyId");

CREATE TABLE IF NOT EXISTS "truthordare_players" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"        TEXT NOT NULL REFERENCES "truthordare_games"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    "seatPosition"  INTEGER NOT NULL,
    "timesSelected" INTEGER NOT NULL DEFAULT 0,
    "joinedAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("gameId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_tod_players_game ON "truthordare_players"("gameId");

CREATE TABLE IF NOT EXISTS "truthordare_rounds" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "gameId"                TEXT NOT NULL REFERENCES "truthordare_games"(id) ON DELETE CASCADE,
    "roundNumber"           INTEGER NOT NULL,
    "spinnerId"             TEXT NOT NULL,
    "spinnerName"           TEXT NOT NULL DEFAULT 'Player',
    "selectedPlayerId"      TEXT,
    "selectedPlayerName"    TEXT,
    choice                  TEXT,                  -- truth | dare
    "promptId"              TEXT REFERENCES "truthordare_prompts"(id),
    "promptText"            TEXT,
    completed               BOOLEAN NOT NULL DEFAULT false,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tod_rounds_game ON "truthordare_rounds"("gameId", "roundNumber");

-- RLS
ALTER TABLE "truthordare_prompts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "truthordare_games"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE "truthordare_players" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "truthordare_rounds"  ENABLE ROW LEVEL SECURITY;

-- Prompts: submitter sees own (any status); all family members see approved
CREATE POLICY "tod_prompts_select_own" ON "truthordare_prompts"
    FOR SELECT USING ("submittedById" = auth.uid()::text);
CREATE POLICY "tod_prompts_select_approved" ON "truthordare_prompts"
    FOR SELECT USING (
        status = 'approved' AND EXISTS (
            SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "truthordare_prompts"."familyId" AND fm."userId" = auth.uid()::text
        )
    );
CREATE POLICY "tod_prompts_insert" ON "truthordare_prompts"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "truthordare_prompts"."familyId" AND fm."userId" = auth.uid()::text)
    );
-- Only the family Creator/admin can update prompt status (approve/reject)
-- We check if the user is the family creator via the Family table
CREATE POLICY "tod_prompts_update" ON "truthordare_prompts"
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM "Family" f
            JOIN "FamilyMember" fm ON fm."familyId" = f.id
            WHERE f.id = "truthordare_prompts"."familyId"
            AND fm."userId" = auth.uid()::text
            AND fm.role = 'creator'
        )
    );

CREATE POLICY "tod_games_select" ON "truthordare_games"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "truthordare_games"."familyId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tod_games_insert" ON "truthordare_games"
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "truthordare_games"."familyId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tod_games_update" ON "truthordare_games"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "truthordare_games"."familyId" AND fm."userId" = auth.uid()::text));

CREATE POLICY "tod_players_select" ON "truthordare_players"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "truthordare_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "truthordare_players"."gameId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tod_players_insert" ON "truthordare_players"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "tod_players_update" ON "truthordare_players"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "truthordare_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "truthordare_players"."gameId" AND fm."userId" = auth.uid()::text));

CREATE POLICY "tod_rounds_select" ON "truthordare_rounds"
    FOR SELECT USING (EXISTS (SELECT 1 FROM "truthordare_games" g JOIN "FamilyMember" fm ON fm."familyId" = g."familyId" WHERE g.id = "truthordare_rounds"."gameId" AND fm."userId" = auth.uid()::text));
CREATE POLICY "tod_rounds_insert" ON "truthordare_rounds"
    FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "truthordare_games" WHERE id = "truthordare_rounds"."gameId") AND fm."userId" = auth.uid()::text));
CREATE POLICY "tod_rounds_update" ON "truthordare_rounds"
    FOR UPDATE USING (EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = (SELECT "familyId" FROM "truthordare_games" WHERE id = "truthordare_rounds"."gameId") AND fm."userId" = auth.uid()::text));

ALTER PUBLICATION supabase_realtime ADD TABLE "truthordare_games";
ALTER PUBLICATION supabase_realtime ADD TABLE "truthordare_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "truthordare_rounds";
ALTER PUBLICATION supabase_realtime ADD TABLE "truthordare_prompts";
