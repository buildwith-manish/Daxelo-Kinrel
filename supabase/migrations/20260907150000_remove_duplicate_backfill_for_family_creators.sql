-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260907150000_remove_duplicate_backfill_for_family_creators
--
-- PURPOSE
-- The v5.178 backfill (migration 20260907140000) created Person nodes for
-- all FamilyMembers who didn't have a linkedUserId in their family.
-- However, this incorrectly created DUPLICATE Person nodes for family
-- CREATORS — the v5.177 trigger already created their anchor Person
-- (with linkedUserId=NULL if the user is linked elsewhere).
--
-- The duplicate caused the viewer to resolve to the backfilled node
-- (wrong name, wrong ID) instead of the anchor, breaking the graph:
--   - "Unable to load graph" / AccessIssueGraph error
--   - Only 1 node visible instead of the full family
--   - Wrong name shown (backfilled name vs. anchor name)
--
-- FIX
-- 1. Delete all backfilled Person nodes where the user is the family
--    creator (they already have an anchor Person).
-- 2. For backfilled nodes where the user is NOT the creator (accepted
--    an invitation), keep them — those are legitimate.
-- 3. Update Family.memberCount to reflect actual Person count.
-- ════════════════════════════════════════════════════════════════════

-- ── Step 1: Delete backfilled Person nodes where the user is the family creator ──
-- These are duplicates — the v5.177 trigger already created the creator's
-- anchor Person (with linkedUserId=NULL if they're linked elsewhere).
DELETE FROM "Person"
WHERE id LIKE 'person_backfill_%'
  AND "linkedUserId" IN (
    SELECT f."createdBy"::uuid
    FROM "Family" f
    WHERE f."createdBy"::uuid = "Person"."linkedUserId"
      AND f.id = "Person"."familyId"
  );

-- ── Step 2: Update Family.memberCount to reflect actual Person count ──
UPDATE "Family" f
SET "memberCount" = (
    SELECT count(*) FROM "Person"
    WHERE "familyId" = f.id AND "deletedAt" IS NULL
  ),
  "updatedAt" = now()
WHERE f."memberCount" != (
    SELECT count(*) FROM "Person"
    WHERE "familyId" = f.id AND "deletedAt" IS NULL
  );

-- ── Verification ──
DO $$
DECLARE
  v_deleted_count int;
  v_remaining_backfills int;
BEGIN
  -- Count remaining backfill nodes (these are for accepted invitations,
  -- not family creators — they're legitimate)
  SELECT count(*) INTO v_remaining_backfills
  FROM "Person" WHERE id LIKE 'person_backfill_%';

  RAISE NOTICE 'Remaining backfill Person nodes (accepted invitations): %', v_remaining_backfills;
  RAISE NOTICE 'Duplicate creator backfills have been deleted';
END;
$$;
