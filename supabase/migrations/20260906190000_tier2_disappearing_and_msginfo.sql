-- =============================================================================
-- Daxelo Kinrel — Tier 2 chat features: disappearing messages + message info
-- =============================================================================
-- Two features in this migration:
--
-- 1. Disappearing messages
--    New column on ChatSettings: disappearingAfterHours. When non-null,
--    a nightly pg_cron job deletes ChatMessage rows older than the
--    threshold for that family chat. Any user can enable; any user can
--    disable (matches WhatsApp's behavior).
--
--    Valid values: NULL (off) · 24 · 168 (7d) · 2160 (90d).
--    The pg_cron job runs nightly at 03:00 UTC.
--
-- 2. Message info screen
--    New RPC fn_get_message_info(p_message_id) that returns:
--      • deliveredTo: family members who haven't read yet (excluding
--        the sender). For family chat with realtime, "delivered" = "is
--        a member" since realtime pushes to all online members.
--      • readBy: family members who have READ the message, with
--        readAt timestamp. Sourced from ChatReadReceipt.
--
--    The Flutter MessageInfoSheet renders two tabs: "Delivered to" +
--    "Read by" (WhatsApp-style).
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
-- DO $$ for the cron schedule (skip if already scheduled).
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Disappearing messages — column
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE "ChatSettings" ADD COLUMN IF NOT EXISTS "disappearingAfterHours" integer;
-- NULL = off, 24 = 24h, 168 = 7d, 2160 = 90d.

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_set_disappearing_messages — enable/disable per chat
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_disappearing_messages(
  p_family_id text,
  p_after_hours integer
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

  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;

  IF p_after_hours IS NOT NULL AND p_after_hours NOT IN (24, 168, 2160) THEN
    RETURN json_build_object('success', false, 'error', 'invalid_value',
      'message', 'Allowed values: NULL (off), 24 (24h), 168 (7d), 2160 (90d).');
  END IF;

  v_id := 'cs_' || v_user_id || '_' || p_family_id;

  INSERT INTO "ChatSettings" (
    "id", "userId", "familyId", "disappearingAfterHours", "updatedAt"
  ) VALUES (
    v_id, v_user_id, p_family_id, p_after_hours, now()
  )
  ON CONFLICT ("userId", "familyId")
  DO UPDATE SET
    "disappearingAfterHours" = p_after_hours,
    "updatedAt" = now();

  RETURN json_build_object(
    'success', true,
    'disappearingAfterHours', p_after_hours
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_disappearing_messages(text, integer) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_get_disappearing_messages — read current setting
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_disappearing_messages(
  p_family_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_hours integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT "disappearingAfterHours" INTO v_hours
  FROM "ChatSettings"
  WHERE "userId" = v_user_id AND "familyId" = p_family_id;

  RETURN json_build_object(
    'success', true,
    'disappearingAfterHours', v_hours
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_disappearing_messages(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. fn_cleanup_disappearing_messages — the nightly cron job
-- ═══════════════════════════════════════════════════════════════════════════
-- For each (userId, familyId) row in ChatSettings with a non-null
-- disappearingAfterHours, soft-delete that user's view of old messages
-- by appending the user's userId to deletedForMe on each old message
-- (other users may still want to see it). Skips rows where the user
-- is already in deletedForMe.
CREATE OR REPLACE FUNCTION fn_cleanup_disappearing_messages()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int := 0;
BEGIN
  UPDATE "ChatMessage" cm
  SET "deletedForMe" = cm."deletedForMe" || jsonb_build_array(cs."userId"),
      "updatedAt" = now()
  FROM "ChatSettings" cs
  WHERE cm."familyId" = cs."familyId"
    AND cs."disappearingAfterHours" IS NOT NULL
    AND cm."createdAt" < (now() - (cs."disappearingAfterHours" || ' hours')::interval)
    AND NOT (cm."deletedForMe" ? cs."userId")
    AND cm."isDeletedForEveryone" = false;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Disappearing cleanup: soft-deleted % rows', v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cleanup_disappearing_messages() TO authenticated;

-- Schedule the nightly cleanup job (idempotent via cron.job lookup).
-- Use a single-quoted command string (NOT dollar-quoted) to avoid the
-- $$ inside $$ nesting issue with the Management API's SQL runner.
DO $$
DECLARE
  v_job_name text := 'cleanup-disappearing-messages';
  v_existing bigint;
BEGIN
  SELECT jobid INTO v_existing FROM cron.job WHERE jobname = v_job_name;
  IF v_existing IS NULL THEN
    PERFORM cron.schedule(
      v_job_name,
      '0 3 * * *',
      'SELECT fn_cleanup_disappearing_messages();'
    );
    RAISE NOTICE 'Scheduled cron job %', v_job_name;
  ELSE
    RAISE NOTICE 'Cron job % already scheduled (jobid=%)', v_job_name, v_existing;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Cron schedule skipped: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Message info — fn_get_message_info
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_message_info(
  p_message_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_msg record;
  v_family_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT "id", "familyId", "senderId", "senderName", "createdAt"
    INTO v_msg
  FROM "ChatMessage" WHERE "id" = p_message_id;

  IF v_msg IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'message_not_found');
  END IF;

  v_family_id := v_msg."familyId";

  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_family_id AND "userId" = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;

  RETURN json_build_object(
    'success', true,
    'messageId', v_msg."id",
    'senderId', v_msg."senderId",
    'senderName', v_msg."senderName",
    'createdAt', to_char(v_msg."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'deliveredTo', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', fm."userId",
        'name', COALESCE(u.name, 'Member'),
        'avatarUrl', u."avatarUrl"
      ) ORDER BY u.name)
      FROM "FamilyMember" fm
      LEFT JOIN "User" u ON u.id = fm."userId"
      WHERE fm."familyId" = v_family_id
        AND fm."userId" <> v_msg."senderId"
        AND fm."userId" NOT IN (
          SELECT "userId" FROM "ChatReadReceipt" WHERE "messageId" = p_message_id
        )
    ), '[]'::jsonb),
    'readBy', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'userId', rr."userId",
        'name', COALESCE(u.name, 'Member'),
        'avatarUrl', u."avatarUrl",
        'readAt', to_char(rr."readAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
      ) ORDER BY rr."readAt" ASC)
      FROM "ChatReadReceipt" rr
      LEFT JOIN "User" u ON u.id = rr."userId"
      WHERE rr."messageId" = p_message_id
    ), '[]'::jsonb)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_message_info(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Verification
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'ChatSettings.disappearingAfterHours' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'ChatSettings' AND column_name = 'disappearingAfterHours'
       ) AS exists;
SELECT 'fn_set_disappearing_messages' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_disappearing_messages') AS exists;
SELECT 'fn_get_disappearing_messages' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_disappearing_messages') AS exists;
SELECT 'fn_cleanup_disappearing_messages' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_cleanup_disappearing_messages') AS exists;
SELECT 'fn_get_message_info' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_message_info') AS exists;
SELECT 'cron job' AS obj,
       EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'cleanup-disappearing-messages') AS exists;
