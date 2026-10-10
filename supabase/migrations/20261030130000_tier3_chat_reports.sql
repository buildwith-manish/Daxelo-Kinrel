-- =============================================================================
-- Daxelo Kinrel — Tier 3 Feature 3.6: Block + Report from chat
-- =============================================================================
-- Lets a user report another user (or a specific message) for abuse.
-- The BlockedUser table already exists for blocking — this migration adds
-- the ChatReport table for moderation queue intake.
--
-- Schema:
--   • ChatReport table — id, reporterId, reportedUserId?, familyId?,
--     messageId?, reason (spam|abuse|fake|harassment|other), details,
--     status (pending|reviewing|resolved|dismissed), createdAt.
--   • RLS: only the reporter can SELECT their own reports. INSERT is open
--     (any authenticated user can report). Updates go through a moderation
--     queue (admin-only via the existing admin module — TODO).
--
-- Idempotent.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "ChatReport" (
  "id"              text PRIMARY KEY,
  "reporterId"      text NOT NULL,
  "reportedUserId"  text,                  -- null when reporting a family-group message generally
  "familyId"        text,                  -- null when reporting a DM
  "messageId"       text,                  -- null when reporting a user (not a specific message)
  "reason"          text NOT NULL,         -- spam | abuse | fake | harassment | other
  "details"         text,                  -- free-form context (max 1000 chars)
  "status"          text NOT NULL DEFAULT 'pending',  -- pending | reviewing | resolved | dismissed
  "createdAt"       timestamptz NOT NULL DEFAULT now(),
  "updatedAt"       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "ChatReport_reason_chk" CHECK (
    "reason" IN ('spam', 'abuse', 'fake', 'harassment', 'other')
  ),
  CONSTRAINT "ChatReport_status_chk" CHECK (
    "status" IN ('pending', 'reviewing', 'resolved', 'dismissed')
  )
);

