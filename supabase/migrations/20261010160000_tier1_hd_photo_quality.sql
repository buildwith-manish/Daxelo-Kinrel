-- =============================================================================
-- Daxelo Kinrel — Tier 1 Feature 1.6: HD Photo Quality Toggle
-- =============================================================================
-- Lets a sender pick "Standard" (compressed to 1600px, ~400KB) or "HD"
-- (original resolution, JPEG 90%, ~3MB) when sending a photo. The
-- recipient sees whichever the sender chose.
--
-- Implementation:
--   • Add `qualityTier text DEFAULT 'standard'` to ChatMessage and
--     DirectMessage. Valid values: 'standard' | 'hd'. CHECK constraint
--     enforces.
--   • The NestJS media.service.ts branches on qualityTier when
--     transforming the upload.
--
-- Idempotent.
-- =============================================================================

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "qualityTier" text NOT NULL DEFAULT 'standard';
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "qualityTier" text NOT NULL DEFAULT 'standard';

-- Add CHECK constraints idempotently. The DROP first protects against
-- re-runs failing if the constraint already exists.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ChatMessage_qualityTier_chk'
  ) THEN
    ALTER TABLE "ChatMessage"
      ADD CONSTRAINT "ChatMessage_qualityTier_chk"
      CHECK ("qualityTier" IN ('standard', 'hd'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'DirectMessage_qualityTier_chk'
  ) THEN
    ALTER TABLE "DirectMessage"
      ADD CONSTRAINT "DirectMessage_qualityTier_chk"
      CHECK ("qualityTier" IN ('standard', 'hd'));
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'qualityTier check constraint: %', SQLERRM;
END $$;

-- Verification
SELECT 'ChatMessage.qualityTier' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'qualityTier'
       ) AS exists;
SELECT 'DirectMessage.qualityTier' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'qualityTier'
       ) AS exists;
