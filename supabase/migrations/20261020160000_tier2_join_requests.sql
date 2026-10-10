-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.10: Join Requests (approval flow for public groups)
-- =============================================================================
-- Schema for the join-request flow. Used by fn_join_via_invite_link when the
-- link has requireApproval=true. Also used directly by the Flutter "Join"
-- button on a public family's discovery page.
--
-- Schema:
--   • GroupJoinRequest table — id, familyId, requesterUserId, status,
--     requestedAt, decidedBy, decidedAt, viaInviteToken (nullable), details.
--   • RLS: requester + family admins can SELECT; only admins can UPDATE
--     (via the approve/reject RPC).
--   • The approve flow inserts a FamilyMember row + logs to GroupAuditLog.
--
-- Status transitions: pending → approved | rejected (terminal).
-- =============================================================================

CREATE TABLE IF NOT EXISTS "GroupJoinRequest" (
  "id"                text PRIMARY KEY,
  "familyId"          text NOT NULL,
  "requesterUserId"   text NOT NULL,
  "status"            text NOT NULL DEFAULT 'pending',  -- pending | approved | rejected
  "requestedAt"       timestamptz NOT NULL DEFAULT now(),
  "decidedBy"         text,
  "decidedAt"         timestamptz,
  "viaInviteToken"    text,
  "details"           jsonb NOT NULL DEFAULT '[]'::jsonb,
  "createdAt"         timestamptz NOT NULL DEFAULT now(),
  "updatedAt"         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "GJR_family_pending_idx" ON "GroupJoinRequest"("familyId", "requestedAt" DESC) WHERE "status" = 'pending';
CREATE INDEX IF NOT EXISTS "GJR_requester_idx"       ON "GroupJoinRequest"("requesterUserId");
CREATE UNIQUE INDEX IF NOT EXISTS "GJR_pending_uniq"  ON "GroupJoinRequest"("familyId", "requesterUserId") WHERE "status" = 'pending';

ALTER TABLE "GroupJoinRequest" ENABLE ROW LEVEL SECURITY;

-- SELECT: requester (own rows) + family admins/creators.
DROP POLICY IF EXISTS "GJR select own_or_admin" ON "GroupJoinRequest";
CREATE POLICY "GJR select own_or_admin" ON "GroupJoinRequest"
  FOR SELECT TO authenticated USING (
    "requesterUserId" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "GroupJoinRequest"."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm.role IN ('admin', 'creator')
    )
  );

-- No INSERT/UPDATE/DELETE policy — writes go through SECURITY DEFINER RPCs.

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_request_to_join_family — creates a pending request
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_request_to_join_family(
  p_family_id text,
  p_details jsonb DEFAULT '[]'::jsonb
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
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Block if already a member.
  IF EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'already_member');
  END IF;

  -- Idempotent: if a pending request already exists, return it.
  SELECT id INTO v_existing FROM "GroupJoinRequest"
    WHERE "familyId" = p_family_id AND "requesterUserId" = v_user_id
      AND "status" = 'pending';
  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', true, 'action', 'already_pending',
      'joinRequestId', v_existing);
  END IF;

  v_id := 'gjr_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "GroupJoinRequest" (
    "id", "familyId", "requesterUserId", "status",
    "requestedAt", "details",
    "createdAt", "updatedAt"
  ) VALUES (
    v_id, p_family_id, v_user_id, 'pending',
    now(), p_details,
    now(), now()
  );

  RETURN json_build_object(
    'success', true,
    'action', 'request_submitted',
    'joinRequestId', v_id,
    'familyId', p_family_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_request_to_join_family(text, jsonb) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_approve_join_request — admin-only approve. Inserts the FamilyMember +
-- bumps memberCount + logs to GroupAuditLog.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_approve_join_request(p_join_request_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_row record;
  v_member_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_row FROM "GroupJoinRequest" WHERE "id" = p_join_request_id;
  IF v_row IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_row."familyId" AND "userId" = v_user_id
      AND role IN ('admin', 'creator')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'not_admin');
  END IF;
  IF v_row."status" <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'not_pending',
      'currentStatus', v_row."status");
  END IF;

  -- Idempotent: if the requester is already a member (e.g., joined via
  -- another link between the request + now), just mark the request approved.
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_row."familyId" AND "userId" = v_row."requesterUserId"
  ) THEN
    v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_row."requesterUserId" from 1 for 8);
    INSERT INTO "FamilyMember" (
      "id", "familyId", "userId", "role", "joinedAt"
    ) VALUES (
      v_member_id, v_row."familyId", v_row."requesterUserId", 'member', now()
    );
    UPDATE "Family"
      SET "memberCount" = "memberCount" + 1, "updatedAt" = now(), "lastActivityAt" = now()
      WHERE id = v_row."familyId";
  END IF;

  UPDATE "GroupJoinRequest"
    SET "status" = 'approved', "decidedBy" = v_user_id, "decidedAt" = now(), "updatedAt" = now()
    WHERE "id" = p_join_request_id;

  PERFORM fn_log_group_audit(
    v_row."familyId", v_user_id, 'join_request_approved',
    v_row."requesterUserId", NULL,
    jsonb_build_object('joinRequestId', p_join_request_id)
  );

  RETURN json_build_object('success', true, 'action', 'approved', 'familyId', v_row."familyId");
END;
$$;

GRANT EXECUTE ON FUNCTION fn_approve_join_request(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_reject_join_request — admin-only reject
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_reject_join_request(p_join_request_id text)
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
  SELECT * INTO v_row FROM "GroupJoinRequest" WHERE "id" = p_join_request_id;
  IF v_row IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_row."familyId" AND "userId" = v_user_id
      AND role IN ('admin', 'creator')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'not_admin');
  END IF;
  IF v_row."status" <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'not_pending',
      'currentStatus', v_row."status");
  END IF;

  UPDATE "GroupJoinRequest"
    SET "status" = 'rejected', "decidedBy" = v_user_id, "decidedAt" = now(), "updatedAt" = now()
    WHERE "id" = p_join_request_id;

  PERFORM fn_log_group_audit(
    v_row."familyId", v_user_id, 'join_request_rejected',
    v_row."requesterUserId", NULL,
    jsonb_build_object('joinRequestId', p_join_request_id)
  );

  RETURN json_build_object('success', true, 'action', 'rejected', 'familyId', v_row."familyId");
END;
$$;

GRANT EXECUTE ON FUNCTION fn_reject_join_request(text) TO authenticated;

-- Verification
SELECT 'GroupJoinRequest' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'GroupJoinRequest') AS exists;
SELECT 'fn_request_to_join_family' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_request_to_join_family') AS exists;
SELECT 'fn_approve_join_request' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_approve_join_request') AS exists;
SELECT 'fn_reject_join_request' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_reject_join_request') AS exists;
