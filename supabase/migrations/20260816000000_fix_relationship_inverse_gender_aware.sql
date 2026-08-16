-- 20260816000000_fix_relationship_inverse_gender_aware.sql
--
-- v5.8: Fix the RelationshipInverse table to use gender-aware inverse pairs.
--
-- PROBLEM:
-- The original RelationshipInverse table (from 20260627000000_viewer_perspective_graph.sql)
-- had incorrect gender mappings:
--   ('father', 'son')  — but father's inverse should be 'son' OR 'daughter'
--   ('mother', 'son')  — but mother's inverse should be 'son' OR 'daughter'
--   ('grandfather', 'grandson') — should also include 'granddaughter'
--   etc.
--
-- The trigger (trg_fill_inverse_label) looks up the inverse by:
--   SELECT "inverseType" INTO NEW."labelBtoA"
--   FROM "RelationshipInverse"
--   WHERE "relationshipType" = NEW."labelAtoB";
--
-- Since the table only has ONE inverse per relationshipType, the trigger
-- always picks the same inverse regardless of the target person's gender.
-- This means a father adding a daughter gets "son" as the inverse label.
--
-- FIX:
-- This migration adds CORRECT gender-aware inverse pairs. Since the
-- RelationshipInverse table can only store one inverse per relationshipType,
-- we use the gender-NEUTRAL form as the inverse (e.g. 'child' instead of
-- 'son'/'daughter'). The Flutter client's getGenderAwareInverseKey() function
-- (v5.3) then converts the neutral form to the gender-specific form at
-- display time.
--
-- This migration is IDEMPOTENT — it uses ON CONFLICT to avoid duplicate
-- key errors if run multiple times.

-- First, ensure the unique constraint exists (it should from the original migration)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'RelationshipInverse_relationshipType_key'
    ) THEN
        ALTER TABLE "RelationshipInverse"
        ADD CONSTRAINT "RelationshipInverse_relationshipType_key"
        UNIQUE ("relationshipType");
    END IF;
END $$;

-- Update existing entries to use gender-NEUTRAL inverses
-- (the client will convert to gender-specific at display time)
INSERT INTO "RelationshipInverse" ("relationshipType", "inverseType") VALUES
  -- Parent → Child (neutral)
  ('father', 'child'),
  ('mother', 'child'),
  ('parent', 'child'),
  -- Child → Parent (neutral)
  ('son', 'parent'),
  ('daughter', 'parent'),
  ('child', 'parent'),
  -- Sibling (symmetric — already correct)
  ('brother', 'sibling'),
  ('sister', 'sibling'),
  ('sibling', 'sibling'),
  -- Spouse (gender-specific — already correct)
  ('husband', 'wife'),
  ('wife', 'husband'),
  ('spouse', 'spouse'),
  -- Grandparent → Grandchild (neutral)
  ('grandfather', 'grandchild'),
  ('grandmother', 'grandchild'),
  ('grandparent', 'grandchild'),
  -- Grandchild → Grandparent (neutral)
  ('grandson', 'grandparent'),
  ('granddaughter', 'grandparent'),
  ('grandchild', 'grandparent'),
  -- Uncle/Aunt → Nephew/Niece (neutral)
  ('uncle', 'nephew_or_niece'),
  ('aunt', 'nephew_or_niece'),
  -- Nephew/Niece → Uncle/Aunt (neutral)
  ('nephew', 'uncle_or_aunt'),
  ('niece', 'uncle_or_aunt'),
  ('nephew_or_niece', 'uncle_or_aunt'),
  -- Cousin (symmetric)
  ('cousin', 'cousin'),
  -- In-laws (neutral)
  ('father_in_law', 'child_in_law'),
  ('mother_in_law', 'child_in_law'),
  ('son_in_law', 'parent_in_law'),
  ('daughter_in_law', 'parent_in_law'),
  ('brother_in_law', 'sibling_in_law'),
  ('sister_in_law', 'sibling_in_law'),
  -- Step-parent/child (neutral)
  ('step_father', 'step_child'),
  ('step_mother', 'step_child'),
  ('step_son', 'step_parent'),
  ('step_daughter', 'step_parent'),
  ('step_brother', 'step_sibling'),
  ('step_sister', 'step_sibling')
ON CONFLICT ("relationshipType") DO UPDATE
  SET "inverseType" = EXCLUDED."inverseType";

-- Verify the update
SELECT 'RelationshipInverse updated:' as status, COUNT(*) as count FROM "RelationshipInverse";

-- Re-run the backfill to update any existing Relationship rows that have
-- NULL or incorrect labelBtoA values
UPDATE "Relationship" r
SET "labelBtoA" = ri."inverseType"
FROM "RelationshipInverse" ri
WHERE ri."relationshipType" = r."labelAtoB"
  AND (r."labelBtoA" IS NULL OR r."labelBtoA" != ri."inverseType");

-- Also backfill labelAtoB from relationshipKey for any rows that still have it NULL
UPDATE "Relationship"
SET "labelAtoB" = "relationshipKey"
WHERE "labelAtoB" IS NULL
  AND "relationshipKey" IS NOT NULL;

SELECT 'Relationship labels backfilled:' as status, COUNT(*) as count FROM "Relationship" WHERE "labelAtoB" IS NOT NULL AND "labelBtoA" IS NOT NULL;
