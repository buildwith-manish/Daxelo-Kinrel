-- =============================================================================
-- Daxelo Kinrel — Chat Enhancement Schema (Phase 1)
-- =============================================================================
-- Adds columns to ChatMessage for: replies, reactions, read receipts,
-- editing, deletion, and message status. Also creates ChatReaction,
-- ChatReadReceipt, and ChatTypingStatus tables.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Add columns to ChatMessage
-- ═══════════════════════════════════════════════════════════════════════════

-- replyToId: references another ChatMessage.id (for reply threading)
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "replyToId" text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "replyToContent" text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "replyToSenderName" text;

-- isEdited: true if the message was edited after sending
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "isEdited" boolean NOT NULL DEFAULT false;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "editedAt" timestamptz;

-- isDeletedForMe: soft-delete per user (stored as JSON array of userIds)
-- This allows "Delete for Me" without affecting other users
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "deletedForMe" jsonb NOT NULL DEFAULT '[]'::jsonb;

-- isDeletedForEveryone: hard soft-delete (message content cleared for all)
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "isDeletedForEveryone" boolean NOT NULL DEFAULT false;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "deletedAt" timestamptz;

-- messageStatus: 'sent' | 'delivered' | 'read'
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "messageStatus" text NOT NULL DEFAULT 'sent';

-- isStarred: user can star/bookmark important messages
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "isStarred" boolean NOT NULL DEFAULT false;

-- isPinned: admin/creator can pin messages in group chat
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "isPinned" boolean NOT NULL DEFAULT false;

-- messageSubType: 'text' | 'image' | 'video' | 'audio' | 'voice' | 'document' | 'sticker' | 'gif' | 'contact' | 'location' | 'system'
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "messageSubType" text NOT NULL DEFAULT 'text';

-- mediaUrl: URL for media messages (images, videos, audio, documents)
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "mediaUrl" text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "mediaType" text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "mediaFileName" text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "mediaSize" bigint;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "thumbnailUrl" text;

-- voiceMessageDuration: duration in seconds for voice messages
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "voiceMessageDuration" integer;

-- forwardedFrom: original sender name if message was forwarded
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "forwardedFrom" text;

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS "ChatMessage_replyTo_idx" ON "ChatMessage"("replyToId");
CREATE INDEX IF NOT EXISTS "ChatMessage_status_idx" ON "ChatMessage"("messageStatus");
CREATE INDEX IF NOT EXISTS "ChatMessage_starred_idx" ON "ChatMessage"("isStarred") WHERE "isStarred" = true;
CREATE INDEX IF NOT EXISTS "ChatMessage_pinned_idx" ON "ChatMessage"("isPinned") WHERE "isPinned" = true;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. ChatReaction table (emoji reactions on messages)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "ChatReaction" (
  "id" text PRIMARY KEY,
  "messageId" text NOT NULL REFERENCES "ChatMessage"(id) ON DELETE CASCADE,
  "userId" text NOT NULL,
  "emoji" text NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE("messageId", "userId") -- one reaction per user per message
);

CREATE INDEX IF NOT EXISTS "ChatReaction_message_idx" ON "ChatReaction"("messageId");

ALTER TABLE "ChatReaction" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ChatReaction select" ON "ChatReaction"
  FOR SELECT TO authenticated USING (
    "messageId" IN (
      SELECT cm.id FROM "ChatMessage" cm
      JOIN "FamilyMember" fm ON fm."familyId" = cm."familyId"
      WHERE fm."userId" = auth.uid()::text
    )
  );
CREATE POLICY "ChatReaction insert" ON "ChatReaction"
  FOR INSERT TO authenticated WITH CHECK (
    "userId" = auth.uid()::text
  );
CREATE POLICY "ChatReaction delete" ON "ChatReaction"
  FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. ChatReadReceipt table (tracks who has read each message)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "ChatReadReceipt" (
  "id" text PRIMARY KEY,
  "messageId" text NOT NULL REFERENCES "ChatMessage"(id) ON DELETE CASCADE,
  "userId" text NOT NULL,
  "readAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE("messageId", "userId")
);

CREATE INDEX IF NOT EXISTS "ChatReadReceipt_message_idx" ON "ChatReadReceipt"("messageId");
CREATE INDEX IF NOT EXISTS "ChatReadReceipt_user_idx" ON "ChatReadReceipt"("userId");

ALTER TABLE "ChatReadReceipt" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ChatReadReceipt select" ON "ChatReadReceipt"
  FOR SELECT TO authenticated USING (
    "userId" = auth.uid()::text OR
    "messageId" IN (
      SELECT cm.id FROM "ChatMessage" cm
      WHERE cm."senderId" = auth.uid()::text
    )
  );
