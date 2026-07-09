-- =============================================================================
-- Daxelo-Kinrel — Fix fn_generate_family_invite: gen_random_bytes not found
-- =============================================================================
-- The function uses SET search_path = public which prevents PostgreSQL
-- from finding gen_random_bytes() (located in pgcrypto, which is in the
-- extensions schema or pg_catalog). The restricted search_path hides it.
--
-- Fix: replace gen_random_bytes(8) with gen_random_uuid() which is
-- built-in (no extension needed, available in all schemas). This
-- generates a 36-char UUID, we take the first 11 chars after removing
-- hyphens to get a compact URL-safe token.
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

  -- Generate a random token using gen_random_uuid() (built-in, no
  -- extension needed, works with restricted search_path). Take the
  -- first 11 hex chars after removing hyphens for a compact token.
  v_token := replace(gen_random_uuid()::text, '-', '');
  v_token := substring(v_token from 1 for 11);

  v_expires_at := now() + (p_expiry_days || ' days')::interval;
  v_invite_id := 'inv_' || extract(epoch from now())::bigint::text || '_' || v_token;

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
