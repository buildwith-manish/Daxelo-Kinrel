-- =============================================================================
-- Daxelo Kinrel — Fix Family Invitation Acceptance (Phase 19)
-- =============================================================================
-- Problem: When users tapped "Accept" on a family invitation, the RPC
-- fn_accept_family_invite failed with the error:
--   column "actionurl" does not exist
--
-- Root cause: Line in the RPC read:
--     SELECT actionUrl INTO v_inviter_id
--     FROM "Notification"
-- PostgreSQL lowercases unquoted identifiers, so `actionUrl` became
-- `actionurl`, which doesn't exist (the actual column is `"actionUrl"`
-- with a capital U). This threw an exception which the outer
-- `EXCEPTION WHEN OTHERS THEN` block caught and returned as
-- `{success: false, error: 'column "actionurl" does not exist'}`,
-- which the Flutter app rendered as "Could not accept invitation."
--
-- Fix: Quote the column name as `"actionUrl"`. Also tighten the
-- inviter ID extraction so it correctly parses the
-- 'inviter:<userId>:<url>' format stored by fn_send_family_invite_notification.
-- =============================================================================

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
  v_action_url text;
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

  -- ── Extract the inviter's user ID from the original notification ──
  -- The notification's "actionUrl" is stored as 'inviter:<userId>:<url>'.
  -- We MUST quote "actionUrl" because the column name is camelCase
  -- (unquoted `actionUrl` gets lowercased to `actionurl` which doesn't exist).
  SELECT "actionUrl" INTO v_action_url
  FROM "Notification"
  WHERE "userId" = v_user_id
    AND "eventType" = 'family_invite'
    AND "familyId" = p_family_id
    AND "read" = false
  LIMIT 1;

  -- Parse the inviter ID from 'inviter:<userId>:<url>'
  IF v_action_url IS NOT NULL AND v_action_url LIKE 'inviter:%' THEN
    v_inviter_id := substring(v_action_url from 'inviter:([^:]+)');
  ELSE
    -- Fall back to the explicit parameter (if provided)
    v_inviter_id := NULLIF(p_inviter_user_id, '');
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

-- Verification
SELECT 'fn_accept_family_invite (actionUrl quoting fixed)' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_accept_family_invite') AS exists;
