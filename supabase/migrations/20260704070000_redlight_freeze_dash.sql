-- Freeze & Dash (Red Light, Green Light) — Supabase migration
--
-- Server-authoritative game: NestJS /redlight gateway is the clock and
-- referee. Supabase stores lobby membership, final results, cosmetic state,
-- and leaderboard — non-time-critical data only.
--
-- Pattern mirrors ghost_painter (20260704000000_ghost_painter.sql):
--   • camelCase quoted column names
--   • FamilyMember join for RLS
--   • ALTER PUBLICATION supabase_realtime ADD TABLE for live lobby sync

-- ─────────────────────────────────────────────────────────────────
-- redlight_rounds — one row per game session
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "redlight_rounds" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"          TEXT NOT NULL,
    "hostUserId"        TEXT NOT NULL,
    "hostUserName"      TEXT NOT NULL DEFAULT 'Host',
    "callerCharacter"   TEXT NOT NULL DEFAULT 'grandma',  -- grandma | robot | parrot | alien
    "mapTheme"          TEXT NOT NULL DEFAULT 'forest',   -- forest | beach | playground | village
    "weatherModifier"   TEXT,                              -- rain | fog | wind | NULL
    "teamMode"          BOOLEAN NOT NULL DEFAULT false,
    "eliminationMode"   BOOLEAN NOT NULL DEFAULT false,   -- false = knockback (default); true = hard elimination
    "status"            TEXT NOT NULL DEFAULT 'lobby',    -- lobby | countdown | active | finished
    "winnerUserId"      TEXT,
    "winnerUserName"    TEXT,
    "startedAt"         TIMESTAMPTZ,
    "finishedAt"        TIMESTAMPTZ,
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rl_rounds_family
    ON "redlight_rounds"("familyId");
CREATE INDEX IF NOT EXISTS idx_rl_rounds_status
    ON "redlight_rounds"("status");

-- ─────────────────────────────────────────────────────────────────
-- redlight_players — one row per player per round
-- Written by both server (service role) and client.
-- Realtime broadcasts lobby membership changes.
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "redlight_players" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "roundId"       TEXT NOT NULL REFERENCES "redlight_rounds"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    "teamId"        TEXT,                                  -- NULL if not team mode
    progress        NUMERIC(5,2) NOT NULL DEFAULT 0,      -- 0.00 – 100.00
    alive           BOOLEAN NOT NULL DEFAULT true,
    powerups        JSONB NOT NULL DEFAULT '[]'::jsonb,    -- [{type, expiresAt}]
    "joinedAt"      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("roundId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_rl_players_round
    ON "redlight_players"("roundId");
CREATE INDEX IF NOT EXISTS idx_rl_players_user
    ON "redlight_players"("userId");

-- ─────────────────────────────────────────────────────────────────
-- redlight_results — final standings written by the server
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "redlight_results" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "roundId"       TEXT NOT NULL REFERENCES "redlight_rounds"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Player',
    "finalProgress" NUMERIC(5,2) NOT NULL DEFAULT 0,
    placement       INTEGER NOT NULL,                     -- 1 = winner
    "finishedAt"    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rl_results_round
    ON "redlight_results"("roundId");

-- ─────────────────────────────────────────────────────────────────
-- RLS — copy the Ghost Painter pattern exactly
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "redlight_rounds"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE "redlight_players" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "redlight_results" ENABLE ROW LEVEL SECURITY;

-- redlight_rounds: family members read/create/update
CREATE POLICY "rl_rounds_select" ON "redlight_rounds"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "redlight_rounds"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "rl_rounds_insert" ON "redlight_rounds"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "redlight_rounds"."familyId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "rl_rounds_update" ON "redlight_rounds"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm
                WHERE fm."familyId" = "redlight_rounds"."familyId"
                AND fm."userId" = auth.uid()::text)
    );

-- redlight_players: family-scoped read; users insert/update their own row
CREATE POLICY "rl_players_select" ON "redlight_players"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "redlight_rounds" r
                JOIN "FamilyMember" fm ON fm."familyId" = r."familyId"
                WHERE r.id = "redlight_players"."roundId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "rl_players_insert" ON "redlight_players"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "rl_players_update" ON "redlight_players"
    FOR UPDATE USING ("userId" = auth.uid()::text);

-- redlight_results: family-scoped read; server inserts via service role key
CREATE POLICY "rl_results_select" ON "redlight_results"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "redlight_rounds" r
                JOIN "FamilyMember" fm ON fm."familyId" = r."familyId"
                WHERE r.id = "redlight_results"."roundId"
                AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "rl_results_insert" ON "redlight_results"
    FOR INSERT WITH CHECK (TRUE);

-- ─────────────────────────────────────────────────────────────────
-- Realtime Publication — lobby membership + status changes only.
-- Phase transitions / leaderboard / caught events flow through the
-- NestJS /redlight socket — never Supabase Realtime.
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE "redlight_players";
ALTER PUBLICATION supabase_realtime ADD TABLE "redlight_rounds";

-- ─────────────────────────────────────────────────────────────────
-- Storage — the 'game-assets' bucket was created in
-- 20260704000000_ghost_painter.sql. No SQL needed here.
-- Expected asset paths (uploaded by the deploy script):
--   game-assets/freeze-dash/manifest.json
--   game-assets/freeze-dash/callers/{grandma,robot,parrot,alien}.png
--   game-assets/freeze-dash/maps/{forest,beach,playground,village}.png
-- ─────────────────────────────────────────────────────────────────
