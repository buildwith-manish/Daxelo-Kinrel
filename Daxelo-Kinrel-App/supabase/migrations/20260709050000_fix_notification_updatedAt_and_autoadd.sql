-- =============================================================================
-- Daxelo-Kinrel — Fix fn_send_family_invite_notification + auto-add logic
-- =============================================================================
-- Two fixes:
-- 1. Fix "updatedAt NOT NULL" violation — the Notification table requires
--    updatedAt to be set (NOT NULL, no default). The previous version of
--    this function didn't set it.
--
-- 2. Add profile visibility logic:
--    - If the target user has profileVisibility = 'public', automatically
--      add them as a FamilyMember (role='member') AND link their Person
--      node if one exists — no accept/reject needed.
--    - If the target user has profileVisibility = 'private' (or anything
--      else), just send the notification so they can accept/reject
--      manually.
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_send_family_invite_notification(text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.fn_send_family_invite_notification(
  p_target_user_id text,
  p_family_id text,
  p_family_name text,
  p_invite_url text,
  p_inviter_name text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notif_id text;
  v_visibility text;
  v_existing_membership text;
  v_person_id text;
BEGIN
  -- Validate the caller is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to send an invite';
  END IF;

  -- Get the target user's profile visibility
  SELECT "profileVisibility" INTO v_visibility
  FROM "User"
  WHERE id = p_target_user_id AND "deletedAt" IS NULL;

  IF v_visibility IS NULL THEN
    -- User not found or deleted — still send the notification
    -- (they may have been deleted after search results were cached)
    v_visibility := 'private';
  END IF;

  -- Generate a unique notification ID
  v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || p_target_user_id;

  -- Insert the notification with updatedAt set (NOT NULL constraint)
  INSERT INTO "Notification" (
    "id", "userId", "eventType", "title", "body",
    "familyId", "actionUrl", "priority", "read",
    "channels", "createdAt", "updatedAt"
  ) VALUES (
    v_notif_id,
    p_target_user_id,
    'family_invite',
    COALESCE(p_inviter_name, 'Someone') || ' invited you to join ' || p_family_name,
    'You have been invited to join ' || p_family_name || ' on Daxelo Kinrel. Tap to accept.',
    p_family_id,
    p_invite_url,
    'high',
    false,
    '[]',
    now(),
    now()
  );

  -- ── Auto-add logic for public profiles ──────────────────────────
  -- If the target user has profileVisibility = 'public', automatically
  -- add them as a FamilyMember so they're instantly part of the family.
  -- For private profiles, just send the notification — they'll accept
  -- or reject manually via the notification's actionUrl.
  IF v_visibility = 'public' THEN
    -- Check if they're already a member (avoid duplicate)
    SELECT role INTO v_existing_membership
    FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = p_target_user_id;

    IF v_existing_membership IS NULL THEN
      -- Get the caller's FamilyMember.id for invitedBy FK
      DECLARE
        v_inviter_member_id text;
      BEGIN
        SELECT id INTO v_inviter_member_id
        FROM "FamilyMember"
        WHERE "familyId" = p_family_id AND "userId" = auth.uid()::text;

        -- Insert the FamilyMember row
        INSERT INTO "FamilyMember" (
          "id", "familyId", "userId", "role",
          "invitedBy", "joinedAt", "isActive"
        ) VALUES (
          'fm_' || extract(epoch from now())::bigint::text || '_' || p_target_user_id,
          p_family_id,
          p_target_user_id,
          'member',
          v_inviter_member_id,
          now(),
          true
        );

        -- Try to find and link an existing Person node for this user
        SELECT id INTO v_person_id
        FROM "Person"
        WHERE "familyId" = p_family_id
          AND "linkedUserId" = p_target_user_id
          AND "deletedAt" IS NULL
        LIMIT 1;

        -- If no Person exists, create one
        IF v_person_id IS NULL THEN
          SELECT name INTO v_person_id FROM "User" WHERE id = p_target_user_id;
          INSERT INTO "Person" (
            "id", "familyId", "name", "linkedUserId",
            "privacyLevel", "createdAt"
          ) VALUES (
            'person_' || extract(epoch from now())::bigint::text || '_' || p_target_user_id,
            p_family_id,
            COALESCE(v_person_id, 'Family Member'),
            p_target_user_id,
            'family',
            now()
          );
        END IF;

        -- Update the notification to say they were auto-added
        UPDATE "Notification"
        SET "body" = 'You have been added to ' || p_family_name || ' on Daxelo Kinrel.'
        WHERE "id" = v_notif_id;
      END;
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_send_family_invite_notification(text, text, text, text, text) TO authenticated;
