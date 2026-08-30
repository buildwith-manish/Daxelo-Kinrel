-- 20260816030000_relationship_rls_permissions.sql
--
-- v5.12: Enforce relationship-creation permissions at the DB level.
--
-- RULES:
--   - Admins/owners can INSERT any relationship in their family
--   - Regular members can only INSERT relationships where their linked
--     Person ID matches fromPersonId or toPersonId
--
-- This is the SERVER-SIDE enforcement. The client-side check in
-- relationship_permissions.dart is a UX nicety (hiding buttons) —
-- the real security is here in RLS.

-- First, check if RLS is enabled on the Relationship table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE tablename = 'Relationship' AND rowsecurity = true
    ) THEN
        ALTER TABLE "Relationship" ENABLE ROW LEVEL SECURITY;
        RAISE NOTICE 'RLS enabled on Relationship table';
    END IF;
END $$;

-- Drop existing INSERT policies (if any) to avoid duplicates
DROP POLICY IF EXISTS "relationship_insert_policy" ON "Relationship";
DROP POLICY IF EXISTS "relationship_insert_admin_or_self" ON "Relationship";
DROP POLICY IF EXISTS "Relationship_insert_admin_or_self" ON "Relationship";

-- Create the new INSERT policy
-- Allows INSERT if:
--   1. The user is an admin/owner of the family (via FamilyMember table)
--   2. OR the user's linked Person ID matches fromPersonId or toPersonId
CREATE POLICY "Relationship_insert_admin_or_self" ON "Relationship"
    FOR INSERT
    TO authenticated
    WITH CHECK (
        -- Admin/owner check: user has admin/owner role in this family
        EXISTS (
            SELECT 1 FROM "FamilyMember" fm
            WHERE fm."familyId" = "Relationship"."familyId"
              AND fm."userId" = auth.uid()::text
              AND fm.role IN ('admin', 'owner')
        )
        OR
        -- Self check: user's linked Person matches from or to
        EXISTS (
            SELECT 1 FROM "Person" p
            WHERE p."linkedUserId" = auth.uid()
              AND p."deletedAt" IS NULL
              AND (
                  p.id = "Relationship"."fromPersonId" OR
                  p.id = "Relationship"."toPersonId"
              )
        )
    );

-- Also add UPDATE policy (for soft-delete / deactivate)
-- Same rules: admin/owner or self
DROP POLICY IF EXISTS "relationship_update_policy" ON "Relationship";
DROP POLICY IF EXISTS "Relationship_update_admin_or_self" ON "Relationship";

CREATE POLICY "Relationship_update_admin_or_self" ON "Relationship"
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM "FamilyMember" fm
            WHERE fm."familyId" = "Relationship"."familyId"
              AND fm."userId" = auth.uid()::text
              AND fm.role IN ('admin', 'owner')
        )
        OR
        EXISTS (
            SELECT 1 FROM "Person" p
            WHERE p."linkedUserId" = auth.uid()
              AND p."deletedAt" IS NULL
              AND (
                  p.id = "Relationship"."fromPersonId" OR
                  p.id = "Relationship"."toPersonId"
              )
        )
    );

-- Verify
SELECT 'RLS policies created' as status,
       (SELECT count(*) FROM pg_policies WHERE tablename = 'Relationship') as policy_count;
