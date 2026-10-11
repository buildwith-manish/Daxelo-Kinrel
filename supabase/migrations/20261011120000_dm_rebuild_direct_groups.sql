-- =============================================================================
-- Daxelo Kinrel — DM Rebuild: Direct Groups (Part C1)
-- =============================================================================
-- Converts direct chat from the DirectMessage table to ChatMessage rows
-- scoped to a PRIVATE 2-person "Group" (groupType='direct') that lives
-- inside an existing Family. The Group carries a directKey (the two user
-- ids sorted and joined with '_') with a unique partial index for O(1)
-- lookup. Only the two GroupMembers can see the direct group's messages.
--
-- DESIGN (per the Kin Thread spec, Part C0 audit):
--   • Groups table  = "Group"      (created in 20260813000000) — NOT "Family".
--   • Members table = "GroupMember" (UNIQUE("groupId","userId")).
--   • groupType on "Group" has NO check constraint (values are only
--     documented in comments: cousins|parents|siblings|family_event|
--     travel|custom) → 'direct' is already allowed; no constraint needs
--     to be relaxed or added (adding one could break legacy rows).
--   • Direct groups never appear in group lists (app-side filter on
--     groupType <> 'direct'); Group.name gets a neutral value ('Direct')
--     and the app always shows the other person.
--   • No shared family → no message button (the RPC rejects when the two
--     users share no family; the app resolves the family it was started
--     from, or the oldest shared family).
--
-- STOP ITEM 1 fix (privacy): the LIVE ChatMessage policies (from
-- 20260813000000) allow any family member to read/write group-scoped
-- rows via fn_user_is_group_member, whose SECOND branch passes for every
-- FamilyMember of the group's family. For a direct group that means the
-- whole family could read the private chat. This migration replaces the
-- ChatMessage / GroupMember / Group / ChatMessageReaction /
-- ChatReadReceipt policies with versions that treat groupType='direct'
-- groups STRICTLY (GroupMember rows only) while leaving family-wide
-- chat (groupId IS NULL) and normal groups EXACTLY as visible as before.
--
-- STOP ITEM 2 note (notifications — NestJS code, not SQL): the ChatPush
-- scheduler (server/src/modules/chat/chat-push.scheduler.ts) resolves
-- recipients via FamilyMember on msg.familyId and ignores groupId, so it
-- would push a direct-group message to the whole family. Required code
-- fix (to apply in server/, described exactly here per the C0 audit):
--   1. In the batching query, keep rows regardless of groupId.
--   2. When resolving recipients per message, branch on msg.groupId:
--        if (msg.groupId != null) {
--          members = await prisma.groupMember.findMany({
--            where: { groupId: msg.groupId },
--            select: { userId: true },
--          });
--        } else {
--          members = await prisma.familyMember.findMany({
--            where: { familyId: msg.familyId },
--            select: { userId: true },
--          });
--        }
--   3. Keep the sender-skip and readBy-skip logic unchanged.
--   (server/ is intentionally NOT modified in this PR — C1 is SQL+docs,
--   C2 is Dart only. Apply the snippet above when deploying C2.)
--
-- BACKFILL_OLD_DMS = NO: old DirectMessage history stays in the old
-- table. No copy script. The DirectMessage table is NOT dropped or
-- altered in any way.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, CREATE INDEX IF NOT EXISTS,
-- CREATE OR REPLACE FUNCTION, DROP POLICY IF EXISTS before every
-- CREATE POLICY. Safe to re-run.
--
-- APPLY ORDER (safe):
--   1. Back up the database (pg_dump or Supabase dashboard backup).
--   2. Run this migration (all statements are additive/idempotent).
--   3. Run the verification SELECTs at the bottom (and the manual
--      privacy proof in supabase/manual/dm_privacy_proof.sql as two
--      users + a third family member).
--   4. Deploy the C2 Dart changes (they depend on
--      fn_get_or_create_direct_group existing).
--   5. Apply the NestJS ChatPushScheduler snippet above (STOP ITEM 2).
--
-- ROLLBACK (in order):
--   1. Roll back the Dart deploy (C2) — direct chats then fall back to
--      erroring gracefully instead of using the RPC.
--   2. DROP FUNCTION IF EXISTS fn_get_or_create_direct_group(text, text);
--   3. Restore the previous fn_send_thinking_of_you definition by
--      re-running 20260808180000_thinking_of_you_private_1to1.sql.
--   4. Re-run the policy block from 20260813000000_create_family_groups.sql
--      (sections 7-9) and the original ChatMessageReaction /
--      ChatReadReceipt policies from 20260628120000_create_chat_messages.sql
--      to restore the pre-migration (family-wide) policies.
--   5. DELETE FROM "GroupMember" gm USING "Group" g
--        WHERE g.id = gm."groupId" AND g."groupType" = 'direct';
--      DELETE FROM "Group" WHERE "groupType" = 'direct';
--   6. DROP INDEX IF EXISTS "Group_directKey_uniq";
--      ALTER TABLE "Group" DROP COLUMN IF EXISTS "directKey";
--   7. Direct groups' ChatMessage rows (groupId pointing at a deleted
--      group cascade-delete via the FK) — if you want to keep them,
--      export them before step 5.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Group table: directKey column + unique partial index
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE "Group" ADD COLUMN IF NOT EXISTS "directKey" text;

