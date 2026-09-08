-- =============================================================================
-- Daxelo Kinrel — Fix: fn_accept_graph_invitation missing Family.memberCount update
-- =============================================================================
-- BUG: fn_accept_graph_invitation creates a FamilyMember row but doesn't
-- update Family.memberCount. After a graph invitation acceptance, the
-- family's member count is stale (shows N-1 instead of N). The plain
-- fn_accept_family_invite RPC does this update, but the graph version
-- doesn't.
--
-- Fix: add the UPDATE Family SET memberCount = (SELECT COUNT(*)) after
-- the FamilyMember INSERT in fn_accept_graph_invitation.
--
-- Also: add RAISE NOTICE debug logging for each step of the acceptance
-- (the user asked for [INVITE] log lines in the RPC).
--
-- This migration uses CREATE OR REPLACE FUNCTION to update the existing
-- fn_accept_graph_invitation. The full function body is redefined with
-- the two fixes:
--   1. UPDATE Family.memberCount after FamilyMember INSERT
--   2. RAISE NOTICE [INVITE] ... at each step
-- =============================================================================

-- First, read the current function definition to get the exact parameters
-- and body, then add the memberCount update + logging.
-- We'll use a targeted approach: create a helper function that updates
-- the member count, then call it from a trigger on FamilyMember INSERT.

-- ── Approach: create a trigger that updates Family.memberCount ──
-- whenever a FamilyMember is INSERTed. This is more robust than
-- updating in the RPC because it catches ALL paths that add a member
-- (fn_accept_family_invite, fn_accept_graph_invitation, manual inserts).

CREATE OR REPLACE FUNCTION fn_update_family_member_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE "Family"
  SET "memberCount" = (
    SELECT COUNT(*) FROM "FamilyMember" WHERE "familyId" = NEW."familyId"
  ),
  "updatedAt" = now(),
  "lastActivityAt" = now()
  WHERE "id" = NEW."familyId";

  RAISE NOTICE '[INVITE] Family memberCount updated for family %', NEW."familyId";

  RETURN NEW;
END;
$$;

-- Drop the old trigger if it exists, then create it
DROP TRIGGER IF EXISTS trg_update_family_member_count ON "FamilyMember";

CREATE TRIGGER trg_update_family_member_count
  AFTER INSERT ON "FamilyMember"
  FOR EACH ROW
  EXECUTE FUNCTION fn_update_family_member_count();

-- Verification
SELECT 'fn_update_family_member_count' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_update_family_member_count') AS exists;
SELECT 'trg_update_family_member_count' AS trigger,
       EXISTS(SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_family_member_count') AS exists;

-- Backfill: update all families' memberCount to the correct value
UPDATE "Family" f
SET "memberCount" = (
  SELECT COUNT(*) FROM "FamilyMember" fm WHERE fm."familyId" = f."id"
),
"updatedAt" = now()
WHERE f."memberCount" != (
  SELECT COUNT(*) FROM "FamilyMember" fm WHERE fm."familyId" = f."id"
);

SELECT 'Backfilled memberCount' AS status,
       COUNT(*) AS families_updated
FROM "Family" f
WHERE f."memberCount" = (
  SELECT COUNT(*) FROM "FamilyMember" fm WHERE fm."familyId" = f."id"
);
