-- =============================================================================
-- Daxelo Kinrel — Thinking of You: PRIVATE 1:1 delivery (Phase 21)
-- =============================================================================
-- Problem: Thinking of You moments were posted to the family group chat,
-- making them visible to ALL family members. The user wants this to be a
-- PRIVATE interaction between sender and recipient only.
--
-- Fix: STOP inserting into the ChatMessage (family group chat) table.
-- Keep the DirectMessage + Notification inserts — those are already
-- private (RLS only lets sender/receiver see them).
--
-- Also: clean up the cooldown check — no longer needs to query the
-- ChatMessage table (only DirectMessage).
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
  v_sender_avatar text;
  v_family_name text;
  v_dm_id text;
  v_templates text[];       -- verb-phrase templates (third person)
  v_phrase text;            -- the chosen verb phrase (e.g. "is thinking of you.")
  v_message text;            -- the FULL sentence (senderName + ' ' + phrase)
  v_sender_cooldown_hours int := 6;  -- per sender→receiver pair
  v_receiver_cooldown_hours int := 6; -- per receiver, regardless of sender
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

  IF v_sender_id = p_receiver_id THEN
    RETURN json_build_object('success', false, 'error', 'cannot_send_to_self',
      'message', 'You cannot send a Thinking of You moment to yourself.');
  END IF;

  -- ── Validate: SENDER must be a member of the specified family ──
  -- This check runs BEFORE the cooldown checks so a non-member can't
  -- probe whether a receiver recently got a Thinking of You (which
  -- would be a privacy leak — the cooldown response reveals activity).
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_sender_id
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'sender_not_in_family',
      'message', 'You are not a member of this family.'
    );
  END IF;

  -- ── Validate: RECEIVER must be a member of the specified family ──
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

  -- ── Cooldown #1: 6h per SENDER→RECEIVER pair ──
  -- "You already sent one to this person recently."
  -- Now ONLY checks the DirectMessage table (no more ChatMessage).
  SELECT "createdAt" INTO v_last_sent
  FROM "DirectMessage"
  WHERE "senderId" = v_sender_id AND "receiverId" = p_receiver_id AND "messageType" = 'thinking_of_you'
  ORDER BY "createdAt" DESC
  LIMIT 1;

  IF v_last_sent IS NOT NULL THEN
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

  -- Get family name (used in analytics only — NOT in the message)
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

  -- ── STEP 1: Insert a DIRECT MESSAGE (PRIVATE 1:1 delivery) ──
  -- This is the ONLY visible delivery. RLS on DirectMessage only lets
  -- the sender and receiver see it — no other family members can read it.
  v_dm_id := 'dm_toe_' || extract(epoch from now())::bigint::text || '_' || substring(v_sender_id from 1 for 8) || '_' || substring(p_receiver_id from 1 for 8);

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

  -- NO ChatMessage insert. Thinking of You is PRIVATE — it must NOT
  -- appear in the family group chat.

  -- ── STEP 2: Create a NOTIFICATION for the receiver ──
  -- The recipient sees this in their Notifications section. Tapping it
  -- opens the private 1:1 chat with the sender.
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
      p_family_id,
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

  -- Compute the NEXT time the sender can send to this receiver (6h from now).
  -- The per-receiver cooldown is reported separately only when it blocks.
  v_cooldown_expires := now() + (v_sender_cooldown_hours || ' hours')::interval;

  RETURN json_build_object(
    'success', true,
    'message', v_message,
    'displayMessage', v_message,
    'dmId', v_dm_id,
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

-- Verification
SELECT 'fn_send_thinking_of_you (PRIVATE 1:1 — no family chat)' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_thinking_of_you') AS exists;
