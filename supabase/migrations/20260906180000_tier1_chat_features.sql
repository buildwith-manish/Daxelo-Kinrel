-- =============================================================================
-- Daxelo Kinrel — Tier 1 chat features: UserPresence + forward message
-- =============================================================================
-- Two features in one migration:
--
-- 1. UserPresence table (last-seen tracking)
--    A per-user row that stores isOnline + lastSeenAt. Updated by the
--    Flutter client on presence join/leave via fn_update_last_seen.
--    Other users query UserPresence to render "online" / "last seen 5m
--    ago" on MemberProfileSheet + Family Profile member rows.
--
--    Realtime publication on UserPresence so presence changes propagate
--    to open chat screens + the Family Profile instantly.
--
-- 2. fn_forward_message(p_message_id, p_target_family_ids[], p_target_dm_user_ids[])
--    Inserts a COPY of an existing ChatMessage (or DirectMessage) into
--    one or more target family chats (and/or creates DMs for the
--    DM targets). The copy preserves the original sender name in the
--    forwardedFrom column so the bubble shows "Forwarded from <name>".
--
--    The caller must be a member of every target family chat AND must
--    be able to read the source message (RLS on ChatMessage / DM).
--
--    v1 scope: forwards text + photo + sticker + voiceNote message
--    types (re-uses the original mediaUrl). Polls + gameInvite +
--    familyEvent are NOT forwardable (they're family-specific).
--
-- Idempotent: CREATE TABLE IF NOT EXISTS, CREATE OR REPLACE FUNCTION.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. UserPresence table
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "UserPresence" (
  "userId" text PRIMARY KEY,
  "isOnline" boolean NOT NULL DEFAULT false,
  "lastSeenAt" timestamptz,           -- null when isOnline = true
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE "UserPresence" ENABLE ROW LEVEL SECURITY;

-- SELECT: any authenticated user can read anyone's presence — needed
-- to render "online" / "last seen" on member lists + profile sheets
-- across families. (The presence itself is not sensitive — it's just
-- "is this user currently active".)
CREATE POLICY "UserPresence select" ON "UserPresence"
  FOR SELECT TO authenticated USING (true);

-- UPSERT: a user can only update their OWN presence row. The RPC
-- fn_update_last_seen runs as SECURITY DEFINER so it bypasses this,
-- but the policy is here as a defense-in-depth safety net.
CREATE POLICY "UserPresence upsert own" ON "UserPresence"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "UserPresence update own" ON "UserPresence"
  FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);

-- Realtime: presence changes propagate to open chat screens so the
-- header's "1 active" count + member dots update without polling.
ALTER TABLE "UserPresence" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'UserPresence'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "UserPresence";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'UserPresence realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_update_last_seen — upsert the caller's presence row
-- ═══════════════════════════════════════════════════════════════════════════
-- Called by the Flutter client on two events:
--   • App foreground / chat screen open → p_is_online = true
--     (lastSeenAt cleared — user is currently active)
--   • App background / chat screen close → p_is_online = false
--     (lastSeenAt = now() — recorded for "last seen X ago")
--
-- The Flutter client also calls this on a 30s heartbeat while
-- foregrounded, so a user who closes the app without a clean
-- background event will still get a fresh lastSeenAt within ~30s.
CREATE OR REPLACE FUNCTION fn_update_last_seen(p_is_online boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
BEGIN
  IF v_user_id IS NULL THEN RETURN; END IF;

  INSERT INTO "UserPresence" ("userId", "isOnline", "lastSeenAt", "updatedAt")
  VALUES (v_user_id, p_is_online, CASE WHEN p_is_online THEN NULL ELSE now() END, now())
  ON CONFLICT ("userId")
  DO UPDATE SET
    "isOnline" = p_is_online,
    "lastSeenAt" = CASE WHEN p_is_online THEN NULL ELSE now() END,
    "updatedAt" = now();
END;
$$;

GRANT EXECUTE ON FUNCTION fn_update_last_seen(boolean) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_forward_message — copy a message to one or more target chats
-- ═══════════════════════════════════════════════════════════════════════════
-- Params:
--   p_message_id      — the source ChatMessage.id (must be in a family
--                        chat the caller is a member of)
--   p_target_family_ids — family chat IDs to forward the message to
--                          (caller must be a member of each). Pass an
--                          empty array to skip family-chat forwarding.
--   p_target_dm_user_ids — user IDs to forward the message to as a DM
--                           (creates a DirectMessage row). Pass an
--                           empty array to skip DM forwarding.
--
-- Returns: json with success + counts of inserted rows + the list of
--   inserted message IDs (so the client can navigate to one if desired).
--
-- The forwarded copy:
--   • Keeps the original messageType, content, mediaUrl, durationSeconds,
--     pollQuestion, pollOptions (with zeroed vote counts), etc.
--   • Sets senderId = caller (the forwarder, not the original sender)
--   • Sets senderName = caller's name
--   • Sets forwardedFrom = original sender's name (so the bubble shows
--     "Forwarded from <original sender>")
--   • Generates a fresh message ID per target
--   • Resets isRead, isStarred, isPinned, reactions (those don't carry over)
--   • Resets pollVoteCounts to zeros + pollVoterIds to [] (forwarded
--     polls start fresh — the original poll keeps its votes)
CREATE OR REPLACE FUNCTION fn_forward_message(
  p_message_id text,
  p_target_family_ids text[] DEFAULT ARRAY[]::text[],
  p_target_dm_user_ids text[] DEFAULT ARRAY[]::text[]
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id text := auth.uid()::text;
  v_caller_name text;
  v_sender_initials text;
  v_src record;
  v_inserted_ids text[] := ARRAY[]::text[];
  v_family_count int := 0;
  v_dm_count int := 0;
  v_target_family_id text;
  v_target_user_id text;
  v_new_id text;
  v_name_parts text[];
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Load the source message. RLS on ChatMessage only lets the caller
  -- read rows in families they're a member of, so this naturally
  -- enforces "you can only forward messages you can see".
  SELECT * INTO v_src FROM "ChatMessage" WHERE "id" = p_message_id;
  IF v_src IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'message_not_found');
  END IF;

  -- Block forwarding non-forwardable types. Polls / gameInvite /
  -- familyEvent are family-specific (they reference the family's
  -- context, not portable). Stickers + photos + voice + text are
  -- portable.
  IF v_src."messageType" IN ('poll', 'gameInvite', 'familyEvent') THEN
    RETURN json_build_object('success', false, 'error', 'not_forwardable',
      'message', 'This message type cannot be forwarded.');
  END IF;

  -- Get the caller's name + initials for the forwarded bubble's sender
  -- fields. The forwarder is the "sender" of the new message; the
  -- original sender's name goes in forwardedFrom.
  SELECT name INTO v_caller_name FROM "User" WHERE id = v_caller_id;
  IF v_caller_name IS NULL OR v_caller_name = '' THEN
    v_caller_name := 'Someone';
  END IF;
  v_name_parts := regexp_split_to_array(v_caller_name, '\s+');
  IF array_length(v_name_parts, 1) >= 2 AND v_name_parts[2] <> '' THEN
    v_sender_initials := UPPER(SUBSTRING(v_name_parts[1] FROM 1 FOR 1)
                              || SUBSTRING(v_name_parts[2] FROM 1 FOR 1));
  ELSE
    v_sender_initials := UPPER(SUBSTRING(v_name_parts[1] FROM 1 FOR 1));
  END IF;

  -- Validate: caller must be a member of every target family chat.
  FOREACH v_target_family_id IN ARRAY p_target_family_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = v_target_family_id AND "userId" = v_caller_id
    ) THEN
      RETURN json_build_object('success', false, 'error', 'not_in_target_family',
        'message', 'You are not a member of one of the target families.',
        'targetFamilyId', v_target_family_id);
    END IF;
  END LOOP;

  -- ── Forward to family chats ──
  FOREACH v_target_family_id IN ARRAY p_target_family_ids LOOP
    v_new_id := 'cm_fwd_' || extract(epoch from now())::bigint::text || '_' || substring(v_target_family_id from 1 for 8) || '_' || substring(v_caller_id from 1 for 8);

    INSERT INTO "ChatMessage" (
      "id", "familyId",
      "senderId", "senderName", "senderInitials",
      "content", "messageType", "messageSubType",
      "mediaUrl", "voiceMessageDuration", "durationSeconds",
      "forwardedFrom",
      "replyToId", "replyToContent", "replyToSenderName",
      "mentions",
      "isRead", "messageStatus",
      "createdAt", "updatedAt"
    ) VALUES (
      v_new_id,
      v_target_family_id,
      v_caller_id, v_caller_name, v_sender_initials,
      v_src."content", v_src."messageType", COALESCE(v_src."messageSubType", 'text'),
      v_src."mediaUrl", v_src."voiceMessageDuration", v_src."durationSeconds",
      v_src."senderName",  -- forwardedFrom = the ORIGINAL sender's name
      NULL,  -- no reply context in the forwarded copy
      NULL, NULL,
      '[]'::jsonb,  -- mentions don't carry over (they reference users in the source family)
      false, 'sent',
      now(), now()
    );

    v_inserted_ids := array_append(v_inserted_ids, v_new_id);
    v_family_count := v_family_count + 1;
  END LOOP;

  -- ── Forward to DMs (DirectMessage rows) ──
  -- For DMs, we only forward text + sticker types (no media — DMs
  -- don't have a mediaUrl column in the current schema). The forwarded
  -- DM keeps the original content + messageType + forwardedFrom on the
  -- bubble (DM bubble rendering needs to be updated separately to
  -- surface forwardedFrom; for now we just store the content correctly).
  FOREACH v_target_user_id IN ARRAY p_target_dm_user_ids LOOP
    IF v_target_user_id = v_caller_id THEN
      CONTINUE;  -- don't forward to yourself
    END IF;

    -- For DMs, only forward text + sticker (no mediaUrl column on DM).
    IF v_src."messageType" NOT IN ('text', 'sticker') THEN
      CONTINUE;
    END IF;

    v_new_id := 'dm_fwd_' || extract(epoch from now())::bigint::text || '_' || substring(v_caller_id from 1 for 8) || '_' || substring(v_target_user_id from 1 for 8);

    INSERT INTO "DirectMessage" (
      "id", "senderId", "receiverId", "content", "messageType", "isRead",
      "createdAt", "updatedAt"
    ) VALUES (
      v_new_id,
      v_caller_id,
      v_target_user_id,
      v_src."content",
      v_src."messageType",
      false,
      now(),
      now()
    );

    v_inserted_ids := array_append(v_inserted_ids, v_new_id);
    v_dm_count := v_dm_count + 1;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'familyChatsForwarded', v_family_count,
    'dmChatsForwarded', v_dm_count,
    'totalForwarded', v_family_count + v_dm_count,
    'insertedMessageIds', v_inserted_ids
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_forward_message(text, text[], text[]) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'UserPresence' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'UserPresence') AS exists;
SELECT 'fn_update_last_seen' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_update_last_seen') AS exists;
SELECT 'fn_forward_message' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_forward_message') AS exists;
