-- =============================================================================
-- Daxelo Kinrel — Tier 3 Feature 3.5: Read receipts + last-seen privacy toggle
-- =============================================================================
-- Lets a user hide their last-seen + read receipts from OTHER users. The
-- privacy is reciprocal (WhatsApp-style): if you hide your last-seen from
-- someone, you can't see theirs either.
--
-- Schema:
--   • lastSeenVisibility text DEFAULT 'everyone' (everyone | contacts | nobody)
--   • readReceiptsEnabled boolean DEFAULT true
--   (Both on the User table.)
--
-- Behavior:
--   • The NestJS ChatService.getGroupInfo + the UserPresence reader check
--     the requested user's lastSeenVisibility:
--       - 'everyone' → return the timestamp as-is.
--       - 'contacts' → return only if the requester is in a family with the user.
--       - 'nobody'   → return null (requester sees "last seen recently").
--     BUT: if the REQUESTER has lastSeenVisibility='nobody', they ALWAYS
--     get null back (reciprocity).
--   • readReceiptsEnabled: when false, the user's messages don't get
--     readBy updates from other users (suppress markAsRead writes from
--     users who have this set to false). Matched symmetrically: if user A
--     has readReceiptsEnabled=false, their own READ state on others'
--     messages is suppressed (others can't see that A read their message).
--
-- Idempotent.
-- =============================================================================

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "lastSeenVisibility" text NOT NULL DEFAULT 'everyone';
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "readReceiptsEnabled" boolean NOT NULL DEFAULT true;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'User_lastSeenVisibility_chk'
  ) THEN
    ALTER TABLE "User"
      ADD CONSTRAINT "User_lastSeenVisibility_chk"
      CHECK ("lastSeenVisibility" IN ('everyone', 'contacts', 'nobody'));
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'User_lastSeenVisibility_chk: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_privacy_settings — update the caller's own privacy settings
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_privacy_settings(
  p_last_seen_visibility text DEFAULT NULL,
  p_read_receipts_enabled boolean DEFAULT NULL
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

  IF p_last_seen_visibility IS NOT NULL AND p_last_seen_visibility NOT IN ('everyone', 'contacts', 'nobody') THEN
    RETURN json_build_object('success', false, 'error', 'invalid_value',
      'message', 'lastSeenVisibility must be everyone | contacts | nobody.');
  END IF;

  UPDATE "User" SET
    "lastSeenVisibility" = COALESCE(p_last_seen_visibility, "lastSeenVisibility"),
    "readReceiptsEnabled" = COALESCE(p_read_receipts_enabled, "readReceiptsEnabled"),
    "updatedAt" = now()
    WHERE id = v_user_id;

  RETURN json_build_object(
    'success', true,
    'lastSeenVisibility', COALESCE(p_last_seen_visibility, (SELECT "lastSeenVisibility" FROM "User" WHERE id = v_user_id)),
    'readReceiptsEnabled', COALESCE(p_read_receipts_enabled, (SELECT "readReceiptsEnabled" FROM "User" WHERE id = v_user_id))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_privacy_settings(text, boolean) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_get_privacy_settings — read the caller's own settings (used by the
-- Flutter settings screen to render the current state).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_privacy_settings()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_row record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  SELECT "lastSeenVisibility", "readReceiptsEnabled" INTO v_row FROM "User" WHERE id = v_user_id;
  IF v_row IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'user_not_found');
  END IF;
  RETURN json_build_object(
    'success', true,
    'lastSeenVisibility', v_row."lastSeenVisibility",
    'readReceiptsEnabled', v_row."readReceiptsEnabled"
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_privacy_settings() TO authenticated;

-- Verification
SELECT 'User.lastSeenVisibility' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'User' AND column_name = 'lastSeenVisibility'
       ) AS exists;
SELECT 'User.readReceiptsEnabled' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'User' AND column_name = 'readReceiptsEnabled'
       ) AS exists;
SELECT 'fn_set_privacy_settings' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_privacy_settings') AS exists;
SELECT 'fn_get_privacy_settings' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_privacy_settings') AS exists;
