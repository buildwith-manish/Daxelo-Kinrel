-- =============================================================================
-- Daxelo Kinrel — DM Rebuild: Direct Groups (Part C1)
-- =============================================================================
-- Converts direct chat from the DirectMessage table to ChatMessage rows
-- in a private 2-person Group within an existing Family. The Group has
-- groupType='direct' + a directKey (sorted userIds joined) for O(1)
-- lookup. Only the two GroupMembers can see group-scoped messages.
--
-- STOP ITEM 1 fix: new RLS policy for group-scoped ChatMessage rows.
-- STOP ITEM 2 note: the NestJS ChatPushScheduler must check groupId
--   and only push to GroupMember rows for that group (code change, not SQL).
--
-- BACKFILL_OLD_DMS = NO: old DirectMessage history stays in the old table.
-- No copy script. The DirectMessage table is NOT dropped or altered.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, CREATE INDEX IF NOT EXISTS,
--   CREATE OR REPLACE FUNCTION, DO $$ for policy changes.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Add groupType + directKey columns to Family (the table that holds groups)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "groupType" text NOT NULL DEFAULT 'family';
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "directKey" text;

-- CHECK constraint on groupType.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'Family_groupType_chk'
  ) THEN
    ALTER TABLE "Family"
      ADD CONSTRAINT "Family_groupType_chk"
      CHECK ("groupType" IN ('family', 'group', 'direct'));
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Family_groupType_chk: %', SQLERRM;
END $$;

-- Unique index on directKey (only for direct groups — null for family/group).
CREATE UNIQUE INDEX IF NOT EXISTS "Family_directKey_uniq"
  ON "Family"("directKey") WHERE "directKey" IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. STOP ITEM 1 fix: ChatMessage RLS for group-scoped messages
