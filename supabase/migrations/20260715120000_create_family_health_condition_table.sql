-- P12.6 — Family Health Heritage table
-- Per kinrel_final_audited_prompt_v2.md §5.1: HealthHeritageScreen was
-- Category G (backend blocked) because it used hardcoded demo data.
-- This migration creates the backend table needed to wire it.

-- Family health conditions table
-- Stores hereditary health conditions tracked across family generations.
-- RLS: only family members can read/write their own family's health data.
CREATE TABLE IF NOT EXISTS "FamilyHealthCondition" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL REFERENCES "Family"("id") ON DELETE CASCADE,
  "personId" TEXT NOT NULL REFERENCES "Person"("id") ON DELETE CASCADE,
  
  -- The person who reported this condition (may differ from personId
  -- if a family member is reporting on behalf of someone else)
  "reportedByPersonId" TEXT REFERENCES "Person"("id") ON DELETE SET NULL,
  
  -- Health condition details
  "condition" TEXT NOT NULL,
  "category" TEXT NOT NULL DEFAULT 'other',
  "severity" TEXT NOT NULL DEFAULT 'moderate',
  "diagnosedYear" INTEGER,
  "notes" TEXT,
  
  -- Privacy: only family members with appropriate access can see this
  "privacyLevel" TEXT NOT NULL DEFAULT 'family',
  
  -- Metadata
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for family-scoped queries
CREATE INDEX IF NOT EXISTS "idx_FamilyHealthCondition_familyId" 
  ON "FamilyHealthCondition"("familyId");

CREATE INDEX IF NOT EXISTS "idx_FamilyHealthCondition_personId" 
  ON "FamilyHealthCondition"("personId");

-- Enable RLS
ALTER TABLE "FamilyHealthCondition" ENABLE ROW LEVEL SECURITY;

-- Policy: family members can read their own family's health conditions
CREATE POLICY "family_members_can_read_health_conditions"
  ON "FamilyHealthCondition" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid() AND "isActive" = true
    )
  );

-- Policy: family members can insert health conditions for their family
CREATE POLICY "family_members_can_insert_health_conditions"
  ON "FamilyHealthCondition" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid() AND "isActive" = true
    )
  );

-- Policy: family members can update their own family's health conditions
CREATE POLICY "family_members_can_update_health_conditions"
  ON "FamilyHealthCondition" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid() AND "isActive" = true
    )
  );

-- Policy: family members can delete their own family's health conditions
CREATE POLICY "family_members_can_delete_health_conditions"
  ON "FamilyHealthCondition" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid() AND "isActive" = true
    )
  );

-- Updated_at trigger
CREATE TRIGGER "update_FamilyHealthCondition_updatedAt"
  BEFORE UPDATE ON "FamilyHealthCondition"
  FOR EACH ROW EXECUTE FUNCTION "update_updatedAt_column"();
