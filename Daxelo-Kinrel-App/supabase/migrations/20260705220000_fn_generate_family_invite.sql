-- =============================================================================
-- Daxelo-Kinrel — fn_generate_family_invite
-- =============================================================================
-- Bypasses the NestJS backend (which currently rejects Supabase JWTs due to
-- the ES256/HS256 mismatch) by letting the Flutter client generate a family
-- invite link directly via a SECURITY DEFINER RPC.
--
-- Creates a FamilyInvite row with a random token, expiry, and max uses.
-- Returns the invite details for the UI to build the share link.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_generate_family_invite(
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

  -- 3. Generate a random token (11 chars, URL-safe)
  v_token := encode(gen_random_bytes(8), 'base64');
  v_token := replace(replace(v_token, '+', '-'), '/', '_');
  v_token := replace(v_token, '=', '');

  -- 4. Calculate expiry
  v_expires_at := now() + (p_expiry_days || ' days')::interval;

  -- 5. Generate invite ID
  v_invite_id := 'inv_' || extract(epoch from now())::bigint::text || '_' || substring(v_token from 1 for 6);

  -- 6. Insert into FamilyInvite table
  INSERT INTO "FamilyInvite" (
    "id", "familyId", "token", "status", "inviteType",
    "maxUses", "currentUses", "useCount",
    "creatorId", "active",
    "expiresAt", "createdAt", "updatedAt"
  ) VALUES (
    v_invite_id, p_family_id, v_token, 'pending', 'family_id',
    p_max_uses, 0, 0,
    v_caller_id, true,
    v_expires_at, now(), now()
  );

  -- 7. Return the invite details
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

GRANT EXECUTE ON FUNCTION fn_generate_family_invite(text, int, int) TO authenticated;

COMMENT ON FUNCTION fn_generate_family_invite(text, int, int) IS
  'Creates a FamilyInvite row directly via Supabase, bypassing the NestJS '
  'backend. Validates caller is a family member. Returns the invite token + '
  'details for building the share link. Token is URL-safe (base64url, 11 chars).';
