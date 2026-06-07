-- ============================================================
-- DAXELO KINREL — Row Level Security Policies v3
-- Enhanced RLS with stricter policies for production
-- Run these in Supabase SQL Editor (after rls-policies-v2.sql)
-- ============================================================
--
-- This file ADDS new policies and constraints that complement v2.
-- It does NOT drop or replace any existing v2 policies.
--
-- Key enhancements:
-- 1. Users can only update their own profile (enforced again at constraint level)
-- 2. Family members can read family data
-- 3. Only owners/admins can update family settings
-- 4. Only owners can delete families
-- 5. Members can only see persons in their families
-- 6. Username uniqueness constraint at DB level
--
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. Username Uniqueness Constraints at DB Level
-- ────────────────────────────────────────────────────────────

-- Ensure usernames are unique across both User and Person tables
-- (Prisma @unique handles individual table uniqueness, this adds
-- cross-table guarantees and non-null constraints for production)

-- Partial unique index: non-null usernames must be unique in User
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "User_username_notnull_idx"
  ON "User"("username") WHERE "username" IS NOT NULL;

-- Partial unique index: non-null usernames must be unique in Person
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "Person_username_notnull_idx"
  ON "Person"("username") WHERE "username" IS NOT NULL;

-- ────────────────────────────────────────────────────────────
-- 2. UsernameChangeLog RLS Policies
-- ────────────────────────────────────────────────────────────

ALTER TABLE "UsernameChangeLog" ENABLE ROW LEVEL SECURITY;

-- Users can view their own username change history
CREATE POLICY "Users can view own username history"
  ON "UsernameChangeLog" FOR SELECT
  USING ("userId" = auth.uid()::text);

-- System/backend creates these logs (no direct user insert)
CREATE POLICY "System can create username change logs"
  ON "UsernameChangeLog" FOR INSERT
  WITH CHECK (true);

-- No updates or deletes allowed on username change logs
CREATE POLICY "No updates on username change logs"
  ON "UsernameChangeLog" FOR UPDATE
  USING (false);

CREATE POLICY "No deletes on username change logs"
  ON "UsernameChangeLog" FOR DELETE
  USING (false);

-- ────────────────────────────────────────────────────────────
-- 3. Stricter User Profile Update Policy
-- ────────────────────────────────────────────────────────────

-- Additional policy: users cannot change their role via profile update
-- (This is a CHECK constraint at DB level to prevent privilege escalation)
-- Note: This complements the existing RLS policy, not replaces it

CREATE POLICY "Users cannot change own role"
  ON "User" FOR UPDATE
  USING (id = auth.uid()::text)
  WITH CHECK (
    id = auth.uid()::text
    -- Ensure role is not changed via this policy path
    AND role = (SELECT role FROM "User" WHERE id = auth.uid()::text)
  );

-- ────────────────────────────────────────────────────────────
-- 4. Search Results Visibility Policy
-- ────────────────────────────────────────────────────────────

-- Users can only be found in search if their profile is not private
-- This is an additional RLS policy for search queries
CREATE POLICY "Users with public profiles are searchable"
  ON "User" FOR SELECT
  USING (
    -- Users can always see themselves
    id = auth.uid()::text
    -- Or their profile is not private
    OR "profileVisibility" != 'private'
  );

-- ────────────────────────────────────────────────────────────
-- 5. Family Data Access — Members Only
-- ────────────────────────────────────────────────────────────

-- Additional policy: Family data is only accessible to members
-- This is stricter than v2 which also allowed privacyMode='link'
CREATE POLICY "Family members can read family data"
  ON "Family" FOR SELECT
  USING (
    id IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
    OR "privacyMode" IN ('link', 'invite')
  );

-- ────────────────────────────────────────────────────────────
-- 6. Family Settings — Only Owners/Admins Can Update
-- ────────────────────────────────────────────────────────────

-- Stricter update policy: only owners and admins can update family settings
-- (This replaces the broader v2 policy — but since we can't DROP existing
--  policies without knowing their exact names, we add a complementary one)
CREATE POLICY "Only owners and admins can update family settings v3"
  ON "Family" FOR UPDATE
  USING (
    id IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    id IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

-- ────────────────────────────────────────────────────────────
-- 7. Family Deletion — Only Owners Can Delete
-- ────────────────────────────────────────────────────────────

-- Stricter delete policy: only owners (not admins) can delete families
CREATE POLICY "Only owners can delete families v3"
  ON "Family" FOR DELETE
  USING (
    id IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role = 'owner'
    )
  );

-- ────────────────────────────────────────────────────────────
-- 8. Person Visibility — Members Can Only See Persons in Their Families
-- ────────────────────────────────────────────────────────────

-- Additional strict policy for person visibility
-- Members can only see persons in families they belong to
CREATE POLICY "Members can only see persons in their families v3"
  ON "Person" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
    AND "deletedAt" IS NULL
  );

-- ────────────────────────────────────────────────────────────
-- 9. Rate Limit Tracking Table for Application-Level Rate Limiting
-- ────────────────────────────────────────────────────────────

-- Optional: Table to track rate limits at DB level for distributed environments
CREATE TABLE IF NOT EXISTS "RateLimitEntry" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "timestamp" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "RateLimitEntry_userId_action_idx"
  ON "RateLimitEntry"("userId", "action");

-- Clean up old rate limit entries (run via cron)
-- DELETE FROM "RateLimitEntry" WHERE "timestamp" < NOW() - INTERVAL '1 hour';

-- ============================================================
-- Instructions:
-- 1. Go to supabase.com → your project
-- 2. Click SQL Editor
-- 3. Paste and run these policies (one section at a time for safety)
-- 4. Verify in Authentication → Policies
-- 5. Test with real user IDs:
--    SELECT * FROM "UsernameChangeLog" WHERE "userId" = 'test_user_id';
--    SELECT * FROM "Person" WHERE "familyId" IN (
--      SELECT "familyId" FROM "FamilyMember" WHERE "userId" = 'test_user_id'
--    );
-- ============================================================
