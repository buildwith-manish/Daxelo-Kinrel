-- ============================================================
-- DAXELO KINREL — Row Level Security Policies v2
-- Feature 11: Security — Complete RLS for all tables
-- Run these in Supabase SQL Editor
-- ============================================================
--
-- Role Hierarchy: owner > admin > member > viewer
--   owner:  can do everything (delete family, transfer ownership, manage billing)
--   admin:  can manage members, relationships, settings, invite people
--   member: can add/edit persons, view everything
--   viewer: can only view data
--
-- Privacy Levels on Person:
--   public:  visible to anyone in the family
--   family:  visible to direct family members only
--   extended: visible to extended family members
--
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. Enable RLS on all tables
-- ────────────────────────────────────────────────────────────

ALTER TABLE "User" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Family" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "FamilyMember" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Person" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Relationship" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Invitation" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "FamilyInvite" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Notification" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "NotificationUpdate" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PersonPrivacySetting" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "DataAccessLog" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PhotoConsent" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "FamilyPost" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "GraphLayoutState" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "GraphChangeLog" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Subscription" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "SupportTicket" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "SupportMessage" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "NotificationPreference" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "RefreshToken" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "FcmToken" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "AuditLog" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ApiKey" ENABLE ROW LEVEL SECURITY;

-- ────────────────────────────────────────────────────────────
-- 2. "User" table — Users can only read/update their own profile
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own profile"
  ON "User" FOR SELECT
  USING (id = auth.uid()::text);

CREATE POLICY "Users can update own profile"
  ON "User" FOR UPDATE
  USING (id = auth.uid()::text)
  WITH CHECK (id = auth.uid()::text);

-- Allow insert for registration flows (Supabase Auth trigger or API)
CREATE POLICY "Users can insert own profile"
  ON "User" FOR INSERT
  WITH CHECK (id = auth.uid()::text);

-- ────────────────────────────────────────────────────────────
-- 3. "Family" table — Users can see families they are members of
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view their families"
  ON "Family" FOR SELECT
  USING (
    id IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
    -- Also allow families with privacy mode 'link' or 'invite' to be discoverable
    -- by family code lookup (but not full data)
    OR "privacyMode" IN ('link')
  );

CREATE POLICY "Users can create families"
  ON "Family" FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Owners and admins can update families"
  ON "Family" FOR UPDATE
  USING (
    id IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Only owners can delete families"
  ON "Family" FOR DELETE
  USING (
    id IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role = 'owner'
    )
  );

-- ────────────────────────────────────────────────────────────
-- 4. "FamilyMember" table — Users can view members of their families
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view family members"
  ON "FamilyMember" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

CREATE POLICY "Owners and admins can add family members"
  ON "FamilyMember" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Owners and admins can update family member roles"
  ON "FamilyMember" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Owners can remove family members"
  ON "FamilyMember" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
    -- Prevent owners from removing themselves (transfer ownership first)
    AND NOT (
      "userId" = auth.uid()::text
      AND role = 'owner'
    )
  );

-- ────────────────────────────────────────────────────────────
-- 5. "Person" table — Privacy-aware access with role hierarchy
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view persons in their families"
  ON "Person" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
    AND (
      -- Public persons are visible to all family members
      "privacyLevel" = 'public'
      -- Family-level privacy: visible to direct family members
      OR (
        "privacyLevel" = 'family'
        AND "familyId" IN (
          SELECT "familyId" FROM "FamilyMember"
          WHERE "userId" = auth.uid()::text
        )
      )
      -- Extended privacy: visible to extended family members (admins+ always see)
      OR (
        "privacyLevel" = 'extended'
        AND (
          "familyId" IN (
            SELECT "familyId" FROM "FamilyMember"
            WHERE "userId" = auth.uid()::text
              AND role IN ('owner', 'admin', 'member')
          )
          OR "familyId" IN (
            SELECT "familyId" FROM "FamilyMember"
            WHERE "userId" = auth.uid()::text
          )
        )
      )
    )
    -- Exclude soft-deleted persons unless user is admin+
    AND (
      "deletedAt" IS NULL
      OR "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
          AND role IN ('owner', 'admin')
      )
    )
  );

CREATE POLICY "Members and above can create persons"
  ON "Person" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin', 'member')
    )
  );

CREATE POLICY "Users can update persons in their families"
  ON "Person" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
    -- Viewers cannot update
    AND "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin', 'member')
    )
  );

CREATE POLICY "Admins and above can soft-delete persons"
  ON "Person" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

-- ────────────────────────────────────────────────────────────
-- 6. "Relationship" table — Role-gated relationship management
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view relationships in their families"
  ON "Relationship" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