CREATE POLICY "ChatReadReceipt insert" ON "ChatReadReceipt"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. ChatTypingStatus table (who is currently typing)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "ChatTypingStatus" (
  "id" text PRIMARY KEY,
  "familyId" text NOT NULL,
  "userId" text NOT NULL,
  "isTyping" boolean NOT NULL DEFAULT false,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE("familyId", "userId")
);

ALTER TABLE "ChatTypingStatus" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ChatTyping select" ON "ChatTypingStatus"
  FOR SELECT TO authenticated USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text
    )
  );
CREATE POLICY "ChatTyping upsert" ON "ChatTypingStatus"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "ChatTyping update" ON "ChatTypingStatus"
  FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. ChatSettings table (per-user chat wallpaper + preferences)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "ChatSettings" (
  "id" text PRIMARY KEY,
  "userId" text NOT NULL,
  "familyId" text NOT NULL,
  "wallpaperUrl" text,
  "wallpaperColor" text DEFAULT '#131416',
  "isMuted" boolean NOT NULL DEFAULT false,
  "isPinned" boolean NOT NULL DEFAULT false,
  "isArchived" boolean NOT NULL DEFAULT false,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE("userId", "familyId")
);

ALTER TABLE "ChatSettings" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ChatSettings select" ON "ChatSettings"
  FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
CREATE POLICY "ChatSettings insert" ON "ChatSettings"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "ChatSettings update" ON "ChatSettings"
  FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Add realtime to new tables
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE "ChatReaction" REPLICA IDENTITY FULL;
ALTER TABLE "ChatReadReceipt" REPLICA IDENTITY FULL;
ALTER TABLE "ChatTypingStatus" REPLICA IDENTITY FULL;
ALTER TABLE "ChatSettings" REPLICA IDENTITY FULL;
ALTER TABLE "ChatMessage" REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'ChatReaction') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "ChatReaction";
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'ChatReadReceipt') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "ChatReadReceipt";
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'ChatTypingStatus') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "ChatTypingStatus";
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'ChatSettings') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "ChatSettings";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. RPCs for chat operations
-- ═══════════════════════════════════════════════════════════════════════════

