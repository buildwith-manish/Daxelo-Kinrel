-- =============================================================================
-- Daxelo Kinrel — Tier 3 Features 3.2 + 3.3 + 3.4: Pin chats / Mark as unread / Mute with duration
-- =============================================================================
-- Three small-but-high-impact features on the ChatSettings table:
--
-- 3.2 Pin chats (in main list)
--   • Add `pinnedOrder int` to ChatSettings. Null = unpinned, 1..N = top of
--     pinned (lower number = higher up). The Flutter inbox sorts by
--     pinnedOrder ASC then lastMessageAt DESC.
--   • Cap: max 5 pinned chats per user (enforced in the NestJS service).
--
-- 3.3 Mark as unread (toggle)
--   • Add `forcedUnread boolean DEFAULT false` to ChatSettings. When true,
--     the inbox row renders an unread badge EVEN IF all messages in the
--     chat are read. Toggling back to false clears the badge. Matches the
--     WhatsApp "mark as unread" UX.
--
-- 3.4 Mute with custom duration
--   • Add `mutedUntil timestamptz` to ChatSettings. The existing `isMuted`
--     boolean becomes a derived field: `effectiveMuted = isMuted OR
--     (mutedUntil IS NOT NULL AND mutedUntil > now())`. The NestJS push
--     scheduler already checks isMuted — extended to also check mutedUntil.
--
-- Idempotent.
-- =============================================================================

ALTER TABLE "ChatSettings" ADD COLUMN IF NOT EXISTS "pinnedOrder" integer;
ALTER TABLE "ChatSettings" ADD COLUMN IF NOT EXISTS "forcedUnread" boolean NOT NULL DEFAULT false;
ALTER TABLE "ChatSettings" ADD COLUMN IF NOT EXISTS "mutedUntil" timestamptz;

-- Partial index for the inbox "pinned chats" query — quickly find all of a
-- user's pinned chats ordered by pinnedOrder.
CREATE INDEX IF NOT EXISTS "ChatSettings_pinned_idx"
  ON "ChatSettings"("userId", "pinnedOrder")
  WHERE "pinnedOrder" IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_chat_pinned — pin (with order) or unpin (when pinnedOrder=null)
-- Caps at 5 pinned per user.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_chat_pinned(
  p_family_id text,
  p_pinned_order integer  -- null = unpin
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_count int;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  v_id := 'cs_' || v_user_id || '_' || p_family_id;

  -- Enforce max 5 pinned per user when pinning (not unpinning).
  IF p_pinned_order IS NOT NULL THEN
    SELECT count(*) INTO v_count FROM "ChatSettings"
      WHERE "userId" = v_user_id AND "pinnedOrder" IS NOT NULL;
    IF v_count >= 5 THEN
      RETURN json_build_object('success', false, 'error', 'max_pinned_reached',
        'message', 'You can pin at most 5 chats.');
    END IF;
  END IF;

  INSERT INTO "ChatSettings" (
    "id", "userId", "familyId",
    "pinnedOrder",
    "createdAt", "updatedAt"
  ) VALUES (
    v_id, v_user_id, p_family_id,
    p_pinned_order,
    now(), now()
  )
  ON CONFLICT ("userId", "familyId")
  DO UPDATE SET
    "pinnedOrder" = p_pinned_order,
    "updatedAt" = now();

  RETURN json_build_object(
    'success', true,
    'familyId', p_family_id,
    'pinnedOrder', p_pinned_order
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_chat_pinned(text, integer) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_chat_forced_unread — toggle the "mark as unread" badge
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_chat_forced_unread(
  p_family_id text,
  p_forced_unread boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  v_id := 'cs_' || v_user_id || '_' || p_family_id;

  INSERT INTO "ChatSettings" (
    "id", "userId", "familyId",
    "forcedUnread",
    "createdAt", "updatedAt"
  ) VALUES (
    v_id, v_user_id, p_family_id,
    p_forced_unread,
    now(), now()
  )
  ON CONFLICT ("userId", "familyId")
  DO UPDATE SET
    "forcedUnread" = p_forced_unread,
    "updatedAt" = now();

  RETURN json_build_object(
    'success', true,
    'familyId', p_family_id,
    'forcedUnread', p_forced_unread
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_chat_forced_unread(text, boolean) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_chat_muted_until — mute for a duration OR unmute
--   p_muted_until: null = unmute immediately (also clears isMuted)
--                  now() = unmute immediately
--                  future timestamp = mute until that time (also sets isMuted=true)
-- The caller passes the EXACT expiry timestamp (e.g. now + 8h). The NestJS
-- push scheduler checks `mutedUntil IS NULL OR mutedUntil > now()` (plus
-- `isMuted` for the binary case) to decide whether to suppress the push.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_chat_muted_until(
  p_family_id text,
  p_muted_until timestamptz
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_effective_muted boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  v_id := 'cs_' || v_user_id || '_' || p_family_id;

  -- Effective mute: mutedUntil must be in the future for the row to count as
  -- muted. A null or past mutedUntil means unmute (clears isMuted too).
  v_effective_muted := (p_muted_until IS NOT NULL AND p_muted_until > now());

  INSERT INTO "ChatSettings" (
    "id", "userId", "familyId",
    "isMuted", "mutedUntil",
    "createdAt", "updatedAt"
  ) VALUES (
    v_id, v_user_id, p_family_id,
    v_effective_muted, p_muted_until,
    now(), now()
  )
  ON CONFLICT ("userId", "familyId")
  DO UPDATE SET
    "isMuted" = v_effective_muted,
    "mutedUntil" = p_muted_until,
    "updatedAt" = now();

  RETURN json_build_object(
    'success', true,
    'familyId', p_family_id,
    'isMuted', v_effective_muted,
    'mutedUntil', CASE WHEN p_muted_until IS NULL THEN NULL
                       ELSE to_char(p_muted_until AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_chat_muted_until(text, timestamptz) TO authenticated;

-- Verification
SELECT 'ChatSettings.pinnedOrder' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatSettings' AND column_name = 'pinnedOrder'
       ) AS exists;
SELECT 'ChatSettings.forcedUnread' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatSettings' AND column_name = 'forcedUnread'
       ) AS exists;
SELECT 'ChatSettings.mutedUntil' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatSettings' AND column_name = 'mutedUntil'
       ) AS exists;
SELECT 'fn_set_chat_pinned' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_chat_pinned') AS exists;
SELECT 'fn_set_chat_forced_unread' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_chat_forced_unread') AS exists;
SELECT 'fn_set_chat_muted_until' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_chat_muted_until') AS exists;
