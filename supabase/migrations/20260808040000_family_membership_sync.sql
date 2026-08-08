-- =============================================================================
-- Daxelo Kinrel — Complete Family Membership Sync Fix
-- =============================================================================
-- When a user accepts a family invitation:
--   1. Creates a Person node in the family graph (if one doesn't exist)
--   2. Links the Person to the user's Kinrel account (linkedUserId)
--   3. Creates the FamilyMember record
--   4. Posts a 🎉 system chat message
--   5. Creates acceptance notification for the inviter
--   6. Updates the original invite notification's status
--   7. Prevents duplicate Person nodes + duplicate FamilyMember records
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. fn_accept_family_invite (FINAL COMPLETE VERSION)
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
  v_person_id text;
  v_existing_person text;
  v_user_name text;
  v_user_gender text;
  v_user_avatar text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Check if already a FamilyMember (idempotent — prevents duplicates)
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

  -- Get the accepter's name + details from the User table
  SELECT name, gender, "avatarUrl" INTO v_accepter_name, v_user_gender, v_user_avatar
  FROM "User" WHERE id = v_user_id;
  IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
    v_accepter_name := 'A new member';
  END IF;

  -- Find the original family_invite notification to extract the inviter's user ID
  -- (stored in actionUrl as 'inviter:<userId>:<inviteUrl>')
  SELECT actionUrl INTO v_inviter_id
  FROM "Notification"
  WHERE "userId" = v_user_id
    AND "eventType" = 'family_invite'
    AND "familyId" = p_family_id
    AND "read" = false
  LIMIT 1;

  -- Extract inviter ID from actionUrl: 'inviter:<userId>:<url>'
  IF v_inviter_id IS NOT NULL AND v_inviter_id LIKE 'inviter:%' THEN
    -- Parse: inviter:USER_ID:URL → extract USER_ID
    v_inviter_id := substring(v_inviter_id from 'inviter:([^:]+)');
  ELSE
    v_inviter_id := COALESCE(NULLIF(p_inviter_user_id, ''), NULL);
  END IF;

  -- ── STEP 1: Create a Person node for the user in the family graph ──
  -- Check if a Person node with this linkedUserId already exists in THIS family
  SELECT id INTO v_existing_person
  FROM "Person"
  WHERE "familyId" = p_family_id AND "linkedUserId" = v_user_id::uuid
  LIMIT 1;

  IF v_existing_person IS NULL THEN
    -- Check if a Person node with this linkedUserId exists in ANY family
    -- (the global unique index on linkedUserId prevents multiple nodes
    -- for the same user — so if one exists, we DON'T create a new one)
    SELECT id INTO v_existing_person
    FROM "Person"
    WHERE "linkedUserId" = v_user_id::uuid
    LIMIT 1;

    IF v_existing_person IS NULL THEN
      -- No Person node exists for this user → create one in this family
      v_person_id := 'person_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

      INSERT INTO "Person" (
        "id", "familyId", "name", "gender",
        "isAnchor", "generationIndex", "privacyLevel",
        "linkedUserId", "linkedAt",
        "photoUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_person_id,
        p_family_id,
        v_accepter_name,
        v_user_gender,
        false,           -- isAnchor (the family creator is the anchor)
        0,               -- generationIndex (same generation as the anchor)
        'family',
        v_user_id::uuid,
        now(),
        v_user_avatar,
        now(),
        now()
      );
    ELSE
      -- Person node exists in ANOTHER family with this linkedUserId.
      -- The global unique index prevents creating a duplicate.
      -- Use the existing Person's ID (the graph will show them as a node
      -- in the family where they were originally added; joining a new
      -- family creates the FamilyMember record but not a new Person node).
      v_person_id := v_existing_person;
    END IF;
  ELSE
    -- Person node already exists in this family — use it
    v_person_id := v_existing_person;
  END IF;

  -- ── STEP 2: Create the FamilyMember record ──
  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

  INSERT INTO "FamilyMember" (
    "id", "familyId", "userId", "role", "joinedAt"
  ) VALUES (
    v_member_id, p_family_id, v_user_id, 'member', now()
  );

  -- ── STEP 3: Update the original invite notification ──
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

  -- ── STEP 4: Post a 🎉 system message in the Family Chat ──
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

  -- ── STEP 5: Create acceptance notification for the inviter ──
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
    'memberId', v_member_id,
    'personId', v_person_id
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_accept_family_invite(text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'fn_accept_family_invite (with Person node + chat)' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_accept_family_invite') AS exists;
