-- ============================================================
-- Migration: kinrel_v5_master_fix_section_3_4_5_rls
-- Version:  20260611145647
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- SECTION 3: Enable RLS
ALTER TABLE "Family"       ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Person"       ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Relationship" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "FamilyMember" ENABLE ROW LEVEL SECURITY;

-- SECTION 4: Drop ALL old conflicting policies
DROP POLICY IF EXISTS "Users can view their families"                    ON "Family";
DROP POLICY IF EXISTS "Users see own families"                           ON "Family";
DROP POLICY IF EXISTS "Authenticated users can create families"          ON "Family";
DROP POLICY IF EXISTS "Users create families"                            ON "Family";
DROP POLICY IF EXISTS "Creators can update families"                     ON "Family";
DROP POLICY IF EXISTS "Creators can update their families"               ON "Family";
DROP POLICY IF EXISTS "Creators can view their families"                 ON "Family";
DROP POLICY IF EXISTS "Family members can read family data"              ON "Family";
DROP POLICY IF EXISTS "Only owners can delete families"                  ON "Family";
DROP POLICY IF EXISTS "Only owners can delete families v3"               ON "Family";
DROP POLICY IF EXISTS "Only owners and admins can update family settings v3" ON "Family";
DROP POLICY IF EXISTS "Owners and admins can update families"            ON "Family";
DROP POLICY IF EXISTS "family_select"                                    ON "Family";
DROP POLICY IF EXISTS "family_insert"                                    ON "Family";
DROP POLICY IF EXISTS "family_update"                                    ON "Family";
DROP POLICY IF EXISTS "family_delete"                                    ON "Family";

DROP POLICY IF EXISTS "Users can view family members"                    ON "FamilyMember";
DROP POLICY IF EXISTS "Family members see own family"                    ON "FamilyMember";
DROP POLICY IF EXISTS "Owners and admins can add family members"         ON "FamilyMember";
DROP POLICY IF EXISTS "Owners admins and creators can add family members" ON "FamilyMember";
DROP POLICY IF EXISTS "Owners and admins can update family member roles" ON "FamilyMember";
DROP POLICY IF EXISTS "Owners can remove family members"                 ON "FamilyMember";
DROP POLICY IF EXISTS "Users can join families"                          ON "FamilyMember";
DROP POLICY IF EXISTS "Creators can view family members"                 ON "FamilyMember";
DROP POLICY IF EXISTS "family_member_select"                             ON "FamilyMember";
DROP POLICY IF EXISTS "family_member_insert"                             ON "FamilyMember";
DROP POLICY IF EXISTS "family_member_update"                             ON "FamilyMember";
DROP POLICY IF EXISTS "family_member_delete"                             ON "FamilyMember";

DROP POLICY IF EXISTS "Users can view family persons"                    ON "Person";
DROP POLICY IF EXISTS "Users can view persons in their families"         ON "Person";
DROP POLICY IF EXISTS "Members can only see persons in their families v3" ON "Person";
DROP POLICY IF EXISTS "Users can insert family persons"                  ON "Person";
DROP POLICY IF EXISTS "Members and above can create persons"             ON "Person";
DROP POLICY IF EXISTS "Creators can create persons in their families"    ON "Person";
DROP POLICY IF EXISTS "Creators can view persons in their families"      ON "Person";
DROP POLICY IF EXISTS "Creators can update persons in their families"    ON "Person";
DROP POLICY IF EXISTS "Users can update family persons"                  ON "Person";
DROP POLICY IF EXISTS "Users can update persons in their families"       ON "Person";
DROP POLICY IF EXISTS "Admins and above can soft-delete persons"         ON "Person";
DROP POLICY IF EXISTS "person_select"                                    ON "Person";
DROP POLICY IF EXISTS "person_insert"                                    ON "Person";
DROP POLICY IF EXISTS "person_update"                                    ON "Person";
DROP POLICY IF EXISTS "person_delete"                                    ON "Person";

DROP POLICY IF EXISTS "Users can view family relationships"              ON "Relationship";
DROP POLICY IF EXISTS "Users can view relationships in their families"   ON "Relationship";
DROP POLICY IF EXISTS "Family relationships are private"                 ON "Relationship";
DROP POLICY IF EXISTS "Users can insert family relationships"            ON "Relationship";
DROP POLICY IF EXISTS "Admins can create relationships"                  ON "Relationship";
DROP POLICY IF EXISTS "Creators can create relationships in their families" ON "Relationship";
DROP POLICY IF EXISTS "Creators can view relationships in their families" ON "Relationship";
DROP POLICY IF EXISTS "Admins can update relationships"                  ON "Relationship";
DROP POLICY IF EXISTS "Admins can delete relationships"                  ON "Relationship";
DROP POLICY IF EXISTS "relationship_select"                              ON "Relationship";
DROP POLICY IF EXISTS "relationship_insert"                              ON "Relationship";
DROP POLICY IF EXISTS "relationship_update"                              ON "Relationship";
DROP POLICY IF EXISTS "relationship_delete"                              ON "Relationship";

-- SECTION 5: Clean consolidated RLS policies

-- 5a. Family
CREATE POLICY "family_select"
  ON "Family" FOR SELECT
  USING (
    "id" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
    OR "createdBy" = auth.uid()::text
    OR "privacyMode" IN ('link', 'invite')
  );

CREATE POLICY "family_insert"
  ON "Family" FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "family_update"
  ON "Family" FOR UPDATE
  USING (
    "createdBy" = auth.uid()::text
    OR "id" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    "createdBy" = auth.uid()::text
    OR "id" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
  );

CREATE POLICY "family_delete"
  ON "Family" FOR DELETE
  USING (
    "createdBy" = auth.uid()::text
    OR "id" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" = 'owner'
    )
  );

-- 5b. FamilyMember
CREATE POLICY "family_member_select"
  ON "FamilyMember" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

CREATE POLICY "family_member_insert"
  ON "FamilyMember" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

CREATE POLICY "family_member_update"
  ON "FamilyMember" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
  );

CREATE POLICY "family_member_delete"
  ON "FamilyMember" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
    AND NOT (
      "userId" = auth.uid()::text
      AND "role" IN ('owner', 'admin')
    )
  );

-- 5c. Person
CREATE POLICY "person_select"
  ON "Person" FOR SELECT
  USING (
    (
      "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
      )
      OR "familyId" IN (
        SELECT "id" FROM "Family"
        WHERE "createdBy" = auth.uid()::text
      )
    )
    AND (
      "deletedAt" IS NULL
      OR "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
          AND "role" IN ('owner', 'admin')
      )
      OR "familyId" IN (
        SELECT "id" FROM "Family"
        WHERE "createdBy" = auth.uid()::text
      )
    )
  );

CREATE POLICY "person_insert"
  ON "Person" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin', 'member')
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

CREATE POLICY "person_update"
  ON "Person" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin', 'member')
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  )
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin', 'member')
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

CREATE POLICY "person_delete"
  ON "Person" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

-- 5d. Relationship
CREATE POLICY "relationship_select"
  ON "Relationship" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

CREATE POLICY "relationship_insert"
  ON "Relationship" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin', 'member')
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

CREATE POLICY "relationship_update"
  ON "Relationship" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  )
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );

CREATE POLICY "relationship_delete"
  ON "Relationship" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND "role" IN ('owner', 'admin')
    )
    OR "familyId" IN (
      SELECT "id" FROM "Family"
      WHERE "createdBy" = auth.uid()::text
    )
  );
