-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260907140000_fix_invite_accept_person_creation_and_stale_notifs
--
-- PURPOSE
-- Fix three bugs in the family-invite acceptance flow:
--
-- BUG #1: Accepted member doesn't appear in graph
--   Root cause: The fn_accept_family_invite RPC was previously buggy
--   (checked ANY family for an existing Person, not just the accepting
--   family). This was fixed out-of-band (v5.73), but:
--   (a) The fix was never captured in a migration → a fresh DB rebuild
--       would get the OLD buggy version.
--   (b) Users who accepted invitations BEFORE the fix have no Person
--       node → they're invisible in the graph.
--
-- BUG #2: Notification shows stale "X invited you" text after acceptance
--   Root cause: The trigger trg_auto_add_family_member fires AFTER
--   INSERT on FamilyMember and sets Notification.read=true. Then the
--   RPC's UPDATE on Notification (which updates title/body/actionUrl)
--   has `WHERE read = false` — which no longer matches because the
--   trigger already set read=true. So the notification's title/body/
--   actionUrl stay stale (showing the original invitation text instead
--   of "Invitation Accepted" / "You joined X").
--
-- BUG #3: Graph doesn't refresh after acceptance
--   Root cause: Consequence of BUG #1 — no Person INSERT means the
--   realtime subscription (which watches Person + Relationship tables)
--   never fires. Fixing BUG #1 (creating the Person) automatically
--   resolves this.
--
-- FIXES
-- 1. Capture the current (fixed) fn_accept_family_invite function
--    definition in a migration (so fresh DBs get the fix).
-- 2. Drop the redundant trg_auto_add_family_member trigger — the RPC
--    already handles the notification update more completely (title,
--    body, actionUrl, read, readAt). The trigger only sets read=true,
--    which BREAKS the RPC's UPDATE.
-- 3. Backfill Person nodes for all FamilyMembers who don't have one
--    (fixes existing accepted invitations that didn't create a Person).
-- 4. Fix stale notifications: update title/body/actionUrl for
--    family_invite notifications that were accepted (read=true) but
--    still show the original invitation text.
-- ════════════════════════════════════════════════════════════════════

-- ── FIX 1: Drop the redundant trigger (BUG #2) ──
-- The trigger fires AFTER INSERT on FamilyMember and sets
-- Notification.read=true BEFORE the RPC's UPDATE runs. This causes
-- the RPC's UPDATE (WHERE read=false) to match zero rows, leaving
-- the notification's title/body/actionUrl stale.
--
-- The RPC already handles the notification update more completely
-- (title='Invitation Accepted', body='You joined X',
-- actionUrl='accepted:<familyId>', read=true, readAt=now()). The
-- trigger is therefore redundant AND harmful — dropping it fixes
-- BUG #2.
DROP TRIGGER IF EXISTS trg_auto_add_family_member ON "FamilyMember";
DROP FUNCTION IF EXISTS fn_auto_add_family_member();

-- ── FIX 2: Capture the fixed fn_accept_family_invite (BUG #1) ──
-- This is the current production definition (with the v5.73 fix that
-- only checks THIS family for an existing Person, not any family).
-- Capturing it here ensures a fresh DB rebuild gets the fixed version.
CREATE OR REPLACE FUNCTION public.fn_accept_family_invite(
  p_family_id text,
  p_family_name text DEFAULT NULL,
  p_inviter_user_id text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

  -- Extract the inviter's user ID from the original notification
  SELECT "actionUrl" INTO v_action_url
  FROM "Notification"
  WHERE "userId" = v_user_id
    AND "eventType" = 'family_invite'
    AND "familyId" = p_family_id
  LIMIT 1;

  IF v_action_url IS NOT NULL AND v_action_url LIKE 'inviter:%' THEN
    v_inviter_id := substring(v_action_url from 'inviter:([^:]+)');
  ELSE
    v_inviter_id := NULLIF(p_inviter_user_id, '');
  END IF;

  -- ── STEP 1: Create a Person node for the user in THIS family graph ──
  -- v5.73: Only check for existing Person in THIS family (not any family).
  -- The global unique index on Person.linkedUserId has been dropped —
  -- a user can now have a Person node in multiple families. This fixes
  -- the bug where accepting an invite to family B didn't create a
  -- Person node because the user already had one in family A.
  SELECT id INTO v_existing_person
  FROM "Person"
  WHERE "familyId" = p_family_id
    AND "linkedUserId" = v_user_id::uuid
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_existing_person IS NULL THEN
    -- No Person node exists for this user in THIS family → create one.
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

  -- ── STEP 2.5: Update Family.memberCount ──
  UPDATE "Family"
  SET "memberCount" = (
    SELECT COUNT(*) FROM "FamilyMember" WHERE "familyId" = p_family_id
  ),
  "updatedAt" = now(),
  "lastActivityAt" = now()
  WHERE "id" = p_family_id;

  -- ── STEP 3: Update the original invite notification ──
  -- v5.178: Removed `AND "read" = false` from the WHERE clause.
  -- The trg_auto_add_family_member trigger (now dropped) used to set
  -- read=true BEFORE this UPDATE ran, causing it to match zero rows
  -- and leave the notification's title/body/actionUrl stale. Now that
  -- the trigger is gone, this UPDATE always matches and updates the
  -- notification to show "Invitation Accepted" / "You joined X".
  UPDATE "Notification"
  SET "read" = true,
      "readAt" = now(),
      "title" = 'Invitation Accepted',
      "body" = 'You joined ' || v_family_name,
      "actionUrl" = 'accepted:' || p_family_id,
      "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'family_invite'
    AND "familyId" = p_family_id;

  -- ── STEP 4: Post a system message in the Family Chat ──
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
$function$;

-- ── FIX 3: Backfill Person nodes for existing accepted invitations (BUG #1 data fix) ──
-- For every FamilyMember who doesn't have a corresponding Person node
-- in their family, create one using their User profile data.
-- Only processes userIds that are valid UUIDs (auth users).
INSERT INTO "Person" (
  "id", "familyId", "name", "gender",
  "isAnchor", "generationIndex", "privacyLevel",
  "linkedUserId", "linkedAt",
  "photoUrl", "createdAt", "updatedAt"
)
SELECT
  'person_backfill_' || fm."userId" || '_' || fm."familyId",
  fm."familyId",
  COALESCE(NULLIF(u.name, ''), 'Family Member'),
  u.gender,
  false,  -- isAnchor (the family creator is the anchor, not accepted members)
  0,
  'family',
  fm."userId"::uuid,
  fm."joinedAt",
  u."avatarUrl",
  now(),
  now()
FROM "FamilyMember" fm
LEFT JOIN "Person" p
  ON p."familyId" = fm."familyId"
  AND p."linkedUserId" = fm."userId"::uuid
  AND p."deletedAt" IS NULL
LEFT JOIN "User" u
  ON u.id = fm."userId"
WHERE p.id IS NULL
  AND fm."userId" IS NOT NULL
  AND fm."userId" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- ── FIX 4: Update stale notifications (BUG #2 data fix) ──
-- Fix family_invite notifications that were accepted (read=true) but
-- still show the original invitation text (title='Family Invitation').
-- Update them to show "Invitation Accepted" / "You joined X".
UPDATE "Notification" n
SET "title" = 'Invitation Accepted',
    "body" = 'You joined ' || COALESCE(f.name, 'the family'),
    "actionUrl" = 'accepted:' || n."familyId",
    "updatedAt" = now()
FROM "Family" f
WHERE n."eventType" = 'family_invite'
  AND n."read" = true
  AND n."title" = 'Family Invitation'
  AND f.id = n."familyId";

-- ── Verification ──
COMMENT ON FUNCTION public.fn_accept_family_invite(text, text, text) IS
'v5.178: Fixed — always creates Person node in accepting family, updates notification title/body/actionUrl correctly (trigger dropped).';

-- Log the backfill counts for verification
DO $$
DECLARE
  v_backfilled_persons int;
  v_fixed_notifs int;
BEGIN
  SELECT count(*) INTO v_backfilled_persons
  FROM "Person" WHERE id LIKE 'person_backfill_%';

  SELECT count(*) INTO v_fixed_notifs
  FROM "Notification"
  WHERE "eventType" = 'family_invite'
    AND "title" = 'Invitation Accepted'
    AND "actionUrl" LIKE 'accepted:%';

  RAISE NOTICE 'Backfilled % Person nodes for accepted invitations', v_backfilled_persons;
  RAISE NOTICE 'Fixed % stale family_invite notifications', v_fixed_notifs;
END;
$$;
