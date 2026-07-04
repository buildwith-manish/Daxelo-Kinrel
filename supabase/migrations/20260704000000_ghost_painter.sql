-- Ghost Painter game — Supabase migration
-- Creates tables for the drawing-and-guess family game.

-- ─────────────────────────────────────────────────────────────────
-- ghost_painter_rounds — one drawing round per family
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "ghost_painter_rounds" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"          TEXT NOT NULL,
    "drawerPersonId"    TEXT NOT NULL,
    "drawerPersonName"  TEXT NOT NULL DEFAULT 'Member',
    "promptWord"        TEXT NOT NULL,
    "status"            TEXT NOT NULL DEFAULT 'drawing', -- drawing | guessing | completed
    "startedAt"         TIMESTAMPTZ NOT NULL DEFAULT now(),
    "endsAt"            TIMESTAMPTZ,
    "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gp_rounds_family
    ON "ghost_painter_rounds"("familyId");
CREATE INDEX IF NOT EXISTS idx_gp_rounds_status
    ON "ghost_painter_rounds"("status");

-- ─────────────────────────────────────────────────────────────────
-- ghost_painter_strokes — drawing data (broadcast via Realtime)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "ghost_painter_strokes" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "roundId"       TEXT NOT NULL REFERENCES "ghost_painter_rounds"(id) ON DELETE CASCADE,
    "strokeData"    JSONB NOT NULL,  -- array of {x, y} points
    "sequenceOrder" INTEGER NOT NULL,
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gp_strokes_round
    ON "ghost_painter_strokes"("roundId", "sequenceOrder");

-- ─────────────────────────────────────────────────────────────────
-- ghost_painter_guesses — guess attempts
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "ghost_painter_guesses" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "roundId"       TEXT NOT NULL REFERENCES "ghost_painter_rounds"(id) ON DELETE CASCADE,
    "userId"        TEXT NOT NULL,
    "userName"      TEXT NOT NULL DEFAULT 'Member',
    "guessText"     TEXT NOT NULL,
    "isCorrect"     BOOLEAN NOT NULL DEFAULT false,
    "guessedAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("roundId", "userId")
);

CREATE INDEX IF NOT EXISTS idx_gp_guesses_round
    ON "ghost_painter_guesses"("roundId");

-- ─────────────────────────────────────────────────────────────────
-- RLS Policies — family-scoped (same pattern as truth_streak)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE "ghost_painter_rounds" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ghost_painter_strokes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ghost_painter_guesses" ENABLE ROW LEVEL SECURITY;

-- Rounds: family members can read; any family member can create
CREATE POLICY "gp_rounds_select" ON "ghost_painter_rounds"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "ghost_painter_rounds"."familyId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "gp_rounds_insert" ON "ghost_painter_rounds"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "ghost_painter_rounds"."familyId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "gp_rounds_update" ON "ghost_painter_rounds"
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "ghost_painter_rounds"."familyId" AND fm."userId" = auth.uid()::text)
    );

-- Strokes: family members can read; drawer writes
CREATE POLICY "gp_strokes_select" ON "ghost_painter_strokes"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "ghost_painter_rounds" r JOIN "FamilyMember" fm ON fm."familyId" = r."familyId" WHERE r.id = "ghost_painter_strokes"."roundId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "gp_strokes_insert" ON "ghost_painter_strokes"
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM "ghost_painter_rounds" r JOIN "FamilyMember" fm ON fm."familyId" = r."familyId" WHERE r.id = "ghost_painter_strokes"."roundId" AND fm."userId" = auth.uid()::text)
    );

-- Guesses: family members can read; users insert their own
CREATE POLICY "gp_guesses_select" ON "ghost_painter_guesses"
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM "ghost_painter_rounds" r JOIN "FamilyMember" fm ON fm."familyId" = r."familyId" WHERE r.id = "ghost_painter_guesses"."roundId" AND fm."userId" = auth.uid()::text)
    );
CREATE POLICY "gp_guesses_insert" ON "ghost_painter_guesses"
    FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "gp_guesses_update" ON "ghost_painter_guesses"
    FOR UPDATE USING ("userId" = auth.uid()::text);

-- Add to realtime publication for live stroke/guess sync
ALTER PUBLICATION supabase_realtime ADD TABLE "ghost_painter_strokes";
ALTER PUBLICATION supabase_realtime ADD TABLE "ghost_painter_guesses";
ALTER PUBLICATION supabase_realtime ADD TABLE "ghost_painter_rounds";

-- ─────────────────────────────────────────────────────────────────
-- Storage bucket for game assets
-- ─────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'game-assets',
    'game-assets',
    true,
    10485760,  -- 10 MB per file
    ARRAY['application/json', 'image/png', 'image/jpeg', 'image/webp', 'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/wav']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "game_assets_select" ON storage.objects
    FOR SELECT USING (bucket_id = 'game-assets');
CREATE POLICY "game_assets_insert" ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'game-assets' AND owner = auth.uid());
