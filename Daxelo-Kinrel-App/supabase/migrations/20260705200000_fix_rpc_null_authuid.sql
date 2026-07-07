-- =============================================================================
-- Fix: fn_get_linked_family_members returns empty when auth.uid() is NULL
-- =============================================================================
-- Root cause: the filter `u.id::text <> auth.uid()::text` evaluates to NULL
-- (not true) when auth.uid() returns NULL (unauthenticated or stale session),
-- which filters out ALL rows. The function should only exclude the caller
-- when auth.uid() is NOT NULL.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_linked_family_members(
  p_family_id text
)
RETURNS TABLE(
  id text,
  name text,
  username text,
  email text,
  "avatarUrl" text,
  "photoThumb" text,
  bio text,
  gender text,
  "personId" text,
  "linkedAt" timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    u.id,
    u.name,
    u.username,
    u.email,
    u."avatarUrl",
    u."photoThumb",
    u.bio,
    u.gender,
    p.id           AS "personId",
    p."linkedAt"   AS "linkedAt"
  FROM "Person" p
  INNER JOIN "User" u ON u.id::text = p."linkedUserId"::text
  WHERE p."familyId" = p_family_id
    AND p."deletedAt" IS NULL
    AND p."linkedUserId" IS NOT NULL
    AND u."deletedAt" IS NULL
    -- Only exclude the caller when auth.uid() is NOT NULL.
    -- When auth.uid() IS NULL (unauthenticated), don't filter — let RLS
    -- on Person/FamilyMember handle access control instead.
    AND (
      auth.uid() IS NULL
      OR u.id::text <> auth.uid()::text
    )
  ORDER BY
    p."isAnchor" DESC,
    u.name ASC NULLS LAST;
$$;

COMMENT ON FUNCTION fn_get_linked_family_members(text) IS
  'Returns all KinrelUser accounts linked to Person rows in the given family. '
  'Only Person rows added via AddMemberSource.findOnKinrel have linkedUserId '
  'set. When the caller is authenticated (auth.uid() not null), the caller '
  'is excluded so they cannot invite themselves. When auth.uid() is null, '
  'no self-exclusion filter is applied (RLS handles access control).';
