-- =============================================================================
-- v5.79: Backfill — link family creators' anchor Person records to their auth ID
-- =============================================================================
-- ROOT CAUSE: When families were created through the older family-creation
-- flow, the anchor Person's linkedUserId was NOT set to the creator's auth
-- user ID. This caused the viewer-relative perspective to fail — the graph
-- showed "Auth User ID: NULL" / "Viewer Person ID: NULL" because the
-- viewerPersonIdProvider couldn't find a Person linked to the current user.
--
-- This backfill links every family's anchor Person (isAnchor=true,
-- linkedUserId=NULL) to the family creator's auth user ID (Family.createdBy).
-- This is safe because:
--   1. The family creator IS definitionally the anchor person in families
--      they created themselves.
--   2. The global unique index on Person.linkedUserId was dropped in v5.73,
--      so a user can have Person nodes in multiple families.
--   3. The per-family unique index (familyId, linkedUserId) is not violated
--      because each family has exactly one anchor, and we're only setting
--      linkedUserId for anchors that are currently NULL.
--
-- Non-anchor Persons (e.g. JD, hdhd — manually-added family members who
-- are not real Kinrel app users) are NOT touched — their linkedUserId
-- stays NULL, which is correct (no one will ever log in as them).
-- =============================================================================

UPDATE "Person" p
SET "linkedUserId" = f."createdBy"::uuid,
    "linkedAt" = now(),
    "updatedAt" = now()
FROM "Family" f
WHERE p."familyId" = f.id
  AND p."isAnchor" = true
  AND p."linkedUserId" IS NULL
  AND p."deletedAt" IS NULL
  AND f."createdBy" IS NOT NULL
  AND f."createdBy" != '';
