-- =============================================================================
-- Daxelo Kinrel — Fix RECORD field case sensitivity (v5.96)
-- =============================================================================
--
-- PROBLEM:
-- All three graph invitation RPCs that use `SELECT * INTO v_invitation`
-- (fn_accept_graph_invitation, fn_decline_graph_invitation,
-- fn_cancel_graph_invitation, fn_resend_graph_invitation) fail with
-- errors like:
--   record "v_invitation" has no field "inviteruserid"
--   record "v_invitation" has no field "expiresat"
--   record "v_invitation" has no field "recipientemail"
--
-- ROOT CAUSE:
-- When `SELECT * INTO v_invitation FROM "GraphPendingInvitation"` populates
-- a RECORD, the field names match the table's quoted column names (camelCase:
-- "inviterUserId", "expiresAt", "recipientEmail", etc.). But when PL/pgSQL
-- parses `v_invitation.inviterUserId`, it LOWERCASES the identifier to
-- `inviteruserid` — which doesn't match the camelCase field name in the RECORD.
--
-- FIX:
-- Quote all camelCase RECORD field accesses: v_invitation."inviterUserId"
-- instead of v_invitation.inviterUserId.
--
-- This migration CREATE OR REPLACEs all four functions with the fix.
-- The function logic is otherwise IDENTICAL to the previous versions.
-- =============================================================================

