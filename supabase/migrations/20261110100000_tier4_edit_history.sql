-- =============================================================================
-- Daxelo Kinrel — Tier 4 Features 4.2 + 4.3: Edit Media (replace photo after sending) + Edit history view
-- =============================================================================
-- Adds an `editHistory` JSONB column to ChatMessage and DirectMessage so
-- every edit captures a snapshot of the previous content + mediaUrl.
-- The NestJS ChatService.editMessage method (added in this tier) writes
-- to editHistory BEFORE updating the row, so the array grows monotonically.
--
-- Schema shape (editHistory JSONB array, oldest-first):
--   [
--     { "content": "<old text>", "mediaUrl": "<old url>", "editedAt": "2026-..." },
--     { "content": "<older text>", "mediaUrl": "<older url>", "editedAt": "2026-..." }
--   ]
--
-- The array grows on every edit. The current state lives on the row itself
-- (content, mediaUrl, editedAt, isEdited). The Flutter client renders the
-- array via a long-press "Edit history" sheet (Feature 4.3).
--
-- Idempotent.
-- =============================================================================

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "editHistory" jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "editHistory" jsonb NOT NULL DEFAULT '[]'::jsonb;

-- Partial index for the "show my edited messages" admin dashboard query.
CREATE INDEX IF NOT EXISTS "ChatMessage_edited_idx"
  ON "ChatMessage"("senderId", "editedAt" DESC)
  WHERE "isEdited" = true;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_edit_chat_message — atomic edit + edit-history append.
--
--   p_message_id   — the ChatMessage.id to edit
--   p_new_content  — new text content (null = unchanged)
--   p_new_media_url — new media URL (null = unchanged). For media swap.
--   p_new_caption  — new caption (null = unchanged)
--
-- The function:
--   1. Validates the caller is the original sender (only senders can edit).
--   2. Captures the previous (content, mediaUrl, caption) into editHistory.
--   3. Updates the row with the new values + sets isEdited=true + editedAt=now().
--   4. Returns the updated row.
--
-- Idempotent in the sense that re-running with the same payload produces
-- the same final state (but DOES append another edit-history entry, since
-- each edit is a distinct event — matches WhatsApp behavior).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_edit_chat_message(
  p_message_id text,
  p_new_content text DEFAULT NULL,
  p_new_media_url text DEFAULT NULL,
  p_new_caption text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_msg record;
  v_old_snapshot jsonb;
  v_new_history jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT "id", "familyId", "senderId", "content", "mediaUrl", "caption",
         "isEdited", "editedAt", "editHistory"
    INTO v_msg
    FROM "ChatMessage"
    WHERE "id" = p_message_id;

  IF v_msg IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'message_not_found');
  END IF;

  -- Only the original sender can edit their own message.
  IF v_msg."senderId" <> v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'not_sender');
  END IF;

  -- Don't allow editing deleted messages.
  IF EXISTS (SELECT 1 FROM "ChatMessage" WHERE "id" = p_message_id AND "isDeletedForEveryone" = true) THEN
    RETURN json_build_object('success', false, 'error', 'message_deleted');
  END IF;

  -- Capture the previous state into a snapshot.
  v_old_snapshot := jsonb_build_object(
    'content', v_msg."content",
    'mediaUrl', v_msg."mediaUrl",
    'caption', v_msg."caption",
    'editedAt', to_char(COALESCE(v_msg."editedAt", v_msg."createdAt" AT TIME ZONE 'UTC') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );

  -- Append to editHistory (which is a JSON array).
  v_new_history := v_msg."editHistory" || jsonb_build_array(v_old_snapshot);

  -- Apply the edit.
  UPDATE "ChatMessage"
    SET
      "content"     = COALESCE(p_new_content, "content"),
      "mediaUrl"    = COALESCE(p_new_media_url, "mediaUrl"),
      "caption"     = CASE
                       WHEN p_new_caption IS NULL THEN "caption"
                       WHEN p_new_caption = '' THEN NULL
                       ELSE p_new_caption
                     END,
      "isEdited"    = true,
      "editedAt"    = now(),
      "editHistory" = v_new_history,
      "updatedAt"   = now()
    WHERE "id" = p_message_id;

  RETURN json_build_object(
    'success', true,
    'messageId', p_message_id,
    'isEdited', true,
    'editedAt', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'editHistoryLength', jsonb_array_length(v_new_history)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_edit_chat_message(text, text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_edit_direct_message — same pattern for 1:1 DMs
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_edit_direct_message(
  p_message_id text,
  p_new_content text DEFAULT NULL,
  p_new_caption text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_msg record;
  v_old_snapshot jsonb;
  v_new_history jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT "id", "senderId", "receiverId", "content", "caption", "editHistory"
    INTO v_msg
    FROM "DirectMessage"
    WHERE "id" = p_message_id;

  IF v_msg IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'message_not_found');
  END IF;
  IF v_msg."senderId" <> v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'not_sender');
  END IF;

  v_old_snapshot := jsonb_build_object(
    'content', v_msg."content",
    'caption', v_msg."caption",
    'editedAt', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
  v_new_history := v_msg."editHistory" || jsonb_build_array(v_old_snapshot);

  UPDATE "DirectMessage"
    SET
      "content"     = COALESCE(p_new_content, "content"),
      "caption"     = CASE
                       WHEN p_new_caption IS NULL THEN "caption"
                       WHEN p_new_caption = '' THEN NULL
                       ELSE p_new_caption
                     END,
      "editHistory" = v_new_history,
      "updatedAt"   = now()
    WHERE "id" = p_message_id;

  RETURN json_build_object(
    'success', true,
    'messageId', p_message_id,
    'editHistoryLength', jsonb_array_length(v_new_history)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_edit_direct_message(text, text, text) TO authenticated;

-- Verification
SELECT 'ChatMessage.editHistory' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'editHistory'
       ) AS exists;
SELECT 'DirectMessage.editHistory' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'editHistory'
       ) AS exists;
SELECT 'fn_edit_chat_message' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_edit_chat_message') AS exists;
SELECT 'fn_edit_direct_message' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_edit_direct_message') AS exists;
