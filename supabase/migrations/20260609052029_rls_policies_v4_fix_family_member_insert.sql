-- ============================================================
-- Migration: rls_policies_v4_fix_family_member_insert
-- Version:  20260609052029
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Drop old restrictive FamilyMember INSERT policy
DROP POLICY IF EXISTS "Owners and admins can add family members" ON "FamilyMember";
DROP POLICY IF EXISTS "Users can join families" ON "FamilyMember";

-- 1. FamilyMember INSERT — allows creators OR existing owners/admins
CREATE POLICY "Owners admins and creators can add family members"
  ON "FamilyMember" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
    OR
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
    OR auth.uid() IS NOT NULL -- allow self-join via invite
  );

-- 2. Family SELECT — creators can see their own families
DROP POLICY IF EXISTS "Creators can view their families" ON "Family";
CREATE POLICY "Creators can view their families"
  ON "Family" FOR SELECT
  USING ("createdBy" = auth.uid()::text);

-- 3. Family UPDATE — creators can update (covers anchorPersonId set after Person insert)
DROP POLICY IF EXISTS "Creators can update their families" ON "Family";
CREATE POLICY "Creators can update their families"
  ON "Family" FOR UPDATE
  USING ("createdBy" = auth.uid()::text)
  WITH CHECK ("createdBy" = auth.uid()::text);

-- 4. FamilyMember SELECT — creators can see members of families they created
DROP POLICY IF EXISTS "Creators can view family members" ON "FamilyMember";
CREATE POLICY "Creators can view family members"
  ON "FamilyMember" FOR SELECT
  USING (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- 5. Person INSERT — creators can add persons (covers anchor person creation)
DROP POLICY IF EXISTS "Creators can create persons in their families" ON "Person";
CREATE POLICY "Creators can create persons in their families"
  ON "Person" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- 6. Person SELECT — creators can view persons
DROP POLICY IF EXISTS "Creators can view persons in their families" ON "Person";
CREATE POLICY "Creators can view persons in their families"
  ON "Person" FOR SELECT
  USING (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- 7. Person UPDATE — creators can update persons
DROP POLICY IF EXISTS "Creators can update persons in their families" ON "Person";
CREATE POLICY "Creators can update persons in their families"
  ON "Person" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- 8. Relationship INSERT — creators can add relationships
DROP POLICY IF EXISTS "Creators can create relationships in their families" ON "Relationship";
CREATE POLICY "Creators can create relationships in their families"
  ON "Relationship" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- 9. Relationship SELECT — creators can view relationships
DROP POLICY IF EXISTS "Creators can view relationships in their families" ON "Relationship";
CREATE POLICY "Creators can view relationships in their families"
  ON "Relationship" FOR SELECT
  USING (
    "familyId" IN (
      SELECT id FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
