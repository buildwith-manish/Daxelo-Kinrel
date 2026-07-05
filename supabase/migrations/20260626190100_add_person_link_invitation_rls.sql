-- v2.2: Person-Link Invitations RLS policies
-- Continuing from 20260626190000_add_person_link_invitation.sql
--
-- NOTE: `auth.uid()` returns UUID but FamilyMember.userId is TEXT (cuid).
-- The existing FamilyMember RLS policies cast `auth.uid()::text` to bridge
-- this gap. We follow the same pattern here.

-- 1. SELECT: family members can see invitations for their family
DROP POLICY IF EXISTS "PersonLinkInvitation_select_family_member" ON "PersonLinkInvitation";
CREATE POLICY "PersonLinkInvitation_select_family_member" ON "PersonLinkInvitation"
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "PersonLinkInvitation"."familyId"
        AND fm."userId" = (auth.uid())::text
    )
  );

-- 2. INSERT: family editors+ can create invitations
DROP POLICY IF EXISTS "PersonLinkInvitation_insert_family_editor" ON "PersonLinkInvitation";
CREATE POLICY "PersonLinkInvitation_insert_family_editor" ON "PersonLinkInvitation"
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "PersonLinkInvitation"."familyId"
        AND fm."userId" = (auth.uid())::text
        AND fm."role" IN ('editor', 'admin', 'owner')
    )
  );

-- 3. UPDATE: family members can update (accept/revoke) invitations
DROP POLICY IF EXISTS "PersonLinkInvitation_update_family_member" ON "PersonLinkInvitation";
CREATE POLICY "PersonLinkInvitation_update_family_member" ON "PersonLinkInvitation"
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "PersonLinkInvitation"."familyId"
        AND fm."userId" = (auth.uid())::text
    )
  );

-- 4. DELETE: family admins can delete invitations
DROP POLICY IF EXISTS "PersonLinkInvitation_delete_family_admin" ON "PersonLinkInvitation";
CREATE POLICY "PersonLinkInvitation_delete_family_admin" ON "PersonLinkInvitation"
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "PersonLinkInvitation"."familyId"
        AND fm."userId" = (auth.uid())::text
        AND fm."role" IN ('admin', 'owner')
    )
  );
