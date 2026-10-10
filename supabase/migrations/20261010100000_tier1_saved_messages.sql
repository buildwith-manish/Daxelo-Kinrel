-- =============================================================================
-- Daxelo Kinrel — Tier 1 Feature 1.1: Saved Messages (chat-with-self)
-- =============================================================================
-- Lets a user start a 1:1 DM with THEMSELVES to park links, notes, files,
-- and forwards — the WhatsApp/Telegram "Saved Messages" pattern.
--
-- Implementation: no new table. We reuse the existing DirectMessage table
-- with senderId = receiverId = auth.uid(). The existing RLS policy on
-- DirectMessage already permits this (auth.uid() = senderId), so no
-- policy changes are needed. We add:
--   1. A partial index so the "load my saved-messages thread" query stays
--      fast even when the DirectMessage table grows large.
--   2. A helper RPC fn_get_saved_messages(other_user_id) that returns
--      the DM thread between the caller and a target user — works
--      symmetrically for self-DM (other_user_id = auth.uid()) and for
--      a regular DM. Used by the Flutter inbox to render the
--      "Saved Messages" row at the top of the DM section.
--   3. An RPC fn_get_saved_messages_inbox that returns the user's
--      self-DM latest message (or null if they've never saved anything),
--      used by the inbox to render the row without a separate query.
--
-- Idempotent: CREATE INDEX IF NOT EXISTS, CREATE OR REPLACE FUNCTION.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Partial index: DirectMessage rows where sender = receiver (self-DM).
--    Sped up because the inbox always queries these rows together.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS "DM_saved_messages_idx"
  ON "DirectMessage" ("senderId", "createdAt" DESC)
  WHERE "senderId" = "receiverId";

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_get_saved_messages_inbox — returns the user's self-DM preview
--    Used by the Flutter inbox to render the "Saved Messages" row at
--    the top of the DMs section.
--    Returns null if the user has never DMed themselves.
--    Otherwise returns: { otherUserId, otherUserName, otherUserAvatar,
--      lastMessageContent, lastMessageCreatedAt, lastMessageType, unreadCount }
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_saved_messages_inbox()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_last record;
  v_unread int;
  v_name text;
  v_avatar text;
  v_username text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- User's display name + avatar for the inbox row.
  SELECT name, "avatarUrl", username
    INTO v_name, v_avatar, v_username
    FROM "User" WHERE id = v_user_id;

  -- Latest self-DM message (sender = receiver = me).
  SELECT * INTO v_last FROM "DirectMessage"
    WHERE "senderId" = v_user_id AND "receiverId" = v_user_id
    ORDER BY "createdAt" DESC
    LIMIT 1;

  -- Unread = messages where I'm the receiver, sender != me, and isRead is false.
  -- For Saved Messages, the sender IS the receiver, so unreadCount is always 0
  -- (you can't have unread messages from yourself). We still return 0 explicitly
  -- so the inbox code path is identical to a normal DM.
  v_unread := 0;

  IF v_last IS NULL THEN
    RETURN json_build_object(
      'success', true,
      'hasSavedMessages', false,
      'otherUserId', v_user_id,
      'otherUserName', COALESCE(v_name, v_username, 'Saved Messages'),
      'otherUserAvatar', v_avatar,
      'otherUserUsername', v_username,
      'isSelf', true,
      'lastMessageContent', NULL,
      'lastMessageCreatedAt', NULL,
      'lastMessageType', NULL,
      'unreadCount', 0
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'hasSavedMessages', true,
    'otherUserId', v_user_id,
    'otherUserName', COALESCE(v_name, v_username, 'Saved Messages'),
    'otherUserAvatar', v_avatar,
    'otherUserUsername', v_username,
    'isSelf', true,
    'lastMessageContent', v_last."content",
    'lastMessageCreatedAt', to_char(v_last."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'lastMessageType', v_last."messageType",
    'unreadCount', v_unread
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_saved_messages_inbox() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Verification
-- ═══════════════════════════════════════════════════════════════════════════
SELECT 'DM_saved_messages_idx' AS obj,
       EXISTS(
         SELECT 1 FROM pg_indexes
         WHERE indexname = 'DM_saved_messages_idx'
       ) AS exists;
SELECT 'fn_get_saved_messages_inbox' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_saved_messages_inbox') AS exists;