-- fn_delete_message_for_me
CREATE OR REPLACE FUNCTION fn_delete_message_for_me(
  p_message_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  UPDATE "ChatMessage"
  SET "deletedForMe" = "deletedForMe" || jsonb_build_array(v_user_id)
  WHERE "id" = p_message_id;
  RETURN json_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION fn_delete_message_for_me(text) TO authenticated;

-- fn_delete_message_for_everyone (sender or admin only)
CREATE OR REPLACE FUNCTION fn_delete_message_for_everyone(
  p_message_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_sender_id text;
  v_is_admin boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT "senderId" INTO v_sender_id FROM "ChatMessage" WHERE "id" = p_message_id;

  IF v_sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Message not found');
  END IF;

  -- Check if caller is sender or admin
  SELECT EXISTS(
    SELECT 1 FROM "FamilyMember" fm
    JOIN "ChatMessage" cm ON cm."familyId" = fm."familyId"
    WHERE cm."id" = p_message_id
      AND fm."userId" = v_user_id
      AND (fm."role" IN ('admin', 'owner') OR cm."senderId" = v_user_id)
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized');
  END IF;

  UPDATE "ChatMessage"
  SET "isDeletedForEveryone" = true,
      "content" = '',
      "deletedAt" = now()
  WHERE "id" = p_message_id;

  RETURN json_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION fn_delete_message_for_everyone(text) TO authenticated;

-- fn_edit_message
CREATE OR REPLACE FUNCTION fn_edit_message(
  p_message_id text,
  p_new_content text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_sender_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT "senderId" INTO v_sender_id FROM "ChatMessage" WHERE "id" = p_message_id;
  IF v_sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Message not found');
  END IF;
  IF v_sender_id != v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'Can only edit your own messages');
  END IF;

  UPDATE "ChatMessage"
  SET "content" = p_new_content,
      "isEdited" = true,
      "editedAt" = now()
  WHERE "id" = p_message_id;

  RETURN json_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION fn_edit_message(text, text) TO authenticated;

-- fn_mark_messages_read
CREATE OR REPLACE FUNCTION fn_mark_messages_read(
  p_family_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_msg record;
  v_receipt_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Create read receipts for all unread messages not sent by this user
  FOR v_msg IN
    SELECT id FROM "ChatMessage"
    WHERE "familyId" = p_family_id
      AND "senderId" != v_user_id
      AND "isDeletedForEveryone" = false
      AND id NOT IN (
        SELECT "messageId" FROM "ChatReadReceipt" WHERE "userId" = v_user_id
      )
  LOOP
    v_receipt_id := 'rr_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8) || '_' || substring(v_msg.id from 1 for 8);
    INSERT INTO "ChatReadReceipt" ("id", "messageId", "userId", "readAt")
    VALUES (v_receipt_id, v_msg.id, v_user_id, now())
    ON CONFLICT ("messageId", "userId") DO NOTHING;
  END LOOP;

  -- Update message status to 'read' for messages that now have read receipts
  UPDATE "ChatMessage"
  SET "messageStatus" = 'read'
  WHERE "familyId" = p_family_id
    AND "messageStatus" != 'read'
    AND "senderId" != v_user_id
    AND id IN (
      SELECT "messageId" FROM "ChatReadReceipt" WHERE "userId" = v_user_id
    );

  RETURN json_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION fn_mark_messages_read(text) TO authenticated;

-- fn_toggle_reaction
CREATE OR REPLACE FUNCTION fn_toggle_reaction(
  p_message_id text,
  p_emoji text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_existing record;
  v_reaction_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Check if user already has a reaction on this message
  SELECT * INTO v_existing FROM "ChatReaction"
  WHERE "messageId" = p_message_id AND "userId" = v_user_id;

  IF v_existing IS NOT NULL THEN
    IF v_existing.emoji = p_emoji THEN
      -- Same emoji → remove (toggle off)
      DELETE FROM "ChatReaction" WHERE "id" = v_existing.id;
      RETURN json_build_object('success', true, 'action', 'removed');
    ELSE
      -- Different emoji → update
      UPDATE "ChatReaction" SET "emoji" = p_emoji WHERE "id" = v_existing.id;
      RETURN json_build_object('success', true, 'action', 'updated');
    END IF;
  ELSE
    -- No reaction → insert new
    v_reaction_id := 'react_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
    INSERT INTO "ChatReaction" ("id", "messageId", "userId", "emoji")
    VALUES (v_reaction_id, p_message_id, v_user_id, p_emoji);
    RETURN json_build_object('success', true, 'action', 'added');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION fn_toggle_reaction(text, text) TO authenticated;

-- fn_set_typing_status
CREATE OR REPLACE FUNCTION fn_set_typing_status(
  p_family_id text,
  p_is_typing boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
BEGIN
  IF v_user_id IS NULL THEN RETURN; END IF;

  v_id := 'typing_' || p_family_id || '_' || v_user_id;

  INSERT INTO "ChatTypingStatus" ("id", "familyId", "userId", "isTyping", "updatedAt")
  VALUES (v_id, p_family_id, v_user_id, p_is_typing, now())
  ON CONFLICT ("familyId", "userId")
  DO UPDATE SET "isTyping" = p_is_typing, "updatedAt" = now();
END;
$$;
GRANT EXECUTE ON FUNCTION fn_set_typing_status(text, boolean) TO authenticated;

-- fn_star_message
CREATE OR REPLACE FUNCTION fn_star_message(
  p_message_id text,
  p_starred boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE "ChatMessage" SET "isStarred" = p_starred WHERE "id" = p_message_id;
  RETURN json_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION fn_star_message(text, boolean) TO authenticated;

-- fn_pin_message (admin/creator only)
CREATE OR REPLACE FUNCTION fn_pin_message(
  p_message_id text,
  p_pinned boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_is_admin boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM "FamilyMember" fm
    JOIN "ChatMessage" cm ON cm."familyId" = fm."familyId"
    WHERE cm."id" = p_message_id
      AND fm."userId" = v_user_id
      AND fm."role" IN ('admin', 'owner')
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RETURN json_build_object('success', false, 'error', 'Only admins can pin messages');
  END IF;

  UPDATE "ChatMessage" SET "isPinned" = p_pinned WHERE "id" = p_message_id;
  RETURN json_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION fn_pin_message(text, boolean) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'ChatReaction' AS obj, EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChatReaction') AS exists;
SELECT 'ChatReadReceipt' AS obj, EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChatReadReceipt') AS exists;
SELECT 'ChatTypingStatus' AS obj, EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChatTypingStatus') AS exists;
SELECT 'ChatSettings' AS obj, EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChatSettings') AS exists;
SELECT 'fn_delete_message_for_me' AS fn, EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_delete_message_for_me') AS exists;
SELECT 'fn_delete_message_for_everyone' AS fn, EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_delete_message_for_everyone') AS exists;
SELECT 'fn_edit_message' AS fn, EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_edit_message') AS exists;
SELECT 'fn_mark_messages_read' AS fn, EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_mark_messages_read') AS exists;
SELECT 'fn_toggle_reaction' AS fn, EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_toggle_reaction') AS exists;
SELECT 'fn_set_typing_status' AS fn, EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_typing_status') AS exists;
SELECT 'fn_star_message' AS fn, EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_star_message') AS exists;
SELECT 'fn_pin_message' AS fn, EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_pin_message') AS exists;
