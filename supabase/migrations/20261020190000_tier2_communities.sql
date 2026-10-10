-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.3: Communities (umbrella over multiple groups)
-- =============================================================================
-- Schema-only migration. A community holds multiple family-group chats +
-- an announcement channel + a shared media library. Admins can broadcast
-- to all sub-groups at once.
--
-- NOTE: This migration adds the SCHEMA only. The NestJS communities/ module
-- + Flutter CommunityScreen UI are follow-up tasks. See WORKLOG.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "FamilyCommunity" (
  "id"            text PRIMARY KEY,
  "name"          text NOT NULL,
  "description"   text,
  "avatarUrl"     text,
  "ownerUserId"   text NOT NULL,
  "announcementChannelId" text,                  -- the channel used for community-wide announcements
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "FamilyCommunity_owner_idx" ON "FamilyCommunity"("ownerUserId");

-- Join table: which families are sub-groups of which community.
-- A family can belong to at most one community (UNIQUE on familyId).
CREATE TABLE IF NOT EXISTS "FamilyCommunityGroup" (
  "id"          text PRIMARY KEY,
  "communityId" text NOT NULL REFERENCES "FamilyCommunity"(id) ON DELETE CASCADE,
  "familyId"    text NOT NULL,
  "joinedAt"    timestamptz NOT NULL DEFAULT now(),
  UNIQUE("familyId")                              -- one family can't be in 2 communities
);

CREATE INDEX IF NOT EXISTS "FamilyCommunityGroup_community_idx" ON "FamilyCommunityGroup"("communityId");

-- Community admins (the owner + any co-admins they appoint).
CREATE TABLE IF NOT EXISTS "FamilyCommunityAdmin" (
  "id"          text PRIMARY KEY,
  "communityId" text NOT NULL REFERENCES "FamilyCommunity"(id) ON DELETE CASCADE,
  "userId"      text NOT NULL,
  "role"        text NOT NULL DEFAULT 'admin',   -- owner | admin
  "addedAt"     timestamptz NOT NULL DEFAULT now(),
  UNIQUE("communityId", "userId")
);

CREATE INDEX IF NOT EXISTS "FamilyCommunityAdmin_community_idx" ON "FamilyCommunityAdmin"("communityId");
CREATE INDEX IF NOT EXISTS "FamilyCommunityAdmin_user_idx"     ON "FamilyCommunityAdmin"("userId");

-- RLS.
ALTER TABLE "FamilyCommunity" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "FamilyCommunity select" ON "FamilyCommunity";
CREATE POLICY "FamilyCommunity select" ON "FamilyCommunity"
  FOR SELECT TO authenticated USING (true);  -- communities are publicly discoverable
DROP POLICY IF EXISTS "FamilyCommunity insert" ON "FamilyCommunity";
CREATE POLICY "FamilyCommunity insert" ON "FamilyCommunity"
  FOR INSERT TO authenticated WITH CHECK ("ownerUserId" = auth.uid()::text);
DROP POLICY IF EXISTS "FamilyCommunity update" ON "FamilyCommunity";
CREATE POLICY "FamilyCommunity update" ON "FamilyCommunity"
  FOR UPDATE TO authenticated USING ("ownerUserId" = auth.uid()::text);

ALTER TABLE "FamilyCommunityGroup" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "FamilyCommunityGroup select" ON "FamilyCommunityGroup";
CREATE POLICY "FamilyCommunityGroup select" ON "FamilyCommunityGroup"
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "FamilyCommunityGroup insert owner" ON "FamilyCommunityGroup";
CREATE POLICY "FamilyCommunityGroup insert owner" ON "FamilyCommunityGroup"
  FOR INSERT TO authenticated WITH CHECK (
    "communityId" IN (SELECT id FROM "FamilyCommunity" WHERE "ownerUserId" = auth.uid()::text)
  );
DROP POLICY IF EXISTS "FamilyCommunityGroup delete owner" ON "FamilyCommunityGroup";
CREATE POLICY "FamilyCommunityGroup delete owner" ON "FamilyCommunityGroup"
  FOR DELETE TO authenticated USING (
    "communityId" IN (SELECT id FROM "FamilyCommunity" WHERE "ownerUserId" = auth.uid()::text)
  );

ALTER TABLE "FamilyCommunityAdmin" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "FamilyCommunityAdmin select" ON "FamilyCommunityAdmin";
CREATE POLICY "FamilyCommunityAdmin select" ON "FamilyCommunityAdmin"
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "FamilyCommunityAdmin insert owner" ON "FamilyCommunityAdmin";
CREATE POLICY "FamilyCommunityAdmin insert owner" ON "FamilyCommunityAdmin"
  FOR INSERT TO authenticated WITH CHECK (
    "communityId" IN (SELECT id FROM "FamilyCommunity" WHERE "ownerUserId" = auth.uid()::text)
  );
DROP POLICY IF EXISTS "FamilyCommunityAdmin delete owner" ON "FamilyCommunityAdmin";
CREATE POLICY "FamilyCommunityAdmin delete owner" ON "FamilyCommunityAdmin"
  FOR DELETE TO authenticated USING (
    "communityId" IN (SELECT id FROM "FamilyCommunity" WHERE "ownerUserId" = auth.uid()::text)
  );

-- Verification
SELECT 'FamilyCommunity' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'FamilyCommunity') AS exists;
SELECT 'FamilyCommunityGroup' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'FamilyCommunityGroup') AS exists;
SELECT 'FamilyCommunityAdmin' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'FamilyCommunityAdmin') AS exists;
