-- =============================================================================
-- Daxelo-Kinrel — AURA: Ancestral Unified Relationship Archetype
-- Migration: create_aura_tables
-- =============================================================================
-- Creates three tables that store the computed AURA parameters for each family:
--   1. "FamilyAura"          — current AURA symbol parameters (one row per family)
--   2. "FamilyAuraHistory"   — snapshots over time (for AURA Timeline widget)
--   3. "MemberAuraRole"      — each member's role glyph within the family AURA
--
-- Schema notes (verified against live project promxswvsnvilplmrtsj):
--   - "Family"."id"   is TEXT (cuid), NOT NULL, no default — FKs must be TEXT
--   - "Person"."id"   is TEXT (cuid), NOT NULL, no default — FKs must be TEXT
--   - "FamilyMember"  has ("familyId", "userId") — "userId" references "User"."id" (TEXT)
--   - All timestamps in newer columns are TIMESTAMPTZ; we follow that convention here.
--   - All FKs in existing tables use ON DELETE CASCADE ON UPDATE CASCADE; we match.
--   - Existing RLS pattern: family-scoped SELECT for members; service_role-only writes.
--
-- IMPORTANT: Every mixed-case identifier MUST be double-quoted in PostgreSQL.
-- Unquoted identifiers are case-folded to lowercase, breaking camelCase columns.
-- This migration quotes all table AND column names with double quotes.
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "FamilyAura"
-- Stores the current computed AURA parameters for a family.
-- One row per family. Updated every time the family graph changes.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."FamilyAura" (
  "id"                     TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"               TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,

  -- ── Graph metrics (raw, for re-classification without recomputing) ──
  "memberCount"            INTEGER   NOT NULL DEFAULT 0,
  "generationDepth"        INTEGER   NOT NULL DEFAULT 1,
  "edgeCount"              INTEGER   NOT NULL DEFAULT 0,
  "clusteringCoefficient"  NUMERIC(6,4) NOT NULL DEFAULT 0,
  "graphDiameter"          INTEGER   NOT NULL DEFAULT 0,
  "avgDegree"              NUMERIC(6,3) NOT NULL DEFAULT 0,
  "maxBetweennessNode"     TEXT REFERENCES public."Person"("id") ON DELETE SET NULL,
  "rootNode"               TEXT REFERENCES public."Person"("id") ON DELETE SET NULL,
  "distinctLineages"       INTEGER   NOT NULL DEFAULT 1,

  -- ── Language distribution (JSONB map: language_code → ratio, must sum to 1.0) ──
  "languageDistribution"   JSONB     NOT NULL DEFAULT '{}'::JSONB,
  CONSTRAINT "valid_language_distribution" CHECK (
    jsonb_typeof("languageDistribution") = 'object'
  ),

  -- ── AURA Symbol Parameters (output of the parameter generator) ──
  "ringCount"              INTEGER   NOT NULL DEFAULT 2,
  "spokeCount"             INTEGER   NOT NULL DEFAULT 4,
  "innerPatternType"       TEXT      NOT NULL DEFAULT 'lotus',
  "outerRingRadiusPct"     NUMERIC(4,2) NOT NULL DEFAULT 0.85,
  "patternComplexity"      INTEGER   NOT NULL DEFAULT 3,
  "primaryColorHex"        CHAR(7)   NOT NULL DEFAULT '#C8853A',
  "secondaryColorHex"      CHAR(7)   NOT NULL DEFAULT '#6B3FA0',
  "accentColorHex"         CHAR(7)   NOT NULL DEFAULT '#2D8A4E',
  "pulseSpeedMs"           INTEGER   NOT NULL DEFAULT 3000,

  -- ── Archetype classification ──
  "archetypeKey"           TEXT      NOT NULL DEFAULT 'lotus',
  "archetypeConfidence"    NUMERIC(4,3) NOT NULL DEFAULT 0.500,

  -- ── Metadata ──
  "computedAt"             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "createdAt"              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT "FamilyAura_familyId_unique" UNIQUE ("familyId")
);

