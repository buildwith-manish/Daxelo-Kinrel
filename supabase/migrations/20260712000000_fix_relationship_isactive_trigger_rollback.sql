-- ============================================================
-- Rollback: fix_relationship_isactive_trigger
-- Version:  20260712000000
-- Feature:  P0.3
--
-- Reverses the trigger added by 20260712000000_fix_relationship_isactive_trigger.sql.
--
-- NOTE: The NOT NULL constraint, DEFAULT true, and COALESCE RPC changes
-- were added by earlier migrations (20260701070000, 20260701080000) and
-- are NOT reversed here — they are data-integrity improvements that
-- should remain even if the trigger is removed. Only the trigger is
-- rolled back.
--
-- Rolling back is safe: the backfill is idempotent, so existing data
-- remains isActive = true even after the trigger is dropped.
-- ============================================================

DROP TRIGGER IF EXISTS trg_ensure_relationship_isactive_default ON "Relationship";
DROP FUNCTION IF EXISTS ensure_relationship_isactive_default();
