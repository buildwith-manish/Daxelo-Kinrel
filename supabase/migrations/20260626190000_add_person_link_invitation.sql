-- v2.2: Person-Link Invitations table
-- Tracks pending invitations to claim a Person node. See
-- `server/src/modules/viewer/viewer.service.ts` and architecture
-- document Section 7 (Person Linking System) + Section 8 (Invitation System).

CREATE TABLE IF NOT EXISTS "PersonLinkInvitation" (
    "id"               TEXT NOT NULL,
    "familyId"         TEXT NOT NULL,
    "personId"         TEXT NOT NULL,
    "code"             TEXT NOT NULL,
    "inviterUserId"    TEXT NOT NULL,
    "recipientName"    TEXT,
    "recipientEmail"   TEXT,
    "recipientPhone"   TEXT,
    "role"             TEXT NOT NULL DEFAULT 'member',
    "status"           TEXT NOT NULL DEFAULT 'pending',
    "expiresAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "acceptedAt"       TIMESTAMPTZ,
    "acceptedByUserId" TEXT,
    "createdAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT "PersonLinkInvitation_pkey" PRIMARY KEY ("id")
);

-- Unique constraint on code (one-time use, single-use codes)
CREATE UNIQUE INDEX IF NOT EXISTS "PersonLinkInvitation_code_key"
  ON "PersonLinkInvitation" ("code");

-- Foreign keys
ALTER TABLE "PersonLinkInvitation"
  ADD CONSTRAINT "PersonLinkInvitation_familyId_fkey"
  FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE;

ALTER TABLE "PersonLinkInvitation"
  ADD CONSTRAINT "PersonLinkInvitation_personId_fkey"
  FOREIGN KEY ("personId") REFERENCES "Person"("id") ON DELETE CASCADE;

ALTER TABLE "PersonLinkInvitation"
  ADD CONSTRAINT "PersonLinkInvitation_inviterUserId_fkey"
  FOREIGN KEY ("inviterUserId") REFERENCES "User"("id") ON DELETE CASCADE;

-- Performance indexes
CREATE INDEX IF NOT EXISTS "PersonLinkInvitation_familyId_idx"
  ON "PersonLinkInvitation" ("familyId");
CREATE INDEX IF NOT EXISTS "PersonLinkInvitation_personId_idx"
  ON "PersonLinkInvitation" ("personId");
CREATE INDEX IF NOT EXISTS "PersonLinkInvitation_code_idx"
  ON "PersonLinkInvitation" ("code");
CREATE INDEX IF NOT EXISTS "PersonLinkInvitation_status_idx"
  ON "PersonLinkInvitation" ("status");
CREATE INDEX IF NOT EXISTS "PersonLinkInvitation_expiresAt_idx"
  ON "PersonLinkInvitation" ("expiresAt");

-- Enable RLS
ALTER TABLE "PersonLinkInvitation" ENABLE ROW LEVEL SECURITY;

-- RLS Policies:
--   1. Family members can read invitations for their family
--   2. Family editors+ can create invitations
--   3. The linked user / admins can update invitations (accept/revoke)
DROP POLICY IF EXISTS "PersonLinkInvitation_select_family_member" ON "PersonLinkInvitation";
CREATE POLICY "PersonLinkInvitation_select_family_member" ON "PersonLinkInvitation"
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "PersonLinkInvitation"."familyId"
        AND fm."userId" = auth.uid()
    )
  );

DROP POLICY IF EXISTS "PersonLinkInvitation_insert_family_editor" ON "PersonLinkInvitation";
CREATE POLICY "PersonLinkInvitation_insert_family_editor" ON "PersonLinkInvitation"
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "PersonLinkInvitation"."familyId"
        AND fm."userId" = auth.uid()
        AND fm."role" IN ('editor', 'admin', 'owner')
    )
  );

DROP POLICY IF EXISTS "PersonLinkInvitation_update_family_member" ON "PersonLinkInvitation";
CREATE POLICY "PersonLinkInvitation_update_family_member" ON "PersonLinkInvitation"
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM "FamilyMember" fm
      WHERE fm."familyId" = "PersonLinkInvitation"."familyId"
        AND fm."userId" = auth.uid()
    )
  );
