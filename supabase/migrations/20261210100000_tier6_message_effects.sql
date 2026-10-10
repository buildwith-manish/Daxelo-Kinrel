-- =============================================================================
-- Daxelo Kinrel — Tier 6 Feature 6.5: Message Effects (iOS-style)
-- =============================================================================
-- Lets a sender attach a visual effect to a message: 'gentle' | 'loud' |
-- 'invisibleInk' | 'confetti' | 'fireworks' | 'balloons'. The effect
-- plays on the recipient's device when the bubble enters the viewport.
-- For 'invisibleInk', the bubble renders a particle animation that the
-- recipient swipes to reveal the content.
--
-- Schema: add `effectType text` (nullable; null = no effect) +
-- `effectPlayedAt timestamptz` (when the recipient's device last played
-- the effect — used to suppress replays on scroll).
--
-- Valid effect types:
--   • gentle         — bubble scales up softly on receipt
--   • loud           — bubble pops + scales 1.2x briefly
--   • invisibleInk   — content masked by particle animation; recipient
--                       swipes / holds to reveal (matches iOS behavior)
--   • confetti       — confetti bursts from the top of the chat viewport
--   • fireworks     — fireworks animation overlay
--   • balloons       — balloons rise from the bottom
--
-- The Flutter client renders the effect; the server just stores the type.
-- =============================================================================

ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "effectType" text;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "effectPlayedAt" timestamptz;

ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "effectType" text;
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "effectPlayedAt" timestamptz;

-- CHECK constraint enforcing only valid effect types.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ChatMessage_effectType_chk'
  ) THEN
    ALTER TABLE "ChatMessage"
      ADD CONSTRAINT "ChatMessage_effectType_chk"
      CHECK ("effectType" IS NULL OR "effectType" IN (
        'gentle', 'loud', 'invisibleInk',
        'confetti', 'fireworks', 'balloons'
      ));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'DirectMessage_effectType_chk'
  ) THEN
    ALTER TABLE "DirectMessage"
      ADD CONSTRAINT "DirectMessage_effectType_chk"
      CHECK ("effectType" IS NULL OR "effectType" IN (
        'gentle', 'loud', 'invisibleInk',
        'confetti', 'fireworks', 'balloons'
      ));
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'effectType check: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_mark_effect_played — recipient's device marks the effect as played
-- so the next scroll doesn't replay it. Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_mark_effect_played(
  p_message_id text,
  p_is_direct_message boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  IF p_is_direct_message THEN
    -- DirectMessage path: only sender or receiver can mark.
    IF NOT EXISTS (
      SELECT 1 FROM "DirectMessage"
      WHERE "id" = p_message_id
        AND ("senderId" = v_user_id OR "receiverId" = v_user_id)
    ) THEN
      RETURN json_build_object('success', false, 'error', 'not_authorized');
    END IF;
    UPDATE "DirectMessage"
      SET "effectPlayedAt" = now()
      WHERE "id" = p_message_id AND "effectType" IS NOT NULL;
  ELSE
    -- ChatMessage path: validate family membership.
    IF NOT EXISTS (
      SELECT 1 FROM "ChatMessage" cm
      JOIN "FamilyMember" fm ON fm."familyId" = cm."familyId"
      WHERE cm."id" = p_message_id AND fm."userId" = v_user_id
    ) THEN
      RETURN json_build_object('success', false, 'error', 'not_authorized');
    END IF;
    UPDATE "ChatMessage"
      SET "effectPlayedAt" = now()
      WHERE "id" = p_message_id AND "effectType" IS NOT NULL;
  END IF;

  RETURN json_build_object('success', true, 'messageId', p_message_id, 'playedAt', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
END;
$$;

GRANT EXECUTE ON FUNCTION fn_mark_effect_played(text, boolean) TO authenticated;

-- Verification
SELECT 'ChatMessage.effectType' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatMessage' AND column_name = 'effectType'
       ) AS exists;
SELECT 'DirectMessage.effectType' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'DirectMessage' AND column_name = 'effectType'
       ) AS exists;
SELECT 'fn_mark_effect_played' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_mark_effect_played') AS exists;
