-- =============================================================================
-- Daxelo Kinrel — Graph Pending Invitations System (v5.41)
-- =============================================================================
--
-- PROBLEM:
-- When a user invites someone from the Family Graph (e.g. long-press a node
-- → "Invite"), the app currently creates a Person node IMMEDIATELY via
-- AddPersonSheet._submit(). This violates the desired contract:
--   "Invitations Sent from Family Graph → Do not create or display an
--    unlinked node in the graph immediately."
--
-- The graph should only contain confirmed, accepted members. Pending
-- invitations must live in a separate system until accepted.
--
-- SOLUTION:
-- Create a dedicated "GraphPendingInvitation" table that stores:
--   • who invited (inviterUserId)
--   • which existing Person they'll be related to (targetPersonId)
--   • what relationship will be created (relationshipKey + specificLabelAtoB)
--   • recipient contact info (name / email / phone)
--   • status (pending | accepted | declined | cancelled | expired)
--   • the Person + Relationship that get created on accept
--
-- RPCs:
--   • fn_create_graph_pending_invitation  — inviter creates a pending invite
--   • fn_accept_graph_invitation          — invitee accepts → creates Person
--                                            + Relationship + reciprocal edge
--   • fn_decline_graph_invitation         — invitee declines
--   • fn_cancel_graph_invitation          — inviter cancels
--   • fn_get_pending_graph_invitations    — list pending invites for a family
--   • fn_cleanup_expired_graph_invitations — mark expired invites
--
-- The acceptance RPC creates:
--   1. A Person node (linkedUserId = accepter, isAnchor = false)
--   2. A FamilyMember record (role = 'member')
--   3. A Relationship edge from targetPerson → newPerson (forward)
--   4. A Relationship edge from newPerson → targetPerson (inverse, if applicable)
--   5. Updates the invitation status to 'accepted'
--   6. Posts a system chat message
--   7. Creates an 'invitation_accepted' notification for the inviter
--
-- This ensures the new member is FULLY LINKED in the graph on accept —
-- not floating as an unlinked node.
-- =============================================================================

-- ── 1. Create the GraphPendingInvitation table ────────────────────────────

CREATE TABLE IF NOT EXISTS "GraphPendingInvitation" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "inviterUserId" TEXT NOT NULL,             -- FK → User.id (the person sending)
  "targetPersonId" TEXT NOT NULL,             -- FK → Person.id (the anchor they'll relate to)
  "relationshipKey" TEXT NOT NULL,            -- fundamental edge type: 'parent' | 'spouse' | 'adoptive_parent' | 'step_parent'
  "specificLabelAtoB" TEXT NOT NULL,          -- specific label: 'father' | 'brother' | 'wife' etc.
  "recipientName" TEXT,
  "recipientEmail" TEXT,
  "recipientPhone" TEXT,
  "status" TEXT NOT NULL DEFAULT 'pending',   -- pending | accepted | declined | cancelled | expired
  "expiresAt" TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
  "acceptedAt" TIMESTAMPTZ,
  "acceptedByUserId" TEXT,
  "createdPersonId" TEXT,                     -- the Person created on accept
  "createdRelationshipId" TEXT,               -- the forward Relationship created on accept
  "inviteCode" TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(9), 'hex'),
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_graph_pending_inv_family
  ON "GraphPendingInvitation" ("familyId");
CREATE INDEX IF NOT EXISTS idx_graph_pending_inv_status
  ON "GraphPendingInvitation" ("familyId", "status");
CREATE INDEX IF NOT EXISTS idx_graph_pending_inv_inviter
  ON "GraphPendingInvitation" ("inviterUserId");
CREATE INDEX IF NOT EXISTS idx_graph_pending_inv_target
  ON "GraphPendingInvitation" ("targetPersonId");
CREATE INDEX IF NOT EXISTS idx_graph_pending_inv_recipient_email
  ON "GraphPendingInvitation" ("recipientEmail")
  WHERE "recipientEmail" IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_graph_pending_inv_recipient_phone
  ON "GraphPendingInvitation" ("recipientPhone")
  WHERE "recipientPhone" IS NOT NULL;

-- Foreign keys (best-effort — use IF NOT EXISTS guards where possible)
ALTER TABLE "GraphPendingInvitation"
  ADD CONSTRAINT IF NOT EXISTS fk_graph_pending_inv_family
    FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE;

