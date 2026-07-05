-- ============================================================
-- Migration: add_custom_kinship_support
-- Version:  20260701100000
--
-- ADDS:
--   1. customColors JSONB column on Relationship table
--   2. CustomKinshipConfig table for storing custom kinship configs
-- ============================================================

-- ── 1. Add customColors column to Relationship table ─────────
-- Stores a JSON object with custom node/line colors when a user
-- creates a custom kinship term via "Add Your Own Kinship".
-- Example: {"nodeColor": 4280341414, "lineColor": 4280341414,
--           "lineType": "dashed", "dotType": "heart"}
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "customColors" JSONB DEFAULT NULL;

-- ── 2. Create CustomKinshipConfig table ──────────────────────
-- Stores per-family custom kinship configurations so they persist
-- across sessions and are shared with all family members.
CREATE TABLE IF NOT EXISTS "CustomKinshipConfig" (
  "id" TEXT PRIMARY KEY,
  "familyId" TEXT NOT NULL REFERENCES "Family"("id") ON DELETE CASCADE,
  "relationshipKey" TEXT NOT NULL,
  "displayName" TEXT NOT NULL,
  "nodeColor" INTEGER NOT NULL DEFAULT 4289376139,
  "lineColor" INTEGER NOT NULL DEFAULT 4289376139,
  "lineType" TEXT NOT NULL DEFAULT 'solid',
  "dotType" TEXT NOT NULL DEFAULT 'dot',
  "createdBy" TEXT,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS
ALTER TABLE "CustomKinshipConfig" ENABLE ROW LEVEL SECURITY;

-- RLS: Family members can SELECT
CREATE POLICY "custom_kinship_select" ON "CustomKinshipConfig"
  FOR SELECT USING (
    "familyId" IN (SELECT id FROM "Family" WHERE "createdBy" = auth.uid()::text AND "deletedAt" IS NULL)
    OR "familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text)
  );

-- RLS: Family creators can INSERT
CREATE POLICY "custom_kinship_insert" ON "CustomKinshipConfig"
  FOR INSERT TO authenticated WITH CHECK (
    "familyId" IN (SELECT id FROM "Family" WHERE "createdBy" = auth.uid()::text AND "deletedAt" IS NULL)
  );

-- RLS: Family creators can UPDATE
CREATE POLICY "custom_kinship_update" ON "CustomKinshipConfig"
  FOR UPDATE TO authenticated USING (
    "familyId" IN (SELECT id FROM "Family" WHERE "createdBy" = auth.uid()::text AND "deletedAt" IS NULL)
  );

-- RLS: Family creators can DELETE
CREATE POLICY "custom_kinship_delete" ON "CustomKinshipConfig"
  FOR DELETE TO authenticated USING (
    "familyId" IN (SELECT id FROM "Family" WHERE "createdBy" = auth.uid()::text AND "deletedAt" IS NULL)
  );

-- Index for fast family lookups
CREATE INDEX IF NOT EXISTS "CustomKinshipConfig_familyId_idx" ON "CustomKinshipConfig"("familyId");
