-- =============================================================================
-- Daxelo Kinrel — Tier 1 Feature 1.11: Document Sharing (PDF/DOCX/etc.)
-- =============================================================================
-- Lets a sender attach a document (PDF, DOCX, slides, etc.) up to 100 MB.
-- The bubble shows a file icon, name, size, and page count (PDF only).
--
-- Implementation:
--   • Add `documentPages integer` and `documentName text` to ChatMessage
--     (mediaFileName + mediaSize already exist for generic media; these
--     two are document-specific).
--   • DirectMessage gets the same columns so DMs can carry documents.
--   • Server raises the multer file-size cap from 25 MB to 100 MB for
--     mediaType='document'.
--   • PDF page count is computed at upload via pdf-parse on the server.
--
-- NOTE: This migration adds the SCHEMA only. The NestJS media.service.ts
-- branching + Flutter document bubble + PDF viewer are follow-up tasks.
--
-- Idempotent.
-- =============================================================================

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "documentName" text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "documentPages" integer;

ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "documentName" text;
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "documentPages" integer;

-- Verification
SELECT 'ChatMessage.documentName' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'documentName'
       ) AS exists;
SELECT 'ChatMessage.documentPages' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'documentPages'
       ) AS exists;
SELECT 'DirectMessage.documentName' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'documentName'
       ) AS exists;
SELECT 'DirectMessage.documentPages' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'documentPages'
       ) AS exists;
