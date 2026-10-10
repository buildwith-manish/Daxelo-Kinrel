-- =============================================================================
-- DM Privacy Proof — run these queries as three different users to verify
-- that a third family member CANNOT see a direct chat between two others.
-- =============================================================================
-- Prerequisites:
--   1. Apply the C1 migration (20261101120000_dm_rebuild_direct_groups.sql).
--   2. Create two users (User A, User B) in the same family.
--   3. Create a third user (User C) in the same family.
--   4. User A calls fn_get_or_create_direct_group(User B's id, family id).
--   5. User A sends a message to the direct group.
--
-- Then run these queries:
-- =============================================================================

-- ── As User A (one of the DM participants) ─────────────────────────────────
-- Should see the direct group + its messages.
SELECT 'User A sees the direct group' AS test,
       count(*) AS direct_groups_visible
FROM "Family" f
JOIN "FamilyMember" fm ON fm."familyId" = f.id
WHERE f."groupType" = 'direct' AND fm."userId" = auth.uid()::text;

-- Should see the message in the direct group.
SELECT 'User A sees direct messages' AS test,
       count(*) AS messages_visible
FROM "ChatMessage" cm
JOIN "FamilyMember" fm ON fm."familyId" = cm."familyId"
WHERE fm."userId" = auth.uid()::text
  AND cm."familyId" IN (
    SELECT f.id FROM "Family" f WHERE f."groupType" = 'direct'
  );

-- ── As User C (a third family member) ─────────────────────────────────────
-- Should NOT see the direct group between A and B.
SELECT 'User C cannot see the direct group' AS test,
       count(*) AS direct_groups_visible
FROM "Family" f
JOIN "FamilyMember" fm ON fm."familyId" = f.id
WHERE f."groupType" = 'direct' AND fm."userId" = auth.uid()::text;
-- Expected: 0 (User C is not a member of the direct group)

-- Should NOT see any messages from the direct group.
SELECT 'User C cannot see direct messages' AS test,
       count(*) AS messages_visible
FROM "ChatMessage" cm
WHERE cm."familyId" IN (
    SELECT f.id FROM "Family" f WHERE f."groupType" = 'direct'
  )
  AND cm."familyId" NOT IN (
    SELECT fm."familyId" FROM "FamilyMember" fm WHERE fm."userId" = auth.uid()::text
  );
-- Expected: 0 (RLS blocks User C from reading direct-group messages)
