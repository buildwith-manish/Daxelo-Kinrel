-- 20260924040000_thinking_of_you_emotion_and_inbox.sql
--
-- Phase 3.26 — Thinking of You: emotion storage + inbox RPC.
--
-- 1. Adds `emotion` column to thinking_of_you_taps so the recipient
--    can see WHICH emotion the sender picked (💛/🤗/🙏/🌟), not just
--    a generic "thinking of you."
-- 2. Adds `readAt` column so we can track unread taps for the badge.
-- 3. New RPC fn_get_received_taps(p_user_id, p_family_id, p_limit)
--    returns all received taps with sender name + emotion + read status,
--    sorted by tappedAt DESC.
-- 4. New RPC fn_mark_taps_read(p_user_id, p_family_id) marks all
--    unread taps as read (for the badge count).

-- ── 1. Add emotion column ──────────────────────────────────────────
ALTER TABLE "thinking_of_you_taps"
  ADD COLUMN IF NOT EXISTS "emotion" TEXT NOT NULL DEFAULT 'love';
-- Values: 'love' | 'hug' | 'gratitude' | 'proud'

-- ── 2. Add readAt column ───────────────────────────────────────────
ALTER TABLE "thinking_of_you_taps"
  ADD COLUMN IF NOT EXISTS "readAt" TIMESTAMPTZ;
-- NULL = unread, non-null = read timestamp

-- Index for the "unread count" query (WHERE receiverId = X AND readAt IS NULL)
CREATE INDEX IF NOT EXISTS idx_toyt_receiver_unread
  ON "thinking_of_you_taps" ("receiverId", "readAt")
  WHERE "readAt" IS NULL;

-- ── 3. RPC: fn_get_received_taps ──────────────────────────────────
-- Returns received taps with sender name + emotion, paginated.
CREATE OR REPLACE FUNCTION public.fn_get_received_taps(
  p_user_id text,
  p_family_id text,
  p_limit integer DEFAULT 30,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'sender_id', t."senderId",
    'sender_name', u.name,
    'sender_avatar_url', u."avatarUrl",
    'emotion', t.emotion,
    'tapped_at', t."tappedAt",
    'read_at', t."readAt",
    'is_read', t."readAt" IS NOT NULL
  ) ORDER BY t."tappedAt" DESC), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT t.*, u.name, u."avatarUrl"
    FROM "thinking_of_you_taps" t
    LEFT JOIN "User" u ON u.id = t."senderId"
    WHERE t."receiverId" = p_user_id
      AND t."familyId" = p_family_id
    ORDER BY t."tappedAt" DESC
    LIMIT p_limit OFFSET p_offset
  ) sub;

  -- Also return the unread count
  DECLARE v_unread integer;
  BEGIN
    SELECT COUNT(*) INTO v_unread
    FROM "thinking_of_you_taps"
    WHERE "receiverId" = p_user_id
      AND "familyId" = p_family_id
      AND "readAt" IS NULL;
  END;

  RETURN jsonb_build_object('ok', true, 'taps', v_rows, 'unread_count', v_unread);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_get_received_taps(text, text, integer, integer) TO authenticated;

-- ── 4. RPC: fn_mark_taps_read ──────────────────────────────────────
-- Marks all unread taps as read for the user. Called when the user
-- opens the inbox screen.
CREATE OR REPLACE FUNCTION public.fn_mark_taps_read(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE "thinking_of_you_taps"
  SET "readAt" = now()
  WHERE "receiverId" = p_user_id
    AND "familyId" = p_family_id
    AND "readAt" IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'marked_read', v_count);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_mark_taps_read(text, text) TO authenticated;

-- ── 5. RPC: fn_get_unread_tap_count ───────────────────────────────
-- Lightweight RPC for the badge count on the family hub.
CREATE OR REPLACE FUNCTION public.fn_get_unread_tap_count(
  p_user_id text,
  p_family_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM "thinking_of_you_taps"
  WHERE "receiverId" = p_user_id
    AND "familyId" = p_family_id
    AND "readAt" IS NULL;

  RETURN jsonb_build_object('ok', true, 'unread_count', v_count);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_get_unread_tap_count(text, text) TO authenticated;
