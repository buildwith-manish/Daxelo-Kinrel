-- ============================================================
-- Migration: chat_mention_notify_and_group
-- Phase A — @mentions across chat
--
-- Adds the columns the new mention pipeline needs:
--   • ChatMention.groupId     — scopes an unread-mention lookup to a group
--     (NULL for family-wide mentions). Lets the @ badge render per chat.
--   • ChatMention.notify      — server-derived from conversation type.
--     Groups/family-wide chat: true. Direct chat third-person references:
--     false (no push, no ChatMention row created on the server — but the
--     column exists so a future "show all references" view can use it).
--   • ChatMention.notifiedAt  — when the push was sent (NULL = pending).
--     The new ChatMentionPushScheduler uses this to know what to retry.
--   • ChatMention.isRead      — flips to true when the recipient opens
--     the chat. Drives the @ badge count (WHERE "isRead" = false).
--   • NotificationPreference.mentionsBreakMute — per-user toggle.
--     Default TRUE. When TRUE, a mention still pushes even in a muted
--     chat. When FALSE, mentions respect the chat's mute. Quiet hours
--     and block list are ALWAYS respected regardless of this setting.
--
-- All columns are additive (nullable or NOT NULL DEFAULT) so the
-- deploy is non-breaking: existing rows survive, existing queries
-- (which SELECT * or select specific columns) keep working, and the
-- new columns just appear as NULL/false/true until the new code writes
-- to them.
--
-- Deploy order: migration → server → app. See worklog.
-- ============================================================

-- ── ChatMention: 4 new columns ───────────────────────────────────
ALTER TABLE "ChatMention"
  ADD COLUMN IF NOT EXISTS "groupId"    text,
  ADD COLUMN IF NOT EXISTS "notify"      boolean  NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "notifiedAt" timestamptz,
  ADD COLUMN IF NOT EXISTS "isRead"     boolean  NOT NULL DEFAULT false;

-- Backfill: any pre-existing ChatMention rows are family-wide (no
-- groupId), should notify (the old behaviour), and are unread. The
-- column defaults already cover this, but an explicit UPDATE pins the
-- invariant in case a DEFAULT was missed in a partial restore.
UPDATE "ChatMention"
  SET "groupId" = NULL,
      "notify"  = TRUE,
      "isRead"  = FALSE
  WHERE "groupId" IS NULL;

-- ── ChatMention: indexes ─────────────────────────────────────────
-- Partial index: the @ badge queries "all unread mentions for me,
-- grouped by (familyId, groupId)". The isRead=false predicate keeps
-- the index small (only pending mentions) and the query fast.
CREATE INDEX IF NOT EXISTS idx_chatmention_recipient_unread
  ON "ChatMention" ("mentionedUserId")
  WHERE "isRead" = false;

-- Per-group scoping for the @ badge in group chats. The groupId IS
-- NOT NULL predicate keeps family-wide mentions out of this index.
CREATE INDEX IF NOT EXISTS idx_chatmention_group
  ON "ChatMention" ("groupId", "mentionedUserId")
  WHERE "groupId" IS NOT NULL;

-- Per-message lookup (already indexed in the original table, but
-- added here as a safety in case the original was dropped).
CREATE INDEX IF NOT EXISTS idx_chatmention_message
  ON "ChatMention" ("messageId");

-- ── NotificationPreference: mentionsBreakMute ────────────────────
ALTER TABLE "NotificationPreference"
  ADD COLUMN IF NOT EXISTS "mentionsBreakMute" boolean NOT NULL DEFAULT true;

-- Backfill: existing preferences default to the spec'd default (ON).
UPDATE "NotificationPreference"
  SET "mentionsBreakMute" = TRUE
  WHERE "mentionsBreakMute" IS NULL;
