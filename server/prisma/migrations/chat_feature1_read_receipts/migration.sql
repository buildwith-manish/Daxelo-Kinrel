-- Feature 1: Typing Indicators + Read Receipts
-- Adds readBy (text[]) and readAt (timestamptz) to ChatMessage.
--
-- The existing ChatMessage table already has isRead (boolean) and the
-- ChatReadReceipt table for per-user receipts. readBy/readAt are a
-- denormalized cache so the NestJS markAsRead service can do fast
-- "who read this message?" lookups without a JOIN, and so the
-- 'readReceipt' Socket.IO event payload can include the full reader list.
--
-- Idempotent: uses IF NOT EXISTS so re-running is safe.

ALTER TABLE "ChatMessage"
  ADD COLUMN IF NOT EXISTS "readBy" text[] NOT NULL DEFAULT '{}';

ALTER TABLE "ChatMessage"
  ADD COLUMN IF NOT EXISTS "readAt" timestamptz;

CREATE INDEX IF NOT EXISTS "idx_chatmessage_readat"
  ON "ChatMessage" ("readAt");

COMMENT ON COLUMN "ChatMessage"."readBy" IS
  'Feature 1: Array of userIds who have read this message (denormalized cache of ChatReadReceipt).';
COMMENT ON COLUMN "ChatMessage"."readAt" IS
  'Feature 1: Timestamp of the most recent read receipt (null until first reader).';