-- ── 1. Fixed fn_accept_graph_invitation ────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_accept_graph_invitation(
  p_invitation_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_invitation RECORD;
  v_accepter_name text;
  v_user_gender text;
  v_user_avatar text;
  v_person_id text;
  v_member_id text;
  v_relationship_id text;
  v_inverse_relationship_id text;
  v_inverse_key text;
  v_has_known_inverse boolean;
  v_existing_person text;
  v_existing_member text;
  v_chat_msg_id text;
  v_notif_id text;
  v_target_name text;
  v_family_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Invitation not found');
  END IF;

  IF v_invitation."status" <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'invitation_not_pending');
  END IF;

  IF v_invitation."expiresAt" < now() THEN
    UPDATE "GraphPendingInvitation"
    SET status = 'expired', "updatedAt" = now()
    WHERE id = p_invitation_id;
    RETURN json_build_object('success', false, 'error', 'invitation_expired');
  END IF;

  IF v_invitation."recipientUserId" IS NOT NULL
     AND v_invitation."recipientUserId" <> ''
     AND v_invitation."recipientUserId" <> v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'not_authorized',
      'message', 'This invitation was sent to a different user');
  END IF;

  SELECT id INTO v_existing_member
  FROM "FamilyMember"
  WHERE "familyId" = v_invitation."familyId" AND "userId" = v_user_id
  LIMIT 1;

  IF v_existing_member IS NOT NULL THEN
    RETURN json_build_object('success', true, 'message', 'Already a member');
  END IF;

  SELECT name, gender, "avatarUrl" INTO v_accepter_name, v_user_gender, v_user_avatar
  FROM "User" WHERE id = v_user_id;
  IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
    v_accepter_name := v_invitation."recipientName";
  END IF;
  IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
    v_accepter_name := 'A new member';
  END IF;

  SELECT name INTO v_family_name FROM "Family" WHERE id = v_invitation."familyId" LIMIT 1;
  SELECT name INTO v_target_name FROM "Person" WHERE id = v_invitation."targetPersonId" LIMIT 1;

  SELECT id INTO v_existing_person
  FROM "Person"
  WHERE "familyId" = v_invitation."familyId" AND "linkedUserId" = v_user_id::uuid
  LIMIT 1;

  IF v_existing_person IS NULL THEN
    SELECT id INTO v_existing_person
    FROM "Person"
    WHERE "linkedUserId" = v_user_id::uuid
    LIMIT 1;

    IF v_existing_person IS NULL THEN
      v_person_id := 'person_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

      INSERT INTO "Person" (
        "id", "familyId", "name", "gender",
        "isAnchor", "generationIndex", "privacyLevel",
        "linkedUserId", "linkedAt",
        "photoUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_person_id,
        v_invitation."familyId",
        v_accepter_name,
        v_user_gender,
        false, 0, 'family',
        v_user_id::uuid, now(),
        v_user_avatar, now(), now()
      );
    ELSE
      v_person_id := 'person_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
      INSERT INTO "Person" (
        "id", "familyId", "name", "gender",
        "isAnchor", "generationIndex", "privacyLevel",
        "linkedUserId", "linkedAt",
        "photoUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_person_id,
        v_invitation."familyId",
        v_accepter_name,
        v_user_gender,
        false, 0, 'family',
        v_user_id::uuid, now(),
        v_user_avatar, now(), now()
      );
    END IF;
  ELSE
    v_person_id := v_existing_person;
  END IF;

  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "FamilyMember" ("id", "familyId", "userId", "role", "joinedAt")
  VALUES (v_member_id, v_invitation."familyId", v_user_id, 'member', now());

  v_relationship_id := 'rel_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "Relationship" (
    "id", "familyId", "fromPersonId", "toPersonId",
    "relationshipKey", "relationshipType", "labelAtoB",
    "direction", "isActive", "createdAt", "updatedAt"
  ) VALUES (
    v_relationship_id, v_invitation."familyId",
    v_invitation."targetPersonId", v_person_id,
    v_invitation."relationshipKey", v_invitation."relationshipKey",
    v_invitation."specificLabelAtoB",
    'from', true, now(), now()
  );

  v_inverse_key := CASE
    WHEN v_invitation."specificLabelAtoB" IN ('father', 'mother', 'parent') THEN
      CASE WHEN v_user_gender = 'female' THEN 'daughter' ELSE 'son' END
    WHEN v_invitation."specificLabelAtoB" IN ('son', 'daughter', 'child') THEN
      CASE WHEN v_user_gender = 'female' THEN 'mother' ELSE 'father' END
    WHEN v_invitation."specificLabelAtoB" IN ('husband', 'wife', 'spouse') THEN
      v_invitation."specificLabelAtoB"
    WHEN v_invitation."specificLabelAtoB" IN ('brother', 'sister', 'sibling') THEN
      CASE WHEN v_user_gender = 'female' THEN 'sister' ELSE 'brother' END
    WHEN v_invitation."specificLabelAtoB" IN ('grandfather', 'grandmother') THEN
      CASE WHEN v_user_gender = 'female' THEN 'granddaughter' ELSE 'grandson' END
    WHEN v_invitation."specificLabelAtoB" IN ('grandson', 'granddaughter') THEN
      CASE WHEN v_user_gender = 'female' THEN 'grandmother' ELSE 'grandfather' END
    WHEN v_invitation."specificLabelAtoB" IN ('uncle', 'aunt') THEN
      CASE WHEN v_user_gender = 'female' THEN 'niece' ELSE 'nephew' END
    WHEN v_invitation."specificLabelAtoB" IN ('nephew', 'niece') THEN
      CASE WHEN v_user_gender = 'female' THEN 'aunt' ELSE 'uncle' END
    ELSE NULL
  END;

  v_has_known_inverse := v_inverse_key IS NOT NULL
    AND v_inverse_key <> v_invitation."specificLabelAtoB"
    AND v_inverse_key NOT IN ('husband', 'wife', 'spouse');

  IF v_has_known_inverse THEN
    BEGIN
      v_inverse_relationship_id := 'rel_inv_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
      INSERT INTO "Relationship" (
        "id", "familyId", "fromPersonId", "toPersonId",
        "relationshipKey", "relationshipType", "labelAtoB",
        "direction", "isActive", "createdAt", "updatedAt"
      ) VALUES (
        v_inverse_relationship_id, v_invitation."familyId",
        v_person_id, v_invitation."targetPersonId",
        v_invitation."relationshipKey", v_invitation."relationshipKey",
        v_inverse_key, 'inverse', true, now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      v_inverse_relationship_id := NULL;
    END;
  END IF;

  UPDATE "GraphPendingInvitation"
  SET status = 'accepted', "acceptedAt" = now(),
      "acceptedByUserId" = v_user_id,
      "createdPersonId" = v_person_id,
      "createdRelationshipId" = v_relationship_id,
      "updatedAt" = now()
  WHERE id = p_invitation_id;

  BEGIN
    IF v_target_name IS NULL THEN v_target_name := 'a family member'; END IF;
    v_chat_msg_id := 'msg_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
    INSERT INTO "ChatMessage" (
      "id", "familyId", "senderId", "senderName",
      "content", "messageType", "createdAt", "updatedAt"
    ) VALUES (
      v_chat_msg_id, v_invitation."familyId", v_user_id, v_accepter_name,
      '🎉 ' || v_accepter_name || ' joined the family as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name || '.',
      'system', now(), now()
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  BEGIN
    v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_invitation."inviterUserId" from 1 for 8);
    INSERT INTO "Notification" (
      "id", "userId", "eventType", "title", "body",
      "familyId", "channels", "priority", "read",
      "actionUrl", "createdAt", "updatedAt"
    ) VALUES (
      v_notif_id, v_invitation."inviterUserId",
      'invitation_accepted', 'Family Invitation Accepted',
      v_accepter_name || ' accepted your invitation and is now the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name || '.',
      v_invitation."familyId", 'in_app', 'normal', false, NULL, now(), now()
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  UPDATE "Notification"
  SET "read" = true, "readAt" = now(),
      "actionUrl" = 'accepted:' || v_invitation."familyId",
      "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'graph_invite'
    AND "actionUrl" = 'graph_invite:' || p_invitation_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined the family',
    'familyId', v_invitation."familyId",
    'personId', v_person_id,
    'memberId', v_member_id,
    'relationshipId', v_relationship_id
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_accept_graph_invitation(text) TO authenticated;

-- ── 2. Fixed fn_decline_graph_invitation ───────────────────────────────────

CREATE OR REPLACE FUNCTION fn_decline_graph_invitation(
  p_invitation_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_invitation RECORD;
  v_user_email text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Invitation not found');
  END IF;

  IF v_invitation."status" <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'invitation_not_pending');
  END IF;

  SELECT email INTO v_user_email FROM "User" WHERE id = v_user_id;

  IF v_invitation."recipientEmail" IS NOT NULL
     AND v_invitation."recipientEmail" = v_user_email THEN
    NULL;
  ELSIF EXISTS(
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_invitation."familyId" AND "userId" = v_user_id
  ) THEN
    NULL;
  ELSE
    RETURN json_build_object('success', false, 'error', 'Not authorized to decline this invitation');
  END IF;

  UPDATE "GraphPendingInvitation"
  SET status = 'declined', "updatedAt" = now()
  WHERE id = p_invitation_id;

  RETURN json_build_object('success', true, 'message', 'Invitation declined');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_decline_graph_invitation(text) TO authenticated;

-- ── 3. Fixed fn_cancel_graph_invitation ────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_cancel_graph_invitation(
  p_invitation_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_invitation RECORD;
  v_recipient_user_id text;
  v_notif_id text;
  v_family_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Invitation not found');
  END IF;

  IF v_invitation."status" <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'invitation_not_pending');
  END IF;

  -- Only the inviter or a family admin can cancel
  IF v_invitation."inviterUserId" <> v_user_id THEN
    IF NOT EXISTS(
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = v_invitation."familyId"
        AND "userId" = v_user_id
        AND "role" IN ('admin', 'owner')
    ) THEN
      RETURN json_build_object('success', false, 'error', 'Not authorized to cancel this invitation');
    END IF;
  END IF;

  -- Mark as cancelled — NO Person node or Relationship is created
  UPDATE "GraphPendingInvitation"
  SET status = 'cancelled', "updatedAt" = now()
  WHERE id = p_invitation_id;

  -- v5.94: Notify the recipient so any pending-invite view on the
  -- receiver's side updates/removes itself.
  v_recipient_user_id := v_invitation."recipientUserId";

  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    IF v_invitation."recipientEmail" IS NOT NULL AND v_invitation."recipientEmail" <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE email = v_invitation."recipientEmail"
      LIMIT 1;
    END IF;
  END IF;

  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    IF v_invitation."recipientPhone" IS NOT NULL AND v_invitation."recipientPhone" <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE phone = v_invitation."recipientPhone"
      LIMIT 1;
    END IF;
  END IF;

  IF v_recipient_user_id IS NOT NULL AND v_recipient_user_id <> '' THEN
    BEGIN
      SELECT name INTO v_family_name FROM "Family" WHERE id = v_invitation."familyId" LIMIT 1;
      IF v_family_name IS NULL THEN v_family_name := 'the family'; END IF;

      v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_recipient_user_id from 1 for 8);

      INSERT INTO "Notification" (
        "id", "userId", "eventType", "title", "body",
        "familyId", "channels", "priority", "read",
        "actionUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_notif_id,
        v_recipient_user_id,
        'graph_invite_cancelled',
        'Family Invitation Cancelled',
        'This family invitation was cancelled by the sender.',
        v_invitation."familyId",
        'in_app',
        'normal',
        false,
        'graph_invite:' || p_invitation_id,
        now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN json_build_object('success', true, 'message', 'Invitation cancelled');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cancel_graph_invitation(text) TO authenticated;

-- ── 4. Fixed fn_resend_graph_invitation ────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_resend_graph_invitation(
  p_invitation_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_invitation RECORD;
  v_recipient_user_id text;
  v_notif_id text;
  v_target_name text;
  v_family_name text;
  v_inviter_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Invitation not found');
  END IF;

  IF v_invitation."status" <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'invitation_not_pending');
  END IF;

  -- Only the inviter or a family admin/owner can resend
  IF v_invitation."inviterUserId" <> v_user_id THEN
    IF NOT EXISTS(
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = v_invitation."familyId"
        AND "userId" = v_user_id
        AND "role" IN ('admin', 'owner')
    ) THEN
      RETURN json_build_object('success', false, 'error', 'Not authorized to resend this invitation');
    END IF;
  END IF;

  -- Extend expiry by 7 days (matching the original default)
  UPDATE "GraphPendingInvitation"
  SET "updatedAt" = now(),
      "expiresAt" = now() + interval '7 days'
  WHERE id = p_invitation_id;

  -- Resolve the recipient's user ID for the notification
  v_recipient_user_id := v_invitation."recipientUserId";

  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    IF v_invitation."recipientEmail" IS NOT NULL AND v_invitation."recipientEmail" <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE email = v_invitation."recipientEmail"
      LIMIT 1;
    END IF;
  END IF;

  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    IF v_invitation."recipientPhone" IS NOT NULL AND v_invitation."recipientPhone" <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE phone = v_invitation."recipientPhone"
      LIMIT 1;
    END IF;
  END IF;

  -- Create a reminder notification (best-effort)
  IF v_recipient_user_id IS NOT NULL AND v_recipient_user_id <> '' THEN
    BEGIN
      SELECT name INTO v_target_name FROM "Person" WHERE id = v_invitation."targetPersonId" LIMIT 1;
      SELECT name INTO v_family_name FROM "Family" WHERE id = v_invitation."familyId" LIMIT 1;
      SELECT name INTO v_inviter_name FROM "User" WHERE id = v_invitation."inviterUserId" LIMIT 1;
      IF v_family_name IS NULL THEN v_family_name := 'the family'; END IF;
      IF v_inviter_name IS NULL THEN v_inviter_name := 'Someone'; END IF;

      v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_recipient_user_id from 1 for 8);

      INSERT INTO "Notification" (
        "id", "userId", "eventType", "title", "body",
        "familyId", "channels", "priority", "read",
        "actionUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_notif_id,
        v_recipient_user_id,
        'graph_invite',
        'Family Tree Invitation Reminder',
        v_inviter_name || ' sent you a reminder to join ' || v_family_name || ' as the ' || v_invitation."specificLabelAtoB" || ' of ' || COALESCE(v_target_name, 'a family member'),
        v_invitation."familyId",
        'in_app',
        'normal',
        false,
        'graph_invite:' || p_invitation_id,
        now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'Invitation resent',
    'expiresAt', now() + interval '7 days'
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_resend_graph_invitation(text) TO authenticated;
