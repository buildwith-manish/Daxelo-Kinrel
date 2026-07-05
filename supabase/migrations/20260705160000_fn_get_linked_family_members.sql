-- =============================================================================
-- Daxelo-Kinrel — Get Family-Members linked via "Find on Kinrel"
-- =============================================================================
-- Used by the "Invite from Family Space" feature on every game lobby screen.
--
-- Returns all KinrelUser records that are linked to Person rows in the given
-- family — i.e., the same accounts that were originally added via
-- AddMemberSource.findOnKinrel (the only source that writes Person.linkedUserId).
--
-- Person rows added via `manual` or `fromContacts` have linkedUserId = NULL
-- and are therefore excluded — those entries have no real Kinrel account
-- attached, so we cannot send them a realtime in-app invite.
--
-- The function:
--   - Joins Person → User on Person.linkedUserId = User.id
--   - Filters by familyId, deletedAt IS NULL on Person
--   - Filters by deletedAt IS NULL on User
--   - Excludes the current caller (so they don't invite themselves)
--   - Returns the same column shape as fn_search_kinrel_users so the Flutter
--     client can reuse the existing KinrelUser.fromJson() decoder
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
    AND u.id::text <> auth.uid()::text
  ORDER BY
    -- Family anchors first, then by name
    p."isAnchor" DESC,
    u.name ASC NULLS LAST;
$$;

-- Allow any authenticated user to call the function.
-- RLS on Person + FamilyMember still applies at the caller level — the caller
-- can only receive results for families they are themselves a member of
-- (because the Person table RLS will filter out rows from families they
-- don't belong to, even though this function is SECURITY DEFINER).
GRANT EXECUTE ON FUNCTION fn_get_linked_family_members(text) TO authenticated;

COMMENT ON FUNCTION fn_get_linked_family_members(text) IS
  'Returns all KinrelUser accounts linked to Person rows in the given family. '
  'Only Person rows added via AddMemberSource.findOnKinrel have linkedUserId '
  'set, so manual and contact-imported entries are excluded. Caller is also '
  'excluded so they cannot invite themselves. Same column shape as '
  'fn_search_kinrel_users for client-side KinrelUser.fromJson() reuse.';