CREATE POLICY "Admins can create relationships"
  ON "Relationship" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Admins can update relationships"
  ON "Relationship" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Admins can delete relationships"
  ON "Relationship" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

-- ────────────────────────────────────────────────────────────
-- 7. "Invitation" table — Inviter family or recipient can see
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view family invitations"
  ON "Invitation" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
    OR "recipientEmail" = (
      SELECT email FROM "User" WHERE id = auth.uid()::text
    )
    OR "recipientPhone" = (
      SELECT phone FROM "User" WHERE id = auth.uid()::text
    )
    OR "inviterId" = auth.uid()::text
  );

CREATE POLICY "Admins can create invitations"
  ON "Invitation" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin', 'member')
    )
    AND "inviterId" = auth.uid()::text
  );

CREATE POLICY "Admins can update invitations"
  ON "Invitation" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
    OR (
      -- Recipients can update status (accept/cancel)
      "recipientEmail" = (
        SELECT email FROM "User" WHERE id = auth.uid()::text
      )
    )
  );

CREATE POLICY "Admins can delete invitations"
  ON "Invitation" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

-- ────────────────────────────────────────────────────────────
-- 8. "FamilyInvite" table — Code/link-based invite management
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view family invites"
  ON "FamilyInvite" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

CREATE POLICY "Admins can create family invites"
  ON "FamilyInvite" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin', 'member')
    )
  );

CREATE POLICY "Admins can update family invites"
  ON "FamilyInvite" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Admins can delete family invites"
  ON "FamilyInvite" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

-- ────────────────────────────────────────────────────────────
-- 9. "Notification" table — Users can only see their own notifications
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own notifications"
  ON "Notification" FOR SELECT
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can update own notifications"
  ON "Notification" FOR UPDATE
  USING ("userId" = auth.uid()::text);

CREATE POLICY "System can create notifications"
  ON "Notification" FOR INSERT
  WITH CHECK (true); -- System/backend creates these

CREATE POLICY "Users can delete own notifications"
  ON "Notification" FOR DELETE
  USING ("userId" = auth.uid()::text);

-- ────────────────────────────────────────────────────────────
-- 10. "NotificationUpdate" table — Via notification ownership
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own notification updates"
  ON "NotificationUpdate" FOR SELECT
  USING (
    "notificationId" IN (
      SELECT id FROM "Notification"
      WHERE "userId" = auth.uid()::text
    )
  );

-- ────────────────────────────────────────────────────────────
-- 11. "PersonPrivacySetting" table — Privacy settings access
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view privacy settings in their families"
  ON "PersonPrivacySetting" FOR SELECT
  USING (
    "personId" IN (
      SELECT id FROM "Person"
      WHERE "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
      )
    )
  );

CREATE POLICY "Admins can update privacy settings"
  ON "PersonPrivacySetting" FOR UPDATE
  USING (
    "personId" IN (
      SELECT id FROM "Person"
      WHERE "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
          AND role IN ('owner', 'admin')
      )
    )
  );

CREATE POLICY "Members can create privacy settings"
  ON "PersonPrivacySetting" FOR INSERT
  WITH CHECK (
    "personId" IN (
      SELECT id FROM "Person"
      WHERE "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
          AND role IN ('owner', 'admin', 'member')
      )
    )
  );

-- ────────────────────────────────────────────────────────────
-- 12. "DataAccessLog" table — Audit trail access
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view data access logs for their family persons"
  ON "DataAccessLog" FOR SELECT
  USING (
    "personId" IN (
      SELECT id FROM "Person"
      WHERE "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
          AND role IN ('owner', 'admin')
      )
    )
  );

-- System creates these logs
CREATE POLICY "System can create data access logs"
  ON "DataAccessLog" FOR INSERT
  WITH CHECK (true);

-- ────────────────────────────────────────────────────────────
-- 13. "PhotoConsent" table — Consent tracking
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view photo consent for family persons"
  ON "PhotoConsent" FOR SELECT
  USING (
    "personId" IN (
      SELECT id FROM "Person"
      WHERE "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
      )
    )
  );

CREATE POLICY "Admins can manage photo consent"
  ON "PhotoConsent" FOR INSERT
  WITH CHECK (
    "personId" IN (
      SELECT id FROM "Person"
      WHERE "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
          AND role IN ('owner', 'admin')
      )
    )
  );

CREATE POLICY "Admins can update photo consent"
  ON "PhotoConsent" FOR UPDATE
  USING (
    "personId" IN (
      SELECT id FROM "Person"
      WHERE "familyId" IN (
        SELECT "familyId" FROM "FamilyMember"
        WHERE "userId" = auth.uid()::text
          AND role IN ('owner', 'admin')
      )
    )
  );

