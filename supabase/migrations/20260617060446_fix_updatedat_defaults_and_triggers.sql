-- ============================================================
-- Migration: fix_updatedat_defaults_and_triggers
-- Version:  20260617060446
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ================================================================
-- FIX: Add DEFAULT CURRENT_TIMESTAMP to updatedAt on Person,
--      Relationship, and Family tables, plus auto-update triggers.
--
-- ROOT CAUSE: Supabase fallback insert (when Render/NestJS is cold)
-- fails with NOT NULL constraint on updatedAt → _isSubmitting stays
-- true forever → spinner never stops.
-- ================================================================

-- 1. Person.updatedAt default
ALTER TABLE "Person" 
  ALTER COLUMN "updatedAt" SET DEFAULT CURRENT_TIMESTAMP;

-- 2. Relationship.updatedAt default
ALTER TABLE "Relationship" 
  ALTER COLUMN "updatedAt" SET DEFAULT CURRENT_TIMESTAMP;

-- 3. Family.updatedAt default
ALTER TABLE "Family" 
  ALTER COLUMN "updatedAt" SET DEFAULT CURRENT_TIMESTAMP;

-- 4. Auto-update trigger function
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW."updatedAt" = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Attach trigger to Person
DROP TRIGGER IF EXISTS trg_person_updated_at ON "Person";
CREATE TRIGGER trg_person_updated_at
  BEFORE UPDATE ON "Person"
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 6. Attach trigger to Relationship
DROP TRIGGER IF EXISTS trg_relationship_updated_at ON "Relationship";
CREATE TRIGGER trg_relationship_updated_at
  BEFORE UPDATE ON "Relationship"
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 7. Attach trigger to Family
DROP TRIGGER IF EXISTS trg_family_updated_at ON "Family";
CREATE TRIGGER trg_family_updated_at
  BEFORE UPDATE ON "Family"
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
