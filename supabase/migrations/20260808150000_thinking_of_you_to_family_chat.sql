-- =============================================================================
-- Daxelo Kinrel — Thinking of You: deliver to family chat (Phase 18)
-- =============================================================================
-- Problem: When a user tapped a family member in "Thinking of You", the
-- RPC inserted a row into the DirectMessage table, but the Flutter app has
-- NO direct-message (1:1) chat screen. The DM rows were written but never
-- displayed to either user.
--
-- Fix: ALSO insert a ChatMessage (family group chat) with
-- messageType='familyEvent', messageSubType='thinking_of_you',
-- eventTitle='Thinking of You', content=<warm message>. The family group
-- chat IS the conversation where both members are present, has working
-- Supabase Realtime, and is already rendered by the Flutter chat screen.
--
-- The DirectMessage + ThinkingOfYouEvent inserts are KEPT for analytics
-- and future 1:1 chat support, but the VISIBLE delivery is the ChatMessage.
--
-- Also: tighten the cooldown check. Previously it only checked
-- DirectMessage rows; now it ALSO checks ChatMessage rows with
-- messageSubType='thinking_of_you' so the cooldown is consistent
-- regardless of which table the previous message landed in.
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
  v_templates text[];       -- verb-phrase templates (third person)
  v_phrase text;            -- the chosen verb phrase (e.g. "is thinking of you.")
  v_message text;            -- the FULL sentence (senderName + ' ' + phrase)
  v_sender_cooldown_hours int := 12;  -- per sender→receiver pair
  v_receiver_cooldown_hours int := 6; -- per receiver, regardless of sender
  v_last_sent timestamptz;
  v_last_sent_dm timestamptz;
  v_last_sent_cm timestamptz;
  v_last_received timestamptz;
  v_cooldown_expires timestamptz;
  v_remaining_minutes int;
  v_name_parts text[];
BEGIN
  IF v_sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF v_sender_id = p_receiver_id THEN
    RETURN json_build_object('success', false, 'error', 'Cannot send to yourself');
  END IF;

  -- ── Cooldown #1: 12h per SENDER→RECEIVER pair ──
  -- "You already sent one to this person recently."
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
    IF now() - v_last_sent < (v_sender_cooldown_hours || ' hours')::interval THEN
      v_cooldown_expires := v_last_sent + (v_sender_cooldown_hours || ' hours')::interval;
      v_remaining_minutes := CEIL(EXTRACT(EPOCH FROM (v_cooldown_expires - now())) / 60.0)::int;
      RETURN json_build_object(
        'success', false,
        'error', 'cooldown',
        'message', 'You already sent a Thinking of You to this person recently. Try again in '
                   || FLOOR(v_remaining_minutes / 60.0)::int || 'h '
                   || (v_remaining_minutes % 60) || 'm.',
        'cooldownHours', v_sender_cooldown_hours,
        'cooldownExpiresAt', to_char(v_cooldown_expires AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'cooldownRemainingMinutes', v_remaining_minutes
      );
    END IF;
  END IF;

  -- ── Cooldown #2 (NEW): 6h per RECEIVER, regardless of sender ──
  -- "This person already got one recently (from anyone in the family)."
  -- Prevents 3 family members from sending near-identical nudges to the
  -- same person within an hour. Returns a CLEAR 'receiver_cooldown'
  -- error so the Flutter UI can surface "X already received a Thinking
  -- of You moment recently" instead of failing silently.
  SELECT "createdAt" INTO v_last_received
  FROM "DirectMessage"
  WHERE "receiverId" = p_receiver_id
    AND "messageType" = 'thinking_of_you'
  ORDER BY "createdAt" DESC
  LIMIT 1;

  IF v_last_received IS NOT NULL THEN
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

  -- ── 16 warm verb-phrase templates (third person) ──
  -- Each is grammatically correct when prefixed with "<SenderName> ".
  -- Expanded from 4 → 16 so repeated nudges from different family members
  -- don't read as copy-pasted spam. Picked at random per send.
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

  -- ── Task 1: store the FULL GRAMMATICAL SENTENCE in content ──
  -- Old: content = "is thinking of you."  (Flutter prepended "You " → "You is thinking of you.")
  -- New: content = "Manish is thinking of you."  (Flutter renders content as-is)
  v_message := v_sender_name || ' ' || v_phrase;

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

  -- v109.7: NO Notification row is created. Thinking of You is a chat
  -- message, not an actionable notification.

  -- ── STEP 3: Store analytics event (best-effort) ──
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

  RETURN json_build_object(
    'success', true,
    'message', v_message,
    'dmId', v_dm_id,
    'chatMessageId', v_cm_id,
    'senderName', v_sender_name,
    'familyName', v_family_name
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_thinking_of_you(text, text) TO authenticated;

-- Verification
SELECT 'fn_send_thinking_of_you (delivers to ChatMessage)' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_thinking_of_you') AS exists;