ALTER TABLE "GraphPendingInvitation"
  ADD CONSTRAINT IF NOT EXISTS fk_graph_pending_inv_inviter
    FOREIGN KEY ("inviterUserId") REFERENCES "User"("id") ON DELETE CASCADE;

ALTER TABLE "GraphPendingInvitation"
  ADD CONSTRAINT IF NOT EXISTS fk_graph_pending_inv_target
    FOREIGN KEY ("targetPersonId") REFERENCES "Person"("id") ON DELETE CASCADE;

-- ── 2. Enable RLS ──────────────────────────────────────────────────────────

ALTER TABLE "GraphPendingInvitation" ENABLE ROW LEVEL SECURITY;

-- Policy: family members can read pending invitations for their families
CREATE POLICY graph_pending_inv_read_policy ON "GraphPendingInvitation"
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "GraphPendingInvitation"."familyId"
        AND fm."userId" = auth.uid()::text
    )
    -- OR the recipient email/phone matches the current user's email/phone
    -- (so invitees can see invitations sent to them even before accepting)
    OR (
      "recipientEmail" IS NOT NULL
      AND "recipientEmail" = (
        SELECT email FROM "User" WHERE id = auth.uid()::text
      )
    )
  );

-- Policy: family members (admin/owner) can create pending invitations
CREATE POLICY graph_pending_inv_insert_policy ON "GraphPendingInvitation"
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "GraphPendingInvitation"."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm."role" IN ('admin', 'owner', 'member')
    )
  );

-- Policy: family members can update (accept/decline/cancel) invitations
CREATE POLICY graph_pending_inv_update_policy ON "GraphPendingInvitation"
  FOR UPDATE TO authenticated
  USING (
    -- Inviter can cancel
    "inviterUserId" = auth.uid()::text
    -- OR any family member can accept/decline (for email-matched recipients)
    OR EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "GraphPendingInvitation"."familyId"
        AND fm."userId" = auth.uid()::text
    )
    -- OR the recipient email matches the current user's email
    OR (
      "recipientEmail" IS NOT NULL
      AND "recipientEmail" = (
        SELECT email FROM "User" WHERE id = auth.uid()::text
      )
    )
  );

-- Policy: inviter can delete their own pending invitations
CREATE POLICY graph_pending_inv_delete_policy ON "GraphPendingInvitation"
  FOR DELETE TO authenticated
  USING (
    "inviterUserId" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "GraphPendingInvitation"."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm."role" IN ('admin', 'owner')
    )
  );

-- ── 3. RPC: fn_create_graph_pending_invitation ────────────────────────────
-- Called by the Flutter app when a user invites someone from the graph.
-- Stores the invitation WITHOUT creating a Person node.

CREATE OR REPLACE FUNCTION fn_create_graph_pending_invitation(
  p_family_id text,
  p_target_person_id text,
  p_relationship_key text,
  p_specific_label text,
  p_recipient_name text DEFAULT NULL,
  p_recipient_email text DEFAULT NULL,
  p_recipient_phone text DEFAULT NULL,
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
    RETURN json_build_object('success', false, 'error', 'Invalid relationship key — must be parent, spouse, adoptive_parent, or step_parent');
  END IF;

  -- Validate the target Person exists and belongs to this family
  IF NOT EXISTS(
    SELECT 1 FROM "Person"
    WHERE id = p_target_person_id
      AND "familyId" = p_family_id
      AND "deletedAt" IS NULL
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Target person not found in this family');
  END IF;

  -- Check for duplicate pending invitation (same family + target + recipient email/phone)
  IF p_recipient_email IS NOT NULL AND p_recipient_email <> '' THEN
    SELECT id INTO v_existing_pending
    FROM "GraphPendingInvitation"
    WHERE "familyId" = p_family_id
      AND "targetPersonId" = p_target_person_id
      AND "recipientEmail" = p_recipient_email
      AND "status" = 'pending'
    LIMIT 1;
  ELSIF p_recipient_phone IS NOT NULL AND p_recipient_phone <> '' THEN
    SELECT id INTO v_existing_pending
    FROM "GraphPendingInvitation"
    WHERE "familyId" = p_family_id
      AND "targetPersonId" = p_target_person_id
      AND "recipientPhone" = p_recipient_phone
      AND "status" = 'pending'
    LIMIT 1;
  END IF;

  IF v_existing_pending IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'duplicate_invitation',
      'message', 'A pending invitation already exists for this recipient'
    );
  END IF;

  -- Generate IDs
  v_invitation_id := 'gpi_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  v_invite_code := encode(gen_random_bytes(9), 'hex');

  -- Insert the pending invitation
  INSERT INTO "GraphPendingInvitation" (
    "id", "familyId", "inviterUserId",
    "targetPersonId", "relationshipKey", "specificLabelAtoB",
    "recipientName", "recipientEmail", "recipientPhone",
    "status", "expiresAt", "inviteCode",
    "createdAt", "updatedAt"
  ) VALUES (
    v_invitation_id, p_family_id, v_user_id,
    p_target_person_id, p_relationship_key, p_specific_label,
    NULLIF(p_recipient_name, ''), NULLIF(p_recipient_email, ''), NULLIF(p_recipient_phone, ''),
    'pending', now() + (p_expiry_days || ' days')::interval, v_invite_code,
    now(), now()
  );

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
  text, text, text, text, text, text, text, integer
) TO authenticated;

