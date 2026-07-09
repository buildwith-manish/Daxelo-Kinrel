-- =============================================================================
-- Daxelo-Kinrel — Fix fn_send_family_invite_notification: FamilyMember columns
-- =============================================================================
-- The auto-add logic tried to INSERT into FamilyMember with "invitedBy" and
-- "isActive" columns that DON'T EXIST on the FamilyMember table.
-- The actual FamilyMember table has only: id, familyId, userId, role, joinedAt.
--
-- Fix: only insert into the columns that exist. Drop invitedBy and isActive.
-- Also fix the Person insert to only use columns that exist on the Person table.
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
  v_existing_role text;
  v_person_id text;
  v_user_name text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to send an invite';
  END IF;

  -- Get the target user's profile visibility
  SELECT "profileVisibility", name INTO v_visibility, v_user_name
  FROM "User"
  WHERE id = p_target_user_id AND "deletedAt" IS NULL;

  IF v_visibility IS NULL THEN
    v_visibility := 'private';
  END IF;
  IF v_user_name IS NULL THEN
    v_user_name := 'Family Member';
  END IF;

  -- Generate notification ID
  v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || p_target_user_id;

  -- Insert notification — updatedAt and channels are NOT NULL
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

  -- ── Auto-add for public profiles ────────────────────────────────
  IF v_visibility = 'public' THEN
    -- Check if already a member
    SELECT role INTO v_existing_role
    FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = p_target_user_id;

    IF v_existing_role IS NULL THEN
      -- Insert FamilyMember — ONLY the columns that exist:
      -- id, familyId, userId, role, joinedAt
      INSERT INTO "FamilyMember" (
        "id", "familyId", "userId", "role", "joinedAt"
      ) VALUES (
        'fm_' || extract(epoch from now())::bigint::text || '_' || p_target_user_id,
        p_family_id,
        p_target_user_id,
        'member',
        now()
      );

      -- Find or create a Person node for this user
      SELECT id INTO v_person_id
      FROM "Person"
      WHERE "familyId" = p_family_id
        AND "linkedUserId" = p_target_user_id
        AND "deletedAt" IS NULL
      LIMIT 1;

      IF v_person_id IS NULL THEN
        INSERT INTO "Person" (
          "id", "familyId", "name", "linkedUserId",
          "privacyLevel"
        ) VALUES (
          'person_' || extract(epoch from now())::bigint::text || '_' || p_target_user_id,
          p_family_id,
          v_user_name,
          p_target_user_id,
          'family'
        );
      END IF;

      -- Update notification to say they were auto-added
      UPDATE "Notification"
      SET "body" = 'You have been added to ' || p_family_name || ' on Daxelo Kinrel.'
      WHERE "id" = v_notif_id;
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_send_family_invite_notification(text, text, text, text, text) TO authenticated;
