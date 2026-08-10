-- =============================================================================
-- Daxelo Kinrel — Fix Thinking of You + 6-hour Cooldown (Phase 20)
-- =============================================================================
-- Problem: When a user tapped "Thinking of You" for a valid family member,
-- the app showed "Something went wrong. Try again." even though the member
-- existed in the family.
--
-- Root cause: The v_sender_initials computation had a broken subquery:
--   (SELECT name2 FROM "User" WHERE id = v_sender_id ORDER BY name OFFSET 1 LIMIT 1)
-- The column "name2" does not exist — this was a refactoring artifact. The
-- RPC threw "column name2 does not exist", caught by the outer EXCEPTION
-- block, and returned {success: false, error: 'column "name2" does not exist'}.
-- The Flutter app rendered this as "Something went wrong. Try again."
--
-- Also: cooldown was 12 hours; user wants 6 hours + countdown display.
--
-- Fix:
--   1. Replace the broken initials computation with a simple split-on-space
--      approach that takes the first letter of the first two name parts.
--   2. Change cooldown from 12h to 6h.
--   3. Return cooldownExpiresAt (ISO 8601 timestamp) so the client can
--      show a live countdown like "Available again in 5h 23m".
--   4. Add family-membership validation: reject if receiver is NOT a
--      member of the specified family.
--   5. Return meaningful error codes for each failure case:
--        - 'not_authenticated'
--        - 'cannot_send_to_self'
--        - 'receiver_not_in_family'
--        - 'cooldown' (with cooldownExpiresAt + cooldownHours + cooldownMinutes)
-- =============================================================================

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
  v_sender_initials text;
  v_sender_avatar text;
  v_family_name text;
  v_dm_id text;
  v_cm_id text;
  v_messages text[];
  v_message text;
  v_cooldown_hours int := 6;
  v_last_sent timestamptz;
  v_last_sent_dm timestamptz;
  v_last_sent_cm timestamptz;
  v_cooldown_expires timestamptz;
  v_remaining_minutes int;
  v_receiver_in_family boolean;
  v_name_parts text[];
