-- =============================================================================
-- Daxelo Kinrel — Fix: fn_accept_graph_invitation relationshipKey CHECK constraint
-- =============================================================================
-- BUG: The v5.182 rewrite of fn_accept_graph_invitation introduced a CASE
-- statement that derives relationshipKey from specificLabelAtoB. For sibling
-- relationships (brother/sister/elder_brother/etc.), it produces 'sibling'
-- which violates the Relationship table's CHECK constraint:
--   relationship_fundamental_edge_check: ('parent','spouse','adoptive_parent','step_parent')
-- The INSERT fails, the EXCEPTION rolls back the whole transaction, and
-- the RPC returns success=false.
--
-- FIX: Use v_invitation."relationshipKey" directly (it's already validated
-- at creation time by fn_create_graph_pending_invitation to be one of the
-- four fundamental types). Also re-wrap the inverse-edge INSERT in
-- BEGIN...EXCEPTION so a best-effort inverse failure doesn't abort the
-- whole acceptance.
--
-- Also: re-mark any failed-acceptance invitations back to 'pending' so
-- affected users can accept again after this fix.
-- =============================================================================

-- Re-mark failed-acceptance invitations back to pending so users can re-accept
UPDATE "GraphPendingInvitation"
SET status = 'pending', "acceptedAt" = NULL, "acceptedByUserId" = NULL,
    "createdPersonId" = NULL, "createdRelationshipId" = NULL, "updatedAt" = now()
WHERE status = 'accepted'
  AND "createdRelationshipId" IS NULL;
-- (Only re-mark ones where the relationship wasn't actually created.
-- Successful acceptances have a non-null createdRelationshipId.)

-- Now recreate the function with the fix.
-- We need to read the current definition and modify just the relationshipKey
-- derivation + re-wrap the inverse edge.