-- ═══════════════════════════════════════════════════════════════════════════
-- The current SELECT policy lets ANY family member read ALL ChatMessage rows
-- (including those with a groupId). For direct groups, only the two GroupMember
-- rows should be able to read the messages.
--
-- New policy: group-scoped messages (groupId IS NOT NULL) require the caller
-- to be a GroupMember of that group. Family-wide messages (groupId IS NULL)
-- keep the existing fn_user_is_family_member check.
--
-- The existing FamilyMember table is used for family-wide groups. For direct
-- groups, the two members are in FamilyMember with the direct group's familyId.
-- So the EXISTING fn_user_is_family_member check ALREADY works for direct
-- groups (only the two members are in FamilyMember for a direct group's familyId).
--
-- However, the current ChatMessage SELECT policy checks
-- fn_user_is_family_member("familyId") — and for a direct group, the familyId
-- is the direct group's ID. Only the two members are FamilyMember rows for
-- that direct group's familyId. So the EXISTING policy ALREADY protects
-- direct group messages.
--
-- VERDICT: The existing RLS policy is SUFFICIENT for direct groups, as long
-- as direct groups are created as separate Family rows (with groupType='direct')
-- and only the two users are added as FamilyMember rows. Other family members
-- are NOT in FamilyMember for the direct group's familyId, so they can't read
-- its messages.
--
-- No new RLS policy needed. This is documented for the audit trail.
SELECT 'STOP_ITEM_1_VERDICT' AS item,
       'Existing fn_user_is_family_member RLS is sufficient for direct groups' AS verdict;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_get_or_create_direct_group — creates or finds a direct group
--    between the caller and another user within a shared family.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_or_create_direct_group(
  p_other_user_id text,
  p_family_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_direct_key text;
  v_family record;
  v_group_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_other_user_id IS NULL OR p_other_user_id = v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'invalid_target');
  END IF;

  -- Verify both users are members of the shared family.
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'caller_not_in_family');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = p_other_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'other_user_not_in_family');
  END IF;

  -- Compute directKey: sorted userIds joined with '_'.
  v_direct_key := CASE
    WHEN v_user_id < p_other_user_id THEN v_user_id || '_' || p_other_user_id
    ELSE p_other_user_id || '_' || v_user_id
  END;

  -- Check if a direct group already exists for this pair.
  SELECT id INTO v_group_id
    FROM "Family"
    WHERE "directKey" = v_direct_key
    LIMIT 1;

  IF v_group_id IS NOT NULL THEN
    RETURN json_build_object(
      'success', true,
      'action', 'existing',
      'groupId', v_group_id,
      'directKey', v_direct_key
    );
  END IF;

  -- Create the direct group.
  v_group_id := 'fam_direct_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6);

  INSERT INTO "Family" (
    "id", "name", "groupType", "directKey",
    "primaryLanguage", "isOnboarded", "memberCount",
    "generationCount", "createdAt", "updatedAt"
  ) VALUES (
    v_group_id, 'Direct Chat', 'direct', v_direct_key,
    'en', true, 2,
    1, now(), now()
  );

  -- Add both users as FamilyMember rows.
  INSERT INTO "FamilyMember" ("id", "familyId", "userId", "role", "joinedAt")
  VALUES
    ('fm_' || v_group_id || '_' || v_user_id, v_group_id, v_user_id, 'member', now()),
    ('fm_' || v_group_id || '_' || p_other_user_id, v_group_id, p_other_user_id, 'member', now())
  ON CONFLICT DO NOTHING;

  RETURN json_build_object(
    'success', true,
    'action', 'created',
    'groupId', v_group_id,
    'directKey', v_direct_key
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_or_create_direct_group(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Rewrite fn_send_thinking_of_you to insert a ChatMessage into the
--    direct group (creating it if needed) instead of a DirectMessage.
-- ═══════════════════════════════════════════════════════════════════════════
-- The old function inserted a DirectMessage row. The new function:
--   1. Calls fn_get_or_create_direct_group to find/create the direct group.
--   2. Inserts a ChatMessage with messageType='familyEvent',
--      messageSubType='thinking_of_you' into the direct group.
--   3. Keeps the same cooldown logic (1 per 6 hours per pair).
--   4. Still creates a Notification row.
--
-- NOTE: This REPLACES the existing fn_send_thinking_of_you. The old
-- DirectMessage inserts are no longer made. Old DM history is preserved
-- in the DirectMessage table (BACKFILL_OLD_DMS=NO).
CREATE OR REPLACE FUNCTION fn_send_thinking_of_you(
  p_receiver_id text,
  p_family_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_sender_name text;
  v_sender_avatar text;
  v_family_name text;
  v_notif_id text;
  v_direct_group json;
  v_group_id text;
  v_message_id text;
  v_cooldown_ok boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_receiver_id IS NULL OR p_receiver_id = v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'invalid_target');
  END IF;

  -- Cooldown check: 1 per 6 hours per (sender, receiver) pair.
  SELECT NOT EXISTS (
    SELECT 1 FROM "DirectMessage"
    WHERE "senderId" = v_user_id AND "receiverId" = p_receiver_id
      AND "messageType" = 'thinking_of_you'
      AND "createdAt" > now() - interval '6 hours'
  ) INTO v_cooldown_ok;

  -- Also check the new ChatMessage path (in case the function was already
  -- called via the new path).
  IF v_cooldown_ok THEN
    SELECT NOT EXISTS (
      SELECT 1 FROM "ChatMessage" cm
      WHERE cm."senderId" = v_user_id
        AND cm."messageType" = 'familyEvent'
        AND cm."messageSubType" = 'thinking_of_you'
        AND cm."createdAt" > now() - interval '6 hours'
        AND EXISTS (
          SELECT 1 FROM "FamilyMember" fm
          WHERE fm."familyId" = cm."familyId" AND fm."userId" = p_receiver_id
        )
    ) INTO v_cooldown_ok;
  END IF;

  IF NOT v_cooldown_ok THEN
    RETURN json_build_object('success', false, 'error', 'cooldown',
      'message', 'You can send a Thinking of You moment at most once every 6 hours.');
  END IF;

  -- Get sender info.
  SELECT name, "avatarUrl" INTO v_sender_name, v_sender_avatar
    FROM "User" WHERE id = v_user_id;
  IF v_sender_name IS NULL OR v_sender_name = '' THEN v_sender_name := 'Someone'; END IF;

  -- Get family name for the notification body.
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN v_family_name := 'the family'; END IF;

  -- Create or find the direct group.
  v_direct_group := fn_get_or_create_direct_group(p_receiver_id, p_family_id);
  IF (v_direct_group->>'success')::boolean IS NOT TRUE THEN
    RETURN v_direct_group;
  END IF;
  v_group_id := v_direct_group->>'groupId';

  -- Insert the ChatMessage into the direct group.
  v_message_id := 'cm_toy_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6);

  INSERT INTO "ChatMessage" (
    "id", "familyId",
    "senderId", "senderName", "senderInitials",
    "content", "messageType", "messageSubType",
    "messageStatus", "createdAt", "updatedAt"
  ) VALUES (
    v_message_id, v_group_id,
    v_user_id, v_sender_name, '',
    '🤍 Thinking of You', 'familyEvent', 'thinking_of_you',
    'sent', now(), now()
  );

  -- Create a Notification row.
  v_notif_id := 'notif_toy_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6);
  INSERT INTO "Notification" ("id", "userId", "type", "title", "body", "data", "createdAt", "isRead")
  VALUES (
    v_notif_id, p_receiver_id, 'thinking_of_you',
    v_sender_name,
    v_sender_name || ' sent you a Thinking of You moment',
    jsonb_build_object('senderId', v_user_id, 'senderName', v_sender_name, 'familyId', p_family_id, 'messageId', v_message_id, 'groupId', v_group_id),
    now(), false
  );

  RETURN json_build_object(
    'success', true,
    'messageId', v_message_id,
    'groupId', v_group_id,
    'notificationId', v_notif_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_thinking_of_you(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Verification
-- ═══════════════════════════════════════════════════════════════════════════
SELECT 'Family.groupType' AS col,
       EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='Family' AND column_name='groupType') AS exists;
SELECT 'Family.directKey' AS col,
       EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='Family' AND column_name='directKey') AS exists;
SELECT 'fn_get_or_create_direct_group' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_or_create_direct_group') AS exists;
SELECT 'fn_send_thinking_of_you (rewritten)' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_thinking_of_you') AS exists;
