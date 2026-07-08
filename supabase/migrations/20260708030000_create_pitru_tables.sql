-- =============================================================================
-- Daxelo-Kinrel — PITRU: Ancestral Voice Memory
-- Migration: create_pitru_tables
-- =============================================================================
-- Pitru is the "forever lock-in" — family elders record voice/video memories,
-- AI transcribes + translates + tags them, and when an elder passes away their
-- node becomes a living memorial. Future generations can hear their voice.
--
-- Four tables:
--   1. "AncestralMemory"  — the core memory record (audio/video + AI metadata)
--   2. "MemoryTag"         — many-to-many between memories and Persons
--   3. "MemoryConsent"     — consent records for AI persona / voice cloning use
--   4. "MemorialProfile"   — when a Person is deceased, their memorial page config
--
-- Schema conventions (matches AURA + Pulse migrations):
--   - All table names PascalCase, double-quoted
--   - All column names camelCase, double-quoted
--   - FKs are TEXT (cuid), ON DELETE CASCADE ON UPDATE CASCADE
--   - Nullable FKs to Person use ON DELETE SET NULL (memories survive person deletion)
--   - RLS: family-scoped SELECT, service_role-only writes
--   - Realtime: AncestralMemory in supabase_realtime publication
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "AncestralMemory"
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."AncestralMemory" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "recorderId"      TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "elderPersonId"   TEXT REFERENCES public."Person"("id") ON DELETE SET NULL ON UPDATE CASCADE,

  -- ── Media storage ──
  "mediaType"       TEXT NOT NULL DEFAULT 'audio', -- audio | video
  "mediaUrl"        TEXT NOT NULL,                  -- Supabase Storage URL
  "thumbnailUrl"    TEXT,                           -- for video memories
  "durationSec"     INTEGER NOT NULL DEFAULT 0,     -- media duration in seconds

  -- ── Title + topic (user-provided at recording time) ──
  "title"           TEXT NOT NULL,                  -- e.g. "My wedding day"
  "topic"           TEXT,                            -- e.g. "wedding", "partition", "recipe", "blessing"
  "language"        TEXT NOT NULL DEFAULT 'en',     -- ISO-639-1 of the spoken language
  "description"     TEXT,                            -- optional longer description

  -- ── AI processing results (set asynchronously by the transcription pipeline) ──
  "transcript"      TEXT,                            -- Whisper transcription
  "transcriptLanguage" TEXT,                         -- language of the transcript (usually same as `language`)
  "translation"     TEXT,                            -- English translation (for cross-language search)
  "aiSummary"       TEXT,                            -- 1-2 sentence GPT summary
  "aiTags"          JSONB NOT NULL DEFAULT '[]'::JSONB, -- AI-extracted tags: ["wedding","1962","monsoon"]
  "aiProcessedAt"   TIMESTAMPTZ,                     -- when AI pipeline finished
  "aiProcessingError" TEXT,                          -- if processing failed, the error message

  -- ── Lifecycle ──
  "status"          TEXT NOT NULL DEFAULT 'pending', -- pending | processing | ready | failed | archived
  "isPublic"        BOOLEAN NOT NULL DEFAULT false,  -- visible to non-family members?
  "revealAt"        TIMESTAMPTZ,                     -- time-capsule: reveal on this date (null = immediate)
  "isRevealed"      BOOLEAN NOT NULL DEFAULT true,   -- false if revealAt is in the future

  -- ── Engagement (denormalized for fast queries) ──
  "viewCount"       INTEGER NOT NULL DEFAULT 0,
  "listenCount"     INTEGER NOT NULL DEFAULT 0,
  "lastListenedAt"  TIMESTAMPTZ,

  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "AncestralMemory_family_created_idx"    ON public."AncestralMemory"("familyId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "AncestralMemory_elder_idx"             ON public."AncestralMemory"("elderPersonId");
CREATE INDEX IF NOT EXISTS "AncestralMemory_status_idx"            ON public."AncestralMemory"("status");
CREATE INDEX IF NOT EXISTS "AncestralMemory_topic_idx"             ON public."AncestralMemory"("topic");
CREATE INDEX IF NOT EXISTS "AncestralMemory_reveal_idx"            ON public."AncestralMemory"("revealAt") WHERE "revealAt" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "AncestralMemory_isRevealed_idx"        ON public."AncestralMemory"("isRevealed");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "MemoryTag"
-- Many-to-many: a memory can be tagged with multiple Persons (who is in this story?)
-- and a Person can be tagged in multiple memories.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."MemoryTag" (
  "id"          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "memoryId"    TEXT NOT NULL REFERENCES public."AncestralMemory"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "personId"    TEXT NOT NULL REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "taggedById"  TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "tagType"     TEXT NOT NULL DEFAULT 'mentions', -- mentions | about | recorded_by | featured
  "taggedAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "MemoryTag_memory_idx"     ON public."MemoryTag"("memoryId");
CREATE INDEX IF NOT EXISTS "MemoryTag_person_idx"     ON public."MemoryTag"("personId");
CREATE UNIQUE INDEX IF NOT EXISTS "MemoryTag_memory_person_type_unique" ON public."MemoryTag"("memoryId", "personId", "tagType");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "MemoryConsent"
-- Consent records for AI persona / voice cloning use.
-- One row per (elderPersonId, consentType). Updated when consent changes.
-- CRITICAL: Without explicit consent, AI persona features are disabled for that person.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."MemoryConsent" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "elderPersonId"   TEXT NOT NULL REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "consentType"     TEXT NOT NULL, -- ai_persona | voice_cloning | public_memorial | cross_family_share
  "consentGiven"    BOOLEAN NOT NULL DEFAULT false,
  "consentedById"   TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "consentedAt"     TIMESTAMPTZ,
  "consentExpiresAt" TIMESTAMPTZ, -- null = no expiry
  "consentNotes"    TEXT,          -- e.g. "Elder gave verbal consent, recorded on 2024-01-15"
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "MemoryConsent_elder_idx"      ON public."MemoryConsent"("elderPersonId");
CREATE INDEX IF NOT EXISTS "MemoryConsent_family_idx"     ON public."MemoryConsent"("familyId");
CREATE UNIQUE INDEX IF NOT EXISTS "MemoryConsent_elder_type_unique" ON public."MemoryConsent"("elderPersonId", "consentType");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "MemorialProfile"
-- When a Person is marked deceased (Person.isDeceased = true), a MemorialProfile
-- row can be created to configure their "living memorial" page.
-- One row per deceased Person.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."MemorialProfile" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "personId"        TEXT NOT NULL REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "memorialTitle"   TEXT,        -- e.g. "In loving memory of Dadi"
  "memorialBio"     TEXT,        -- longer biography for the memorial page
  "birthDate"       DATE,         -- for display (may differ from Person.dateOfBirth if unknown)
  "deathDate"       DATE,
  "coverPhotoUrl"   TEXT,         -- memorial cover image
  "isPublic"        BOOLEAN NOT NULL DEFAULT false, -- visible to non-family?
  "allowMessages"   BOOLEAN NOT NULL DEFAULT true,  -- family can leave messages
  "aiPersonaEnabled" BOOLEAN NOT NULL DEFAULT false, -- requires MemoryConsent ai_persona
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS "MemorialProfile_person_unique" ON public."MemorialProfile"("personId");
CREATE INDEX IF NOT EXISTS "MemorialProfile_family_idx"           ON public."MemorialProfile"("familyId");

-- ────────────────────────────────────────────────────────────────────────────
-- RLS: enable on all 4 Pitru tables + family-scoped SELECT policies.
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."AncestralMemory"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MemoryTag"        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MemoryConsent"    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MemorialProfile"  ENABLE ROW LEVEL SECURITY;

-- AncestralMemory: family members can SELECT (non-archived, revealed)
DROP POLICY IF EXISTS "AncestralMemory_member_select" ON public."AncestralMemory";
CREATE POLICY "AncestralMemory_member_select" ON public."AncestralMemory"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "AncestralMemory"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "AncestralMemory_service_insert" ON public."AncestralMemory";
CREATE POLICY "AncestralMemory_service_insert" ON public."AncestralMemory"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "AncestralMemory_service_update" ON public."AncestralMemory";
CREATE POLICY "AncestralMemory_service_update" ON public."AncestralMemory"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "AncestralMemory_service_delete" ON public."AncestralMemory";
CREATE POLICY "AncestralMemory_service_delete" ON public."AncestralMemory"
  FOR DELETE USING (auth.role() = 'service_role');

-- MemoryTag: family members can SELECT
DROP POLICY IF EXISTS "MemoryTag_member_select" ON public."MemoryTag";
CREATE POLICY "MemoryTag_member_select" ON public."MemoryTag"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      JOIN public."AncestralMemory" am ON am."id" = "MemoryTag"."memoryId"
      WHERE fm."familyId" = am."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "MemoryTag_service_insert" ON public."MemoryTag";
CREATE POLICY "MemoryTag_service_insert" ON public."MemoryTag"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "MemoryTag_service_update" ON public."MemoryTag";
CREATE POLICY "MemoryTag_service_update" ON public."MemoryTag"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "MemoryTag_service_delete" ON public."MemoryTag";
CREATE POLICY "MemoryTag_service_delete" ON public."MemoryTag"
  FOR DELETE USING (auth.role() = 'service_role');

-- MemoryConsent: family members can SELECT (consent is visible to all family)
DROP POLICY IF EXISTS "MemoryConsent_member_select" ON public."MemoryConsent";
CREATE POLICY "MemoryConsent_member_select" ON public."MemoryConsent"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "MemoryConsent"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "MemoryConsent_service_insert" ON public."MemoryConsent";
CREATE POLICY "MemoryConsent_service_insert" ON public."MemoryConsent"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "MemoryConsent_service_update" ON public."MemoryConsent";
CREATE POLICY "MemoryConsent_service_update" ON public."MemoryConsent"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "MemoryConsent_service_delete" ON public."MemoryConsent";
CREATE POLICY "MemoryConsent_service_delete" ON public."MemoryConsent"
  FOR DELETE USING (auth.role() = 'service_role');

-- MemorialProfile: family members can SELECT; public profiles visible to all
DROP POLICY IF EXISTS "MemorialProfile_select" ON public."MemorialProfile";
CREATE POLICY "MemorialProfile_select" ON public."MemorialProfile"
  FOR SELECT
  USING (
    "isPublic" = true
    OR EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "MemorialProfile"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "MemorialProfile_service_insert" ON public."MemorialProfile";
CREATE POLICY "MemorialProfile_service_insert" ON public."MemorialProfile"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "MemorialProfile_service_update" ON public."MemorialProfile";
CREATE POLICY "MemorialProfile_service_update" ON public."MemorialProfile"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "MemorialProfile_service_delete" ON public."MemorialProfile";
CREATE POLICY "MemorialProfile_service_delete" ON public."MemorialProfile"
  FOR DELETE USING (auth.role() = 'service_role');

-- ────────────────────────────────────────────────────────────────────────────
-- REALTIME: AncestralMemory broadcast (so clients see new memories live).
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."AncestralMemory" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'AncestralMemory'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public."AncestralMemory";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not add AncestralMemory to supabase_realtime: %', SQLERRM;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- GRANTS (defense-in-depth: anon/authenticated SELECT only; service_role ALL)
-- ────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public."AncestralMemory"  TO anon, authenticated;
GRANT SELECT ON public."MemoryTag"        TO anon, authenticated;
GRANT SELECT ON public."MemoryConsent"    TO anon, authenticated;
GRANT SELECT ON public."MemorialProfile"  TO anon, authenticated;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."AncestralMemory"  FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."MemoryTag"        FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."MemoryConsent"    FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."MemorialProfile"  FROM anon, authenticated;

GRANT ALL ON public."AncestralMemory"  TO service_role;
GRANT ALL ON public."MemoryTag"        TO service_role;
GRANT ALL ON public."MemoryConsent"    TO service_role;
GRANT ALL ON public."MemorialProfile"  TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- COMMENTS
-- ────────────────────────────────────────────────────────────────────────────
COMMENT ON TABLE public."AncestralMemory" IS
  'PITRU: ancestral voice/video memory. Family elders record stories, AI transcribes + translates + tags. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."MemoryTag" IS
  'PITRU: many-to-many between AncestralMemory and Person. Records who is mentioned/featured in each memory. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."MemoryConsent" IS
  'PITRU: consent records for AI persona / voice cloning / public memorial. CRITICAL: without explicit consent, AI persona features are disabled. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."MemorialProfile" IS
  'PITRU: memorial page config for deceased Persons. One row per deceased Person. RLS: family members SELECT (or public if isPublic=true), service_role ALL.';