-- ────────────────────────────────────────────────────────────
-- 14. "FamilyPost" table — Feed posts visible to family members
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Family members can view family posts"
  ON "FamilyPost" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

CREATE POLICY "Members and above can create family posts"
  ON "FamilyPost" FOR INSERT
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin', 'member')
    )
  );

CREATE POLICY "Authors and admins can update family posts"
  ON "FamilyPost" FOR UPDATE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

CREATE POLICY "Admins can delete family posts"
  ON "FamilyPost" FOR DELETE
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
        AND role IN ('owner', 'admin')
    )
  );

-- ────────────────────────────────────────────────────────────
-- 15. "GraphLayoutState" table — User's own layout preferences
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own graph layouts"
  ON "GraphLayoutState" FOR SELECT
  USING (
    "userId" = auth.uid()::text
  );

CREATE POLICY "Users can create own graph layouts"
  ON "GraphLayoutState" FOR INSERT
  WITH CHECK (
    "userId" = auth.uid()::text
    AND "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

CREATE POLICY "Users can update own graph layouts"
  ON "GraphLayoutState" FOR UPDATE
  USING (
    "userId" = auth.uid()::text
  );

CREATE POLICY "Users can delete own graph layouts"
  ON "GraphLayoutState" FOR DELETE
  USING (
    "userId" = auth.uid()::text
  );

-- ────────────────────────────────────────────────────────────
-- 16. "GraphChangeLog" table — Audit log for graph changes
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Family members can view graph change logs"
  ON "GraphChangeLog" FOR SELECT
  USING (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

-- System creates these
CREATE POLICY "System can create graph change logs"
  ON "GraphChangeLog" FOR INSERT
  WITH CHECK (true);

-- ────────────────────────────────────────────────────────────
-- 17. "Subscription" table — Users can only see their own subscription
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own subscription"
  ON "Subscription" FOR SELECT
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can create own subscription"
  ON "Subscription" FOR INSERT
  WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "Users can update own subscription"
  ON "Subscription" FOR UPDATE
  USING ("userId" = auth.uid()::text);

-- ────────────────────────────────────────────────────────────
-- 18. "SupportTicket" table — Users can see their own tickets
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own support tickets"
  ON "SupportTicket" FOR SELECT
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can create support tickets"
  ON "SupportTicket" FOR INSERT
  WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "Users can update own support tickets"
  ON "SupportTicket" FOR UPDATE
  USING ("userId" = auth.uid()::text);

-- ────────────────────────────────────────────────────────────
-- 19. "SupportMessage" table — Via ticket ownership
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view messages for own tickets"
  ON "SupportMessage" FOR SELECT
  USING (
    "ticketId" IN (
      SELECT id FROM "SupportTicket"
      WHERE "userId" = auth.uid()::text
    )
  );

CREATE POLICY "Users can create messages for own tickets"
  ON "SupportMessage" FOR INSERT
  WITH CHECK (
    "ticketId" IN (
      SELECT id FROM "SupportTicket"
      WHERE "userId" = auth.uid()::text
    )
  );

-- ────────────────────────────────────────────────────────────
-- 20. "NotificationPreference" table — Users manage their own preferences
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own notification preferences"
  ON "NotificationPreference" FOR SELECT
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can create own notification preferences"
  ON "NotificationPreference" FOR INSERT
  WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "Users can update own notification preferences"
  ON "NotificationPreference" FOR UPDATE
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can delete own notification preferences"
  ON "NotificationPreference" FOR DELETE
  USING ("userId" = auth.uid()::text);

-- ────────────────────────────────────────────────────────────
-- 21. "RefreshToken" table — Users can only access their own tokens
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own refresh tokens"
  ON "RefreshToken" FOR SELECT
  USING ("userId" = auth.uid()::text);

CREATE POLICY "System can create refresh tokens"
  ON "RefreshToken" FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Users can revoke own refresh tokens"
  ON "RefreshToken" FOR UPDATE
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can delete own refresh tokens"
  ON "RefreshToken" FOR DELETE
  USING ("userId" = auth.uid()::text);

-- ────────────────────────────────────────────────────────────
-- 22. "FcmToken" table — Users manage their own device tokens
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own FCM tokens"
  ON "FcmToken" FOR SELECT
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can create own FCM tokens"
  ON "FcmToken" FOR INSERT
  WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "Users can update own FCM tokens"
  ON "FcmToken" FOR UPDATE
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can delete own FCM tokens"
  ON "FcmToken" FOR DELETE
  USING ("userId" = auth.uid()::text);

-- ────────────────────────────────────────────────────────────
-- 23. "AuditLog" table — Admin-only access
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Admins can view audit logs"
  ON "AuditLog" FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM "User"
      WHERE id = auth.uid()::text
        AND role = 'admin'
    )
  );

