-- Pack 13.3 Feature 3: Message Pinning
--
-- Adds pinnedBy (userId) and pinnedAt columns to ChatMessage so we can
-- track WHO pinned a message + WHEN (for audit + display in the pinned bar).
--
-- The existing isPinned boolean is kept (it's the fast-query field for
-- 'get all pinned messages in this chat'); pinnedBy/pinnedAt are the
-- metadata fields that go with it.
--
-- Idempotent: uses IF NOT EXISTS.

ALTER TABLE "ChatMessage"
  ADD COLUMN IF NOT EXISTS "pinnedBy" text;

ALTER TABLE "ChatMessage"
  ADD COLUMN IF NOT EXISTS "pinnedAt" timestamptz;

CREATE INDEX IF NOT EXISTS "idx_chatmessage_pinnedby"
  ON "ChatMessage" ("pinnedBy")
  WHERE "pinnedBy" IS NOT NULL;

COMMENT ON COLUMN "ChatMessage"."pinnedBy" IS
  'Feature 3: userId who pinned this message (null when unpinned).';
COMMENT ON COLUMN "ChatMessage"."pinnedAt" IS
  'Feature 3: timestamp when the message was pinned (null when unpinned).';
