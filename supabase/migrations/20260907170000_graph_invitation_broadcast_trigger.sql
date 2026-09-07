-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260907170000_graph_invitation_broadcast_trigger.sql
--
-- PURPOSE
-- Fix the graph invitation acceptance flow. When Account 2 accepts a
-- graph invitation, Account 1's pending list must update in REALTIME.
--
-- This migration:
-- 1. Adds a broadcast trigger on GraphPendingInvitation so status changes
--    (pending → accepted/declined/cancelled) are broadcast to the
--    family's realtime topic. The client's graphPendingInvitationsProvider
--    will receive the broadcast and refresh the pending list.
-- 2. Also broadcasts GraphPendingInvitation INSERT so the inviter sees
--    the new pending invitation appear in realtime.
--
-- The trigger broadcasts to topic 'family:{familyId}' with event 'change'
-- (same as Person/Relationship triggers) so the client's existing
-- onBroadcast('change') handler picks it up.
--
-- The payload includes:
--   {
--     "old_record": {...} | null,
--     "record": {...} | null,
--     "operation": "INSERT|UPDATE|DELETE",
--     "table": "GraphPendingInvitation",
--     "schema": "public"
--   }
-- ════════════════════════════════════════════════════════════════════

-- ── Broadcast trigger function for GraphPendingInvitation ──
CREATE OR REPLACE FUNCTION _fn_broadcast_graph_invitation_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, realtime
AS $$
DECLARE
  v_family_id text;
  v_operation text;
  v_new_record record;
  v_old_record record;
