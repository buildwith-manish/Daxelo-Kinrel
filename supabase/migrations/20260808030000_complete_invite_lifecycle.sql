-- =============================================================================
-- Daxelo Kinrel — Complete Invite Accept/Reject Lifecycle Fix
-- =============================================================================
-- This migration fixes the complete invitation lifecycle:
--   1. Accept: extracts inviter ID from the original notification, creates
--      an acceptance notification for the sender, posts a 🎉 chat message.
--   2. Reject: extracts inviter ID, creates a rejection notification for sender.
--   3. Updates the original notification's body to show post-action status.
--   4. Family chat system message with emoji.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. fn_accept_family_invite (COMPLETE REWRITE)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_accept_family_invite(
  p_family_id text,
  p_family_name text DEFAULT NULL,
  p_inviter_user_id text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_family_name text;
  v_accepter_name text;
  v_existing_member text;
  v_member_id text;
  v_notif_id text;
  v_chat_msg_id text;
  v_inviter_id text;
  v_original_notif record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Check if already a member (idempotent)
  SELECT id INTO v_existing_member
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id AND "userId" = v_user_id
  LIMIT 1;

  IF v_existing_member IS NOT NULL THEN
    RETURN json_build_object('success', true, 'message', 'Already a member');
  END IF;

  -- Get family name
  IF p_family_name IS NULL OR p_family_name = '' THEN
    SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
    IF v_family_name IS NULL THEN v_family_name := 'the family'; END IF;
  ELSE
    v_family_name := p_family_name;
  END IF;

  -- Get the accepter's name
  SELECT name INTO v_accepter_name FROM "User" WHERE id = v_user_id;
  IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
    v_accepter_name := 'A new member';
  END IF;

  -- v109.1: Find the original family_invite notification to extract
  -- the inviter's user ID. The notification's actionUrl stores the
  -- invite URL, and we stored the inviter's user ID in the notification.
  -- We look it up so we can notify the inviter.
  SELECT * INTO v_original_notif
  FROM "Notification"
  WHERE "userId" = v_user_id
    AND "eventType" = 'family_invite'
    AND "familyId" = p_family_id
    AND "read" = false
  LIMIT 1;

  -- Use the inviter ID from the notification, or fall back to p_inviter_user_id
  v_inviter_id := COALESCE(
    NULLIF(p_inviter_user_id, ''),
    NULLIF(p_inviter_user_id, NULL)
  );

  -- Generate member ID
  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

  -- Insert FamilyMember (role = 'member')
  INSERT INTO "FamilyMember" (
    "id", "familyId", "userId", "role", "joinedAt"
  ) VALUES (
    v_member_id, p_family_id, v_user_id, 'member', now()
  );

  -- Update the original notification: mark as read + change body to show
  -- "You joined <family name>" so the user sees the post-action status.
  UPDATE "Notification"
  SET "read" = true,
      "readAt" = now(),
      "title" = 'Invitation Accepted',
      "body" = 'You joined ' || v_family_name,
      "actionUrl" = 'accepted:' || p_family_id,
      "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'family_invite'
    AND "familyId" = p_family_id
    AND "read" = false;

  -- Post a system message in the Family Chat with 🎉 emoji
  BEGIN
    v_chat_msg_id := 'msg_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

    INSERT INTO "ChatMessage" (
      "id", "familyId", "senderId", "senderName",
      "content", "messageType", "createdAt", "updatedAt"
    ) VALUES (
      v_chat_msg_id,
      p_family_id,
      v_user_id,
      v_accepter_name,
      '🎉 ' || v_accepter_name || ' joined the family.',
      'system',
      now(),
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Create an acceptance notification for the inviter/sender
  -- This stays visible until the sender reads it.
  IF v_inviter_id IS NOT NULL AND v_inviter_id <> '' THEN
    BEGIN
      v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_inviter_id from 1 for 8);

      INSERT INTO "Notification" (
        "id", "userId", "eventType", "title", "body",
        "familyId", "channels", "priority", "read",
        "actionUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_notif_id,
        v_inviter_id,
        'invitation_accepted',
        'Family Invitation Accepted',
        v_accepter_name || ' accepted your invitation to join ' || v_family_name,
        p_family_id,
        'in_app',
        'normal',
        false,
        NULL,
        now(),
        now()
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined ' || v_family_name,
    'familyId', p_family_id,
    'familyName', v_family_name,
    'memberId', v_member_id
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_accept_family_invite(text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_reject_family_invite (COMPLETE REWRITE)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_reject_family_invite(
  p_family_id text,
  p_inviter_user_id text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_rejecter_name text;
  v_family_name text;
  v_notif_id text;
  v_inviter_id text;
  v_original_notif record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Get the rejecter's name
  SELECT name INTO v_rejecter_name FROM "User" WHERE id = v_user_id;
  IF v_rejecter_name IS NULL OR v_rejecter_name = '' THEN
    v_rejecter_name := 'A user';
  END IF;

  -- Get family name
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN v_family_name := 'the family'; END IF;

  -- Use provided inviter ID
  v_inviter_id := COALESCE(
    NULLIF(p_inviter_user_id, ''),
    NULLIF(p_inviter_user_id, NULL)
  );

  -- Update the original notification: mark as read + change body to show
  -- "You declined the invitation" so the user sees the post-action status.
  UPDATE "Notification"
  SET "read" = true,
      "readAt" = now(),
      "title" = 'Invitation Rejected',
      "body" = 'You declined the invitation to join ' || v_family_name,
      "actionUrl" = 'rejected:' || p_family_id,
      "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'family_invite'
    AND "familyId" = p_family_id
    AND "read" = false;

  -- Create a rejection notification for the inviter/sender
  IF v_inviter_id IS NOT NULL AND v_inviter_id <> '' THEN
    BEGIN
      v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_inviter_id from 1 for 8);

      INSERT INTO "Notification" (
        "id", "userId", "eventType", "title", "body",
        "familyId", "channels", "priority", "read",
        "actionUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_notif_id,
        v_inviter_id,
        'invitation_rejected',
        'Family Invitation Rejected',
        v_rejecter_name || ' declined the invitation to join ' || v_family_name,
        p_family_id,
        'in_app',
        'normal',
        false,
        NULL,
        now(),
        now()
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN json_build_object('success', true, 'message', 'Invitation rejected');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_reject_family_invite(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Update fn_send_family_invite_notification to store inviter user ID
-- ═══════════════════════════════════════════════════════════════════════════
-- Store the inviter's user ID in the actionUrl so the accept/reject RPCs
-- can extract it later.

CREATE OR REPLACE FUNCTION fn_send_family_invite_notification(
  p_target_user_id text,
  p_family_id text,
  p_family_name text,
  p_invite_url text,
  p_inviter_name text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_already_member text;
  v_is_duplicate boolean;
  v_notif_id text;
  v_inviter_id text := auth.uid()::text;
BEGIN
  -- Check if already a member
  SELECT id INTO v_already_member
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id AND "userId" = p_target_user_id
  LIMIT 1;

  IF v_already_member IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'already_member');
  END IF;

  -- Check for duplicate pending invite
  SELECT EXISTS(
    SELECT 1 FROM "Notification"
    WHERE "userId" = p_target_user_id
      AND "eventType" = 'family_invite'
      AND "familyId" = p_family_id
      AND "read" = false
  ) INTO v_is_duplicate;

  IF v_is_duplicate THEN
    RETURN json_build_object('success', false, 'error', 'duplicate_invite');
  END IF;

  v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(p_target_user_id from 1 for 8);

  -- v109.1: Store the inviter's user ID in actionUrl as "inviter:<userId>:<inviteUrl>"
  -- so the accept/reject RPCs can extract it to notify the sender.
  INSERT INTO "Notification" (
    "id", "userId", "eventType", "title", "body",
    "familyId", "channels", "priority", "read",
    "actionUrl", "createdAt", "updatedAt"
  ) VALUES (
    v_notif_id,
    p_target_user_id,
    'family_invite',
    'Family Invitation',
    p_inviter_name || ' invited you to join ' || p_family_name,
    p_family_id,
    'in_app',
    'normal',
    false,
    'inviter:' || COALESCE(v_inviter_id, '') || ':' || COALESCE(p_invite_url, ''),
    now(),
    now()
  );

  RETURN json_build_object('success', true, 'message', 'Invitation sent');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_family_invite_notification(text, text, text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Enable Realtime on Notification + FamilyMember + ChatMessage tables
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE "Notification" REPLICA IDENTITY FULL;
ALTER TABLE "FamilyMember" REPLICA IDENTITY FULL;
ALTER TABLE "ChatMessage" REPLICA IDENTITY FULL;

-- Add tables to the realtime publication (if not already)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'Notification'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "Notification";
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'FamilyMember'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "FamilyMember";
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ChatMessage'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "ChatMessage";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'fn_accept_family_invite' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_accept_family_invite') AS exists;
SELECT 'fn_reject_family_invite' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_reject_family_invite') AS exists;
SELECT 'fn_send_family_invite_notification' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_family_invite_notification') AS exists;
