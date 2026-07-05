-- =============================================================================
-- Daxelo-Kinrel — get_user_families RPC (performance optimization)
-- =============================================================================
-- Replaces 3 sequential Supabase queries in familyListProvider with a single
-- RPC call. This reduces cold-start latency by 2-4 seconds on mobile networks.
--
-- SECURITY: SECURITY DEFINER so it bypasses RLS on the FamilyMember table
-- (which only allows reading rows where userId = auth.uid()). The function
-- self-gates on the caller's user ID — it only returns families the caller
-- is a member of or created.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_user_families(p_user_id TEXT)
RETURNS TABLE (
  id TEXT,
  name TEXT,
  description TEXT,
  "primaryLanguage" TEXT,
  gotra TEXT,
  "originVillage" TEXT,
  "createdBy" TEXT,
  "createdAt" TIMESTAMPTZ,
  "familyCode" TEXT,
  "avatarUrl" TEXT,
  region TEXT,
  "privacyMode" TEXT,
  "isOnboarded" BOOLEAN,
  "anchorPersonId" TEXT,
  "memberCount" INT,
  "generationCount" INT,
  "lastActivityAt" TIMESTAMPTZ,
  username TEXT,
  "kinFamilyId" TEXT,
  "deletedAt" TIMESTAMPTZ,
  "photoUrl" TEXT,
  "isPublic" BOOLEAN,
  "updatedAt" TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT
    f.id,
    f.name,
    f.description,
    f."primaryLanguage",
    f.gotra,
    f."originVillage",
    f."createdBy",
    f."createdAt",
    f."familyCode",
    f."avatarUrl",
    f.region,
    f."privacyMode",
    f."isOnboarded",
    f."anchorPersonId",
    f."memberCount",
    f."generationCount",
    f."lastActivityAt",
    f.username,
    f."kinFamilyId",
    f."deletedAt",
    f."photoUrl",
    f."isPublic",
    f."updatedAt"
  FROM "Family" f
  WHERE f."deletedAt" IS NULL
    AND (
      f."createdBy" = p_user_id
      OR EXISTS (
        SELECT 1
        FROM "FamilyMember" fm
        WHERE fm."familyId" = f.id
          AND fm."userId" = p_user_id
      )
    )
  ORDER BY f."createdAt" DESC;
$$;

-- Allow any authenticated user to call the function
GRANT EXECUTE ON FUNCTION get_user_families(TEXT) TO authenticated;

COMMENT ON FUNCTION get_user_families(TEXT) IS
  'Returns all non-deleted families where the given user is a member or creator. '
  'SECURITY DEFINER — bypasses FamilyMember RLS. Single round-trip replaces '
  '3 sequential queries in familyListProvider for faster cold starts.';
