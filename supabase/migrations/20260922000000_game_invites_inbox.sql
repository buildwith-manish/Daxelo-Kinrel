-- =============================================================================
-- Daxelo-Kinrel — offline game-invite inbox (isRead / shownAt)
-- =============================================================================
-- QA follow-up item 4: invites sent while a member was OFFLINE (app closed,
-- socket dead, realtime channel gone) were never surfaced — the durable
-- game_invites row existed but nothing read it back on the next app start.
--
-- This migration adds the two inbox bookkeeping columns:
--   isRead   — the recipient has been surfaced this invite (dialog shown
--              at least once, via any leg: socket / realtime / catch-up).
--   shownAt  — when that first surfacing happened (diagnostics).
--
-- The Flutter client's catch-up leg (GameInviteListener leg 3) selects
--   status = 'pending' AND isRead = false AND expiresAt > now()
-- ordered by createdAt, shows the SAME Accept/Decline dialog, and marks
-- the row isRead as each dialog is surfaced.
--
-- RLS: no new policies needed — the recipient already has UPDATE on their
-- own rows (game_invites_update_invited) and SELECT
-- (game_invites_select_self).
--
-- Backfill: not required. Pre-existing 'pending' rows are at most 10
-- minutes old (expiresAt) — surfacing them once after this migration is
-- correct inbox behaviour; everything older is already 'expired'.
-- =============================================================================

ALTER TABLE "public"."game_invites"
  ADD COLUMN IF NOT EXISTS "isRead" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "shownAt" timestamptz;

-- Inbox scan: the catch-up query hits exactly this predicate.
CREATE INDEX IF NOT EXISTS idx_game_invites_inbox_unread
  ON "public"."game_invites" ("invitedUserId", "createdAt" ASC)
  WHERE "status" = 'pending' AND "isRead" = false;
