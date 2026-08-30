-- =============================================================================
-- Daxelo Kinrel — v5.43 Graph Invitation: recipientUserId + Notification
-- =============================================================================
--
-- This migration enhances the GraphPendingInvitation system to:
-- 1. Add a `recipientUserId` column for Find-on-Kinrel invites (where the
--    recipient already has a Kinrel account).
-- 2. Update `fn_create_graph_pending_invitation` to accept an optional
--    `p_recipient_user_id` parameter.
-- 3. When `p_recipient_user_id` is set, create a `graph_invite` notification
--    so the recipient sees the invitation in their Notifications screen.
-- 4. Update `fn_accept_graph_invitation` to also create a notification for
--    the inviter when the invitation is accepted via the Notifications screen.
--
-- This enables the "Find on Kinrel" flow: search for a Kinrel user →
-- select them → pick a relationship → submit. The system stores a pending
-- invitation AND sends a notification to the recipient. No Person node is
-- created until the recipient accepts.
-- =============================================================================

-- ── 1. Add recipientUserId column ──────────────────────────────────────────

ALTER TABLE "GraphPendingInvitation"
  ADD COLUMN IF NOT EXISTS "recipientUserId" TEXT;

CREATE INDEX IF NOT EXISTS idx_graph_pending_inv_recipient_user
  ON "GraphPendingInvitation" ("recipientUserId")
  WHERE "recipientUserId" IS NOT NULL;

-- ── 2. Update fn_create_graph_pending_invitation ───────────────────────────