-- Unique index: at most ONE direct group per user pair. Partial (WHERE
-- directKey IS NOT NULL) so normal groups are unaffected.
CREATE UNIQUE INDEX IF NOT EXISTS "Group_directKey_uniq"
  ON "Group"("directKey") WHERE "directKey" IS NOT NULL;

-- Helpful lookup for the inbox (my direct groups).
CREATE INDEX IF NOT EXISTS "GroupMember_userId_idx" ON "GroupMember"("userId");

-- NOTE on groupType: "Group"."groupType" has NO CHECK constraint in any
-- migration (its values are comment-documented only), so 'direct' is
-- valid without any constraint change. We deliberately do NOT add a
-- CHECK here — legacy rows may contain undocumented values and adding
-- a constraint could fail the migration.

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. STOP ITEM 1 fix — strict access helper for direct groups
-- ═══════════════════════════════════════════════════════════════════════════
-- fn_user_is_group_member(group_id) passes for ANY FamilyMember of the
-- group's family (second branch). That is fine for normal sub-groups but
-- leaks a direct chat to the whole family. This helper is strict for
-- groupType='direct' (GroupMember rows only) and delegates to the
-- existing behavior for every other group.
CREATE OR REPLACE FUNCTION fn_user_can_access_group_chat(group_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        CASE
            WHEN EXISTS (
                SELECT 1 FROM "Group" g
                WHERE g.id = group_id AND g."groupType" = 'direct'
            )
            THEN EXISTS (
                SELECT 1 FROM "GroupMember" gm
                WHERE gm."groupId" = group_id
                  AND gm."userId" = auth.uid()::text
            )
            ELSE fn_user_is_group_member(group_id)
        END;
$$;

-- ── ChatMessage policies: replace the group branch with the helper ──
-- Family-wide rows (groupId IS NULL) and normal groups keep EXACTLY the
-- previous visibility; direct-group rows become GroupMember-only.

DROP POLICY IF EXISTS chatmessage_select_policy ON "ChatMessage";
CREATE POLICY chatmessage_select_policy
    ON "ChatMessage" FOR SELECT
    USING (
        ("groupId" IS NULL AND fn_user_is_family_member("familyId"))
        OR ("groupId" IS NOT NULL AND fn_user_can_access_group_chat("groupId"))
    );

DROP POLICY IF EXISTS chatmessage_insert_policy ON "ChatMessage";
CREATE POLICY chatmessage_insert_policy
    ON "ChatMessage" FOR INSERT
    WITH CHECK (
        "senderId" = auth.uid()::text
        AND (
            ("groupId" IS NULL AND fn_user_is_family_member("familyId"))
            OR ("groupId" IS NOT NULL AND fn_user_can_access_group_chat("groupId"))
        )
    );

DROP POLICY IF EXISTS chatmessage_update_policy ON "ChatMessage";
CREATE POLICY chatmessage_update_policy
    ON "ChatMessage" FOR UPDATE
    USING (
        ("groupId" IS NULL AND fn_user_is_family_member("familyId"))
        OR ("groupId" IS NOT NULL AND fn_user_can_access_group_chat("groupId"))
    )
    WITH CHECK (
        ("groupId" IS NULL AND fn_user_is_family_member("familyId"))
        OR ("groupId" IS NOT NULL AND fn_user_can_access_group_chat("groupId"))
    );
-- (chatmessage_delete_policy stays sender-only — unchanged.)

-- ── GroupMember SELECT: strict for direct groups ─────────────────────
-- Previously fn_user_is_group_member("groupId") let any family member
-- list WHO is in a direct group. Now direct-group memberships are
-- visible only to the two members.
DROP POLICY IF EXISTS groupmember_select_policy ON "GroupMember";
CREATE POLICY groupmember_select_policy
    ON "GroupMember" FOR SELECT
    USING (fn_user_can_access_group_chat("groupId"));
-- (insert/update/delete policies unchanged — the RPC below creates
-- memberships as SECURITY DEFINER, and self-update/delete stays open.)

-- ── Group SELECT: strict for direct groups ───────────────────────────
-- Family members keep seeing every NORMAL group in their family;
-- direct groups are visible only to their two members.
DROP POLICY IF EXISTS group_select_policy ON "Group";
CREATE POLICY group_select_policy
    ON "Group" FOR SELECT
    USING (
        (("groupType" IS NULL OR "groupType" <> 'direct')
            AND fn_user_is_family_member("familyId"))
        OR ("groupType" = 'direct'
            AND EXISTS (
                SELECT 1 FROM "GroupMember" gm
                WHERE gm."groupId" = "Group".id
                  AND gm."userId" = auth.uid()::text
            ))
    );
-- (insert/update/delete policies on "Group" unchanged.)

-- ── ChatMessageReaction: strict for direct-group messages ────────────
DROP POLICY IF EXISTS chatreaction_select_policy ON "ChatMessageReaction";
CREATE POLICY chatreaction_select_policy
    ON "ChatMessageReaction" FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM "ChatMessage" m
            WHERE m.id = "ChatMessageReaction"."messageId"
              AND (
                  (m."groupId" IS NULL AND fn_user_is_family_member(m."familyId"))
                  OR (m."groupId" IS NOT NULL AND fn_user_can_access_group_chat(m."groupId"))
              )
        )
    );