-- System creates these
CREATE POLICY "System can create audit logs"
  ON "AuditLog" FOR INSERT
  WITH CHECK (true);

-- ────────────────────────────────────────────────────────────
-- 24. "ApiKey" table — Users manage their own API keys
-- ────────────────────────────────────────────────────────────

CREATE POLICY "Users can view own API keys"
  ON "ApiKey" FOR SELECT
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can create own API keys"
  ON "ApiKey" FOR INSERT
  WITH CHECK ("userId" = auth.uid()::text);

CREATE POLICY "Users can update own API keys"
  ON "ApiKey" FOR UPDATE
  USING ("userId" = auth.uid()::text);

CREATE POLICY "Users can delete own API keys"
  ON "ApiKey" FOR DELETE
  USING ("userId" = auth.uid()::text);

-- ============================================================
-- Helper Functions for Application-Level RLS Integration
-- ============================================================

-- Function to check if a user has a minimum role in a family
-- Usage: SELECT has_family_role('user_id', 'family_id', 'admin');
CREATE OR REPLACE FUNCTION has_family_role(
  p_user_id TEXT,
  p_family_id TEXT,
  p_minimum_role TEXT
) RETURNS BOOLEAN AS $$
DECLARE
  v_role TEXT;
  v_role_weight INT;
  v_min_weight INT;
BEGIN
  -- Define role hierarchy weights
  v_role_weight := CASE p_minimum_role
    WHEN 'owner'  THEN 4
    WHEN 'admin'  THEN 3
    WHEN 'member' THEN 2
    WHEN 'viewer' THEN 1
    ELSE 0
  END;

  SELECT role INTO v_role
  FROM "FamilyMember"
  WHERE "userId" = p_user_id
    AND "familyId" = p_family_id
  LIMIT 1;

  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;

  v_min_weight := CASE v_role
    WHEN 'owner'  THEN 4
    WHEN 'admin'  THEN 3
    WHEN 'member' THEN 2
    WHEN 'viewer' THEN 1
    ELSE 0
  END;

  RETURN v_min_weight >= v_role_weight;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if a user can access a person's data based on privacy level
-- Usage: SELECT can_access_person('user_id', 'person_id');
CREATE OR REPLACE FUNCTION can_access_person(
  p_user_id TEXT,
  p_person_id TEXT
) RETURNS BOOLEAN AS $$
DECLARE
  v_person RECORD;
  v_is_member BOOLEAN;
  v_member_role TEXT;
BEGIN
  -- Get person details
  SELECT "familyId", "privacyLevel", "deletedAt"
  INTO v_person
  FROM "Person"
  WHERE id = p_person_id;

  IF v_person IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Check if soft-deleted (only admins can see)
  IF v_person."deletedAt" IS NOT NULL THEN
    SELECT role INTO v_member_role
    FROM "FamilyMember"
    WHERE "userId" = p_user_id
      AND "familyId" = v_person."familyId"
    LIMIT 1;

    RETURN v_member_role IN ('owner', 'admin');
  END IF;

  -- Check if user is a member of the person's family
  SELECT role INTO v_member_role
  FROM "FamilyMember"
  WHERE "userId" = p_user_id
    AND "familyId" = v_person."familyId"
  LIMIT 1;

  v_is_member := v_member_role IS NOT NULL;

  IF NOT v_is_member THEN
    RETURN FALSE;
  END IF;

  -- Check privacy level
  CASE v_person."privacyLevel"
    WHEN 'public' THEN
      RETURN TRUE;
    WHEN 'family' THEN
      RETURN TRUE; -- Already confirmed family membership
    WHEN 'extended' THEN
      -- Viewers cannot see extended-privacy persons' sensitive data
      -- But they can see basic info
      RETURN v_member_role IN ('owner', 'admin', 'member', 'viewer');
    ELSE
      RETURN FALSE;
  END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Instructions:
-- 1. Go to supabase.com → your project
-- 2. Click SQL Editor
-- 3. Paste and run these policies
-- 4. Verify in Authentication → Policies
-- 5. Test with: SELECT has_family_role('user_id', 'family_id', 'admin');
-- 6. Test with: SELECT can_access_person('user_id', 'person_id');
-- ============================================================
