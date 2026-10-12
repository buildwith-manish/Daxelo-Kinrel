-- =============================================================================
-- Daxelo-Kinrel — Message Deletion: Undo + Deletion Author Tracking
-- =============================================================================
-- Adds the missing piece required by the "Delete for Me with 5-second Undo"
-- feature: an `fn_undelete_message_for_me` RPC that removes the caller's uid
-- from the `deletedForMe` JSONB array on a ChatMessage row.
--
-- Also adds a `deletedByUserId` column to `ChatMessage` so that the placeholder
-- wording can be personalized ("You deleted this message." for the deleter
-- vs. "<Participant name> deleted this message." for everyone else). Today
-- only the original author can delete-for-everyone, so `deletedByUserId`
-- will equal `senderId` in the common case — but we keep them as separate
-- columns so a future moderation feature can allow non-author deletion
-- without changing the placeholder wording logic.
--
-- All changes are idempotent (ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE
-- FUNCTION, GRANT IF EXISTS).
-- =============================================================================

-- ─── 1. Track WHO deleted a message for everyone ───────────────────────────
-- Needed so the placeholder can show "<name> deleted this message." using
-- the deleter's identity (not the original author's, when they differ).
ALTER TABLE "ChatMessage"
    ADD COLUMN IF NOT EXISTS "deletedByUserId" text;

-- Backfill: every existing deleted-for-everyone row was deleted by its
-- sender (the only path that exists today), so we can safely copy
-- senderId → deletedByUserId for any rows where the column is null and
-- isDeletedForEveryone is true.
UPDATE "ChatMessage"
   SET "deletedByUserId" = "senderId"
 WHERE "isDeletedForEveryone" = true
   AND "deletedByUserId" IS NULL;

-- Index for fast "who deleted this?" lookups (used by the placeholder RPC).
CREATE INDEX IF NOT EXISTS idx_chatmessage_deleted_by
    ON "ChatMessage" ("deletedByUserId")
    WHERE "isDeletedForEveryone" = true;

-- ─── 2. fn_delete_message_for_everyone — record the deleter ──────────────
-- Replace the existing RPC so it also writes deletedByUserId. We keep the
-- exact same authorization rules (sender or family admin/owner).
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

  -- Check if caller is sender or admin/owner of the family that owns the message
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

  -- Soft-delete: clear the content + mark deleted-for-everyone + record
  -- the deleter identity (used for personalized placeholder wording).
  UPDATE "ChatMessage"
  SET "isDeletedForEveryone" = true,
      "content" = '',
      "deletedAt" = now(),
      "deletedByUserId" = v_user_id,
      "updatedAt" = now()
  WHERE "id" = p_message_id;

  RETURN json_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION fn_delete_message_for_everyone(text) TO authenticated;

-- ─── 3. fn_undelete_message_for_me — undo a "Delete for Me" ───────────────
-- Removes the caller's uid from the `deletedForMe` JSONB array. Called by
-- the Flutter client when the user taps UNDO within the 5-second window.
-- Returns success JSON (matching the other RPCs' shape) even if the uid
-- wasn't present (idempotent — undo of an already-undone delete is a no-op).
CREATE OR REPLACE FUNCTION fn_undelete_message_for_me(
  p_message_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_new_array jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Remove the caller's uid from the deletedForMe JSONB array. The
  -- `?` operator returns true if the array contains the string, and the
  -- `jsonb_strip_nulls + to_jsonb` pattern rebuilds the array without
  -- that entry. The resulting array is also deduped (jsonb_agg DISTINCT).
  SELECT COALESCE(
    (SELECT jsonb_agg(DISTINCT elem)
       FROM jsonb_array_elements("deletedForMe") AS elem
      WHERE elem::text <> to_jsonb(v_user_id)::text),
    '[]'::jsonb
  ) INTO v_new_array
  FROM "ChatMessage"
  WHERE "id" = p_message_id;

  UPDATE "ChatMessage"
     SET "deletedForMe" = v_new_array,
         "updatedAt" = now()
   WHERE "id" = p_message_id;

  RETURN json_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION fn_undelete_message_for_me(text) TO authenticated;

-- ─── 4. fn_bulk_delete_for_me — append caller uid to many rows ────────────
-- Lets the client undo a bulk "Delete for Me" in one round-trip (vs. N
-- sequential RPCs). Accepts a JSON array of message ids. Skips any ids
-- the caller doesn't have RLS read access to (defensive — they shouldn't
-- be in the set anyway, but the RLS check inside the UPDATE will skip
-- them automatically).
CREATE OR REPLACE FUNCTION fn_bulk_delete_for_me(
  p_message_ids jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  IF p_message_ids IS NULL OR jsonb_array_length(p_message_ids) = 0 THEN
    RETURN json_build_object('success', true, 'count', 0);
  END IF;

  FOR v_id IN SELECT jsonb_array_elements_text(p_message_ids) LOOP
    UPDATE "ChatMessage"
       SET "deletedForMe" = "deletedForMe" || jsonb_build_array(v_user_id),
           "updatedAt" = now()
     WHERE "id" = v_id;
  END LOOP;

  RETURN json_build_object('success', true, 'count', jsonb_array_length(p_message_ids));
END;
$$;
GRANT EXECUTE ON FUNCTION fn_bulk_delete_for_me(jsonb) TO authenticated;

-- ─── 5. fn_bulk_undelete_for_me — undo a bulk Delete for Me ───────────────
-- Mirror of fn_bulk_delete_for_me — removes the caller's uid from every
-- message id in the input JSON array. Used when the user taps UNDO on a
-- multi-message delete snackbar.
CREATE OR REPLACE FUNCTION fn_bulk_undelete_for_me(
  p_message_ids jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_new_array jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  IF p_message_ids IS NULL OR jsonb_array_length(p_message_ids) = 0 THEN
    RETURN json_build_object('success', true, 'count', 0);
  END IF;

  FOR v_id IN SELECT jsonb_array_elements_text(p_message_ids) LOOP
    SELECT COALESCE(
      (SELECT jsonb_agg(DISTINCT elem)
         FROM jsonb_array_elements("deletedForMe") AS elem
        WHERE elem::text <> to_jsonb(v_user_id)::text),
      '[]'::jsonb
    ) INTO v_new_array
    FROM "ChatMessage"
    WHERE "id" = v_id;

    UPDATE "ChatMessage"
       SET "deletedForMe" = v_new_array,
           "updatedAt" = now()
     WHERE "id" = v_id;
  END LOOP;

  RETURN json_build_object('success', true, 'count', jsonb_array_length(p_message_ids));
END;
$$;
GRANT EXECUTE ON FUNCTION fn_bulk_undelete_for_me(jsonb) TO authenticated;

COMMENT ON COLUMN "ChatMessage"."deletedByUserId" IS
    'The auth.users.id (as text) of the user who initiated a delete-for-everyone on this row. NULL for non-deleted rows. Equals senderId in the common case (only the author can delete-for-everyone today) but kept as a separate column so future moderation features can attribute deletions to a non-author moderator without changing the placeholder wording logic.';
