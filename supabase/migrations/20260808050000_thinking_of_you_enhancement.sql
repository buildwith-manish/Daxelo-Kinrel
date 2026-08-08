-- =============================================================================
-- Daxelo Kinrel — "Thinking of You" Feature Enhancement
-- =============================================================================
-- Creates a Supabase RPC that:
--   1. Checks cooldown (12 hours between same sender→receiver pairs)
--   2. Creates a personalized notification for the receiver
--   3. Stores an analytics event for future engagement insights
--   4. Returns success/error with user-friendly messages
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. fn_send_thinking_of_you — creates a personalized notification
-- ═══════════════════════════════════════════════════════════════════════════

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
  v_notif_id text;
  v_messages text[];
  v_message text;
  v_cooldown_hours int := 12;
  v_last_sent timestamptz;
BEGIN
  IF v_sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Can't think of yourself
  IF v_sender_id = p_receiver_id THEN
    RETURN json_build_object('success', false, 'error', 'Cannot send to yourself');
  END IF;

  -- Check cooldown: has this sender sent to this receiver within 12 hours?
  SELECT "createdAt" INTO v_last_sent
  FROM "Notification"
  WHERE "userId" = p_receiver_id
    AND "eventType" = 'thinking_of_you'
    AND "actionUrl" = 'thinking:' || v_sender_id
  ORDER BY "createdAt" DESC
  LIMIT 1;

  IF v_last_sent IS NOT NULL THEN
    IF now() - v_last_sent < (v_cooldown_hours || ' hours')::interval THEN
      RETURN json_build_object(
        'success', false,
        'error', 'cooldown',
        'message', 'You already sent a Thinking of You to this person recently. Try again later.',
        'cooldownHours', v_cooldown_hours
      );
    END IF;
  END IF;

  -- Get sender's name + avatar
  SELECT name, "avatarUrl" INTO v_sender_name, v_sender_avatar
  FROM "User" WHERE id = v_sender_id;
  IF v_sender_name IS NULL OR v_sender_name = '' THEN
    v_sender_name := 'Someone';
  END IF;

  -- Get family name
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN v_family_name := 'your family'; END IF;

  -- Pick a random message from a set of warm, personal options
  v_messages := ARRAY[
    '❤️ ' || v_sender_name || ' is thinking of you.',
    '🌟 ' || v_sender_name || ' thought about you today.',
    '💭 ' || v_sender_name || ' sent a Thinking of You moment.',
    '🫶 ' || v_sender_name || ' wants you to know you''re on their mind.'
  ];
  v_message := v_messages[1 + floor(random() * array_length(v_messages, 1))::int];

  -- Generate notification ID
  v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(p_receiver_id from 1 for 8);

  -- Create the notification with:
  --   - Personal message (randomly picked)
  --   - eventType = 'thinking_of_you'
  --   - actionUrl = 'thinking:<senderId>' (for cooldown checking + "Send Love Back")
  --   - familyId = the family context
  INSERT INTO "Notification" (
    "id", "userId", "eventType", "title", "body",
    "familyId", "channels", "priority", "read",
    "actionUrl", "createdAt", "updatedAt"
  ) VALUES (
    v_notif_id,
    p_receiver_id,
    'thinking_of_you',
    'Thinking of You',
    v_message,
    p_family_id,
    'in_app',
    'normal',
    false,
    'thinking:' || v_sender_id,
    now(),
    now()
  );

  -- Store analytics event (best-effort — create table if not exists)
  BEGIN
    -- Create the analytics table if it doesn't exist
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
      CREATE INDEX "ThinkingOfYouEvent_family_idx" ON "ThinkingOfYouEvent"("familyId");
      ALTER TABLE "ThinkingOfYouEvent" ENABLE ROW LEVEL SECURITY;
      CREATE POLICY "Users can insert thinking events" ON "ThinkingOfYouEvent"
        FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = "senderUserId");
      CREATE POLICY "Users can read their own events" ON "ThinkingOfYouEvent"
        FOR SELECT TO authenticated USING (
          auth.uid()::text = "senderUserId" OR auth.uid()::text = "receiverUserId"
        );
    END IF;

    -- Insert the analytics event
    INSERT INTO "ThinkingOfYouEvent" (
      "id", "senderUserId", "receiverUserId", "familyId", "familyName", "message", "createdAt"
    ) VALUES (
      'toe_' || extract(epoch from now())::bigint::text || '_' || substring(v_sender_id from 1 for 8),
      v_sender_id,
      p_receiver_id,
      p_family_id,
      v_family_name,
      v_message,
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    -- Best-effort — don't fail the notification if analytics fails
    NULL;
  END;

  RETURN json_build_object(
    'success', true,
    'message', v_message,
    'senderName', v_sender_name,
    'familyName', v_family_name
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_thinking_of_you(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Map 'thinking_of_you' event type to the Flutter notification provider
-- ═══════════════════════════════════════════════════════════════════════════
-- (The Flutter _mapEventType function already has a default case that
-- maps unknown types to NotificationType.newMember. The Flutter code
-- will need to add a 'thinking_of_you' case — handled in the Dart code.)

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'fn_send_thinking_of_you' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_thinking_of_you') AS exists;
