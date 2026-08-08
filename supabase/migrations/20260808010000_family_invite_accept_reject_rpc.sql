-- =============================================================================
-- Daxelo Kinrel — Family Invite Accept/Reject RPCs + Duplicate Prevention
-- =============================================================================
-- Uses the CORRECT Notification table schema:
--   eventType (not "type"), read (not "isRead"), familyId (direct column),
--   actionUrl (for invite URL), no "data" JSON column.
-- FamilyMember table: id, familyId, userId, role, joinedAt
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. fn_send_family_invite_notification (UPDATED with duplicate check)
-- ═══════════════════════════════════════════════════════════════════════════

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
BEGIN
  -- Check if already a member
  SELECT id INTO v_already_member
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id AND "userId" = p_target_user_id
  LIMIT 1;

  IF v_already_member IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'already_member');
  END IF;

  -- Check for duplicate pending invite (read = false, eventType = family_invite, same family)
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

  -- Generate notification ID
  v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(p_target_user_id from 1 for 8);

  -- Insert the notification using the CORRECT schema
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
    p_invite_url,
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
-- 2. fn_accept_family_invite — accept + auto-add to FamilyMember
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

  -- Notify the inviter (best-effort)
  IF p_inviter_user_id IS NOT NULL AND p_inviter_user_id <> '' THEN
    BEGIN
      SELECT name INTO v_accepter_name FROM "User" WHERE id = v_user_id;
      IF v_accepter_name IS NULL THEN v_accepter_name := 'A user'; END IF;

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

  RETURN json_build_object('success', true, 'message', 'Joined ' || v_family_name);
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_accept_family_invite(text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_reject_family_invite — reject + mark notification read
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
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Mark the family_invite notification as read + update actionUrl to mark rejected
  UPDATE "Notification"
  SET "read" = true,
      "readAt" = now(),
      "actionUrl" = 'rejected:' || p_family_id,
      "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'family_invite'
    AND "familyId" = p_family_id
    AND "read" = false;

  -- Notify the inviter (best-effort)
  IF p_inviter_user_id IS NOT NULL AND p_inviter_user_id <> '' THEN
    BEGIN
      SELECT name INTO v_rejecter_name FROM "User" WHERE id = v_user_id;
      IF v_rejecter_name IS NULL THEN v_rejecter_name := 'A user'; END IF;

      SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
      IF v_family_name IS NULL THEN v_family_name := 'the family'; END IF;

      v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(p_inviter_user_id from 1 for 8);

      INSERT INTO "Notification" (
        "id", "userId", "eventType", "title", "body",
        "familyId", "channels", "priority", "read",
        "actionUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_notif_id,
        p_inviter_user_id,
        'invitation_rejected',
        'Invite Rejected',
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
-- 4. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'fn_accept_family_invite' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_accept_family_invite') AS exists;
SELECT 'fn_reject_family_invite' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_reject_family_invite') AS exists;
SELECT 'fn_send_family_invite_notification' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_family_invite_notification') AS exists;