CREATE OR REPLACE FUNCTION fn_create_graph_pending_invitation(
  p_family_id text,
  p_target_person_id text,
  p_relationship_key text,
  p_specific_label text,
  p_recipient_name text DEFAULT NULL,
  p_recipient_email text DEFAULT NULL,
  p_recipient_phone text DEFAULT NULL,
  p_recipient_user_id text DEFAULT NULL,
  p_expiry_days integer DEFAULT 7
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_invitation_id text;
  v_invite_code text;
  v_existing_pending text;
  v_is_member boolean;
  v_target_name text;
  v_family_name text;
  v_notif_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Validate the caller is a family member
  SELECT EXISTS(
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN json_build_object('success', false, 'error', 'You are not a member of this family');
  END IF;

  -- Validate the relationship key is a fundamental edge type
  IF p_relationship_key NOT IN ('parent', 'spouse', 'adoptive_parent', 'step_parent') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid relationship key');
  END IF;

  -- Validate the target Person exists and belongs to this family
  IF NOT EXISTS(
    SELECT 1 FROM "Person"
    WHERE id = p_target_person_id
      AND "familyId" = p_family_id
      AND "deletedAt" IS NULL
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Target person not found');
  END IF;

  -- v5.43: If recipient_user_id is provided, check they're not already a member
  IF p_recipient_user_id IS NOT NULL AND p_recipient_user_id <> '' THEN
    IF EXISTS(
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = p_family_id AND "userId" = p_recipient_user_id
    ) THEN
      RETURN json_build_object('success', false, 'error', 'duplicate_member',
        'message', 'This user is already a member of your family');
    END IF;

    -- Check for existing pending invitation to this user
    SELECT id INTO v_existing_pending
    FROM "GraphPendingInvitation"
    WHERE "familyId" = p_family_id
      AND "recipientUserId" = p_recipient_user_id
      AND "status" = 'pending'
    LIMIT 1;

    IF v_existing_pending IS NOT NULL THEN
      RETURN json_build_object('success', false, 'error', 'duplicate_invitation',
        'message', 'A pending invitation already exists for this user');
    END IF;
  ELSIF p_recipient_email IS NOT NULL AND p_recipient_email <> '' THEN
    SELECT id INTO v_existing_pending
    FROM "GraphPendingInvitation"
    WHERE "familyId" = p_family_id
      AND "recipientEmail" = p_recipient_email
      AND "status" = 'pending'
    LIMIT 1;
    IF v_existing_pending IS NOT NULL THEN
      RETURN json_build_object('success', false, 'error', 'duplicate_invitation');
    END IF;
  ELSIF p_recipient_phone IS NOT NULL AND p_recipient_phone <> '' THEN
    SELECT id INTO v_existing_pending
    FROM "GraphPendingInvitation"
    WHERE "familyId" = p_family_id
      AND "recipientPhone" = p_recipient_phone
      AND "status" = 'pending'
    LIMIT 1;
    IF v_existing_pending IS NOT NULL THEN
      RETURN json_build_object('success', false, 'error', 'duplicate_invitation');
    END IF;
  ELSE
    RETURN json_build_object('success', false, 'error', 'no_recipient',
      'message', 'Must provide recipient_user_id, email, or phone');
  END IF;

  -- Generate IDs
  v_invitation_id := 'gpi_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  v_invite_code := encode(gen_random_bytes(9), 'hex');

  -- Get target person + family name for the notification
  SELECT name INTO v_target_name FROM "Person" WHERE id = p_target_person_id LIMIT 1;
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id LIMIT 1;
  IF v_family_name IS NULL THEN v_family_name := 'the family'; END IF;

  -- Insert the pending invitation
  INSERT INTO "GraphPendingInvitation" (
    "id", "familyId", "inviterUserId",
    "targetPersonId", "relationshipKey", "specificLabelAtoB",
    "recipientName", "recipientEmail", "recipientPhone", "recipientUserId",
    "status", "expiresAt", "inviteCode",
    "createdAt", "updatedAt"
  ) VALUES (
    v_invitation_id, p_family_id, v_user_id,
    p_target_person_id, p_relationship_key, p_specific_label,
    NULLIF(p_recipient_name, ''), NULLIF(p_recipient_email, ''), NULLIF(p_recipient_phone, ''), NULLIF(p_recipient_user_id, ''),
    'pending', now() + (p_expiry_days || ' days')::interval, v_invite_code,
    now(), now()
  );

  -- v5.43: If recipient_user_id is set, create a notification so they see it
  IF p_recipient_user_id IS NOT NULL AND p_recipient_user_id <> '' THEN
    BEGIN
      v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(p_recipient_user_id from 1 for 8);

      INSERT INTO "Notification" (
        "id", "userId", "eventType", "title", "body",
        "familyId", "channels", "priority", "read",
        "actionUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_notif_id,
        p_recipient_user_id,
        'graph_invite',
        'Family Graph Invitation',
        'You have been invited to join ' || v_family_name || ' as the ' || p_specific_label || ' of ' || COALESCE(v_target_name, 'a family member'),
        p_family_id,
        'in_app',
        'normal',
        false,
        'graph_invite:' || v_invitation_id,
        now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Notification is best-effort — don't fail the invitation
      NULL;
    END;
  END IF;

  RETURN json_build_object(
    'success', true,
    'invitationId', v_invitation_id,
    'inviteCode', v_invite_code,
    'status', 'pending'
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_create_graph_pending_invitation(
  text, text, text, text, text, text, text, text, integer
) TO authenticated;

-- ── 3. Update fn_accept_graph_invitation to handle graph_invite notifications ──

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

  IF v_invitation.status <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'invitation_not_pending');
  END IF;

  IF v_invitation.expiresAt < now() THEN
    UPDATE "GraphPendingInvitation"
    SET status = 'expired', "updatedAt" = now()
    WHERE id = p_invitation_id;
    RETURN json_build_object('success', false, 'error', 'invitation_expired');
  END IF;

  -- v5.43: If the invitation has a recipientUserId, verify the caller matches
  IF v_invitation.recipientUserId IS NOT NULL
     AND v_invitation.recipientUserId <> ''
     AND v_invitation.recipientUserId <> v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'not_authorized',
      'message', 'This invitation was sent to a different user');
  END IF;

  -- Check if already a family member
  SELECT id INTO v_existing_member
  FROM "FamilyMember"
  WHERE "familyId" = v_invitation.familyId AND "userId" = v_user_id
  LIMIT 1;

  IF v_existing_member IS NOT NULL THEN
    RETURN json_build_object('success', true, 'message', 'Already a member');
  END IF;

  -- Get the accepter's details
  SELECT name, gender, "avatarUrl" INTO v_accepter_name, v_user_gender, v_user_avatar
  FROM "User" WHERE id = v_user_id;
  IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
    v_accepter_name := v_invitation.recipientName;
  END IF;
  IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
    v_accepter_name := 'A new member';
  END IF;

  -- Get family + target names
  SELECT name INTO v_family_name FROM "Family" WHERE id = v_invitation.familyId LIMIT 1;
  SELECT name INTO v_target_name FROM "Person" WHERE id = v_invitation.targetPersonId LIMIT 1;

  -- STEP 1: Create or reuse the Person node
  SELECT id INTO v_existing_person
  FROM "Person"
  WHERE "familyId" = v_invitation.familyId AND "linkedUserId" = v_user_id::uuid
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
        v_invitation.familyId,
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
        v_invitation.familyId,
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

  -- STEP 2: Create the FamilyMember record
  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "FamilyMember" ("id", "familyId", "userId", "role", "joinedAt")
  VALUES (v_member_id, v_invitation.familyId, v_user_id, 'member', now());

  -- STEP 3: Create the forward Relationship edge
  v_relationship_id := 'rel_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "Relationship" (
    "id", "familyId", "fromPersonId", "toPersonId",
    "relationshipKey", "relationshipType", "labelAtoB",
    "direction", "isActive", "createdAt", "updatedAt"
  ) VALUES (
    v_relationship_id, v_invitation.familyId,
    v_invitation.targetPersonId, v_person_id,
    v_invitation.relationshipKey, v_invitation.relationshipKey,
    v_invitation.specificLabelAtoB,
    'from', true, now(), now()
  );

  -- STEP 4: Create the inverse Relationship edge
  v_inverse_key := CASE
    WHEN v_invitation.specificLabelAtoB IN ('father', 'mother', 'parent') THEN
      CASE WHEN v_user_gender = 'female' THEN 'daughter' ELSE 'son' END
    WHEN v_invitation.specificLabelAtoB IN ('son', 'daughter', 'child') THEN
      CASE WHEN v_user_gender = 'female' THEN 'mother' ELSE 'father' END
    WHEN v_invitation.specificLabelAtoB IN ('husband', 'wife', 'spouse') THEN
      v_invitation.specificLabelAtoB
    WHEN v_invitation.specificLabelAtoB IN ('brother', 'sister', 'sibling') THEN
      CASE WHEN v_user_gender = 'female' THEN 'sister' ELSE 'brother' END
    WHEN v_invitation.specificLabelAtoB IN ('grandfather', 'grandmother') THEN
      CASE WHEN v_user_gender = 'female' THEN 'granddaughter' ELSE 'grandson' END
    WHEN v_invitation.specificLabelAtoB IN ('grandson', 'granddaughter') THEN
      CASE WHEN v_user_gender = 'female' THEN 'grandmother' ELSE 'grandfather' END
    WHEN v_invitation.specificLabelAtoB IN ('uncle', 'aunt') THEN
      CASE WHEN v_user_gender = 'female' THEN 'niece' ELSE 'nephew' END
    WHEN v_invitation.specificLabelAtoB IN ('nephew', 'niece') THEN
      CASE WHEN v_user_gender = 'female' THEN 'aunt' ELSE 'uncle' END
    ELSE NULL
  END;

  v_has_known_inverse := v_inverse_key IS NOT NULL
    AND v_inverse_key <> v_invitation.specificLabelAtoB
    AND v_inverse_key NOT IN ('husband', 'wife', 'spouse');

  IF v_has_known_inverse THEN
    BEGIN
      v_inverse_relationship_id := 'rel_inv_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
      INSERT INTO "Relationship" (
        "id", "familyId", "fromPersonId", "toPersonId",
        "relationshipKey", "relationshipType", "labelAtoB",
        "direction", "isActive", "createdAt", "updatedAt"
      ) VALUES (
        v_inverse_relationship_id, v_invitation.familyId,
        v_person_id, v_invitation.targetPersonId,
        v_invitation.relationshipKey, v_invitation.relationshipKey,
        v_inverse_key, 'inverse', true, now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      v_inverse_relationship_id := NULL;
    END;
  END IF;

  -- STEP 5: Update the invitation to 'accepted'
  UPDATE "GraphPendingInvitation"
  SET status = 'accepted', "acceptedAt" = now(),
      "acceptedByUserId" = v_user_id,
      "createdPersonId" = v_person_id,
      "createdRelationshipId" = v_relationship_id,
      "updatedAt" = now()
  WHERE id = p_invitation_id;

  -- STEP 6: Post a system chat message
  BEGIN
    IF v_target_name IS NULL THEN v_target_name := 'a family member'; END IF;
    v_chat_msg_id := 'msg_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
    INSERT INTO "ChatMessage" (
      "id", "familyId", "senderId", "senderName",
      "content", "messageType", "createdAt", "updatedAt"
    ) VALUES (
      v_chat_msg_id, v_invitation.familyId, v_user_id, v_accepter_name,
      '🎉 ' || v_accepter_name || ' joined the family as the ' || v_invitation.specificLabelAtoB || ' of ' || v_target_name || '.',
      'system', now(), now()
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- STEP 7: Create acceptance notification for the inviter
  BEGIN
    v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_invitation.inviterUserId from 1 for 8);
    INSERT INTO "Notification" (
      "id", "userId", "eventType", "title", "body",
      "familyId", "channels", "priority", "read",
      "actionUrl", "createdAt", "updatedAt"
    ) VALUES (
      v_notif_id, v_invitation.inviterUserId,
      'invitation_accepted', 'Family Invitation Accepted',
      v_accepter_name || ' accepted your invitation and is now the ' || v_invitation.specificLabelAtoB || ' of ' || v_target_name || '.',
      v_invitation.familyId, 'in_app', 'normal', false, NULL, now(), now()
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- STEP 8: Mark the original graph_invite notification as read
  UPDATE "Notification"
  SET "read" = true, "readAt" = now(),
      "actionUrl" = 'accepted:' || v_invitation.familyId,
      "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'graph_invite'
    AND "actionUrl" = 'graph_invite:' || p_invitation_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined the family',
    'familyId', v_invitation.familyId,
    'personId', v_person_id,
    'memberId', v_member_id,
    'relationshipId', v_relationship_id
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_accept_graph_invitation(text) TO authenticated;

-- Verification
SELECT 'recipientUserId column added' AS step,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'GraphPendingInvitation' AND column_name = 'recipientUserId'
       ) AS success;
