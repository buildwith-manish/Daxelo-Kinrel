-- ============================================================
-- Migration: fix_rls_tables_with_missing_policies
-- Version:  20260608182557
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ══════════════════════════════════════════════
-- FIX 2: Add policies to RLS-enabled tables
-- that were missing them entirely
-- ══════════════════════════════════════════════

-- BlockedUser
CREATE POLICY "Users can view own blocked users" ON "BlockedUser" FOR SELECT USING ("blockerId" = auth.uid()::text);
CREATE POLICY "Users can block others" ON "BlockedUser" FOR INSERT WITH CHECK ("blockerId" = auth.uid()::text);
CREATE POLICY "Users can unblock others" ON "BlockedUser" FOR DELETE USING ("blockerId" = auth.uid()::text);

-- FamilyInvite
CREATE POLICY "Family members can view invites" ON "FamilyInvite" FOR SELECT
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Members can create invites" ON "FamilyInvite" FOR INSERT
  WITH CHECK ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin','member')));
CREATE POLICY "Admins can update invites" ON "FamilyInvite" FOR UPDATE
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin')));
CREATE POLICY "Admins can delete invites" ON "FamilyInvite" FOR DELETE
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin')));

-- FcmToken
CREATE POLICY "Users can view own FCM tokens" ON "FcmToken" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can create own FCM tokens" ON "FcmToken" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can update own FCM tokens" ON "FcmToken" FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can delete own FCM tokens" ON "FcmToken" FOR DELETE USING ("userId" = auth.uid()::text);

-- GraphChangeLog
CREATE POLICY "Family members can view graph change logs" ON "GraphChangeLog" FOR SELECT
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "System can create graph change logs" ON "GraphChangeLog" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- GraphLayoutState
CREATE POLICY "Users can view own graph layouts" ON "GraphLayoutState" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can create own graph layouts" ON "GraphLayoutState" FOR INSERT
  WITH CHECK ("userId" = auth.uid()::text AND "familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Users can update own graph layouts" ON "GraphLayoutState" FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can delete own graph layouts" ON "GraphLayoutState" FOR DELETE USING ("userId" = auth.uid()::text);

-- Invitation
CREATE POLICY "Users can view family invitations" ON "Invitation" FOR SELECT
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text)
    OR "inviterId" = auth.uid()::text);
CREATE POLICY "Members can create invitations" ON "Invitation" FOR INSERT
  WITH CHECK ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin','member'))
    AND "inviterId" = auth.uid()::text);
CREATE POLICY "Admins can update invitations" ON "Invitation" FOR UPDATE
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin')));
CREATE POLICY "Admins can delete invitations" ON "Invitation" FOR DELETE
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin')));

-- NotificationPreference
CREATE POLICY "Users can view own notification preferences" ON "NotificationPreference" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can create own notification preferences" ON "NotificationPreference" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can update own notification preferences" ON "NotificationPreference" FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can delete own notification preferences" ON "NotificationPreference" FOR DELETE USING ("userId" = auth.uid()::text);

-- NotificationUpdate
CREATE POLICY "Users can view own notification updates" ON "NotificationUpdate" FOR SELECT
  USING ("notificationId" IN (SELECT id FROM "Notification" WHERE "userId" = auth.uid()::text));

-- PersonPrivacySetting
CREATE POLICY "Members can view privacy settings in their families" ON "PersonPrivacySetting" FOR SELECT
  USING ("personId" IN (SELECT id FROM "Person" WHERE "familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text)));
CREATE POLICY "Members can create privacy settings" ON "PersonPrivacySetting" FOR INSERT
  WITH CHECK ("personId" IN (SELECT id FROM "Person" WHERE "familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin','member'))));
CREATE POLICY "Admins can update privacy settings" ON "PersonPrivacySetting" FOR UPDATE
  USING ("personId" IN (SELECT id FROM "Person" WHERE "familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin'))));

-- RefreshToken
CREATE POLICY "Users can view own refresh tokens" ON "RefreshToken" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "System can create refresh tokens" ON "RefreshToken" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Users can revoke own refresh tokens" ON "RefreshToken" FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can delete own refresh tokens" ON "RefreshToken" FOR DELETE USING ("userId" = auth.uid()::text);

-- SparqView
CREATE POLICY "Users can view sparq views" ON "SparqView" FOR SELECT
  USING ("viewerId" = auth.uid()::text OR "sparqId" IN (SELECT id FROM "Sparq" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Users can record sparq views" ON "SparqView" FOR INSERT WITH CHECK ("viewerId" = auth.uid()::text);

-- Story
CREATE POLICY "Users can view stories" ON "Story" FOR SELECT
  USING ("userId" = auth.uid()::text
    OR "familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Users can create stories" ON "Story" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can delete own stories" ON "Story" FOR DELETE USING ("userId" = auth.uid()::text);

-- StoryView
CREATE POLICY "Users can view story views" ON "StoryView" FOR SELECT
  USING ("viewerId" = auth.uid()::text OR "storyId" IN (SELECT id FROM "Story" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Users can record story views" ON "StoryView" FOR INSERT WITH CHECK ("viewerId" = auth.uid()::text);

-- Subscription
CREATE POLICY "Users can view own subscription" ON "Subscription" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "System can create subscriptions" ON "Subscription" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System can update subscriptions" ON "Subscription" FOR UPDATE USING ("userId" = auth.uid()::text);
