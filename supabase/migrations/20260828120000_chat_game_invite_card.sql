-- =============================================================================
-- Daxelo-Kinrel — Persistent game-invite card in the family chat thread
-- =============================================================================
-- Adds game-invite payload columns to "ChatMessage" so a game-room invite can
-- be posted as a persistent, live-updating card in the family chat thread,
-- in ADDITION to the existing realtime Socket.IO popup (GameInviteListener)
-- and the FCM push fired by the game_invites AFTER INSERT trigger.
--
-- Flow:
--   • ChatNotifier.sendGameInvite() inserts one ChatMessage row with
--     messageType='gameInvite' per invite action (the card represents the
--     room as a whole — not one card per recipient).
--   • syncGameInviteChatCards()
--     (lib/features/games/shared/data/game_invite_chat_sync.dart) UPDATEs
--     gameCurrentPlayers / gameInviteStatus on those rows whenever the
--     game's player count or lifecycle changes (player joins via the card's
--     Join button, host starts the game, game finishes).
--   • chat_provider.dart already holds a Supabase Realtime UPDATE
--     subscription on "ChatMessage" (filtered by familyId, REPLICA IDENTITY
--     FULL), so the refreshed row propagates to every family member's open
--     chat UI automatically — "2/4 players", "Full", "Started", "Ended".
--
-- RLS: unchanged. The existing chatmessage_update_policy already permits any
-- family member to UPDATE rows in their own family (required by the isRead
-- trigger), so a joining player may bump gameCurrentPlayers on the host's
-- card. New columns simply inherit the table's policies.
--
-- Idempotent: every ALTER is ADD COLUMN IF NOT EXISTS; index is IF NOT EXISTS.
-- =============================================================================

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "gameId"   text;   -- game room id (FK by convention to <game>_games.id)
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "gameType" text;   -- route segment, e.g. 'sos', 'bingo', 'freeze-dash'
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "roomCode" text;   -- 6-char display room code

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "gameMaxPlayers"     integer;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "gameCurrentPlayers" integer;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "gameInviteStatus"   text;  -- 'pending' | 'accepted' | 'expired' | 'cancelled'
                                                                                -- null on non-game rows; app treats null as 'pending'

-- Sync lookups: find every game-invite chat card for a given game room.
-- Partial index keeps it tiny (only the rare gameInvite rows) and makes the
-- syncGameInviteChatCards() UPDATE (.eq('gameId', …) WHERE messageType =
-- 'gameInvite') an index scan instead of a seq scan.
CREATE INDEX IF NOT EXISTS "ChatMessage_gameInvite_gameId_idx"
    ON "ChatMessage" ("gameId")
    WHERE "messageType" = 'gameInvite';
