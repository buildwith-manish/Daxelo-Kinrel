-- =============================================================================
-- Daxelo Kinrel — Tier 1 Feature 1.4: Send Without Sound (silent notifications)
-- =============================================================================
-- Lets a sender mark a message as "silent": the recipient still receives it
-- instantly, but the FCM push notification is delivered at low priority
-- with no sound + no vibration (so the recipient's phone doesn't buzz).
--
-- Implementation:
--   • Add `silent boolean DEFAULT false` to ChatMessage and DirectMessage.
--   • The NestJS chat-push.scheduler.ts already builds the FCM payload;
--     when silent=true, it sets android.notification.priority='low' and
--     clears the sound field; on iOS it sets interruptionLevel='passive'.
--   • RLS / policies are unchanged (the column is just a per-message flag).
--
-- Idempotent.
-- =============================================================================

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "silent" boolean NOT NULL DEFAULT false;
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "silent" boolean NOT NULL DEFAULT false;

-- Partial index to find silent messages fast (mainly for the analytics
-- "how many silent messages did this user send?" dashboard query).
CREATE INDEX IF NOT EXISTS "ChatMessage_silent_idx"
  ON "ChatMessage"("senderId")
  WHERE "silent" = true;

CREATE INDEX IF NOT EXISTS "DM_silent_idx"
  ON "DirectMessage"("senderId")
  WHERE "silent" = true;

-- Verification
SELECT 'ChatMessage.silent' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'silent'
       ) AS exists;
SELECT 'DirectMessage.silent' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'silent'
       ) AS exists;