DROP POLICY IF EXISTS chatreaction_insert_policy ON "ChatMessageReaction";
CREATE POLICY chatreaction_insert_policy
    ON "ChatMessageReaction" FOR INSERT
    WITH CHECK (
        "userId" = auth.uid()::text
        AND EXISTS (
            SELECT 1 FROM "ChatMessage" m
            WHERE m.id = "ChatMessageReaction"."messageId"
              AND (
                  (m."groupId" IS NULL AND fn_user_is_family_member(m."familyId"))
                  OR (m."groupId" IS NOT NULL AND fn_user_can_access_group_chat(m."groupId"))
              )
        )
    );
-- (chatreaction_delete_policy stays reactor-only — unchanged.)

-- ── ChatReadReceipt: strict for direct-group messages ────────────────
DROP POLICY IF EXISTS chatreadreceipt_select_policy ON "ChatReadReceipt";
CREATE POLICY chatreadreceipt_select_policy
    ON "ChatReadReceipt" FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM "ChatMessage" m
            WHERE m.id = "ChatReadReceipt"."messageId"
              AND (
                  (m."groupId" IS NULL AND fn_user_is_family_member(m."familyId"))
                  OR (m."groupId" IS NOT NULL AND fn_user_can_access_group_chat(m."groupId"))
              )
        )
    );

DROP POLICY IF EXISTS chatreadreceipt_insert_policy ON "ChatReadReceipt";
CREATE POLICY chatreadreceipt_insert_policy
    ON "ChatReadReceipt" FOR INSERT
    WITH CHECK (
        "userId" = auth.uid()::text
        AND EXISTS (
            SELECT 1 FROM "ChatMessage" m
            WHERE m.id = "ChatReadReceipt"."messageId"
              AND (
                  (m."groupId" IS NULL AND fn_user_is_family_member(m."familyId"))
                  OR (m."groupId" IS NOT NULL AND fn_user_can_access_group_chat(m."groupId"))
              )
        )
    );
