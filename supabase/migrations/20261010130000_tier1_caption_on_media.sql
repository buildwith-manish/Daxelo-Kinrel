-- =============================================================================
-- Daxelo Kinrel — Tier 1 Feature 1.14: Caption on Photos / Videos / Documents
-- =============================================================================
-- Lets a sender attach a text caption to any media message. The caption
-- renders below the photo/video inside the bubble (WhatsApp-style).
--
-- Implementation:
--   • Add `caption text` to ChatMessage and DirectMessage (nullable).
--   • For voice messages, caption stays null (voice bubbles don't render
--     a caption).
--   • The NestJS ChatService.sendMessage + the existing
--     fn_forward_message RPC both propagate the caption.
--
-- Idempotent.
-- =============================================================================

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "caption" text;
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "caption" text;

-- Verification
SELECT 'ChatMessage.caption' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'caption'
       ) AS exists;
SELECT 'DirectMessage.caption' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'caption'
       ) AS exists;
