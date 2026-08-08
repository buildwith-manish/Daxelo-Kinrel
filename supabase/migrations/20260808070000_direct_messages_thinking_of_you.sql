-- =============================================================================
-- Daxelo Kinrel — Direct Messages + Thinking of You DM Integration
-- =============================================================================
-- Creates a DirectMessage table for 1:1 conversations + updates the
-- fn_send_thinking_of_you RPC to also create a DM + notification.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. DirectMessage table
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS "DirectMessage" (
  "id" text PRIMARY KEY,
  "senderId" text NOT NULL,
  "receiverId" text NOT NULL,
  "content" text NOT NULL DEFAULT '',
  "messageType" text NOT NULL DEFAULT 'text',
  "isRead" boolean NOT NULL DEFAULT false,
  "readAt" timestamptz,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS "DM_sender_idx" ON "DirectMessage"("senderId");
CREATE INDEX IF NOT EXISTS "DM_receiver_idx" ON "DirectMessage"("receiverId");
CREATE INDEX IF NOT EXISTS "DM_pair_idx" ON "DirectMessage"("senderId", "receiverId");
CREATE INDEX IF NOT EXISTS "DM_created_idx" ON "DirectMessage"("createdAt" DESC);

-- RLS: users can only see DMs where they're sender or receiver
ALTER TABLE "DirectMessage" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "DM insert policy" ON "DirectMessage";
CREATE POLICY "DM insert policy" ON "DirectMessage"
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid()::text = "senderId");

DROP POLICY IF EXISTS "DM select policy" ON "DirectMessage";
CREATE POLICY "DM select policy" ON "DirectMessage"
  FOR SELECT TO authenticated
  USING (auth.uid()::text = "senderId" OR auth.uid()::text = "receiverId");

DROP POLICY IF EXISTS "DM update policy" ON "DirectMessage";
CREATE POLICY "DM update policy" ON "DirectMessage"
  FOR UPDATE TO authenticated
  USING (auth.uid()::text = "senderId" OR auth.uid()::text = "receiverId");

-- Add to realtime publication
ALTER TABLE "DirectMessage" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'DirectMessage'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "DirectMessage";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_send_thinking_of_you (UPDATED to also create a DM)
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
  v_dm_id text;
  v_messages text[];
  v_message text;
  v_cooldown_hours int := 12;
  v_last_sent timestamptz;
BEGIN
  IF v_sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF v_sender_id = p_receiver_id THEN
    RETURN json_build_object('success', false, 'error', 'Cannot send to yourself');
  END IF;

  -- Check cooldown: 12 hours per sender→receiver pair
  SELECT "createdAt" INTO v_last_sent
  FROM "DirectMessage"
  WHERE "senderId" = v_sender_id AND "receiverId" = p_receiver_id AND "messageType" = 'thinking_of_you'
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

  -- Get sender info
  SELECT name, "avatarUrl" INTO v_sender_name, v_sender_avatar
  FROM "User" WHERE id = v_sender_id;
  IF v_sender_name IS NULL OR v_sender_name = '' THEN
    v_sender_name := 'Someone';
  END IF;

  -- Get family name
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN v_family_name := 'your family'; END IF;

  -- Pick a random warm message
  v_messages := ARRAY[
    '❤️ ' || v_sender_name || ' is thinking of you.',
    '🌟 ' || v_sender_name || ' thought about you today.',
    '💭 ' || v_sender_name || ' sent a Thinking of You moment.',
    '🫶 ' || v_sender_name || ' wants you to know you''re on their mind.'
  ];
  v_message := v_messages[1 + floor(random() * array_length(v_messages, 1))::int];

  -- ── STEP 1: Create a DirectMessage (1:1 chat message) ──
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

  -- ── STEP 2: Create a notification ──
  v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(p_receiver_id from 1 for 8);

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
    'dm:' || v_dm_id || ':sender:' || v_sender_id,
    now(),
    now()
  );

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
    'senderName', v_sender_name,
    'familyName', v_family_name
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_thinking_of_you(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'DirectMessage table' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'DirectMessage') AS exists;
SELECT 'fn_send_thinking_of_you (with DM)' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_thinking_of_you') AS exists;