-- (chatreadreceipt_delete_policy stays self-only — unchanged.)

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_get_or_create_direct_group — find or create the private 2-person
--    group between the caller and another user (Part C1, per spec).
-- ═══════════════════════════════════════════════════════════════════════════
-- Follows the house RPC style (SECURITY DEFINER + SET search_path, manual
-- ids, membership verification via FamilyMember, GRANT to authenticated)
-- exactly like fn_create_group in 20260813000000.
--
-- p_family_id semantics: the family the direct group lives in — the one
-- it was started from. When NULL, the OLDEST family both users share is
-- chosen automatically. Self-chat is rejected. Returns json:
--   { success, action: 'existing'|'created', groupId, familyId, directKey,
--     otherUserName }
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
  v_family_id text := p_family_id;
  v_direct_key text;
  v_group_id text;
  v_my_name text;
  v_other_name text;
  v_other_avatar text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Reject self chat.
  IF p_other_user_id IS NULL OR p_other_user_id = v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'invalid_target');
  END IF;

  -- Resolve the family: the caller-provided one, or (when unknown, e.g.
  -- opened from the global inbox) the OLDEST family both users share.
  IF v_family_id IS NULL OR v_family_id = '' THEN
    SELECT f.id INTO v_family_id
    FROM "Family" f
    JOIN "FamilyMember" fm1 ON fm1."familyId" = f.id AND fm1."userId" = v_user_id
    JOIN "FamilyMember" fm2 ON fm2."familyId" = f.id AND fm2."userId" = p_other_user_id
    ORDER BY f."createdAt" ASC
    LIMIT 1;
  END IF;

  IF v_family_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'no_shared_family');
  END IF;

  -- Verify BOTH users are members of that family (explicit, even when
  -- resolved above, to also cover the caller-provided case).
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_family_id AND "userId" = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'caller_not_in_family');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_family_id AND "userId" = p_other_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'other_user_not_in_family');
  END IF;

  -- directKey: the two user ids sorted and joined with '_'.
  v_direct_key := CASE
    WHEN v_user_id < p_other_user_id THEN v_user_id || '_' || p_other_user_id
    ELSE p_other_user_id || '_' || v_user_id
  END;

  -- Existing direct group for this pair?
  SELECT id INTO v_group_id
    FROM "Group"
    WHERE "directKey" = v_direct_key
    LIMIT 1;

  IF v_group_id IS NOT NULL THEN
    SELECT COALESCE(name, 'Kinrel member') INTO v_other_name
      FROM "User" WHERE id = p_other_user_id;
    RETURN json_build_object(
      'success', true,
      'action', 'existing',
      'groupId', v_group_id,
      'familyId', v_family_id,
      'directKey', v_direct_key,
      'otherUserName', COALESCE(v_other_name, 'Kinrel member')
    );
  END IF;

  -- Display names for the GroupMember rows.
  SELECT COALESCE(name, 'Kinrel member') INTO v_my_name
    FROM "User" WHERE id = v_user_id;
  SELECT COALESCE(name, 'Kinrel member'), "avatarUrl" INTO v_other_name, v_other_avatar
    FROM "User" WHERE id = p_other_user_id;

  -- Create the direct group. Group.name gets a NEUTRAL value — the app
  -- always displays the other person's name instead.
  v_group_id := 'grp_direct_'
    || extract(epoch from now())::bigint::text
    || '_' || substring(v_user_id from 1 for 6)
    || '_' || substring(p_other_user_id from 1 for 6);

  INSERT INTO "Group" (
    "id", "familyId", "name", "groupType", "directKey",
    "createdBy", "lastActivityAt", "createdAt", "updatedAt"
  ) VALUES (
    v_group_id, v_family_id, 'Direct', 'direct', v_direct_key,
    v_user_id, now(), now(), now()
  );

  -- The two (and only two) members.
  INSERT INTO "GroupMember" (
    "id", "groupId", "userId", "displayName", "role", "isGuest", "joinedAt"
  ) VALUES
    ('gm_' || v_group_id || '_a', v_group_id, v_user_id,
     COALESCE(v_my_name, 'Kinrel member'), 'member', false, now()),
    ('gm_' || v_group_id || '_b', v_group_id, p_other_user_id,
     COALESCE(v_other_name, 'Kinrel member'), 'member', false, now())
  ON CONFLICT ("groupId", "userId") DO NOTHING;

  RETURN json_build_object(
    'success', true,
    'action', 'created',
    'groupId', v_group_id,
    'familyId', v_family_id,
    'directKey', v_direct_key,
    'otherUserName', COALESCE(v_other_name, 'Kinrel member'),
    'otherUserAvatar', v_other_avatar
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_or_create_direct_group(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Rewrite fn_send_thinking_of_you — insert a ChatMessage into the
--    direct group (creating it if needed) instead of a DirectMessage.
-- ═══════════════════════════════════════════════════════════════════════════
-- Same text templates, same 6h cooldowns (sender→receiver pair AND
-- receiver-wide), same Notification + analytics. Only the delivery
-- changes: messageType='familyEvent', messageSubType='thinking_of_you',
-- into the pair's direct group. The signature is unchanged, so the
-- Flutter thinking_service keeps working without modification.
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
  v_sender_id text := auth.uid()::text;
  v_sender_name text;
  v_sender_avatar text;
  v_family_name text;
  v_direct_group json;
  v_group_id text;
  v_used_family_id text;
  v_message_id text;
  v_notif_id text;
  v_templates text[];
  v_phrase text;
  v_message text;
  v_sender_cooldown_hours int := 6;
  v_receiver_cooldown_hours int := 6;
  v_last_sent timestamptz;
  v_last_received timestamptz;
  v_cooldown_expires timestamptz;
  v_remaining_minutes int;
  v_receiver_in_family boolean;
BEGIN
  IF v_sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated',
      'message', 'You must be signed in to send a Thinking of You moment.');
  END IF;

  IF p_receiver_id IS NULL OR p_receiver_id = v_sender_id THEN
    RETURN json_build_object('success', false, 'error', 'cannot_send_to_self',
      'message', 'You cannot send a Thinking of You moment to yourself.');
  END IF;

  -- ── Validate: SENDER must be a member of the specified family ──
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_sender_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'sender_not_in_family',
      'message', 'You are not a member of this family.');
  END IF;

  -- ── Validate: RECEIVER must be a member of the specified family ──
  SELECT EXISTS(
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = p_receiver_id
  ) INTO v_receiver_in_family;

  IF NOT v_receiver_in_family THEN
    RETURN json_build_object('success', false, 'error', 'receiver_not_in_family',
      'message', 'Recipient not found in this family.');
  END IF;

  -- ── Cooldown #1: 6h per SENDER→RECEIVER pair ──
  -- Checks BOTH the legacy DirectMessage rows and the new ChatMessage
  -- rows (familyEvent + thinking_of_you inside a direct group).
  SELECT GREATEST(
    COALESCE((
      SELECT max("createdAt") FROM "DirectMessage"
      WHERE "senderId" = v_sender_id
        AND "receiverId" = p_receiver_id
        AND "messageType" = 'thinking_of_you'
    ), timestamptz '-infinity'),
    COALESCE((
      SELECT max(cm."createdAt") FROM "ChatMessage" cm
      JOIN "Group" g ON g.id = cm."groupId" AND g."groupType" = 'direct'
      WHERE cm."senderId" = v_sender_id
        AND cm."messageSubType" = 'thinking_of_you'
        AND EXISTS (
          SELECT 1 FROM "GroupMember" gm
          WHERE gm."groupId" = g.id AND gm."userId" = p_receiver_id
        )
    ), timestamptz '-infinity')
  ) INTO v_last_sent;

  IF v_last_sent > timestamptz '-infinity' THEN
    v_cooldown_expires := v_last_sent + (v_sender_cooldown_hours || ' hours')::interval;
    IF now() < v_cooldown_expires THEN
      v_remaining_minutes := CEIL(EXTRACT(EPOCH FROM (v_cooldown_expires - now())) / 60.0)::int;
      RETURN json_build_object(
        'success', false,
        'error', 'cooldown',
        'message', 'You can send another Thinking of You moment to this person in '
                   || FLOOR(v_remaining_minutes / 60.0)::int || 'h '
                   || (v_remaining_minutes % 60) || 'm.',
        'cooldownHours', v_sender_cooldown_hours,
        'cooldownExpiresAt', to_char(v_cooldown_expires AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'cooldownRemainingMinutes', v_remaining_minutes
      );
    END IF;
  END IF;

  -- ── Cooldown #2: 6h per RECEIVER, regardless of sender ──
  SELECT GREATEST(
    COALESCE((
      SELECT max("createdAt") FROM "DirectMessage"
      WHERE "receiverId" = p_receiver_id
        AND "messageType" = 'thinking_of_you'
    ), timestamptz '-infinity'),
    COALESCE((
      SELECT max(cm."createdAt") FROM "ChatMessage" cm
      JOIN "Group" g ON g.id = cm."groupId" AND g."groupType" = 'direct'
      WHERE cm."messageSubType" = 'thinking_of_you'
        AND EXISTS (
          SELECT 1 FROM "GroupMember" gm
          WHERE gm."groupId" = g.id AND gm."userId" = p_receiver_id
        )
    ), timestamptz '-infinity')
  ) INTO v_last_received;

  IF v_last_received > timestamptz '-infinity' THEN
    v_cooldown_expires := v_last_received + (v_receiver_cooldown_hours || ' hours')::interval;
    IF now() < v_cooldown_expires THEN
      v_remaining_minutes := CEIL(EXTRACT(EPOCH FROM (v_cooldown_expires - now())) / 60.0)::int;
      RETURN json_build_object(
        'success', false,
        'error', 'receiver_cooldown',
        'message', 'This person already received a Thinking of You moment recently. Try again in '
                   || FLOOR(v_remaining_minutes / 60.0)::int || 'h '
                   || (v_remaining_minutes % 60) || 'm.',
        'cooldownHours', v_receiver_cooldown_hours,
        'cooldownExpiresAt', to_char(v_cooldown_expires AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'cooldownRemainingMinutes', v_remaining_minutes
      );
    END IF;
  END IF;

  -- Sender info.
  SELECT name, "avatarUrl" INTO v_sender_name, v_sender_avatar
    FROM "User" WHERE id = v_sender_id;
  IF v_sender_name IS NULL OR v_sender_name = '' THEN
    v_sender_name := 'Someone';
  END IF;

  -- Family name (analytics only — NOT in the message).
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN v_family_name := 'your family'; END IF;

  -- ── 16 warm verb-phrase templates (unchanged) ──
  v_templates := ARRAY[
    'is thinking of you.',
    'thought about you today.',
    'sent you a Thinking of You moment.',
    'wants you to know you''re on their mind.',
    'just wanted to say you matter to them.',
    'is sending a little warmth your way.',
    'is holding you close in thought today.',
    'wanted to brighten your day with a hello.',
    'is sending good vibes your way.',
    'just paused to think of you.',
    'is hoping you''re doing well today.',
    'wanted to remind you you''re loved.',
    'sent a little heartbeat your way.',
    'is thinking of the times you shared.',
    'wanted you to know they''re in your corner.',
    'is sending a quiet little smile your way.'
  ];
  v_phrase := v_templates[1 + floor(random() * array_length(v_templates, 1))::int];
  v_message := v_sender_name || ' ' || v_phrase;

  -- ── STEP 1: find or create the private direct group ──
  v_direct_group := fn_get_or_create_direct_group(p_receiver_id, p_family_id);
  IF (v_direct_group->>'success')::boolean IS NOT TRUE THEN
    RETURN v_direct_group;
  END IF;
  v_group_id := v_direct_group->>'groupId';
  v_used_family_id := v_direct_group->>'familyId';

  -- ── STEP 2: insert the ChatMessage into the direct group ──
  -- messageType='familyEvent', messageSubType='thinking_of_you' (per
  -- the Kin Thread spec). Group-scoped: only the two members can read
  -- it (STOP ITEM 1 policies above).
  v_message_id := 'cm_toy_'
    || extract(epoch from now())::bigint::text
    || '_' || substring(v_sender_id from 1 for 8)
    || '_' || substring(p_receiver_id from 1 for 8);

  INSERT INTO "ChatMessage" (
    "id", "familyId", "groupId",
    "senderId", "senderName", "senderInitials",
    "content", "messageType", "messageSubType",
    "isRead", "messageStatus", "createdAt", "updatedAt"
  ) VALUES (
    v_message_id, v_used_family_id, v_group_id,
    v_sender_id, v_sender_name, '',
    v_message, 'familyEvent', 'thinking_of_you',
    false, 'sent', now(), now()
  );

  -- ── STEP 3: notification for the receiver (real Notification schema) ──
  -- actionUrl 'dm:<senderId>' — the same deep link the app already
  -- routes (the /dm route now redirects into the direct group chat).
  BEGIN
    INSERT INTO "Notification" (
      "id", "userId", "eventType", "title", "body",
      "familyId", "channels", "priority", "read",
      "actionUrl", "createdAt", "updatedAt"
    ) VALUES (
      'notif_toe_' || extract(epoch from now())::bigint::text || '_' || substring(p_receiver_id from 1 for 8),
      p_receiver_id,
      'thinking_of_you',
      'Thinking of You',
      v_message,
      v_used_family_id,
      'in_app',
      'normal',
      false,
      'dm:' || v_sender_id,
      now(),
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- ── STEP 4: analytics event (best-effort, unchanged) ──
  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'ThinkingOfYouEvent'
    ) THEN
      CREATE TABLE "ThinkingOfYouEvent" (
        "id" text PRIMARY KEY,
        "senderUserId" text NOT NULL,
        "receiverUserId" text NOT NULL,
        "familyId" text NOT NULL,
        "familyName" text,
        "message" text,
        "createdAt" timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX "ThinkingOfYouEvent_sender_idx" ON "ThinkingOfYouEvent"("senderUserId");
      CREATE INDEX "ThinkingOfYouEvent_receiver_idx" ON "ThinkingOfYouEvent"("receiverUserId");
      ALTER TABLE "ThinkingOfYouEvent" ENABLE ROW LEVEL SECURITY;
      CREATE POLICY "TOE insert" ON "ThinkingOfYouEvent"
        FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = "senderUserId");
      CREATE POLICY "TOE select" ON "ThinkingOfYouEvent"
        FOR SELECT TO authenticated
        USING (auth.uid()::text = "senderUserId" OR auth.uid()::text = "receiverUserId");
    END IF;

    INSERT INTO "ThinkingOfYouEvent" (
      "id", "senderUserId", "receiverUserId", "familyId", "familyName", "message", "createdAt"
    ) VALUES (
      'toe_' || extract(epoch from now())::bigint::text || '_' || substring(v_sender_id from 1 for 8),
      v_sender_id, p_receiver_id, v_used_family_id, v_family_name, v_message, now()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  v_cooldown_expires := now() + (v_sender_cooldown_hours || ' hours')::interval;

  RETURN json_build_object(
    'success', true,
    'message', v_message,
    'displayMessage', v_message,
    -- Kept for backward compatibility with the Dart ThinkingOfYouResult
    -- parser (dmId now carries the new ChatMessage id).
    'dmId', v_message_id,
    'messageId', v_message_id,
    'groupId', v_group_id,
    'senderName', v_sender_name,
    'receiverName', COALESCE((SELECT name FROM "User" WHERE id = p_receiver_id), 'them'),
    'familyName', v_family_name,
    'cooldownHours', v_sender_cooldown_hours,
    'cooldownExpiresAt', to_char(v_cooldown_expires AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_thinking_of_you(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Verification (informational SELECTs — safe to run)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT 'Group.directKey' AS column_added,
       EXISTS(SELECT 1 FROM information_schema.columns
              WHERE table_name = 'Group' AND column_name = 'directKey') AS exists_;

SELECT 'Group_directKey_uniq index' AS index_added,
       EXISTS(SELECT 1 FROM pg_indexes
              WHERE indexname = 'Group_directKey_uniq') AS exists_;

SELECT 'fn_user_can_access_group_chat' AS function_created,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_user_can_access_group_chat') AS exists_;

SELECT 'fn_get_or_create_direct_group' AS function_created,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_or_create_direct_group') AS exists_;

SELECT 'chatmessage policies count (expect 4)' AS policies,
       count(*) AS n FROM pg_policies WHERE tablename = 'ChatMessage';

SELECT 'groupmember policies count (expect 4)' AS policies,
       count(*) AS n FROM pg_policies WHERE tablename = 'GroupMember';
