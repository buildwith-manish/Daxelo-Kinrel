-- ============================================================
-- Migration: fix_relationship_isactive_trigger
-- Version:  20260712000000
-- Feature:  P0.3 — Fix isActive null-handling bug at the DB trigger level
--
-- PURPOSE:
--   Adds a BEFORE INSERT trigger as a safety net that guarantees
--   "isActive" is never NULL on the Relationship table, even if an
--   ORM or raw SQL INSERT bypasses the column default.
--
-- PRIOR STATE (verified in production 2026-07-12):
--   - Column "isActive" is already NOT NULL  (is_not_null = true)
--   - Column default is already true          (default_value = 'true')
--   - 0 NULL rows exist                       (backfill done by 20260701080000)
--   - RPCs already use COALESCE(isActive, true) (done by 20260701070000)
--   - NO trigger existed on isActive           ← THIS MIGRATION ADDS IT
--
-- This migration is IDEMPOTENT — safe to re-run. All statements use
-- CREATE OR REPLACE / DROP IF EXISTS.
-- ============================================================

-- ── Step 1: Idempotent backfill (0 rows affected in current prod) ──
UPDATE "Relationship" SET "isActive" = true WHERE "isActive" IS NULL;

-- ── Step 2: Idempotent column default (already set, no-op) ─────────
ALTER TABLE "Relationship" ALTER COLUMN "isActive" SET DEFAULT true;

-- ── Step 3: Idempotent NOT NULL constraint (already set, no-op) ────
ALTER TABLE "Relationship" ALTER COLUMN "isActive" SET NOT NULL;

-- ── Step 4: Trigger function (safety net for ORM bypasses) ─────────
-- If an INSERT explicitly sets isActive = NULL (e.g. via Prisma's
-- isActive: null or a raw SQL insert), this trigger coerces it to
-- true BEFORE the row is written, preventing a constraint violation
-- and ensuring the relationship is immediately visible to queries
-- that filter WHERE "isActive" = true.
CREATE OR REPLACE FUNCTION ensure_relationship_isactive_default()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW."isActive" IS NULL THEN
    NEW."isActive" = true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── Step 5: Trigger (drop-if-exists + create) ──────────────────────
DROP TRIGGER IF EXISTS trg_ensure_relationship_isactive_default ON "Relationship";
CREATE TRIGGER trg_ensure_relationship_isactive_default
  BEFORE INSERT ON "Relationship"
  FOR EACH ROW EXECUTE FUNCTION ensure_relationship_isactive_default();

-- ── Step 6: Verify (run manually in SQL editor to confirm) ─────────
-- SELECT count(*) FROM "Relationship" WHERE "isActive" IS NULL;  -- must be 0
-- SELECT tgname FROM pg_trigger WHERE tgrelid = '"Relationship"'::regclass
--   AND tgname = 'trg_ensure_relationship_isactive_default';    -- must return 1 row
