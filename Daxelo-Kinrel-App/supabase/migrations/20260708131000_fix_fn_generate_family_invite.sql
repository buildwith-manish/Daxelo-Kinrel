-- =============================================================================
-- Daxelo-Kinrel — fix fn_generate_family_invite (Screenshot Bug A)
-- =============================================================================
-- The original fn_generate_family_invite (migration 20260705220000) was
-- broken because its INSERT statement referenced columns that don't exist
-- on the "FamilyInvite" table:
--
--   1. INSERT into "token" — no such column. The actual column is "inviteCode".
--   2. INSERT into "updatedAt" — no such column. The table has no updatedAt.
--   3. Missing NOT NULL column "invitedBy" — the INSERT failed the NOT NULL
--      constraint because invitedBy was never supplied.
--
-- Result: every call to fn_generate_family_invite raised an exception,
-- Flutter caught it and showed "Failed to generate invite" (Screenshot Bug A).
--
-- This migration drops and recreates the function with the correct column
-- names and supplies the missing NOT NULL "invitedBy" value (set to the
-- caller's auth.uid). The return shape is unchanged so the Flutter client
-- and the FamilyInviteModel parser don't need any changes.
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_generate_family_invite(text, int, int);

CREATE OR REPLACE FUNCTION public.fn_generate_family_invite(
  p_family_id text,
  p_expiry_days int DEFAULT 7,
  p_max_uses int DEFAULT 0
)
RETURNS TABLE(
  id text,
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
  v_member_role text;
  v_family_name text;
  v_token text;
  v_expires_at timestamptz;
  v_invite_id text;
BEGIN
  -- 1. Validate caller is a family member
  SELECT role INTO v_member_role
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id AND "userId" = v_caller_id;

  IF v_member_role IS NULL THEN
    RAISE EXCEPTION 'You are not a member of this family';
  END IF;

  -- 2. Get the family name
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN
    v_family_name := 'Family';
  END IF;

  -- 3. Generate a random token (URL-safe base64url, ~11 chars)
  v_token := encode(gen_random_bytes(8), 'base64');
  v_token := replace(replace(v_token, '+', '-'), '/', '_');
  v_token := replace(v_token, '=', '');

  -- 4. Calculate expiry
  v_expires_at := now() + (p_expiry_days || ' days')::interval;

  -- 5. Generate invite ID
  v_invite_id := 'inv_' || extract(epoch from now())::bigint::text || '_' || substring(v_token from 1 for 6);

  -- 6. Insert into FamilyInvite with the CORRECT column names:
  --    - "inviteCode" (NOT "token" — the column was misnamed in the old RPC)
  --    - "invitedBy"  (NOT NULL — must be supplied; set to the caller)
  --    - no "updatedAt" (the table has no such column)
  INSERT INTO "FamilyInvite" (
    "id", "familyId", "inviteCode", "invitedBy",
    "status", "inviteType",
    "maxUses", "currentUses", "useCount",
    "creatorId", "active",
    "expiresAt", "createdAt"
  ) VALUES (
    v_invite_id, p_family_id, v_token, v_caller_id,
    'pending', 'link',
    p_max_uses, 0, 0,
    v_caller_id, true,
    v_expires_at, now()
  );

  -- 7. Return the invite details (shape unchanged from the original RPC
  --    so the Flutter FamilyInviteModel.fromJson parser keeps working).
  RETURN QUERY SELECT
    v_invite_id AS id,
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

COMMENT ON FUNCTION public.fn_generate_family_invite(text, int, int) IS
  'Creates a FamilyInvite row directly via Supabase, bypassing the NestJS '
  'backend. Validates caller is a family member. Returns the invite token + '
  'details for building the share link. Token is URL-safe (base64url, ~11 chars). '
  'Fixed in 20260708130000 to use the correct column names (inviteCode instead '
  'of token, supply NOT NULL invitedBy, drop non-existent updatedAt).';
