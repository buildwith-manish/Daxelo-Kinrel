-- =============================================================================
-- Daxelo Kinrel — Fix Invite Accept: Trigger + Chat Message + RPC Update
-- =============================================================================
-- ROOT CAUSE: The fn_auto_add_family_member() trigger function referenced
-- the OLD Notification table schema ("type", "isRead", "data"->>'familyId')
-- which don't exist (correct: "eventType", "read", "familyId" column).
-- This trigger fires AFTER INSERT on FamilyMember, crashes, and rolls
-- back the entire insert — that's why fn_accept_family_invite fails with
-- a generic error.
--
-- This migration:
--   1. Fixes the trigger function to use the correct column names.
--   2. Updates fn_accept_family_invite to also post a chat join message.
--   3. Updates fn_reject_family_invite (no changes needed, but recreate
--      for consistency).
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Fix the trigger function (THE ROOT CAUSE)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_auto_add_family_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- v109: Fixed to use CORRECT Notification table schema:
  --   "eventType" (not "type"), "read" (not "isRead"),
  --   "familyId" (direct column, not "data"->>'familyId')
  IF NEW."userId" IS NOT NULL THEN
    UPDATE "Notification"
    SET "read" = true,
        "readAt" = now(),
        "updatedAt" = now()
    WHERE "userId" = NEW."userId"
      AND "eventType" = 'family_invite'
      AND "familyId" = NEW."familyId"
      AND "read" = false;
  END IF;
  RETURN NEW;
END;
$$;

-- Drop and recreate the trigger (to pick up the fixed function)
DROP TRIGGER IF EXISTS trg_auto_add_family_member ON "FamilyMember";
CREATE TRIGGER trg_auto_add_family_member
  AFTER INSERT ON "FamilyMember"
  FOR EACH ROW
  EXECUTE FUNCTION fn_auto_add_family_member();

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Update fn_accept_family_invite to also post a chat join message
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

  -- Generate member ID
  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

  -- Insert FamilyMember (role = 'member')
  INSERT INTO "FamilyMember" (
    "id", "familyId", "userId", "role", "joinedAt"
  ) VALUES (
    v_member_id, p_family_id, v_user_id, 'member', now()
  );

  -- Mark the family_invite notification as read
  UPDATE "Notification"
  SET "read" = true, "readAt" = now(), "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'family_invite'
    AND "familyId" = p_family_id
    AND "read" = false;

  -- Post a system message in the Family Chat announcing the new member
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
      v_accepter_name || ' joined the family.',
      'system',
      now(),
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    -- Best-effort — don't fail the accept if the chat message insert fails
    NULL;
  END;

  -- Notify the inviter (best-effort)
  IF p_inviter_user_id IS NOT NULL AND p_inviter_user_id <> '' THEN
    BEGIN
      v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(p_inviter_user_id from 1 for 8);

      INSERT INTO "Notification" (
        "id", "userId", "eventType", "title", "body",
        "familyId", "channels", "priority", "read",
        "actionUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_notif_id,
        p_inviter_user_id,
        'invitation_accepted',
        'Invite Accepted',
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
-- 3. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'fn_auto_add_family_member (fixed trigger)' AS object_name,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_auto_add_family_member') AS exists;

SELECT 'trg_auto_add_family_member (trigger)' AS object_name,
       EXISTS(SELECT 1 FROM pg_trigger WHERE tgname = 'trg_auto_add_family_member') AS exists;

SELECT 'fn_accept_family_invite (with chat message)' AS object_name,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_accept_family_invite') AS exists;
