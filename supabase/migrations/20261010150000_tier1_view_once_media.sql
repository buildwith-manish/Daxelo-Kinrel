-- =============================================================================
-- Daxelo Kinrel — Tier 1 Feature 1.5: View-Once Media
-- =============================================================================
-- Lets a sender attach a photo or video that disappears after one view.
-- The recipient sees a special bubble; opening marks it viewed and the
-- server deletes the media file within 24h.
--
-- Implementation:
--   • Add `isViewOnce boolean DEFAULT false` + `viewedAt timestamptz`
--     to ChatMessage and DirectMessage.
--   • The viewonce/ storage bucket is configured separately with a 24h
--     lifecycle policy via the Supabase Storage API (server-side).
--   • On markAsRead: if the row is view-once and not yet viewed, set
--     viewedAt=now().
--
-- NOTE: This migration adds the SCHEMA only. The NestJS server extension
-- (markAsRead honoring viewedAt) and the Flutter bubble rendering are
-- follow-up tasks.
--
-- Idempotent.
-- =============================================================================

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "isViewOnce" boolean NOT NULL DEFAULT false;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "viewedAt" timestamptz;

ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "isViewOnce" boolean NOT NULL DEFAULT false;
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "viewedAt" timestamptz;

-- Partial index: "find all un-viewed view-once messages" — used by the
-- nightly GC to delete media from expired rows.
CREATE INDEX IF NOT EXISTS "ChatMessage_viewonce_unviewed_idx"
  ON "ChatMessage"("createdAt")
  WHERE "isViewOnce" = true AND "viewedAt" IS NULL;

CREATE INDEX IF NOT EXISTS "DM_viewonce_unviewed_idx"
  ON "DirectMessage"("createdAt")
  WHERE "isViewOnce" = true AND "viewedAt" IS NULL;

-- Verification
SELECT 'ChatMessage.isViewOnce' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'isViewOnce'
       ) AS exists;
SELECT 'ChatMessage.viewedAt' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'viewedAt'
       ) AS exists;
SELECT 'DirectMessage.isViewOnce' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'isViewOnce'
       ) AS exists;
SELECT 'DirectMessage.viewedAt' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'viewedAt'
       ) AS exists;
