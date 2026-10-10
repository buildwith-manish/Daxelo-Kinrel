-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.4: Broadcast Lists (send to many DMs at once)
-- =============================================================================
-- Schema-only migration. Lets a user pick up to 256 contacts + name a list
-- ("Family Updates"). Sending a message to the list fans out one DM per
-- recipient (private — recipients don't see each other). Replies come back
-- to your DM with each recipient, not to the list.
--
-- NOTE: This migration adds the SCHEMA only. The NestJS broadcasts/ module
-- + Flutter BroadcastListScreen UI are follow-up tasks. See WORKLOG.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "BroadcastList" (
  "id"            text PRIMARY KEY,
  "ownerId"       text NOT NULL,
  "name"          text NOT NULL,
  "memberUserIds" jsonb NOT NULL DEFAULT '[]'::jsonb,   -- array of userId strings, max 256
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "BroadcastList_owner_idx" ON "BroadcastList"("ownerId");

-- Track which broadcast sent which DM (so the UI can show "sent to N/256").
CREATE TABLE IF NOT EXISTS "BroadcastSend" (
  "id"               text PRIMARY KEY,
  "broadcastListId" text NOT NULL REFERENCES "BroadcastList"(id) ON DELETE CASCADE,
  "messageId"        text NOT NULL,                  -- the DirectMessage id fanned out
  "recipientUserId"  text NOT NULL,
  "status"           text NOT NULL DEFAULT 'sent',   -- sent | failed | blocked
  "sentAt"           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "BroadcastSend_list_idx"  ON "BroadcastSend"("broadcastListId");
CREATE INDEX IF NOT EXISTS "BroadcastSend_recipient_idx" ON "BroadcastSend"("recipientUserId");

-- RLS: only the owner can see / manage their broadcast lists.
ALTER TABLE "BroadcastList" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "BroadcastList select own" ON "BroadcastList";
CREATE POLICY "BroadcastList select own" ON "BroadcastList"
  FOR SELECT TO authenticated USING ("ownerId" = auth.uid()::text);
DROP POLICY IF EXISTS "BroadcastList insert own" ON "BroadcastList";
CREATE POLICY "BroadcastList insert own" ON "BroadcastList"
  FOR INSERT TO authenticated WITH CHECK ("ownerId" = auth.uid()::text);
DROP POLICY IF EXISTS "BroadcastList update own" ON "BroadcastList";
CREATE POLICY "BroadcastList update own" ON "BroadcastList"
  FOR UPDATE TO authenticated USING ("ownerId" = auth.uid()::text);
DROP POLICY IF EXISTS "BroadcastList delete own" ON "BroadcastList";
CREATE POLICY "BroadcastList delete own" ON "BroadcastList"
  FOR DELETE TO authenticated USING ("ownerId" = auth.uid()::text);

ALTER TABLE "BroadcastSend" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "BroadcastSend select own" ON "BroadcastSend";
CREATE POLICY "BroadcastSend select own" ON "BroadcastSend"
  FOR SELECT TO authenticated USING (
    "broadcastListId" IN (SELECT id FROM "BroadcastList" WHERE "ownerId" = auth.uid()::text)
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_send_broadcast — fan-out one DM per recipient. Skips blocked users
-- (their DMs bounce silently). Returns counts per status.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_send_broadcast(
  p_broadcast_list_id text,
  p_content text,
  p_message_type text DEFAULT 'text'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_list record;
  v_recipient text;
  v_new_id text;
  v_sent int := 0;
  v_blocked int := 0;
  v_failed int := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_list FROM "BroadcastList" WHERE "id" = p_broadcast_list_id;
  IF v_list IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_list."ownerId" <> v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'not_owner');
  END IF;

  -- Cap at 256 recipients (anti-spam, matches WhatsApp).
  IF jsonb_array_length(v_list."memberUserIds") > 256 THEN
    RETURN json_build_object('success', false, 'error', 'too_many_recipients',
      'message', 'Maximum 256 recipients per broadcast.');
  END IF;

  FOR v_recipient IN SELECT * FROM jsonb_array_elements_text(v_list."memberUserIds") LOOP
    IF v_recipient = v_user_id THEN
      CONTINUE;  -- skip self
    END IF;

    -- Skip if the recipient has blocked the sender.
    IF EXISTS (
      SELECT 1 FROM "BlockedUser"
      WHERE "blockerId" = v_recipient AND "blockedId" = v_user_id
    ) THEN
      v_blocked := v_blocked + 1;
      INSERT INTO "BroadcastSend" ("id", "broadcastListId", "messageId", "recipientUserId", "status")
      VALUES ('bs_' || extract(epoch from now())::bigint::text || '_' || v_recipient, p_broadcast_list_id, '', v_recipient, 'blocked')
      ON CONFLICT DO NOTHING;
      CONTINUE;
    END IF;

    BEGIN
      v_new_id := 'dm_bcast_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6) || '_' || substring(v_recipient from 1 for 6);
      INSERT INTO "DirectMessage" (
        "id", "senderId", "receiverId",
        "content", "messageType",
        "isRead", "createdAt", "updatedAt"
      ) VALUES (
        v_new_id, v_user_id, v_recipient,
        p_content, p_message_type,
        false, now(), now()
      );

      INSERT INTO "BroadcastSend" ("id", "broadcastListId", "messageId", "recipientUserId", "status")
      VALUES ('bs_' || v_new_id, p_broadcast_list_id, v_new_id, v_recipient, 'sent')
      ON CONFLICT DO NOTHING;

      v_sent := v_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
    END;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'sent', v_sent,
    'blocked', v_blocked,
    'failed', v_failed,
    'total', v_sent + v_blocked + v_failed
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_broadcast(text, text, text) TO authenticated;

-- Verification
SELECT 'BroadcastList' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'BroadcastList') AS exists;
SELECT 'BroadcastSend' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'BroadcastSend') AS exists;
SELECT 'fn_send_broadcast' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_broadcast') AS exists;
