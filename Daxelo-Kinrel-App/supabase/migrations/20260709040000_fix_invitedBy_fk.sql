-- =============================================================================
-- Daxelo-Kinrel — Fix fn_generate_family_invite: invitedBy FK violation
-- =============================================================================
-- The FamilyInvite.invitedBy column has a FK to FamilyMember(id), NOT
-- User(id). The function was setting invitedBy = auth.uid() (the auth
-- user ID), which violates the FK constraint because auth.uid() is not
-- a FamilyMember row ID.
--
-- Fix: look up the caller's FamilyMember row ID for this family and
-- use that as invitedBy. Also use it for creatorId (which is nullable
-- and has no FK, but should be the auth user ID for tracking).
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_generate_family_invite(text, int, int);

CREATE OR REPLACE FUNCTION public.fn_generate_family_invite(
  p_family_id text,
  p_expiry_days int DEFAULT 7,
  p_max_uses int DEFAULT 0
)
RETURNS TABLE(
  invite_id text,
  token text,
  family_id text,
  family_name text,
  status text,
  expiry_days int,
  max_uses int,
  current_uses int,
  expires_at timestamptz,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id text := auth.uid()::text;
  v_member_id text;
  v_member_role text;
  v_family_name text;
  v_token text;
  v_expires_at timestamptz;
  v_invite_id text;
BEGIN
  -- 1. Validate caller is a family member AND get their FamilyMember.id
  --    (the invitedBy FK references FamilyMember.id, NOT User.id)
  SELECT id, role INTO v_member_id, v_member_role
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id AND "userId" = v_caller_id;

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'You are not a member of this family';
  END IF;

  -- 2. Get the family name
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN
    v_family_name := 'Family';
  END IF;

  -- 3. Generate a random token using gen_random_uuid() (built-in)
  v_token := replace(gen_random_uuid()::text, '-', '');
  v_token := substring(v_token from 1 for 11);

  -- 4. Calculate expiry
  v_expires_at := now() + (p_expiry_days || ' days')::interval;

  -- 5. Generate invite ID
  v_invite_id := 'inv_' || extract(epoch from now())::bigint::text || '_' || v_token;

  -- 6. Insert into FamilyInvite — invitedBy = FamilyMember.id (NOT User.id)
  INSERT INTO "FamilyInvite" (
    "id", "familyId", "inviteCode", "invitedBy",
    "status", "inviteType",
    "maxUses", "currentUses", "useCount",
    "creatorId", "active",
    "expiresAt", "createdAt"
  ) VALUES (
    v_invite_id, p_family_id, v_token, v_member_id,
    'pending', 'link',
    p_max_uses, 0, 0,
    v_caller_id, true,
    v_expires_at, now()
  );

  -- 7. Return the invite details
  RETURN QUERY SELECT
    v_invite_id AS invite_id,
    v_token AS token,
    p_family_id AS family_id,
    v_family_name AS family_name,
    'pending' AS status,
    p_expiry_days AS expiry_days,
    p_max_uses AS max_uses,
    0 AS current_uses,
    v_expires_at AS expires_at,
    now() AS created_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_generate_family_invite(text, int, int) TO authenticated;
