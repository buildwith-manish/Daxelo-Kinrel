-- =============================================================================
-- Daxelo-Kinrel — fn_create_person_link_invitation
-- =============================================================================
-- Bypasses the NestJS backend (which currently rejects Supabase JWTs due to
-- the ES256/HS256 mismatch) by letting the Flutter client create a
-- PersonLinkInvitation row directly via a SECURITY DEFINER RPC.
--
-- The RPC:
--   1. Validates that the caller is a family member with editor+ role
--   2. Validates that the Person exists in the family and isn't already linked
--   3. Generates a URL-safe invite code (11 chars, like the NestJS version)
--   4. Inserts a PersonLinkInvitation row with 7-day TTL
--   5. Returns the invite code + person details for the share message
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_create_person_link_invitation(
  p_family_id text,
  p_person_id text,
  p_recipient_name text DEFAULT NULL,
  p_recipient_email text DEFAULT NULL,
  p_recipient_phone text DEFAULT NULL,
  p_role text DEFAULT 'member'
)
RETURNS TABLE(
  invitation_code text,
  person_id text,
  person_name text,
  family_id text,
  family_name text,
  expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id text := auth.uid()::text;
  v_member_role text;
  v_person_name text;
  v_family_name text;
  v_code text;
  v_expires_at timestamptz := now() + interval '7 days';
BEGIN
  -- 1. Validate caller is a family member with editor+ role
  SELECT role INTO v_member_role
  FROM "FamilyMember"
  WHERE "familyId" = p_family_id AND "userId" = v_caller_id;

  IF v_member_role IS NULL THEN
    RAISE EXCEPTION 'You are not a member of this family';
  END IF;

  IF v_member_role NOT IN ('editor', 'admin', 'owner') THEN
    RAISE EXCEPTION 'You need editor or higher role to send person invites';
  END IF;

  -- 2. Validate the Person exists in this family and isn't already linked
  SELECT name INTO v_person_name
  FROM "Person"
  WHERE id = p_person_id
    AND "familyId" = p_family_id
    AND "deletedAt" IS NULL;

  IF v_person_name IS NULL THEN
    RAISE EXCEPTION 'Person not found in this family';
  END IF;

  IF EXISTS (
    SELECT 1 FROM "Person" WHERE id = p_person_id AND "linkedUserId" IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'This person is already linked to a Kinrel account';
  END IF;

  -- 3. Validate at least one contact field is provided
  IF (p_recipient_email IS NULL OR p_recipient_email = '')
     AND (p_recipient_phone IS NULL OR p_recipient_phone = '') THEN
    RAISE EXCEPTION 'At least one of email or phone must be provided';
  END IF;

  -- 4. Get the family name for the share message
  SELECT name INTO v_family_name FROM "Family" WHERE id = p_family_id;
  IF v_family_name IS NULL THEN
    v_family_name := 'Family';
  END IF;

  -- 5. Generate a URL-safe invite code (11 chars, matching NestJS's base64url approach)
  v_code := encode(gen_random_bytes(8), 'base64');
  -- Make it URL-safe: replace +/ with -_ and strip = padding
  v_code := replace(replace(v_code, '+', '-'), '/', '_');
  v_code := replace(v_code, '=', '');

  -- 6. Insert the PersonLinkInvitation row
  INSERT INTO "PersonLinkInvitation" (
    "familyId", "personId", "code", "inviterUserId",
    "recipientName", "recipientEmail", "recipientPhone",
    "role", "status", "expiresAt", "createdAt"
  ) VALUES (
    p_family_id, p_person_id, v_code, v_caller_id,
    p_recipient_name, p_recipient_email, p_recipient_phone,
    p_role, 'pending', v_expires_at, now()
  );

  -- 7. Return the invite details
  RETURN QUERY SELECT
    v_code AS invitation_code,
    p_person_id AS person_id,
    v_person_name AS person_name,
    p_family_id AS family_id,
    v_family_name AS family_name,
    v_expires_at AS expires_at;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_create_person_link_invitation(text, text, text, text, text, text) TO authenticated;

COMMENT ON FUNCTION fn_create_person_link_invitation(text, text, text, text, text, text) IS
  'Creates a PersonLinkInvitation row directly via Supabase, bypassing the '
  'NestJS backend (which currently rejects Supabase JWTs). Validates caller '
  'is a family editor+, the Person exists and isn''t already linked, and at '
  'least one contact field (email or phone) is provided. Returns the invite '
  'code + person/family details for building the personalized share message.';