BEGIN
  IF v_sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated',
      'message', 'You must be signed in to send a Thinking of You moment.');
  END IF;

  IF v_sender_id = p_receiver_id THEN
    RETURN json_build_object('success', false, 'error', 'cannot_send_to_self',
      'message', 'You cannot send a Thinking of You moment to yourself.');
  END IF;

  -- ── Validate: receiver must be a member of the specified family ──
  -- This prevents abuse (sending to a user who isn't in the family) and
  -- gives a meaningful error instead of a silent success-with-no-audience.
  SELECT EXISTS(
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = p_receiver_id
  ) INTO v_receiver_in_family;

  IF NOT v_receiver_in_family THEN
    RETURN json_build_object(
      'success', false,
      'error', 'receiver_not_in_family',
      'message', 'Recipient not found in this family.'
    );
  END IF;

  -- ── Cooldown check: 6 hours per sender→receiver pair ──
  -- Check BOTH the DirectMessage table AND the ChatMessage table so
  -- the cooldown is consistent regardless of where the previous
  -- Thinking of You message was stored.
  SELECT "createdAt" INTO v_last_sent_dm
  FROM "DirectMessage"
  WHERE "senderId" = v_sender_id AND "receiverId" = p_receiver_id AND "messageType" = 'thinking_of_you'
  ORDER BY "createdAt" DESC
  LIMIT 1;

  SELECT "createdAt" INTO v_last_sent_cm
  FROM "ChatMessage"
  WHERE "senderId" = v_sender_id
    AND "familyId" = p_family_id
    AND "messageSubType" = 'thinking_of_you'
  ORDER BY "createdAt" DESC
  LIMIT 1;

  v_last_sent := GREATEST(v_last_sent_dm, v_last_sent_cm);

  IF v_last_sent IS NOT NULL THEN
    v_cooldown_expires := v_last_sent + (v_cooldown_hours || ' hours')::interval;
    IF now() < v_cooldown_expires THEN
      -- Compute remaining minutes for the client countdown
      v_remaining_minutes := CEIL(EXTRACT(EPOCH FROM (v_cooldown_expires - now())) / 60.0)::int;

      RETURN json_build_object(
        'success', false,
        'error', 'cooldown',
        'message', 'You can send another Thinking of You moment in '
                   || FLOOR(v_remaining_minutes / 60.0)::int || 'h '
                   || (v_remaining_minutes % 60) || 'm.',
        'cooldownHours', v_cooldown_hours,
        'cooldownExpiresAt', to_char(v_cooldown_expires AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'cooldownRemainingMinutes', v_remaining_minutes
      );
    END IF;
  END IF;

  -- Get sender info
  SELECT name, "avatarUrl" INTO v_sender_name, v_sender_avatar
  FROM "User" WHERE id = v_sender_id;
  IF v_sender_name IS NULL OR v_sender_name = '' THEN
    v_sender_name := 'Someone';
  END IF;

  -- ── Compute sender initials (SIMPLE, CORRECT version) ──
  -- Split the name on whitespace and take the first letter of the first
  -- two parts. E.g. "Manish Sharma" -> "MS", "Yakshitha" -> "Y".
  v_name_parts := regexp_split_to_array(v_sender_name, '\s+');
  IF array_length(v_name_parts, 1) >= 2 AND v_name_parts[2] <> '' THEN
    v_sender_initials := UPPER(SUBSTRING(v_name_parts[1] FROM 1 FOR 1)
                              || SUBSTRING(v_name_parts[2] FROM 1 FOR 1));
  ELSE
    v_sender_initials := UPPER(SUBSTRING(v_name_parts[1] FROM 1 FOR 1));
  END IF;

  -- Get family name
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN v_family_name := 'your family'; END IF;

  -- Pick a random warm message (the receiver sees "<sender> <message>")
  v_messages := ARRAY[
    'is thinking of you.',
    'thought about you today.',
    'sent you a Thinking of You moment.',
    'wants you to know you''re on their mind.'
  ];
  v_message := v_messages[1 + floor(random() * array_length(v_messages, 1))::int];

  -- ── STEP 1: Insert a ChatMessage into the FAMILY GROUP CHAT ──
  -- This is the VISIBLE delivery. Both sender and receiver are members
  -- of the family, so both will see this message in their family chat.
  -- Realtime is already wired on ChatMessage, so the message appears
  -- instantly for both users on all their devices.
  v_cm_id := 'cm_toe_' || extract(epoch from now())::bigint::text || '_' || substring(v_sender_id from 1 for 8) || '_' || substring(p_receiver_id from 1 for 8);

  INSERT INTO "ChatMessage" (
    "id", "familyId",
    "senderId", "senderName", "senderInitials",
    "content", "messageType", "messageSubType",
    "eventTitle", "eventDate",
    "isRead", "messageStatus",
    "createdAt", "updatedAt"
  ) VALUES (
    v_cm_id,
    p_family_id,
    v_sender_id, v_sender_name, v_sender_initials,
    v_message, 'familyEvent', 'thinking_of_you',
    'Thinking of You', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"'),
    false, 'sent',
    now(), now()
  );

  -- ── STEP 2: Also insert a DirectMessage (for future 1:1 chat + analytics) ──
  v_dm_id := 'dm_' || extract(epoch from now())::bigint::text || '_' || substring(v_sender_id from 1 for 8);

  INSERT INTO "DirectMessage" (
    "id", "senderId", "receiverId", "content", "messageType", "isRead", "createdAt", "updatedAt"
  ) VALUES (
    v_dm_id,
    v_sender_id,
    p_receiver_id,
    v_message,
    'thinking_of_you',
    false,
    now(),
    now()
  );

  -- ── STEP 3: Create a NOTIFICATION for the receiver ──
  -- The user wants the recipient to receive a notification in the
  -- Notifications section AS WELL AS a message in chat. The notification
  -- is non-actionable (just an FYI) — tapping it opens the family chat.
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
      v_sender_name || ' ' || v_message,
      p_family_id,
      'in_app',
      'normal',
      false,
      'family:' || p_family_id || ':chat',
      now(),
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    -- Notification insert is best-effort — don't fail the whole RPC
    NULL;
  END;

  -- ── STEP 4: Store analytics event (best-effort) ──
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
      v_sender_id, p_receiver_id, p_family_id, v_family_name, v_message, now()
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Compute the NEXT time the sender can send to this receiver (6h from now)
  v_cooldown_expires := now() + (v_cooldown_hours || ' hours')::interval;

  RETURN json_build_object(
    'success', true,
    'message', v_sender_name || ' ' || v_message,
    'displayMessage', v_sender_name || ' ' || v_message,
    'dmId', v_dm_id,
    'chatMessageId', v_cm_id,
    'senderName', v_sender_name,
    'familyName', v_family_name,
    'cooldownHours', v_cooldown_hours,
    'cooldownExpiresAt', to_char(v_cooldown_expires AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_thinking_of_you(text, text) TO authenticated;

-- Verification
SELECT 'fn_send_thinking_of_you (initials fixed + 6h cooldown + notification)' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_thinking_of_you') AS exists;
