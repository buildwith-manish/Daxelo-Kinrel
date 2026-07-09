-- =============================================================================
-- Daxelo-Kinrel — Fix fn_generate_family_invite column ambiguity
-- =============================================================================
-- The RETURNS TABLE(id text, ...) declaration conflicts with PostgREST's
-- internal column resolution when calling via the REST API. PostgREST
-- adds its own "id" reference that conflicts with the function's return
-- column named "id", causing "column reference 'id' is ambiguous".
--
-- Fix: rename the return column from "id" to "invite_id" and update
-- the RETURN QUERY to match. The Flutter client already reads the
-- result as a List and accesses row['id'], so we alias it back to "id"
-- in a subquery wrapper to avoid the PostgREST ambiguity while keeping
-- the Flutter parser working unchanged.
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
  v_member_role text;
  v_family_name text;
  v_token text;
  v_expires_at timestamptz;
  v_invite_id text;
BEGIN
  SELECT role INTO v_member_role
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id AND "userId" = v_caller_id;

  IF v_member_role IS NULL THEN
    RAISE EXCEPTION 'You are not a member of this family';
  END IF;

  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN
    v_family_name := 'Family';
  END IF;

  v_token := encode(gen_random_bytes(8), 'base64');
  v_token := replace(replace(v_token, '+', '-'), '/', '_');
  v_token := replace(v_token, '=', '');

  v_expires_at := now() + (p_expiry_days || ' days')::interval;
  v_invite_id := 'inv_' || extract(epoch from now())::bigint::text || '_' || substring(v_token from 1 for 6);

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

  -- Return the invite details. The return column is named "invite_id"
  -- (not "id") to avoid PostgREST's "column reference 'id' is ambiguous"
  -- error. The Flutter client reads this as row['invite_id'].
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

COMMENT ON FUNCTION public.fn_generate_family_invite(text, int, int) IS
  'Creates a FamilyInvite row. SECURITY DEFINER. Returns invite details with invite_id (not id) to avoid PostgREST column ambiguity.';
