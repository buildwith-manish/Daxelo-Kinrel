-- =============================================================================
-- Daxelo Kinrel — Tier 1 Feature 1.2: Message Scheduling (send later)
-- =============================================================================
-- Lets a user compose a message now and have the server deliver it at a
-- future timestamp. Works for both family-group chat (familyId set,
-- receiverId null) and DM (receiverId set, familyId null).
--
-- Schema:
--   • ScheduledMessage table — id, senderId, familyId, receiverId, content,
--     messageType, mediaUrl, mediaType, mentions, replyToId, scheduledFor,
--     status (pending|sent|cancelled|failed), sentMessageId (the actual
--     ChatMessage/DirectMessage id once we deliver), createdAt, sentAt.
--   • RLS: only the sender can SELECT/INSERT/UPDATE their own rows.
--
-- Cron:
--   A nightly pg_cron job (every minute — not nightly) picks up rows where
--   status = 'pending' AND scheduledFor <= now() and delivers them via
--   fn_send_scheduled_message. The function itself calls the existing
--   fn_chatmessage_gen_id / DM insert pattern.
--
-- Idempotent.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. ScheduledMessage table
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS "ScheduledMessage" (
  "id"              text PRIMARY KEY,
  "senderId"        text NOT NULL,
  "familyId"        text,                          -- null when this is a DM
  "receiverId"      text,                          -- null when this is a family-group message
  "content"         text NOT NULL DEFAULT '',
  "messageType"     text NOT NULL DEFAULT 'text',
  "mediaUrl"        text,
  "mediaType"       text,
  "mentions"        jsonb NOT NULL DEFAULT '[]'::jsonb,
  "replyToId"       text,
  "scheduledFor"    timestamptz NOT NULL,
  "status"          text NOT NULL DEFAULT 'pending',  -- pending | sent | cancelled | failed
  "sentMessageId"   text,                           -- the ChatMessage/DirectMessage id once delivered
  "failureReason"   text,
  "createdAt"       timestamptz NOT NULL DEFAULT now(),
  "sentAt"          timestamptz,
  "updatedAt"       timestamptz NOT NULL DEFAULT now(),
  -- Constraint: a scheduled message must target EITHER a family chat OR a DM.
  CONSTRAINT "sm_target_chk" CHECK (
    ("familyId" IS NOT NULL AND "receiverId" IS NULL) OR
    ("familyId" IS NULL AND "receiverId" IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS "SM_sender_idx"          ON "ScheduledMessage"("senderId");
CREATE INDEX IF NOT EXISTS "SM_pending_due_idx"     ON "ScheduledMessage"("scheduledFor")
  WHERE "status" = 'pending';
CREATE INDEX IF NOT EXISTS "SM_family_idx"          ON "ScheduledMessage"("familyId");
CREATE INDEX IF NOT EXISTS "SM_receiver_idx"        ON "ScheduledMessage"("receiverId");

ALTER TABLE "ScheduledMessage" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "SM select own" ON "ScheduledMessage";
CREATE POLICY "SM select own" ON "ScheduledMessage"
  FOR SELECT TO authenticated USING ("senderId" = auth.uid()::text);

DROP POLICY IF EXISTS "SM insert own" ON "ScheduledMessage";
CREATE POLICY "SM insert own" ON "ScheduledMessage"
  FOR INSERT TO authenticated WITH CHECK ("senderId" = auth.uid()::text);

DROP POLICY IF EXISTS "SM update own" ON "ScheduledMessage";
CREATE POLICY "SM update own" ON "ScheduledMessage"
  FOR UPDATE TO authenticated USING ("senderId" = auth.uid()::text);

DROP POLICY IF EXISTS "SM delete own" ON "ScheduledMessage";
CREATE POLICY "SM delete own" ON "ScheduledMessage"
  FOR DELETE TO authenticated USING ("senderId" = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_schedule_message — insert a scheduled send
--    Caller must be a member of the family (for family messages) OR
--    must be the sender themselves (for DMs — we don't validate DM
--    blocking here; that's checked at delivery time).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_schedule_message(
  p_family_id text,
  p_receiver_id text,
  p_content text,
  p_scheduled_for timestamptz,
  p_message_type text DEFAULT 'text',
  p_media_url text DEFAULT NULL,
  p_media_type text DEFAULT NULL,
  p_mentions jsonb DEFAULT '[]'::jsonb,
  p_reply_to_id text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_now timestamptz := now();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Must target exactly one of family / DM.
  IF (p_family_id IS NULL) = (p_receiver_id IS NULL) THEN
    RETURN json_build_object('success', false, 'error', 'invalid_target',
      'message', 'Pass exactly one of familyId or receiverId.');
  END IF;

  -- Scheduled time must be in the future (at least 1 minute from now).
  IF p_scheduled_for <= v_now + interval '1 minute' THEN
    RETURN json_build_object('success', false, 'error', 'invalid_schedule_time',
      'message', 'Scheduled time must be at least 1 minute in the future.');
  END IF;

  -- For family messages: caller must be a member.
  IF p_family_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = p_family_id AND "userId" = v_user_id
    ) THEN
      RETURN json_build_object('success', false, 'error', 'not_in_family');
    END IF;
  END IF;

  -- For DMs: receiverId must not equal senderId (use Saved Messages for
  -- scheduling notes to yourself — different table-level constraint).
  IF p_receiver_id IS NOT NULL AND p_receiver_id = v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'self_dm_not_supported_via_schedule',
      'message', 'Use Saved Messages instead of scheduling a self-DM.');
  END IF;

  v_id := 'sm_' || extract(epoch from v_now)::bigint::text || '_' || substring(v_user_id from 1 for 8);

  INSERT INTO "ScheduledMessage" (
    "id", "senderId", "familyId", "receiverId",
    "content", "messageType", "mediaUrl", "mediaType",
    "mentions", "replyToId",
    "scheduledFor", "status",
    "createdAt", "updatedAt"
  ) VALUES (
    v_id, v_user_id, p_family_id, p_receiver_id,
    p_content, p_message_type, p_media_url, p_media_type,
    p_mentions, p_reply_to_id,
    p_scheduled_for, 'pending',
    v_now, v_now
  );

  RETURN json_build_object(
    'success', true,
    'scheduledMessageId', v_id,
    'scheduledFor', to_char(p_scheduled_for AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'status', 'pending'
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_schedule_message(
  text, text, text, timestamptz, text, text, text, jsonb, text
) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_cancel_scheduled_message — caller-owned cancel
--    Only pending rows can be cancelled. Sent/failed are immutable.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_cancel_scheduled_message(p_scheduled_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_row record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_row FROM "ScheduledMessage" WHERE "id" = p_scheduled_id;
  IF v_row IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_row."senderId" <> v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'not_owner');
  END IF;
  IF v_row."status" <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'not_pending',
      'message', 'Only pending scheduled messages can be cancelled.');
  END IF;

  UPDATE "ScheduledMessage"
    SET "status" = 'cancelled', "updatedAt" = now()
    WHERE "id" = p_scheduled_id;

  RETURN json_build_object('success', true, 'scheduledMessageId', p_scheduled_id, 'status', 'cancelled');
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cancel_scheduled_message(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. fn_get_scheduled_messages — list caller's pending scheduled sends
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_scheduled_messages()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', s."id",
      'familyId', s."familyId",
      'receiverId', s."receiverId",
      'content', s."content",
      'messageType', s."messageType",
      'mediaUrl', s."mediaUrl",
      'mentions', s."mentions",
      'replyToId', s."replyToId",
      'scheduledFor', to_char(s."scheduledFor" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'status', s."status",
      'createdAt', to_char(s."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    ) ORDER BY s."scheduledFor" ASC)
    FROM "ScheduledMessage" s
    WHERE s."senderId" = v_user_id
      AND s."status" IN ('pending', 'failed')
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_scheduled_messages() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. fn_send_scheduled_messages — the per-minute cron dispatcher.
--    Picks up all pending rows due now, dispatches them by writing the
--    actual ChatMessage / DirectMessage row, and updates the scheduled
--    row to 'sent' (or 'failed' with a reason).
--
--    The NestJS server (chat-push.scheduler.ts) calls this every minute.
--    It is SECURITY DEFINER so the cron process doesn't need any
--    particular user identity.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_send_scheduled_messages(
  p_limit int DEFAULT 50
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_sent int := 0;
  v_failed int := 0;
  v_new_id text;
  v_sender_name text;
  v_sender_initials text;
  v_name_parts text[];
  v_receiver_blocked boolean := false;
BEGIN
  FOR v_row IN
    SELECT * FROM "ScheduledMessage"
    WHERE "status" = 'pending' AND "scheduledFor" <= now()
    ORDER BY "scheduledFor" ASC
    LIMIT p_limit
  LOOP
    BEGIN
      -- Resolve sender display name + initials.
      SELECT name INTO v_sender_name FROM "User" WHERE id = v_row."senderId";
      IF v_sender_name IS NULL OR v_sender_name = '' THEN
        v_sender_name := 'Someone';
      END IF;
      v_name_parts := regexp_split_to_array(v_sender_name, '\s+');
      IF array_length(v_name_parts, 1) >= 2 AND v_name_parts[2] <> '' THEN
        v_sender_initials := UPPER(SUBSTRING(v_name_parts[1] FROM 1 FOR 1)
                                  || SUBSTRING(v_name_parts[2] FROM 1 FOR 1));
      ELSE
        v_sender_initials := UPPER(SUBSTRING(v_name_parts[1] FROM 1 FOR 1));
      END IF;

      IF v_row."familyId" IS NOT NULL THEN
        -- ── Family group chat delivery ──
        -- Re-check membership (user may have left between schedule and fire).
        IF NOT EXISTS (
          SELECT 1 FROM "FamilyMember"
          WHERE "familyId" = v_row."familyId" AND "userId" = v_row."senderId"
        ) THEN
          UPDATE "ScheduledMessage"
            SET "status" = 'failed', "failureReason" = 'sender_no_longer_member',
                "updatedAt" = now()
            WHERE "id" = v_row."id";
          v_failed := v_failed + 1;
          CONTINUE;
        END IF;

        v_new_id := 'cm_sched_' || extract(epoch from now())::bigint::text || '_' || substring(v_row."id" from 1 for 12);

        INSERT INTO "ChatMessage" (
          "id", "familyId",
          "senderId", "senderName", "senderInitials",
          "content", "messageType",
          "mediaUrl", "mediaType",
          "replyToId",
          "mentions",
          "messageStatus",
          "createdAt", "updatedAt"
        ) VALUES (
          v_new_id, v_row."familyId",
          v_row."senderId", v_sender_name, v_sender_initials,
          v_row."content", v_row."messageType",
          v_row."mediaUrl", v_row."mediaType",
          v_row."replyToId",
          v_row."mentions",
          'sent',
          now(), now()
        );

        UPDATE "ScheduledMessage"
          SET "status" = 'sent', "sentMessageId" = v_new_id, "sentAt" = now(), "updatedAt" = now()
          WHERE "id" = v_row."id";
        v_sent := v_sent + 1;

      ELSIF v_row."receiverId" IS NOT NULL THEN
        -- ── Direct Message delivery ──
        -- Check the receiver hasn't blocked the sender. Skip silently
        -- if blocked (this matches WhatsApp: scheduled message just
        -- disappears without an error notification to the sender — they
        -- already left the chat).
        SELECT EXISTS(
          SELECT 1 FROM "BlockedUser"
          WHERE "blockerId" = v_row."receiverId" AND "blockedId" = v_row."senderId"
        ) INTO v_receiver_blocked;

        IF v_receiver_blocked THEN
          UPDATE "ScheduledMessage"
            SET "status" = 'failed', "failureReason" = 'receiver_blocked_sender',
                "updatedAt" = now()
            WHERE "id" = v_row."id";
          v_failed := v_failed + 1;
          CONTINUE;
        END IF;

        v_new_id := 'dm_sched_' || extract(epoch from now())::bigint::text || '_' || substring(v_row."id" from 1 for 12);

        INSERT INTO "DirectMessage" (
          "id", "senderId", "receiverId",
          "content", "messageType",
          "isRead",
          "createdAt", "updatedAt"
        ) VALUES (
          v_new_id, v_row."senderId", v_row."receiverId",
          v_row."content", v_row."messageType",
          false,
          now(), now()
        );

        UPDATE "ScheduledMessage"
          SET "status" = 'sent', "sentMessageId" = v_new_id, "sentAt" = now(), "updatedAt" = now()
          WHERE "id" = v_row."id";
        v_sent := v_sent + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      UPDATE "ScheduledMessage"
        SET "status" = 'failed', "failureReason" = SQLERRM, "updatedAt" = now()
        WHERE "id" = v_row."id";
      v_failed := v_failed + 1;
    END;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'sent', v_sent,
    'failed', v_failed,
    'processed', v_sent + v_failed
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_scheduled_messages(int) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Realtime publication (so the sender's other devices see a scheduled
--    row appear / disappear live).
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE "ScheduledMessage" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ScheduledMessage'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "ScheduledMessage";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. Schedule the per-minute cron dispatcher.
--    The server also calls fn_send_scheduled_messages on startup + every
--    minute via NestJS @Cron — this is the DB-side fallback that fires
--    even if the NestJS instance is briefly down (Supabase's pg_cron runs
--    independently).
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_job_name text := 'send-scheduled-messages';
  v_existing bigint;
BEGIN
  SELECT jobid INTO v_existing FROM cron.job WHERE jobname = v_job_name;
  IF v_existing IS NULL THEN
    PERFORM cron.schedule(
      v_job_name,
      '* * * * *',
      'SELECT fn_send_scheduled_messages(50);'
    );
    RAISE NOTICE 'Scheduled cron job %', v_job_name;
  ELSE
    RAISE NOTICE 'Cron job % already scheduled (jobid=%)', v_job_name, v_existing;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Cron schedule skipped: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. Verification
-- ═══════════════════════════════════════════════════════════════════════════
SELECT 'ScheduledMessage' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ScheduledMessage') AS exists;
SELECT 'fn_schedule_message' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_schedule_message') AS exists;
SELECT 'fn_cancel_scheduled_message' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_cancel_scheduled_message') AS exists;
SELECT 'fn_get_scheduled_messages' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_scheduled_messages') AS exists;
SELECT 'fn_send_scheduled_messages' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_scheduled_messages') AS exists;
SELECT 'cron job' AS obj,
       EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'send-scheduled-messages') AS exists;
