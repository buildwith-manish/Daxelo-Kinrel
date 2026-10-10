-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.7: Anonymous Admin Messages
-- =============================================================================
-- Lets an admin send a message with the sender hidden — the bubble shows
-- "Admin" instead of the admin's name. Useful for moderation announcements
-- where the speaker shouldn't be targeted for the message they sent.
--
-- Implementation:
--   • Add `isAnonymousAdmin boolean DEFAULT false` to ChatMessage.
--   • DirectMessage gets the same column so DMs aren't different — even
--     though DM anonymity is unusual, schema parity keeps the bubble renderer
--     simpler.
--   • The NestJS ChatService.sendMessage checks the caller's role before
--     honoring isAnonymousAdmin=true (only admins/creators can use it).
-- =============================================================================

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "isAnonymousAdmin" boolean NOT NULL DEFAULT false;
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "isAnonymousAdmin" boolean NOT NULL DEFAULT false;

-- Verification
SELECT 'ChatMessage.isAnonymousAdmin' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'isAnonymousAdmin'
       ) AS exists;
SELECT 'DirectMessage.isAnonymousAdmin' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'isAnonymousAdmin'
       ) AS exists;