CREATE INDEX IF NOT EXISTS "FamilyAura_familyId_idx" ON public."FamilyAura"("familyId");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "FamilyAuraHistory"
-- Stores a snapshot every time the AURA changes significantly.
-- Used by the AURA Timeline widget.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."FamilyAuraHistory" (
  "id"                   TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"             TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,

  "memberCount"          INTEGER NOT NULL,
  "generationDepth"      INTEGER NOT NULL,
  "archetypeKey"         TEXT    NOT NULL,
  "ringCount"            INTEGER NOT NULL,
  "spokeCount"           INTEGER NOT NULL,
  "innerPatternType"     TEXT    NOT NULL,
  "primaryColorHex"      CHAR(7) NOT NULL,
  "secondaryColorHex"    CHAR(7) NOT NULL,
  "accentColorHex"       CHAR(7) NOT NULL,

  "triggerMemberId"      TEXT REFERENCES public."Person"("id") ON DELETE SET NULL,
  "triggerEventType"     TEXT    NOT NULL DEFAULT 'member_added',

  "archetypeChanged"     BOOLEAN NOT NULL DEFAULT FALSE,
  "previousArchetype"    TEXT,

  "capturedAt"           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "FamilyAuraHistory_family_time_idx"
  ON public."FamilyAuraHistory"("familyId", "capturedAt" DESC);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "MemberAuraRole"
-- Stores each member's computed role within the family AURA.
-- One row per member. Updated when graph changes affect role.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."MemberAuraRole" (
  "id"                   TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"             TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "memberId"             TEXT NOT NULL REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,

  "roleKey"              TEXT NOT NULL DEFAULT 'leaf',

  "betweennessScore"     NUMERIC(8,6) NOT NULL DEFAULT 0,
  "degreeCount"          INTEGER NOT NULL DEFAULT 0,
  "generationIndex"      INTEGER NOT NULL DEFAULT 0,

  "glyphShape"           TEXT NOT NULL DEFAULT 'petal',
  "glyphColorHex"        CHAR(7) NOT NULL DEFAULT '#C8853A',

  "computedAt"           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "createdAt"            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT "MemberAuraRole_family_member_unique" UNIQUE ("familyId", "memberId")
);

CREATE INDEX IF NOT EXISTS "MemberAuraRole_family_idx" ON public."MemberAuraRole"("familyId");
CREATE INDEX IF NOT EXISTS "MemberAuraRole_member_idx" ON public."MemberAuraRole"("memberId");

-- ────────────────────────────────────────────────────────────────────────────
-- FUNCTION + TRIGGER: auto-update "updatedAt" on FamilyAura + MemberAuraRole
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_update_aura_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW."updatedAt" = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_family_aura_updated_at ON public."FamilyAura";
CREATE TRIGGER trg_family_aura_updated_at
  BEFORE UPDATE ON public."FamilyAura"
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_aura_timestamp();

DROP TRIGGER IF EXISTS trg_member_aura_role_updated_at ON public."MemberAuraRole";
CREATE TRIGGER trg_member_aura_role_updated_at
  BEFORE UPDATE ON public."MemberAuraRole"
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_aura_timestamp();

-- ────────────────────────────────────────────────────────────────────────────
-- RLS POLICIES
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."FamilyAura"        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."FamilyAuraHistory" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MemberAuraRole"    ENABLE ROW LEVEL SECURITY;

-- ── FamilyAura: SELECT for family members ──────────────────────────────────
DROP POLICY IF EXISTS "FamilyAura_select" ON public."FamilyAura";
CREATE POLICY "FamilyAura_select" ON public."FamilyAura"
  FOR SELECT USING (
    "familyId" IN (
      SELECT "familyId" FROM public."FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "FamilyAura_service_insert" ON public."FamilyAura";
CREATE POLICY "FamilyAura_service_insert" ON public."FamilyAura"
  FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "FamilyAura_service_update" ON public."FamilyAura";
CREATE POLICY "FamilyAura_service_update" ON public."FamilyAura"
  FOR UPDATE
  USING     (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "FamilyAura_service_delete" ON public."FamilyAura";
CREATE POLICY "FamilyAura_service_delete" ON public."FamilyAura"
  FOR DELETE
  USING (auth.role() = 'service_role');

-- ── FamilyAuraHistory: same pattern ────────────────────────────────────────
DROP POLICY IF EXISTS "FamilyAuraHistory_select" ON public."FamilyAuraHistory";
CREATE POLICY "FamilyAuraHistory_select" ON public."FamilyAuraHistory"
  FOR SELECT USING (
    "familyId" IN (
      SELECT "familyId" FROM public."FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "FamilyAuraHistory_service_insert" ON public."FamilyAuraHistory";
CREATE POLICY "FamilyAuraHistory_service_insert" ON public."FamilyAuraHistory"
  FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "FamilyAuraHistory_service_update" ON public."FamilyAuraHistory";
CREATE POLICY "FamilyAuraHistory_service_update" ON public."FamilyAuraHistory"
  FOR UPDATE
  USING     (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "FamilyAuraHistory_service_delete" ON public."FamilyAuraHistory";
CREATE POLICY "FamilyAuraHistory_service_delete" ON public."FamilyAuraHistory"
  FOR DELETE
  USING (auth.role() = 'service_role');

-- ── MemberAuraRole: same pattern ───────────────────────────────────────────
DROP POLICY IF EXISTS "MemberAuraRole_select" ON public."MemberAuraRole";
CREATE POLICY "MemberAuraRole_select" ON public."MemberAuraRole"
  FOR SELECT USING (
    "familyId" IN (
      SELECT "familyId" FROM public."FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "MemberAuraRole_service_insert" ON public."MemberAuraRole";
CREATE POLICY "MemberAuraRole_service_insert" ON public."MemberAuraRole"
  FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "MemberAuraRole_service_update" ON public."MemberAuraRole";
CREATE POLICY "MemberAuraRole_service_update" ON public."MemberAuraRole"
  FOR UPDATE
  USING     (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "MemberAuraRole_service_delete" ON public."MemberAuraRole";
CREATE POLICY "MemberAuraRole_service_delete" ON public."MemberAuraRole"
  FOR DELETE
  USING (auth.role() = 'service_role');

-- ────────────────────────────────────────────────────────────────────────────
-- REALTIME: Enable Supabase Realtime broadcast on FamilyAura + MemberAuraRole.
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."FamilyAura"     REPLICA IDENTITY FULL;
ALTER TABLE public."MemberAuraRole" REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'FamilyAura'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public."FamilyAura";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not add FamilyAura to supabase_realtime: %', SQLERRM;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'MemberAuraRole'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public."MemberAuraRole";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not add MemberAuraRole to supabase_realtime: %', SQLERRM;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- GRANTS
-- ────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public."FamilyAura"        TO anon, authenticated;
GRANT SELECT ON public."FamilyAuraHistory" TO anon, authenticated;
GRANT SELECT ON public."MemberAuraRole"    TO anon, authenticated;

-- Revoke write privileges from anon/authenticated (Supabase auto-grants ALL on CREATE TABLE).
-- RLS policies enforce the same restriction, but defense-in-depth: only service_role can write.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public."FamilyAura"        FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public."FamilyAuraHistory" FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public."MemberAuraRole"    FROM anon, authenticated;

GRANT ALL ON public."FamilyAura"        TO service_role;
GRANT ALL ON public."FamilyAuraHistory" TO service_role;
GRANT ALL ON public."MemberAuraRole"    TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- COMMENTS
-- ────────────────────────────────────────────────────────────────────────────
COMMENT ON TABLE public."FamilyAura" IS
  'AURA: Ancestral Unified Relationship Archetype. Current computed symbol parameters for a family. One row per family. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."FamilyAuraHistory" IS
  'AURA: snapshot history of family_aura parameters over time. Used by AURA Timeline widget. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."MemberAuraRole" IS
  'AURA: each member role glyph classification within the family AURA (root/anchor/bridge/weaver/leaf/twin_node). One row per member. RLS: family members SELECT, service_role ALL.';