BEGIN
  IF (TG_OP = 'DELETE') THEN
    v_family_id := OLD."familyId";
    v_operation := 'DELETE';
    v_new_record := NULL;
    v_old_record := OLD;
  ELSIF (TG_OP = 'UPDATE') THEN
    v_family_id := NEW."familyId";
    v_operation := 'UPDATE';
    v_new_record := NEW;
    v_old_record := OLD;
  ELSIF (TG_OP = 'INSERT') THEN
    v_family_id := NEW."familyId";
    v_operation := 'INSERT';
    v_new_record := NEW;
    v_old_record := NULL;
  END IF;

  IF v_family_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Broadcast to the family's realtime topic so both inviter + invitee
  -- receive the update. The client's onBroadcast('change') handler
  -- will receive this and invalidate graphPendingInvitationsProvider.
  PERFORM realtime.broadcast_changes(
    topic_name := 'family:' || v_family_id,
    event_name := 'change',
    operation := v_operation,
    table_name := 'GraphPendingInvitation',
    table_schema := 'public',
    new := v_new_record,
    old := v_old_record,
    level := 'ROW'
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Drop existing trigger if any + create new one
DROP TRIGGER IF EXISTS trg_broadcast_graph_invitation_change ON "GraphPendingInvitation";
CREATE TRIGGER trg_broadcast_graph_invitation_change
  AFTER INSERT OR UPDATE OR DELETE ON "GraphPendingInvitation"
  FOR EACH ROW
  EXECUTE FUNCTION _fn_broadcast_graph_invitation_change();

COMMENT ON FUNCTION _fn_broadcast_graph_invitation_change() IS
'v5.182: Broadcasts GraphPendingInvitation changes to family:{familyId} Realtime topic. Enables realtime pending list refresh.';

-- ── Fix #5: Update fn_accept_graph_invitation inverse CASE ──
-- Add elder_brother/younger_brother/elder_sister/younger_sister handling.
-- The current CASE (in migration 20260825010000_fix_invitation_rpc_record_case.sql)
-- doesn't handle these relationship types, so the inverse edge is never created.
--
-- We can't modify the existing function in-place (it's defined in a prior
-- migration), so we CREATE OR REPLACE it here with the fix.
-- Read the current function body and add the missing CASE branches.
CREATE OR REPLACE FUNCTION public.fn_accept_graph_invitation(p_invitation_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
BEGIN
  -- ── Step 0: Load the invitation ──
  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
    AND "expiresAt" > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Invitation not found or expired');
  END IF;

  IF v_invitation.status != 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'Invitation already ' || v_invitation.status);
  END IF;

  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- ── Step 1: Create or reuse Person node ──
  SELECT id INTO v_existing_person
  FROM "Person"
  WHERE "familyId" = v_invitation."familyId"
    AND "linkedUserId" = v_user_id::uuid
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_existing_person IS NULL THEN
    v_person_id := 'person_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

    SELECT name INTO v_accepter_name FROM "User" WHERE id = v_user_id;
    IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
      v_accepter_name := COALESCE(v_invitation."recipientName", 'New Member');
    END IF;

    INSERT INTO "Person" (
      "id", "familyId", "name",
      "isAnchor", "generationIndex", "privacyLevel",
      "linkedUserId", "linkedAt",
      "createdAt", "updatedAt"
    ) VALUES (
      v_person_id, v_invitation."familyId", v_accepter_name,
      false, 0, 'family',
      v_user_id::uuid, now(),
      now(), now()
    );
  ELSE
    v_person_id := v_existing_person;
  END IF;

  -- ── Step 2: Create FamilyMember ──
  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

  INSERT INTO "FamilyMember" ("id", "familyId", "userId", "role", "joinedAt")
  VALUES (v_member_id, v_invitation."familyId", v_user_id, 'member', now())
  ON CONFLICT ("familyId", "userId") DO NOTHING;

  -- ── Step 3: Create forward Relationship edge ──
  -- targetPerson → newPerson, with labelAtoB = specificLabelAtoB (e.g. elder_brother)
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
    CASE
      WHEN v_invitation."specificLabelAtoB" IN ('father', 'mother', 'parent') THEN 'parent'
      WHEN v_invitation."specificLabelAtoB" IN ('son', 'daughter', 'child') THEN 'parent'
      WHEN v_invitation."specificLabelAtoB" IN ('husband', 'wife', 'spouse') THEN 'spouse'
      WHEN v_invitation."specificLabelAtoB" IN ('brother', 'sister', 'sibling',
        'elder_brother', 'younger_brother', 'elder_sister', 'younger_sister') THEN 'sibling'
      WHEN v_invitation."specificLabelAtoB" IN ('grandfather', 'grandmother', 'grandparent') THEN 'parent'
      WHEN v_invitation."specificLabelAtoB" IN ('grandson', 'granddaughter', 'grandchild') THEN 'parent'
      WHEN v_invitation."specificLabelAtoB" IN ('uncle', 'aunt') THEN 'parent'
      WHEN v_invitation."specificLabelAtoB" IN ('nephew', 'niece') THEN 'parent'
      ELSE 'custom'
    END,
    v_invitation."specificLabelAtoB",
    'from', true,
    now(), now()
  );

  -- ── Step 4: Create inverse Relationship edge ──
  -- v5.182 FIX: Added elder_brother/younger_brother/elder_sister/younger_sister
  -- handling. Previously these were not in any CASE branch, so no inverse
  -- edge was created — the relationship was one-directional.
  v_inverse_key := CASE
    WHEN v_invitation."specificLabelAtoB" IN ('father', 'mother', 'parent') THEN 'son'
    WHEN v_invitation."specificLabelAtoB" IN ('son', 'daughter', 'child') THEN 'father'
    WHEN v_invitation."specificLabelAtoB" IN ('husband', 'wife', 'spouse') THEN v_invitation."specificLabelAtoB"
    WHEN v_invitation."specificLabelAtoB" IN ('brother', 'sister', 'sibling') THEN v_invitation."specificLabelAtoB"
    -- v5.182: elder/younger brother/sister → inverse is the opposite age ordering
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

  IF v_has_known_inverse THEN
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
      CASE
        WHEN v_inverse_key IN ('father', 'mother', 'parent', 'son', 'daughter', 'child',
            'grandfather', 'grandmother', 'grandparent', 'grandson', 'granddaughter',
            'grandchild', 'uncle', 'aunt', 'nephew', 'niece') THEN 'parent'
        WHEN v_inverse_key IN ('husband', 'wife', 'spouse') THEN 'spouse'
        WHEN v_inverse_key IN ('brother', 'sister', 'sibling',
            'elder_brother', 'younger_brother', 'elder_sister', 'younger_sister') THEN 'sibling'
        ELSE 'custom'
      END,
      v_inverse_key,
      'inverse', true,
      now(), now()
    );
  END IF;

  -- ── Step 5: Update GraphPendingInvitation status ──
  UPDATE "GraphPendingInvitation"
  SET status = 'accepted',
      "acceptedAt" = now(),
      "acceptedByUserId" = v_user_id,
      "createdPersonId" = v_person_id,
      "createdRelationshipId" = v_relationship_id,
      "updatedAt" = now()
  WHERE id = p_invitation_id;

  -- ── Step 6: System chat message ──
  BEGIN
    v_chat_msg_id := 'msg_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

    INSERT INTO "ChatMessage" (
      "id", "familyId", "senderId", "senderName",
      "content", "messageType", "createdAt", "updatedAt"
    ) VALUES (
      v_chat_msg_id, v_invitation."familyId", v_user_id, v_accepter_name,
      '🎉 ' || v_accepter_name || ' joined the family as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
      'system', now(), now()
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- ── Step 7: Notification to inviter ──
  BEGIN
    v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_invitation."inviterUserId" from 1 for 8);

    INSERT INTO "Notification" (
      "id", "userId", "eventType", "title", "body",
      "familyId", "channels", "priority", "read",
      "actionUrl", "createdAt", "updatedAt"
    ) VALUES (
      v_notif_id, v_invitation."inviterUserId", 'invitation_accepted',
      'Graph Invitation Accepted',
      v_accepter_name || ' accepted your invitation and is now the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
      v_invitation."familyId", 'in_app', 'normal', false,
      'accepted:' || v_invitation."familyId",
      now(), now()
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- ── Step 8: Mark original graph_invite notification as read ──
  UPDATE "Notification"
  SET "read" = true,
      "readAt" = now(),
      "title" = 'Invitation Accepted',
      "body" = 'You joined as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
      "actionUrl" = 'accepted:' || v_invitation."familyId",
      "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'graph_invite'
    AND "familyId" = v_invitation."familyId"
    AND "actionUrl" = 'graph_invite:' || p_invitation_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
    'familyId', v_invitation."familyId",
    'personId', v_person_id,
    'memberId', v_member_id,
    'relationshipId', v_relationship_id,
    'inverseRelationshipId', v_inverse_relationship_id
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$function$;

COMMENT ON FUNCTION public.fn_accept_graph_invitation(text) IS
'v5.182: Fixed — now handles elder_brother/younger_brother/elder_sister/younger_sister inverse edges. Also broadcasts GraphPendingInvitation changes via trigger.';