CREATE OR REPLACE FUNCTION fn_accept_graph_invitation(p_invitation_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_invitation "GraphPendingInvitation"%ROWTYPE;
  v_user_id text := auth.uid()::text;
  v_existing_person text;
  v_person_id text;
  v_member_id text;
  v_relationship_id text;
  v_inverse_relationship_id text;
  v_inverse_key text;
  v_has_known_inverse boolean := false;
  v_inviter_name text;
  v_target_name text;
  v_accepter_name text;
  v_notif_id text;
  v_chat_msg_id text;
  v_target_gender text;
  v_accepter_gender text;
  v_accepter_avatar text;
BEGIN
  RAISE NOTICE '[INVITE] Accept started — invitationId=%', p_invitation_id;

  -- Step 0: Load the invitation
  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
    AND "expiresAt" > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE NOTICE '[INVITE ERROR] Invitation not found or expired';
    RETURN json_build_object('success', false, 'error', 'Invitation not found or expired');
  END IF;

  IF v_invitation.status != 'pending' THEN
    RAISE NOTICE '[INVITE ERROR] Invitation already %', v_invitation.status;
    RETURN json_build_object('success', false, 'error', 'Invitation already ' || v_invitation.status);
  END IF;

  IF v_user_id IS NULL THEN
    RAISE NOTICE '[INVITE ERROR] Not authenticated';
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- v5.43: If recipientUserId is set, verify the caller matches
  IF v_invitation."recipientUserId" IS NOT NULL
     AND v_invitation."recipientUserId" != '' THEN
    IF v_user_id != v_invitation."recipientUserId" THEN
      RAISE NOTICE '[INVITE ERROR] Caller % does not match recipientUserId %', v_user_id, v_invitation."recipientUserId";
      RETURN json_build_object('success', false, 'error', 'This invitation was sent to a different user');
    END IF;
  END IF;

  RAISE NOTICE '[INVITE] Invitation loaded — familyId=%, targetPersonId=%, relationshipKey=%, specificLabelAtoB=%',
    v_invitation."familyId", v_invitation."targetPersonId", v_invitation."relationshipKey", v_invitation."specificLabelAtoB";

  -- Step 1: Create or reuse Person node
  SELECT id INTO v_existing_person
  FROM "Person"
  WHERE "familyId" = v_invitation."familyId"
    AND "linkedUserId" = v_user_id::uuid
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_existing_person IS NULL THEN
    -- Also check globally (user might have a Person in another family)
    SELECT id INTO v_existing_person
    FROM "Person"
    WHERE "linkedUserId" = v_user_id::uuid
      AND "deletedAt" IS NULL
    LIMIT 1;
  END IF;

  IF v_existing_person IS NULL THEN
    v_person_id := 'person_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

    SELECT name, "avatarUrl" INTO v_accepter_name, v_accepter_avatar
    FROM "User" WHERE id = v_user_id;
    IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
      v_accepter_name := COALESCE(v_invitation."recipientName", 'New Member');
    END IF;

    -- Also get gender if available
    BEGIN
      SELECT gender INTO v_accepter_gender FROM "User" WHERE id = v_user_id;
    EXCEPTION WHEN OTHERS THEN v_accepter_gender := NULL; END;

    INSERT INTO "Person" (
      "id", "familyId", "name",
      "isAnchor", "generationIndex", "privacyLevel",
      "linkedUserId", "linkedAt",
      "photoUrl", "gender",
      "createdAt", "updatedAt"
    ) VALUES (
      v_person_id, v_invitation."familyId", v_accepter_name,
      false, 0, 'family',
      v_user_id::uuid, now(),
      v_accepter_avatar, v_accepter_gender,
      now(), now()
    );
    RAISE NOTICE '[INVITE] Person created: %', v_person_id;
  ELSE
    v_person_id := v_existing_person;
    RAISE NOTICE '[INVITE] Person reused: %', v_person_id;
  END IF;

  -- Step 2: Create FamilyMember
  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "FamilyMember" ("id", "familyId", "userId", "role", "joinedAt")
  VALUES (v_member_id, v_invitation."familyId", v_user_id, 'member', now())
  ON CONFLICT ("familyId", "userId") DO NOTHING;
  RAISE NOTICE '[INVITE] Family membership created: %', v_member_id;

  -- Step 3: Create forward Relationship edge
  -- FIX v5.183: Use v_invitation."relationshipKey" directly instead of
  -- deriving from specificLabelAtoB. The relationshipKey was validated at
  -- creation time by fn_create_graph_pending_invitation to be one of:
  -- 'parent', 'spouse', 'adoptive_parent', 'step_parent'. The CHECK
  -- constraint on the Relationship table only allows these four values.
  -- The previous v5.182 CASE derivation produced 'sibling' and 'custom'
  -- which violated the constraint and caused the entire RPC to fail.
  v_relationship_id := 'rel_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  SELECT name INTO v_target_name FROM "Person" WHERE id = v_invitation."targetPersonId";
  IF v_target_name IS NULL THEN v_target_name := 'the person'; END IF;

  INSERT INTO "Relationship" (
    "id", "familyId",
    "fromPersonId", "toPersonId",
    "relationshipKey", "labelAtoB",
    "direction", "isActive",
    "createdAt", "updatedAt"
  ) VALUES (
    v_relationship_id, v_invitation."familyId",
    v_invitation."targetPersonId", v_person_id,
    v_invitation."relationshipKey",  -- ← FIX: use the validated fundamental key directly
    v_invitation."specificLabelAtoB",
    'from', true,
    now(), now()
  );
  RAISE NOTICE '[INVITE] Relationship created: % (fromPerson=% → toPerson=%, key=%, label=%)',
    v_relationship_id, v_invitation."targetPersonId", v_person_id,
    v_invitation."relationshipKey", v_invitation."specificLabelAtoB";

  -- Step 4: Inverse edge (best-effort, wrapped in BEGIN...EXCEPTION)
  -- Compute gender-aware inverse label
  v_inverse_key := CASE
    WHEN v_invitation."specificLabelAtoB" IN ('father', 'mother', 'parent') THEN 'son'
    WHEN v_invitation."specificLabelAtoB" IN ('son', 'daughter', 'child') THEN 'father'
    WHEN v_invitation."specificLabelAtoB" IN ('husband', 'wife', 'spouse') THEN v_invitation."specificLabelAtoB"
    WHEN v_invitation."specificLabelAtoB" IN ('brother', 'sister', 'sibling') THEN v_invitation."specificLabelAtoB"
    WHEN v_invitation."specificLabelAtoB" = 'elder_brother' THEN 'younger_brother'
    WHEN v_invitation."specificLabelAtoB" = 'younger_brother' THEN 'elder_brother'
    WHEN v_invitation."specificLabelAtoB" = 'elder_sister' THEN 'younger_sister'
    WHEN v_invitation."specificLabelAtoB" = 'younger_sister' THEN 'elder_sister'
    WHEN v_invitation."specificLabelAtoB" IN ('grandfather', 'grandmother', 'grandparent') THEN 'grandson'
    WHEN v_invitation."specificLabelAtoB" IN ('grandson', 'granddaughter', 'grandchild') THEN 'grandfather'
    WHEN v_invitation."specificLabelAtoB" IN ('uncle', 'aunt') THEN 'nephew'
    WHEN v_invitation."specificLabelAtoB" IN ('nephew', 'niece') THEN 'uncle'
    ELSE NULL
  END;

  IF v_inverse_key IS NOT NULL THEN
    v_has_known_inverse := true;
  END IF;

  -- FIX v5.183: Re-wrap in BEGIN...EXCEPTION so inverse-edge failure
  -- doesn't roll back the whole acceptance (best-effort, same as original)
  IF v_has_known_inverse THEN
    BEGIN
      v_inverse_relationship_id := 'rel_inv_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
      INSERT INTO "Relationship" (
        "id", "familyId",
        "fromPersonId", "toPersonId",
        "relationshipKey", "labelAtoB",
        "direction", "isActive",
        "createdAt", "updatedAt"
      ) VALUES (
        v_inverse_relationship_id, v_invitation."familyId",
        v_person_id, v_invitation."targetPersonId",
        v_invitation."relationshipKey",  -- ← FIX: use the validated fundamental key
        v_inverse_key,
        'inverse', true,
        now(), now()
      );
      RAISE NOTICE '[INVITE] Inverse relationship created: %', v_inverse_relationship_id;
    EXCEPTION WHEN OTHERS THEN
      v_inverse_relationship_id := NULL;
      RAISE NOTICE '[INVITE] Inverse relationship failed (best-effort, continuing): %', SQLERRM;
    END;
  END IF;

  -- Step 5: Update GraphPendingInvitation status
  UPDATE "GraphPendingInvitation"
  SET status = 'accepted',
      "acceptedAt" = now(),
      "acceptedByUserId" = v_user_id,
      "createdPersonId" = v_person_id,
      "createdRelationshipId" = v_relationship_id,
      "updatedAt" = now()
  WHERE id = p_invitation_id;
  RAISE NOTICE '[INVITE] Invitation status updated to accepted';

  -- Step 6: System chat message
  BEGIN
    v_chat_msg_id := 'msg_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
    INSERT INTO "ChatMessage" (
      "id", "familyId",
      "senderId", "senderName", "senderInitials",
      "content", "messageType", "messageSubType",
      "isRead", "messageStatus",
      "createdAt", "updatedAt"
    ) VALUES (
      v_chat_msg_id, v_invitation."familyId",
      v_user_id, v_accepter_name, UPPER(SUBSTRING(v_accepter_name FROM 1 FOR 1)),
      v_accepter_name || ' joined the family as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name || '.',
      'system', 'system',
      false, 'sent',
      now(), now()
    );
    RAISE NOTICE '[INVITE] System chat message created';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[INVITE] Chat message failed (best-effort): %', SQLERRM;
  END;

  -- Step 7: Notification to inviter
  BEGIN
    SELECT name INTO v_inviter_name FROM "User" WHERE id = v_invitation."inviterUserId";
    IF v_inviter_name IS NULL OR v_inviter_name = '' THEN
      v_inviter_name := 'Someone';
    END IF;

    v_notif_id := 'notif_accept_' || extract(epoch from now())::bigint::text || '_' || substring(v_invitation."inviterUserId" from 1 for 8);
    INSERT INTO "Notification" (
      "id", "userId", "eventType", "title", "body",
      "familyId", "channels", "priority", "read",
      "actionUrl", "createdAt", "updatedAt"
    ) VALUES (
      v_notif_id,
      v_invitation."inviterUserId",
      'invitation_accepted',
      'Invitation Accepted',
      v_accepter_name || ' accepted your invitation and joined as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
      v_invitation."familyId",
      'in_app',
      'normal',
      false,
      'accepted:' || v_invitation."familyId",
      now(), now()
    );
    RAISE NOTICE '[INVITE] Inviter notification created';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[INVITE] Inviter notification failed (best-effort): %', SQLERRM;
  END;

  -- Step 8: Mark original graph_invite notification as read
  UPDATE "Notification"
  SET "read" = true, "readAt" = now(),
      "title" = 'Invitation Accepted',
      "body" = 'You joined as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
      "actionUrl" = 'accepted:' || v_invitation."familyId",
      "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'graph_invite'
    AND "familyId" = v_invitation."familyId"
    AND "actionUrl" = 'graph_invite:' || p_invitation_id;
  RAISE NOTICE '[INVITE] Original notification marked as read';

  RAISE NOTICE '[INVITE] Accept completed successfully';
  RETURN json_build_object(
    'success', true,
    'message', v_accepter_name || ' joined as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
    'createdPersonId', v_person_id,
    'createdRelationshipId', v_relationship_id,
    'inverseRelationshipId', v_inverse_relationship_id
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[INVITE ERROR] Exception: %', SQLERRM;
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_accept_graph_invitation(text) TO authenticated;

-- Verification
SELECT 'fn_accept_graph_invitation' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_accept_graph_invitation') AS exists;