CREATE INDEX IF NOT EXISTS "ChatReport_reporter_idx"     ON "ChatReport"("reporterId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ChatReport_reported_idx"    ON "ChatReport"("reportedUserId") WHERE "reportedUserId" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "ChatReport_status_idx"       ON "ChatReport"("status", "createdAt" DESC) WHERE "status" IN ('pending', 'reviewing');

ALTER TABLE "ChatReport" ENABLE ROW LEVEL SECURITY;

-- SELECT: only the reporter sees their own reports.
DROP POLICY IF EXISTS "ChatReport select own" ON "ChatReport";
CREATE POLICY "ChatReport select own" ON "ChatReport"
  FOR SELECT TO authenticated USING ("reporterId" = auth.uid()::text);

-- INSERT: any authenticated user can create a report.
DROP POLICY IF EXISTS "ChatReport insert own" ON "ChatReport";
CREATE POLICY "ChatReport insert own" ON "ChatReport"
  FOR INSERT TO authenticated WITH CHECK ("reporterId" = auth.uid()::text);

-- No UPDATE/DELETE policy — moderation is admin-only via a separate path.

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_report_chat — submit a report. Validates:
--   • At least one of reportedUserId / messageId must be set.
--   • If messageId is set, the reporter must be able to see it (family
--     membership for family messages; sender-or-receiver for DMs).
--   • If messageId is set but reportedUserId is null, the RPC resolves
--     the message's senderId as the reported user.
-- Idempotent on (reporterId, messageId, reason) within 24h — re-submitting
-- the same report returns the existing one instead of creating duplicates.
-- ═══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS fn_report_chat(text, text, text, text, text);
CREATE OR REPLACE FUNCTION fn_report_chat(
  p_reported_user_id text DEFAULT NULL,
  p_family_id text DEFAULT NULL,
  p_message_id text DEFAULT NULL,
  p_reason text DEFAULT 'other',
  p_details text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_existing text;
  v_msg record;
  v_resolved_reported_user text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  IF p_reason NOT IN ('spam', 'abuse', 'fake', 'harassment', 'other') THEN
    RETURN json_build_object('success', false, 'error', 'invalid_reason');
  END IF;

  IF p_details IS NOT NULL AND char_length(p_details) > 1000 THEN
    RETURN json_build_object('success', false, 'error', 'details_too_long');
  END IF;

  IF p_reported_user_id IS NULL AND p_message_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'no_target',
      'message', 'Pass reportedUserId or messageId.');
  END IF;

  -- If messageId given, verify visibility + resolve reportedUserId from
  -- the message's senderId (if reportedUserId wasn't passed).
  IF p_message_id IS NOT NULL THEN
    -- Family message path.
    SELECT "id", "senderId", "familyId" INTO v_msg FROM "ChatMessage" WHERE "id" = p_message_id;
    IF v_msg IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM "FamilyMember"
        WHERE "familyId" = v_msg."familyId" AND "userId" = v_user_id
      ) THEN
        RETURN json_build_object('success', false, 'error', 'not_in_family');
      END IF;
      v_resolved_reported_user := COALESCE(p_reported_user_id, v_msg."senderId");
    ELSE
      -- DM path.
      SELECT "id", "senderId", "receiverId" INTO v_msg FROM "DirectMessage" WHERE "id" = p_message_id;
      IF v_msg IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'message_not_found');
      END IF;
      IF v_user_id <> v_msg."senderId" AND v_user_id <> v_msg."receiverId" THEN
        RETURN json_build_object('success', false, 'error', 'not_authorized');
      END IF;
      v_resolved_reported_user := COALESCE(p_reported_user_id, v_msg."senderId");
    END IF;
  ELSE
    v_resolved_reported_user := p_reported_user_id;
  END IF;

  -- Idempotency: same (reporterId, reportedUserId, reason) within 24h.
  SELECT id INTO v_existing FROM "ChatReport"
    WHERE "reporterId" = v_user_id
      AND "reportedUserId" = v_resolved_reported_user
      AND "reason" = p_reason
      AND "createdAt" > now() - interval '24 hours'
    LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', true, 'action', 'already_reported',
      'reportId', v_existing);
  END IF;

  v_id := 'cr_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "ChatReport" (
    "id", "reporterId", "reportedUserId", "familyId", "messageId",
    "reason", "details", "status",
    "createdAt", "updatedAt"
  ) VALUES (
    v_id, v_user_id, v_resolved_reported_user, p_family_id, p_message_id,
    p_reason, p_details, 'pending',
    now(), now()
  );

  RETURN json_build_object(
    'success', true,
    'action', 'created',
    'reportId', v_id,
    'reportedUserId', v_resolved_reported_user
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_report_chat(
  text, text, text, text, text
) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_block_user — record a block from chat. (BlockedUser table already
-- exists; this RPC just wraps the insert + idempotency check.)
-- ═══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS fn_block_user(text);
CREATE OR REPLACE FUNCTION fn_block_user(p_blocked_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_existing text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_blocked_id IS NULL OR p_blocked_id = v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'invalid_target');
  END IF;

  SELECT id INTO v_existing FROM "BlockedUser"
    WHERE "blockerId" = v_user_id AND "blockedId" = p_blocked_id;
  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', true, 'action', 'already_blocked', 'blockId', v_existing);
  END IF;

  v_id := 'bu_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6) || '_' || substring(p_blocked_id from 1 for 6);
  INSERT INTO "BlockedUser" ("id", "blockerId", "blockedId", "createdAt")
  VALUES (v_id, v_user_id, p_blocked_id, now())
  ON CONFLICT ("blockerId", "blockedId") DO NOTHING;

  RETURN json_build_object('success', true, 'action', 'created', 'blockId', v_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_block_user(text) TO authenticated;

-- Verification
SELECT 'ChatReport' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChatReport') AS exists;
SELECT 'fn_report_chat' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_report_chat') AS exists;
SELECT 'fn_block_user' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_block_user') AS exists;
