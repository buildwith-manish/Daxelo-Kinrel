-- ══════════════════════════════════════════════════════════════════════════
-- KINREL: Complete Database Migration (SAFE - run multiple times)
-- ══════════════════════════════════════════════════════════════════════════

-- STEP 1: Create FamilyMember table
CREATE TABLE IF NOT EXISTS "FamilyMember" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "role" TEXT NOT NULL DEFAULT 'member',
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add unique constraint (catches correct PostgreSQL error 42P07)
DO $$ BEGIN
  ALTER TABLE "FamilyMember" ADD CONSTRAINT "FamilyMember_familyId_userId_key" UNIQUE ("familyId", "userId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "FamilyMember_familyId_idx" ON "FamilyMember" ("familyId");
CREATE INDEX IF NOT EXISTS "FamilyMember_userId_idx" ON "FamilyMember" ("userId");

-- STEP 2: Add missing columns to Family
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "familyCode" TEXT;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "avatarUrl" TEXT;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "region" TEXT;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "privacyMode" TEXT NOT NULL DEFAULT 'private';
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "isOnboarded" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "anchorPersonId" TEXT;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "memberCount" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "generationCount" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "lastActivityAt" TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "createdBy" TEXT;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "description" TEXT;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "primaryLanguage" TEXT NOT NULL DEFAULT 'en';
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "gotra" TEXT;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "originVillage" TEXT;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now();

DO $$ BEGIN
  ALTER TABLE "Family" ADD CONSTRAINT "Family_familyCode_key" UNIQUE ("familyCode");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Family_name_idx" ON "Family" ("name");
CREATE INDEX IF NOT EXISTS "Family_familyCode_idx" ON "Family" ("familyCode");

-- STEP 3: Add missing columns to Person
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "gender" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "birthYear" INTEGER;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "isAnchor" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "generationIndex" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "deletedAt" TIMESTAMPTZ;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "city" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "gotra" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "isDeceased" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "privacyLevel" TEXT NOT NULL DEFAULT 'family';
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "occupation" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "notes" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "sideOfFamily" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "photoUrl" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "dateOfBirth" TIMESTAMPTZ;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS "Person_familyId_name_idx" ON "Person" ("familyId", "name");
CREATE INDEX IF NOT EXISTS "Person_deletedAt_idx" ON "Person" ("deletedAt");

-- STEP 4: Add missing columns to Relationship
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "relationshipKey" TEXT;
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "direction" TEXT NOT NULL DEFAULT 'from';
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "isActive" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "label" TEXT;
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "verifiedAt" TIMESTAMPTZ;
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS "Relationship_familyId_idx" ON "Relationship" ("familyId");
CREATE INDEX IF NOT EXISTS "Relationship_relationshipKey_idx" ON "Relationship" ("relationshipKey");

-- STEP 5: Foreign keys
DO $$ BEGIN
  ALTER TABLE "FamilyMember" ADD CONSTRAINT "FamilyMember_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Person" ADD CONSTRAINT "Person_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Relationship" ADD CONSTRAINT "Relationship_fromPersonId_fkey" FOREIGN KEY ("fromPersonId") REFERENCES "Person"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Relationship" ADD CONSTRAINT "Relationship_toPersonId_fkey" FOREIGN KEY ("toPersonId") REFERENCES "Person"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- STEP 6: Enable RLS
ALTER TABLE "Family" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Person" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Relationship" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "FamilyMember" ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "Users can view their families" ON "Family" FOR SELECT USING ("createdBy" = auth.uid()::text OR EXISTS (SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = "Family"."id" AND fm."userId" = auth.uid()::text));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Authenticated users can create families" ON "Family" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Creators can update families" ON "Family" FOR UPDATE USING ("createdBy" = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Users can view family persons" ON "Person" FOR SELECT USING (EXISTS (SELECT 1 FROM "Family" f WHERE f."id" = "Person"."familyId" AND f."createdBy" = auth.uid()::text));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Users can insert family persons" ON "Person" FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM "Family" f WHERE f."id" = "Person"."familyId" AND f."createdBy" = auth.uid()::text));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Users can update family persons" ON "Person" FOR UPDATE USING (EXISTS (SELECT 1 FROM "Family" f WHERE f."id" = "Person"."familyId" AND f."createdBy" = auth.uid()::text));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Users can view family relationships" ON "Relationship" FOR SELECT USING (EXISTS (SELECT 1 FROM "Family" f WHERE f."id" = "Relationship"."familyId" AND f."createdBy" = auth.uid()::text));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Users can insert family relationships" ON "Relationship" FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM "Family" f WHERE f."id" = "Relationship"."familyId" AND f."createdBy" = auth.uid()::text));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Users can view family members" ON "FamilyMember" FOR SELECT USING ("userId" = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Users can join families" ON "FamilyMember" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
