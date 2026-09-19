-- Feature 2: Message Reactions
--
-- Aligns the ChatReaction table with the user's spec: unique constraint on
-- (messageId, userId, emoji) so one user can leave MULTIPLE different emojis
-- on the same message (WhatsApp/Telegram model) but cannot leave the same
-- emoji twice.
--
-- Previously the table had UNIQUE(messageId, userId) — the iMessage "one
-- reaction per user per message" model. The existing fn_toggle_reaction RPC
-- enforced this by replacing the emoji on update. We drop the old constraint
-- and add the new one, then update fn_toggle_reaction to use INSERT-or-DELETE
-- (toggle) semantics per (messageId, userId, emoji).
--
-- Idempotent: uses IF EXISTS / IF NOT EXISTS. Safe to re-run.

-- 1. Drop the old (messageId, userId) unique constraint.
ALTER TABLE "ChatReaction"
  DROP CONSTRAINT IF EXISTS "ChatReaction_messageId_userId_key";

-- 2. Add the new (messageId, userId, emoji) unique constraint.
ALTER TABLE "ChatReaction"
  ADD CONSTRAINT "ChatReaction_messageId_userId_emoji_key"
  UNIQUE ("messageId", "userId", "emoji");

-- 3. Update fn_toggle_reaction to WhatsApp semantics.
CREATE OR REPLACE FUNCTION public.fn_toggle_reaction(p_message_id text, p_emoji text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id text := auth.uid()::text;
  v_existing record;
  v_reaction_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_existing FROM "ChatReaction"
  WHERE "messageId" = p_message_id
    AND "userId" = v_user_id
    AND "emoji" = p_emoji;

  IF v_existing IS NOT NULL THEN
    DELETE FROM "ChatReaction" WHERE "id" = v_existing.id;
    RETURN json_build_object('success', true, 'action', 'removed');
  ELSE
    v_reaction_id := 'react_' || extract(epoch from now())::bigint::text
      || '_' || substring(v_user_id from 1 for 8)
      || '_' || ascii(p_emoji)::text;
    INSERT INTO "ChatReaction" ("id", "messageId", "userId", "emoji")
    VALUES (v_reaction_id, p_message_id, v_user_id, p_emoji);
    RETURN json_build_object('success', true, 'action', 'added');
  END IF;
END;
$function$;

CREATE INDEX IF NOT EXISTS "ChatReaction_message_user_emoji_idx"
  ON "ChatReaction" ("messageId", "userId", "emoji");

COMMENT ON TABLE "ChatReaction" IS
  'Feature 2: Per-user emoji reactions on chat messages. UNIQUE(messageId, userId, emoji) allows a user to leave multiple different emojis on one message.';
