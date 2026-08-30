-- =============================================================================
-- v5.73: Fix invited member not appearing after accepting invitation
-- =============================================================================
-- ROOT CAUSE: Person.linkedUserId had a GLOBAL unique index
-- (Person_linkedUserId_unique) that prevented a user from having Person
-- nodes in multiple families. When a user accepted an invite to family B
-- but already had a Person in family A, fn_accept_family_invite reused
-- the existing Person's ID (which pointed to family A) instead of
-- creating a new Person in family B. The new family never got its
-- Person node → the member didn't appear on the graph or in the member
-- list.
--
-- FIX:
-- 1. Drop the global unique index Person_linkedUserId_unique.
-- 2. Keep the per-family unique index Person_familyId_linkedUserId_unique
--    (one Person per user PER family — still prevents duplicates within
--    a single family).
-- 3. Update fn_accept_family_invite to only check for existing Person
--    in the ACCEPTING family (not any family), and always create a new
--    Person if none exists in that family.
-- 4. Update fn_accept_family_invite to increment Family.memberCount.
-- =============================================================================

-- Step 1: Drop the global unique index
DROP INDEX IF EXISTS "Person_linkedUserId_unique";

-- Step 2: The per-family unique index already exists:
--   Person_familyId_linkedUserId_unique ON (familyId, linkedUserId)
--   WHERE linkedUserId IS NOT NULL AND deletedAt IS NULL
-- No action needed — it's already correct.

-- Step 3 + 4: The fn_accept_family_invite function is updated in the
-- application code (see the SQL executed via the Supabase Management API).
-- The updated function:
--   - Only checks for existing Person in THIS family (not any family)
--   - Always creates a new Person if none exists in this family
--   - Updates Family.memberCount = COUNT(*) from FamilyMember
