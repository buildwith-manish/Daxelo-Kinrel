-- ============================================================
-- Migration: 20261021100000_enforce_mentions_rpc.sql
-- Phase A follow-up — Task 2 of the pre-Phase-B review.
--
-- PROPOSAL — NOT APPLIED. Awaiting user approval.
-- (The existing migration 20261021051801_chat_mention_notify_and_group.sql
--  added the columns; this migration rewrites the RPC that the
--  Flutter app actually calls on every mention send.)
--
-- WHY THIS MIGRATION
--
-- The Flutter app's mention send path (chat_provider.dart
-- sendMessageWithMentions, lines 1499-1593) is:
--
--   1. INSERT INTO "ChatMessage"  -- direct Supabase insert (works)
--   2. SELECT fn_add_mentions_to_message(p_message_id, p_family_id, p_mentions)
--      -- Supabase RPC call
--
-- The current fn_add_mentions_to_message function (which EXISTS on the
-- live database — created outside the migration system, see Task 1
-- trace report) does:
--   • Validates sender = auth.uid() ✓
--   • Validates the message exists + senderId matches ✓
--   • Skips self-mentions ✓
--   • Skips mentions of non-family-members (defensive) ✓
--   • INSERTs into "ChatMention" with id, messageId, mentionedUserId,
--     mentionedByName, createdAt — but NOT the new Phase A columns
--     (groupId, notify, notifiedAt, isRead) ✗
--   • INSERTs into "Notification" with eventType='chat_mention',
--     channels='in_app,push', priority='high', body=
--     '<sender> mentioned you in the family chat' — but NOTHING
--     picks up that Notification row for an FCM push (no scheduler
--     scans Notification rows with channels='push') ✗
--
-- What's MISSING from the current function:
--   • Cap of 5 (loop inserts as many as it gets)
--   • Dedupe by userId (the ON CONFLICT on (messageId, mentionedUserId)
--     IS a dedupe, but only on those 2 columns — a single user
--     mentioned via 2 different @Name spans still gets 2 ChatMention
--     rows because the function generates a unique `id` per call).
--   • Group membership validation when the message's groupId is set
--     (only family membership is checked today).
--   • Notify derivation from the conversation type (always creates
--     ChatMention + Notification rows, even for DM third-person
--     references which should be notify=false per the spec).
--   • The new Phase A columns (groupId, notify, notifiedAt, isRead).
--   • A trigger for the new ChatMentionPushScheduler (NestJS) to
--     pick up the row for batched FCM push.
--
-- WHAT THIS MIGRATION DOES
--
--   1. CREATE OR REPLACE FUNCTION fn_add_mentions_to_message with:
--      • Hard cap at 5 mentions per message (rejects >5 with a
--        clear error message — the client also hard-stops at 5 but
--        the server rejects per the user's revised plan).
--      • Dedupe by userId (one ChatMention row per mentioned user,
--        even if they're mentioned via multiple @Name spans).
--      • Group membership validation when the message's groupId is
--        set (queries GroupMember). Rejects non-group-members with
--        an error (the Flutter side filters too, but the server
--        re-validates so a malicious client can't slip past).
--      • Notify derivation from the conversation type:
--          groupId IS NULL → family-wide chat → notify = true
--          groupId set, groupType = 'direct' → DM → notify = false
--                                            (no ChatMention row, no Notification)
--          groupId set, groupType != 'direct' → group chat → notify = true
--      • Writes the new Phase A columns (groupId, notify, notifiedAt
--        = NULL, isRead = false) on ChatMention rows.
--      • Still inserts into "Notification" with eventType='chat_mention'
--        for notify=true mentions — BUT now the row carries the
--        groupId too (in actionUrl) so the in-app banner can deep-
--        link to the right chat.
--      • Returns a JSON object with: success, mentionsCount, rejected
--        (list of rejected userIds + reasons), conversationType.
--
--   2. Adds a NOTIFY channel 'chat_mention_inserted' that fires on
--      ChatMention INSERT (with notify=true). The NestJS server can
--      LISTEN on this channel + call ChatMentionPushScheduler.enqueueMention.
--      (Alternative: a Supabase database webhook — but pg_notify is
--      simpler + doesn't require dashboard configuration.)
--
-- TRADE-OFF
--
--   Option A (this migration): rewrite the RPC. Keeps the Flutter app's
--     send path unchanged (still calls fn_add_mentions_to_message).
--     Enforcement is in the database layer ( SECURITY DEFINER RPC =
--     trusted code, can't be bypassed by a malicious client).
--     Downside: the RPC + the NestJS service now both enforce, with
--     slightly different code paths. Risk: drift over time.
--
--   Option B: route Flutter sends through the NestJS gateway (the
--     ChatGateway.handleSendMessageWithMentions socket event). The
--     NestJS ChatService.sendMessageWithMentions already enforces
--     everything correctly. Trade-offs:
--       + Single enforcement path (NestJS service).
--       + Easier to test (NestJS unit tests).
--       + Push trigger is straightforward (the service calls
--         ChatMentionPushScheduler.enqueueMention directly).
--       − Loses the Flutter app's offline-first / optimistic-UI flow
--         (the RPC path can survive a network blip because the
--         ChatMessage row is already persisted; the socket path
--         requires the gateway to be reachable).
--       − Requires changing chat_provider.dart's send path
--         (significant Flutter diff).
--       − Requires the NestJS gateway to be highly available
--         (currently a single instance).
--
--   RECOMMENDATION: Option A (this migration). Smaller change, keeps
--   the Flutter app's existing send path, and the database is the
--   natural enforcement layer for Supabase-direct clients. The NestJS
--   ChatService.sendMessageWithMentions is currently NOT on the live
--   Flutter path (it's only called from the NestJS socket gateway,
--   which the Flutter app doesn't use for sends) — it should either
--   be removed (dead code) or kept as a fallback for future non-
--   Flutter clients. Recommend KEEPING it (it's tested code, and a
--   future web client might use the socket path).
--
-- DEPLOY ORDER
--
--   1. Apply this migration on staging (Supabase Management API).
--   2. Smoke-test: send a mention via the Flutter app, verify:
--        • ChatMention row written with the new columns (groupId,
--          notify, notifiedAt=NULL, isRead=false).
--        • Notification row written with eventType='chat_mention'
--          and actionUrl includes the groupId.
--        • Cap-reject test: try to send 6 mentions, verify the RPC
--          returns success=false with an error.
--        • Non-member test: try to mention a non-family-member,
--          verify the RPC skips that mention (rejected list).
--        • DM test: send a mention in a direct chat, verify NO
--          ChatMention row is created (notify=false).
--   3. Apply on production.
--   4. Deploy the NestJS server (so the ChatMentionPushScheduler
--      can LISTEN on the pg_notify channel + push).
--   5. Deploy the Flutter app (no changes required — the RPC call
--      signature is unchanged).
-- ============================================================

-- Helper function: check if a user is a member of a group.
-- Reuses fn_user_can_access_group_chat (already exists, see Task 3
-- RLS audit) but with an explicit groupId arg.
-- (No new function needed — fn_user_can_access_group_chat already
--  does the right thing.)

-- Main rewrite of fn_add_mentions_to_message.
CREATE OR REPLACE FUNCTION fn_add_mentions_to_message(
  p_message_id text,
  p_family_id text,
  p_mentions jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sender_id text := auth.uid()::text;
  v_sender_name text;
  v_msg_sender_id text;
  v_msg_group_id text;
  v_group_type text;
  v_conversation_notify boolean := true;
  v_mention jsonb;
  v_mention_user_id text;
  v_mention_name text;
  v_mention_id text;
  v_notif_id text;
  v_inserted_count int := 0;
  v_rejected jsonb[] := ARRAY[]::jsonb[];
  v_seen_user_ids text[] := ARRAY[]::text[];
  v_total_mentions int := 0;
  v_mention_count int;
  v_is_family_member boolean;
  v_is_group_member boolean;
BEGIN
  IF v_sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- The message must exist AND be owned by the caller.
  SELECT "senderId", "groupId" INTO v_msg_sender_id, v_msg_group_id
  FROM "ChatMessage" WHERE "id" = p_message_id;
  IF v_msg_sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'message_not_found');
  END IF;
  IF v_msg_sender_id != v_sender_id THEN
    RETURN json_build_object('success', false, 'error', 'not_sender');
  END IF;

  -- Sender name (for the notification body).
  SELECT name INTO v_sender_name FROM "User" WHERE id = v_sender_id;
  IF v_sender_name IS NULL OR v_sender_name = '' THEN
    v_sender_name := 'Someone';
  END IF;

  -- Derive notify from the conversation type.
  IF v_msg_group_id IS NOT NULL THEN
    SELECT "groupType" INTO v_group_type FROM "Group" WHERE "id" = v_msg_group_id;
    IF v_group_type IS NULL THEN
      -- Group doesn't exist — reject (the message references a non-existent group).
      RETURN json_build_object(
        'success', false,
        'error', 'group_not_found',
        'groupId', v_msg_group_id
      );
    END IF;
    -- DM (direct chat) → notify=false (reference-only, no push, no ChatMention row).
    -- Group chat (custom groupType) → notify=true.
    v_conversation_notify := (v_group_type != 'direct');
  END IF;

  IF p_mentions IS NULL OR jsonb_array_length(p_mentions) = 0 THEN
    RETURN json_build_object('success', true, 'mentionsCount', 0, 'conversationNotify', v_conversation_notify);
  END IF;

  -- Count + cap at 5. The client is supposed to hard-stop at 5 too,
  -- but the server REJECTS >5 per the user's revised plan.
  v_total_mentions := jsonb_array_length(p_mentions);
  IF v_total_mentions > 5 THEN
    RETURN json_build_object(
      'success', false,
      'error', 'too_many_mentions',
      'message', 'Cannot mention more than 5 people in one message',
      'received', v_total_mentions,
      'cap', 5
    );
  END IF;

  -- If this is a DM (notify=false), skip ChatMention + Notification
  -- creation entirely. The mentions JSONB on the ChatMessage row
  -- still renders the @Name spans in the bubble, but no push fires,
  -- no @ badge data is written, no in-app banner appears.
  IF NOT v_conversation_notify THEN
    RETURN json_build_object(
      'success', true,
      'mentionsCount', 0,
      'conversationNotify', false,
      'note', 'DM reference — no ChatMention rows created, no push'
    );
  END IF;

  -- Loop through mentions + insert ChatMention + Notification rows.
  FOR v_mention IN SELECT * FROM jsonb_array_elements(p_mentions)
  LOOP
    v_mention_user_id := v_mention->>'userId';
    v_mention_name := v_mention->>'name';

    IF v_mention_user_id IS NULL OR v_mention_user_id = '' THEN
      v_rejected := array_append(v_rejected, jsonb_build_object(
        'userId', v_mention_user_id, 'reason', 'missing_user_id'
      ));
      CONTINUE;
    END IF;

    -- Skip self-mentions.
    IF v_mention_user_id = v_sender_id THEN
      v_rejected := array_append(v_rejected, jsonb_build_object(
        'userId', v_mention_user_id, 'reason', 'self_mention'
      ));
      CONTINUE;
    END IF;

    -- Dedupe by userId (one ChatMention row per user, even if mentioned
    -- via multiple @Name spans).
    IF v_mention_user_id = ANY(v_seen_user_ids) THEN
      v_rejected := array_append(v_rejected, jsonb_build_object(
        'userId', v_mention_user_id, 'reason', 'duplicate'
      ));
      CONTINUE;
    END IF;
    v_seen_user_ids := array_append(v_seen_user_ids, v_mention_user_id);

    -- Family membership check (always enforced).
    v_is_family_member := EXISTS (
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = p_family_id AND "userId" = v_mention_user_id
    );
    IF NOT v_is_family_member THEN
      v_rejected := array_append(v_rejected, jsonb_build_object(
        'userId', v_mention_user_id, 'reason', 'not_family_member'
      ));
      CONTINUE;
    END IF;

    -- Group membership check (when the message is in a group chat).
    IF v_msg_group_id IS NOT NULL THEN
      v_is_group_member := EXISTS (
        SELECT 1 FROM "GroupMember" gm
        JOIN "Group" g ON g.id = gm.groupId
        WHERE gm."groupId" = v_msg_group_id
          AND gm."userId" = v_mention_user_id
          AND g."groupType" != 'direct'
      );
      IF NOT v_is_group_member THEN
        v_rejected := array_append(v_rejected, jsonb_build_object(
          'userId', v_mention_user_id, 'reason', 'not_group_member'
        ));
        CONTINUE;
      END IF;
    END IF;

    -- Insert ChatMention row with the new Phase A columns.
    v_mention_id := 'ment_' || extract(epoch from now())::bigint::text
      || '_' || substring(p_message_id from 1 for 8)
      || '_' || substring(v_mention_user_id from 1 for 8);

    INSERT INTO "ChatMention" (
      "id", "messageId", "mentionedUserId", "mentionedByName",
      "groupId", "notify", "isRead", "createdAt"
    ) VALUES (
      v_mention_id, p_message_id, v_mention_user_id,
      COALESCE(v_mention_name, ''),
      v_msg_group_id, true, false, now()
    )
    ON CONFLICT ("messageId", "mentionedUserId") DO NOTHING;

    IF FOUND THEN
      v_inserted_count := v_inserted_count + 1;

      -- Insert Notification row (eventType='chat_mention', push channel).
      -- The NestJS ChatMentionPushScheduler scans for these rows OR
      -- listens on the pg_notify channel below.
      BEGIN
        v_notif_id := 'notif_mention_' || extract(epoch from now())::bigint::text
          || '_' || substring(v_mention_user_id from 1 for 8)
          || '_' || substring(p_message_id from 1 for 8);
        INSERT INTO "Notification" (
          "id", "userId", "eventType", "title", "body",
          "familyId", "channels", "priority", "read",
          "actionUrl", "createdAt", "updatedAt"
        ) VALUES (
          v_notif_id,
          v_mention_user_id,
          'chat_mention',
          'You were mentioned',
          v_sender_name || ' mentioned you in chat',
          p_family_id,
          'in_app,push',
          'high',
          false,
          'family:' || p_family_id || ':chat:' || p_message_id
            || (CASE WHEN v_msg_group_id IS NOT NULL THEN ':group:' || v_msg_group_id ELSE '' END),
          now(),
          now()
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;

      -- Notify the NestJS ChatMentionPushScheduler that a new mention
      -- row is ready for batched push. The scheduler LISTENs on this
      -- channel and calls enqueueMention(mention_id).
      -- Payload: the ChatMention.id (scheduler fetches the row by id).
      PERFORM pg_notify('chat_mention_inserted', v_mention_id);
    END IF;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'mentionsCount', v_inserted_count,
    'conversationNotify', v_conversation_notify,
    'rejected', v_rejected
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- Comment for discoverability.
COMMENT ON FUNCTION fn_add_mentions_to_message IS
  'Phase A — @mentions across chat. Validates sender = auth.uid(), '
  'caps at 5 mentions per message, dedupes by userId, validates family + '
  'group membership, derives notify from conversation type (group→true, '
  'DM→false — no ChatMention row for DM third-person references), writes '
  'the new Phase A columns (groupId, notify, notifiedAt, isRead). Fires '
  'pg_notify(''chat_mention_inserted'', mention_id) for each new row so '
  'the NestJS ChatMentionPushScheduler can pick it up. See '
  'docs/MENTIONS_DEPLOY.md for the deploy order.';