-- ── 4. RPC: fn_accept_graph_invitation ────────────────────────────────────
-- Called by the invitee when they accept. Creates:
--   1. A Person node (linkedUserId = accepter)
--   2. A FamilyMember record
--   3. A forward Relationship edge (targetPerson → newPerson)
--   4. An inverse Relationship edge (newPerson → targetPerson), if applicable
--   5. Updates the invitation to 'accepted'
--   6. Posts a system chat message
--   7. Creates a notification for the inviter

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
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Fetch the invitation (with FOR UPDATE to prevent race conditions)
  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Invitation not found');
  END IF;

  IF v_invitation.status <> 'pending' THEN
    RETURN json_build_object(
      'success', false,
      'error', 'invitation_not_pending',
      'message', 'This invitation has already been ' || v_invitation.status
    );
  END IF;

  -- Check expiry
  IF v_invitation.expiresAt < now() THEN
    UPDATE "GraphPendingInvitation"
    SET status = 'expired', "updatedAt" = now()
    WHERE id = p_invitation_id;
    RETURN json_build_object('success', false, 'error', 'invitation_expired');
  END IF;

  -- Check if the user is already a family member (idempotent)
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

  -- ── STEP 1: Create or reuse the Person node ──
  -- Check if a Person with this linkedUserId already exists in THIS family
  SELECT id INTO v_existing_person
  FROM "Person"
  WHERE "familyId" = v_invitation.familyId AND "linkedUserId" = v_user_id::uuid
  LIMIT 1;

  IF v_existing_person IS NULL THEN
    -- Check if a Person exists in ANY family (global unique index)
    SELECT id INTO v_existing_person
    FROM "Person"
    WHERE "linkedUserId" = v_user_id::uuid
    LIMIT 1;

    IF v_existing_person IS NULL THEN
      -- Create a new Person node
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
        false,
        0,
        'family',
        v_user_id::uuid,
        now(),
        v_user_avatar,
        now(),
        now()
      );
    ELSE
      -- Person exists in another family — link it to this family too
      -- (We create a NEW Person row in this family pointing to the same user)
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
        false,
        0,
        'family',
        v_user_id::uuid,
        now(),
        v_user_avatar,
        now(),
        now()
      );
    END IF;
  ELSE
    v_person_id := v_existing_person;
  END IF;

  -- ── STEP 2: Create the FamilyMember record ──
  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

  INSERT INTO "FamilyMember" (
    "id", "familyId", "userId", "role", "joinedAt"
  ) VALUES (
    v_member_id, v_invitation.familyId, v_user_id, 'member', now()
  );

  -- ── STEP 3: Create the forward Relationship edge ──
  -- Convention: fromPersonId = target (anchor), toPersonId = new person
  -- labelAtoB = "newPerson is targetPerson's <specificLabel>"
  -- Example: target=Manish, newPerson=Rajesh, labelAtoB='father'
  --   → "Rajesh is Manish's father"
  --   → Relationship: from=Manish, to=Rajesh, key='parent'
  v_relationship_id := 'rel_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

  INSERT INTO "Relationship" (
    "id", "familyId",
    "fromPersonId", "toPersonId",
    "relationshipKey", "relationshipType",
    "labelAtoB",
    "direction", "isActive",
    "createdAt", "updatedAt"
  ) VALUES (
    v_relationship_id,
    v_invitation.familyId,
    v_invitation.targetPersonId,   -- from = anchor
    v_person_id,                    -- to = new person
    v_invitation.relationshipKey,   -- fundamental edge type
    v_invitation.relationshipKey,
    v_invitation.specificLabelAtoB,
    'from',
    true,
    now(), now()
  );

  -- ── STEP 4: Create the inverse Relationship edge (if applicable) ──
  -- The inverse key is derived from the specific label.
  -- Example: 'father' → inverse is 'son' or 'daughter' (depending on gender)
  --          'mother' → inverse is 'son' or 'daughter'
  --          'husband' → inverse is 'wife' (symmetric — only one edge needed)
  --          'brother' → inverse is 'sister' or 'brother'
  --
  -- For simplicity, we compute a gender-aware inverse here. If the inverse
  -- key equals the forward key (symmetric), we skip the inverse edge.
  v_inverse_key := CASE
    WHEN v_invitation.specificLabelAtoB IN ('father', 'mother', 'parent') THEN
      CASE WHEN v_user_gender = 'female' THEN 'daughter' ELSE 'son' END
    WHEN v_invitation.specificLabelAtoB IN ('son', 'daughter', 'child') THEN
      CASE WHEN v_user_gender = 'female' THEN 'mother' ELSE 'father' END
    WHEN v_invitation.specificLabelAtoB IN ('husband', 'wife', 'spouse') THEN
      v_invitation.specificLabelAtoB  -- symmetric, no inverse needed
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
    AND v_inverse_key NOT IN ('husband', 'wife', 'spouse');  -- skip symmetric

  IF v_has_known_inverse THEN
    BEGIN
      v_inverse_relationship_id := 'rel_inv_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

      INSERT INTO "Relationship" (
        "id", "familyId",
        "fromPersonId", "toPersonId",
        "relationshipKey", "relationshipType",
        "labelAtoB",
        "direction", "isActive",
        "createdAt", "updatedAt"
      ) VALUES (
        v_inverse_relationship_id,
        v_invitation.familyId,
        v_person_id,                  -- from = new person
        v_invitation.targetPersonId,  -- to = anchor
        v_invitation.relationshipKey, -- same fundamental edge type
        v_invitation.relationshipKey,
        v_inverse_key,
        'inverse',
        true,
        now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Inverse edge is best-effort — don't fail the whole transaction
      v_inverse_relationship_id := NULL;
    END;
  END IF;

  -- ── STEP 5: Update the invitation to 'accepted' ──
  UPDATE "GraphPendingInvitation"
  SET
    status = 'accepted',
    "acceptedAt" = now(),
    "acceptedByUserId" = v_user_id,
    "createdPersonId" = v_person_id,
    "createdRelationshipId" = v_relationship_id,
    "updatedAt" = now()
  WHERE id = p_invitation_id;

  -- ── STEP 6: Post a system chat message ──
  BEGIN
    SELECT name INTO v_target_name FROM "Person" WHERE id = v_invitation.targetPersonId LIMIT 1;
    IF v_target_name IS NULL THEN v_target_name := 'a family member'; END IF;

    v_chat_msg_id := 'msg_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

    INSERT INTO "ChatMessage" (
      "id", "familyId", "senderId", "senderName",
      "content", "messageType", "createdAt", "updatedAt"
    ) VALUES (
      v_chat_msg_id,
      v_invitation.familyId,
      v_user_id,
      v_accepter_name,
      '🎉 ' || v_accepter_name || ' joined the family as the ' || v_invitation.specificLabelAtoB || ' of ' || v_target_name || '.',
      'system',
      now(), now()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- ── STEP 7: Create a notification for the inviter ──
  BEGIN
    v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_invitation.inviterUserId from 1 for 8);

    INSERT INTO "Notification" (
      "id", "userId", "eventType", "title", "body",
      "familyId", "channels", "priority", "read",
      "actionUrl", "createdAt", "updatedAt"
    ) VALUES (
      v_notif_id,
      v_invitation.inviterUserId,
      'invitation_accepted',
      'Family Invitation Accepted',
      v_accepter_name || ' accepted your invitation and is now the ' || v_invitation.specificLabelAtoB || ' of ' || v_target_name || '.',
      v_invitation.familyId,
      'in_app',
      'normal',
      false,
      NULL,
      now(), now()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN json_build_object(
    'success', true,
    'message', 'Successfully joined the family',
    'familyId', v_invitation.familyId,
    'personId', v_person_id,
    'memberId', v_member_id,
    'relationshipId', v_relationship_id,
    'inverseRelationshipId', v_inverse_relationship_id
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_accept_graph_invitation(text) TO authenticated;

-- ── 5. RPC: fn_decline_graph_invitation ───────────────────────────────────

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

  IF v_invitation.status <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'invitation_not_pending');
  END IF;

  -- Verify the caller is authorized (recipient email matches OR family member)
  SELECT email INTO v_user_email FROM "User" WHERE id = v_user_id;

  IF v_invitation.recipientEmail IS NOT NULL
     AND v_invitation.recipientEmail = v_user_email THEN
    -- Authorized via email match
    NULL;
  ELSIF EXISTS(
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_invitation.familyId AND "userId" = v_user_id
  ) THEN
    -- Authorized as family member
    NULL;
  ELSE
    RETURN json_build_object('success', false, 'error', 'Not authorized to decline this invitation');
  END IF;

  -- Mark as declined — NO Person node or Relationship is created
  UPDATE "GraphPendingInvitation"
  SET status = 'declined', "updatedAt" = now()
  WHERE id = p_invitation_id;

  RETURN json_build_object('success', true, 'message', 'Invitation declined');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_decline_graph_invitation(text) TO authenticated;

-- ── 6. RPC: fn_cancel_graph_invitation ────────────────────────────────────
-- Called by the inviter to cancel a pending invitation.

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

  -- Only the inviter or a family admin can cancel
  IF v_invitation.inviterUserId <> v_user_id THEN
    IF NOT EXISTS(
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = v_invitation.familyId
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

  RETURN json_build_object('success', true, 'message', 'Invitation cancelled');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cancel_graph_invitation(text) TO authenticated;

-- ── 7. RPC: fn_get_pending_graph_invitations ──────────────────────────────
-- Returns all pending invitations for a family.

CREATE OR REPLACE FUNCTION fn_get_pending_graph_invitations(
  p_family_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_result json;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Verify the caller is a family member
  IF NOT EXISTS(
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Not a member of this family');
  END IF;

  SELECT COALESCE(json_agg(
    json_build_object(
      'id', gpi.id,
      'familyId', gpi."familyId",
      'inviterUserId', gpi."inviterUserId",
      'inviterName', u.name,
      'targetPersonId', gpi."targetPersonId",
      'targetPersonName', p.name,
      'relationshipKey', gpi."relationshipKey",
      'specificLabelAtoB', gpi."specificLabelAtoB",
      'recipientName', gpi."recipientName",
      'recipientEmail', gpi."recipientEmail",
      'recipientPhone', gpi."recipientPhone",
      'status', gpi.status,
      'expiresAt', gpi."expiresAt",
      'createdAt', gpi."createdAt",
      'inviteCode', gpi."inviteCode"
    )
    ORDER BY gpi."createdAt" DESC
  ), '[]'::json) INTO v_result
  FROM "GraphPendingInvitation" gpi
  LEFT JOIN "User" u ON u.id = gpi."inviterUserId"
  LEFT JOIN "Person" p ON p.id = gpi."targetPersonId"
  WHERE gpi."familyId" = p_family_id
    AND gpi.status = 'pending'
    AND gpi."expiresAt" > now();

  RETURN json_build_object('success', true, 'invitations', v_result);
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_pending_graph_invitations(text) TO authenticated;

-- ── 8. RPC: fn_cleanup_expired_graph_invitations ──────────────────────────
-- Marks expired invitations as 'expired'. Can be called by a cron job or
-- on-demand before listing pending invitations.

CREATE OR REPLACE FUNCTION fn_cleanup_expired_graph_invitations()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE "GraphPendingInvitation"
  SET status = 'expired', "updatedAt" = now()
  WHERE status = 'pending' AND "expiresAt" < now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cleanup_expired_graph_invitations() TO authenticated;

-- ── 9. Verification ────────────────────────────────────────────────────────

SELECT 'GraphPendingInvitation table created' AS step,
       EXISTS(
         SELECT 1 FROM information_schema.tables
         WHERE table_name = 'GraphPendingInvitation'
       ) AS success;

SELECT 'fn_create_graph_pending_invitation RPC' AS step,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_create_graph_pending_invitation') AS success;

SELECT 'fn_accept_graph_invitation RPC' AS step,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_accept_graph_invitation') AS success;

SELECT 'fn_decline_graph_invitation RPC' AS step,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_decline_graph_invitation') AS success;

SELECT 'fn_cancel_graph_invitation RPC' AS step,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_cancel_graph_invitation') AS success;

SELECT 'fn_get_pending_graph_invitations RPC' AS step,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_pending_graph_invitations') AS success;

SELECT 'fn_cleanup_expired_graph_invitations RPC' AS step,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_cleanup_expired_graph_invitations') AS success;
