-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.9: Group Invite Links (with expiry + limit)
-- =============================================================================
-- Lets a group admin create shareable invite links with options:
--   • never expires / expires in 7d / 30d / custom
--   • unlimited uses / 1-use / 5-uses / 50-uses
--   • require admin approval (toggles the join-requests flow — feature 2.10)
--
-- The link format is `https://kinrel.app/join/<token>` where token is a
-- 22-char URL-safe random string. Tapping the link deep-links into the app
-- → joins the family (or shows the approval flow if requireApproval=true).
--
-- Schema:
--   • GroupInviteLink table — id, familyId, token (unique), createdBy,
--     expiresAt (null = never), maxUses (null = unlimited), useCount,
--     requireApproval, label, createdAt, revokedAt.
--   • RLS: family members can SELECT (so they can share); only the creator
--     or any admin can DELETE (revoke).
--   • Public join: the fn_join_via_invite_link RPC validates the token,
--     checks expiry + max uses, then either joins directly (when
--     requireApproval=false) or creates a GroupJoinRequest (feature 2.10).
-- =============================================================================

CREATE TABLE IF NOT EXISTS "GroupInviteLink" (
  "id"               text PRIMARY KEY,
  "familyId"         text NOT NULL,
  "token"            text NOT NULL UNIQUE,    -- 22-char URL-safe random
  "createdBy"        text NOT NULL,
  "label"            text,                     -- admin-facing name like "Diwali 2026"
  "expiresAt"        timestamptz,              -- null = never expires
  "maxUses"          integer,                  -- null = unlimited
  "useCount"         integer NOT NULL DEFAULT 0,
  "requireApproval"  boolean NOT NULL DEFAULT false,
  "createdAt"        timestamptz NOT NULL DEFAULT now(),
  "revokedAt"        timestamptz,              -- null = active
  "updatedAt"        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "GIL_family_idx"     ON "GroupInviteLink"("familyId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "GIL_token_idx"     ON "GroupInviteLink"("token") WHERE "revokedAt" IS NULL;
CREATE INDEX IF NOT EXISTS "GIL_active_idx"     ON "GroupInviteLink"("familyId") WHERE "revokedAt" IS NULL;

ALTER TABLE "GroupInviteLink" ENABLE ROW LEVEL SECURITY;

-- SELECT: family members can see all links (so they can share any active one).
DROP POLICY IF EXISTS "GIL select member" ON "GroupInviteLink";
CREATE POLICY "GIL select member" ON "GroupInviteLink"
  FOR SELECT TO authenticated USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

-- INSERT: family members can create links (the RPC enforces admin-only; this
-- policy is permissive so the SECURITY DEFINER RPC works).
DROP POLICY IF EXISTS "GIL insert member" ON "GroupInviteLink";
CREATE POLICY "GIL insert member" ON "GroupInviteLink"
  FOR INSERT TO authenticated WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

-- UPDATE: only the creator or any admin.
DROP POLICY IF EXISTS "GIL update creator_or_admin" ON "GroupInviteLink";
CREATE POLICY "GIL update creator_or_admin" ON "GroupInviteLink"
  FOR UPDATE TO authenticated USING (
    "createdBy" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "GroupInviteLink"."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm.role IN ('admin', 'creator')
    )
  );

-- DELETE: same as UPDATE — only creator or admin can revoke (we soft-delete
-- by setting revokedAt, but a hard DELETE is also allowed for cleanup).
DROP POLICY IF EXISTS "GIL delete creator_or_admin" ON "GroupInviteLink";
CREATE POLICY "GIL delete creator_or_admin" ON "GroupInviteLink"
  FOR DELETE TO authenticated USING (
    "createdBy" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "GroupInviteLink"."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm.role IN ('admin', 'creator')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_create_group_invite_link — admin-only link creation
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_create_group_invite_link(
  p_family_id text,
  p_label text DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL,        -- null = never
  p_max_uses integer DEFAULT NULL,               -- null = unlimited
  p_require_approval boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_role text;
  v_id text;
  v_token text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  SELECT role INTO v_role FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id;
  IF v_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;
  IF v_role NOT IN ('admin', 'creator') THEN
    RETURN json_build_object('success', false, 'error', 'not_admin');
  END IF;
  IF p_expires_at IS NOT NULL AND p_expires_at <= now() THEN
    RETURN json_build_object('success', false, 'error', 'invalid_expiry');
  END IF;
  IF p_max_uses IS NOT NULL AND p_max_uses <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_max_uses');
  END IF;

  v_id := 'gil_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  -- 22-char URL-safe random token (extended_letters + digits).
  v_token := substring(encode(gen_random_bytes(16), 'base64') from 1 for 22);
  -- Replace URL-unsafe chars.
  v_token := replace(replace(replace(v_token, '+', '-'), '/', '_'), '=', 'A');

  INSERT INTO "GroupInviteLink" (
    "id", "familyId", "token", "createdBy", "label",
    "expiresAt", "maxUses", "requireApproval",
    "useCount", "createdAt", "updatedAt"
  ) VALUES (
    v_id, p_family_id, v_token, v_user_id, p_label,
    p_expires_at, p_max_uses, p_require_approval,
    0, now(), now()
  );

  PERFORM fn_log_group_audit(
    p_family_id, v_user_id, 'invite_link_created',
    NULL, NULL, jsonb_build_object('inviteLinkId', v_id, 'token', v_token, 'requireApproval', p_require_approval)
  );

  RETURN json_build_object(
    'success', true,
    'inviteLinkId', v_id,
    'token', v_token,
    'url', 'https://kinrel.app/join/' || v_token,
    'familyId', p_family_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_create_group_invite_link(
  text, text, timestamptz, integer, boolean
) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_revoke_group_invite_link — admin-only soft-revoke (sets revokedAt)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_revoke_group_invite_link(p_token text)
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

  SELECT * INTO v_row FROM "GroupInviteLink" WHERE "token" = p_token;
  IF v_row IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;

  IF v_row."createdBy" <> v_user_id AND NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_row."familyId" AND "userId" = v_user_id
      AND role IN ('admin', 'creator')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'not_allowed');
  END IF;

  UPDATE "GroupInviteLink"
    SET "revokedAt" = now(), "updatedAt" = now()
    WHERE "token" = p_token;

  PERFORM fn_log_group_audit(
    v_row."familyId", v_user_id, 'invite_link_revoked',
    NULL, NULL, jsonb_build_object('token', p_token)
  );

  RETURN json_build_object('success', true, 'token', p_token);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_revoke_group_invite_link(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_join_via_invite_link — public entry point. Validates the token, checks
-- expiry + max uses, then either adds the user as a member directly
-- (requireApproval=false) or creates a GroupJoinRequest (requireApproval=true).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_join_via_invite_link(p_token text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_row record;
  v_already_member boolean;
  v_existing_request text;
  v_member_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_row FROM "GroupInviteLink"
    WHERE "token" = p_token AND "revokedAt" IS NULL;
  IF v_row IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'link_not_found_or_revoked');
  END IF;
  IF v_row."expiresAt" IS NOT NULL AND v_row."expiresAt" < now() THEN
    RETURN json_build_object('success', false, 'error', 'link_expired');
  END IF;
  IF v_row."maxUses" IS NOT NULL AND v_row."useCount" >= v_row."maxUses" THEN
    RETURN json_build_object('success', false, 'error', 'link_exhausted');
  END IF;

  -- Check if the caller is already a member.
  SELECT EXISTS(
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = v_row."familyId" AND "userId" = v_user_id
  ) INTO v_already_member;
  IF v_already_member THEN
    RETURN json_build_object('success', true, 'action', 'already_member',
      'familyId', v_row."familyId");
  END IF;

  -- Branch on requireApproval.
  IF v_row."requireApproval" THEN
    -- Idempotent: if there's already a pending request, return it.
    SELECT id INTO v_existing_request FROM "GroupJoinRequest"
      WHERE "familyId" = v_row."familyId" AND "requesterUserId" = v_user_id
        AND "status" = 'pending';
    IF v_existing_request IS NOT NULL THEN
      RETURN json_build_object('success', true, 'action', 'request_already_pending',
        'joinRequestId', v_existing_request, 'familyId', v_row."familyId");
    END IF;

    INSERT INTO "GroupJoinRequest" (
      "id", "familyId", "requesterUserId",
      "status", "requestedAt", "viaInviteToken"
    ) VALUES (
      'gjr_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8),
      v_row."familyId", v_user_id,
      'pending', now(), p_token
    )
    RETURNING id INTO v_existing_request;

    -- Bump the use count (a "use" = token presented to a non-member).
    UPDATE "GroupInviteLink"
      SET "useCount" = "useCount" + 1, "updatedAt" = now()
      WHERE "token" = p_token;

    RETURN json_build_object(
      'success', true,
      'action', 'request_submitted',
      'joinRequestId', v_existing_request,
      'familyId', v_row."familyId"
    );
  END IF;

  -- Direct join — insert the family member row.
  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "FamilyMember" (
    "id", "familyId", "userId", "role", "joinedAt"
  ) VALUES (
    v_member_id, v_row."familyId", v_user_id, 'member', now()
  );

  -- Bump the family memberCount.
  UPDATE "Family"
    SET "memberCount" = "memberCount" + 1, "updatedAt" = now(), "lastActivityAt" = now()
    WHERE id = v_row."familyId";

  UPDATE "GroupInviteLink"
    SET "useCount" = "useCount" + 1, "updatedAt" = now()
    WHERE "token" = p_token;

  PERFORM fn_log_group_audit(
    v_row."familyId", v_user_id, 'member_joined',
    v_user_id, NULL, jsonb_build_object('viaInviteToken', p_token)
  );

  RETURN json_build_object(
    'success', true,
    'action', 'joined',
    'familyId', v_row."familyId"
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_join_via_invite_link(text) TO authenticated;

-- Verification
SELECT 'GroupInviteLink' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'GroupInviteLink') AS exists;
SELECT 'fn_create_group_invite_link' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_create_group_invite_link') AS exists;
SELECT 'fn_revoke_group_invite_link' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_revoke_group_invite_link') AS exists;
SELECT 'fn_join_via_invite_link' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_join_via_invite_link') AS exists;
