-- =============================================================================
-- Daxelo Kinrel — DM Reply Threading (swipe-to-reply parity with group chat)
-- =============================================================================
-- The group chat (ChatMessage table) has supported reply threading since
-- 20260808110000_chat_enhancement_schema.sql:
--   "replyToId", "replyToContent", "replyToSenderName"
-- The DirectMessage table (1:1 DMs) has NOT — which is why the shared
-- ChatMessageList widget had to pass enableSwipeReply=false for DMs.
--
-- This migration mirrors the exact same three columns (same names, same
-- semantics, same denormalized preview pattern) onto DirectMessage so the
-- DM thread can persist replies and the shared SwipeToReply + MessageBubble
-- quote block work identically in both chat types.
--
-- Denormalization rationale (same as group): the quote preview needs the
-- original message's content + sender name at render time. Storing a
-- denormalized snapshot (rather than joining) keeps the realtime INSERT
-- payload self-contained and makes old replies immune to edits/deletes of
-- the original — exactly how the group chat behaves.
-- =============================================================================

-- replyToId: id of the DirectMessage this is replying to (null = not a reply)
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "replyToId" text;

-- replyToContent: denormalized snapshot of the original message's content
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "replyToContent" text;

-- replyToSenderName: denormalized snapshot of the original sender's name
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "replyToSenderName" text;

-- Same index strategy the group chat uses (ChatMessage_replyTo_idx)
CREATE INDEX IF NOT EXISTS "DM_replyTo_idx" ON "DirectMessage"("replyToId");
