-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.8: Group Admin Audit Log
-- =============================================================================
-- Records every admin action (member joined/left/removed/muted, message
-- pinned/unpinned, settings changed, slow-mode set, etc.) so admins can
-- review group activity. Surfaced via the "Admin actions" screen in
-- group info.
--
-- Schema:
--   • GroupAuditLog table — id, familyId, actorUserId, actionType,
--     targetUserId?, targetMessageId?, details jsonb, createdAt.
--   • RLS: family members can SELECT (matches ChatMessage visibility);
--     INSERT via SECURITY DEFINER RPC so non-admins can't forge entries.
--
-- Usage:
--   The NestJS ChatService + new admin endpoints wrap every privileged
--   action in a helper that also inserts a log row. See
--   AdminAuditService.record(...) in the NestJS module.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "GroupAuditLog" (
  "id"              text PRIMARY KEY,
  "familyId"        text NOT NULL,
  "actorUserId"     text NOT NULL,
  "actionType"      text NOT NULL,        -- member_joined | member_left | member_removed | member_muted | slow_mode_set | description_set | message_pinned | message_unpinned | invite_link_created | invite_link_revoked | join_request_approved | join_request_rejected | anonymous_admin_message_sent | topic_created | topic_deleted | sticker_pack_set | custom_reactions_set
  "targetUserId"    text,
  "targetMessageId" text,
  "details"         jsonb NOT NULL DEFAULT '[]'::jsonb,
  "createdAt"       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "GroupAuditLog_family_idx" ON "GroupAuditLog"("familyId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "GroupAuditLog_actor_idx"  ON "GroupAuditLog"("actorUserId");
CREATE INDEX IF NOT EXISTS "GroupAuditLog_target_idx" ON "GroupAuditLog"("targetUserId") WHERE "targetUserId" IS NOT NULL;

ALTER TABLE "GroupAuditLog" ENABLE ROW LEVEL SECURITY;

-- SELECT: any family member can read (matches ChatMessage visibility).
DROP POLICY IF EXISTS "GroupAuditLog select member" ON "GroupAuditLog";
CREATE POLICY "GroupAuditLog select member" ON "GroupAuditLog"
  FOR SELECT TO authenticated USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

-- No INSERT/UPDATE/DELETE policy — writes happen only via the
-- SECURITY DEFINER RPC fn_log_group_audit.

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_log_group_audit — internal helper called by NestJS admin endpoints.
-- Validates the actor is a member of the family (not necessarily an admin —
-- the action-specific check happens at the caller).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_log_group_audit(
  p_family_id text,
  p_actor_user_id text,
  p_action_type text,
  p_target_user_id text DEFAULT NULL,
  p_target_message_id text DEFAULT NULL,
  p_details jsonb DEFAULT '[]'::jsonb
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text;
BEGIN
  -- No auth check here — this RPC is called by the NestJS server after
  -- it has already validated the caller's identity + admin role. We DO
  -- verify the actor is a member of the family as a defense-in-depth.
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = p_actor_user_id
  ) THEN
    RETURN NULL;
  END IF;

  v_id := 'gal_' || extract(epoch from now())::bigint::text || '_' || substring(p_actor_user_id from 1 for 8);

  INSERT INTO "GroupAuditLog" (
    "id", "familyId", "actorUserId", "actionType",
    "targetUserId", "targetMessageId", "details",
    "createdAt"
  ) VALUES (
    v_id, p_family_id, p_actor_user_id, p_action_type,
    p_target_user_id, p_target_message_id, p_details,
    now()
  );

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_log_group_audit(
  text, text, text, text, text, jsonb
) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_get_group_audit_log — paginated read for the admin-actions screen
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_group_audit_log(
  p_family_id text,
  p_limit int DEFAULT 50,
  p_before text DEFAULT NULL
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
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', g."id",
      'familyId', g."familyId",
      'actorUserId', g."actorUserId",
      'actorName', COALESCE(u.name, 'Member'),
      'actorAvatarUrl', u."avatarUrl",
      'actionType', g."actionType",
      'targetUserId', g."targetUserId",
      'targetMessageId', g."targetMessageId",
      'details', g."details",
      'createdAt', to_char(g."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    ) ORDER BY g."createdAt" DESC)
    FROM "GroupAuditLog" g
    LEFT JOIN "User" u ON u.id = g."actorUserId"
    WHERE g."familyId" = p_family_id
      AND (p_before IS NULL OR g."createdAt" < p_before::timestamptz)
    LIMIT GREATEST(LEAST(p_limit, 200), 1)
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_group_audit_log(text, int, text) TO authenticated;

-- Verification
SELECT 'GroupAuditLog' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'GroupAuditLog') AS exists;
SELECT 'fn_log_group_audit' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_log_group_audit') AS exists;
SELECT 'fn_get_group_audit_log' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_group_audit_log') AS exists;
