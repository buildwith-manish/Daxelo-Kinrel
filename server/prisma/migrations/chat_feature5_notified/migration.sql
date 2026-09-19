-- Feature 5: Smart Batched Push Notifications
--
-- Adds the `notified` boolean column to ChatMessage. The batched-push
-- cron job (chat-push.scheduler.ts) sets notified=true after sending an
-- FCM push for that message, so the next cron run doesn't re-notify.
--
-- The column was reserved in the Prisma schema in Feature 1; this
-- migration creates it in the actual Supabase database.
--
-- Idempotent: uses IF NOT EXISTS. Safe to re-run.

ALTER TABLE "ChatMessage"
  ADD COLUMN IF NOT EXISTS "notified" boolean NOT NULL DEFAULT false;

-- Index to speed up the cron's query: find unread messages older than
-- 2 minutes with notified=false. The partial index (WHERE notified = false)
-- keeps it small — only un-notified rows are indexed.
CREATE INDEX IF NOT EXISTS "idx_chatmessage_notified_unread"
  ON "ChatMessage" ("createdAt")
  WHERE "notified" = false;

COMMENT ON COLUMN "ChatMessage"."notified" IS
  'Feature 5: True once the batched-push cron has sent an FCM notification for this message. Prevents duplicate pushes on subsequent cron runs.';
