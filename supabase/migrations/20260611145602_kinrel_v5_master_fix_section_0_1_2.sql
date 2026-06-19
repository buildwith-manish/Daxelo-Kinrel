-- ============================================================
-- Migration: kinrel_v5_master_fix_section_0_1_2
-- Version:  20260611145602
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- SECTION 0: Extensions
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- SECTION 1: Ensure core table columns exist
ALTER TABLE "Family"
  ADD COLUMN IF NOT EXISTS "familyCode"      TEXT,
  ADD COLUMN IF NOT EXISTS "avatarUrl"       TEXT,
  ADD COLUMN IF NOT EXISTS "region"          TEXT,
  ADD COLUMN IF NOT EXISTS "privacyMode"     TEXT NOT NULL DEFAULT 'private',
  ADD COLUMN IF NOT EXISTS "isOnboarded"     BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "anchorPersonId"  TEXT,
  ADD COLUMN IF NOT EXISTS "memberCount"     INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "generationCount" INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS "lastActivityAt"  TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS "createdBy"       TEXT,
  ADD COLUMN IF NOT EXISTS "description"     TEXT,
  ADD COLUMN IF NOT EXISTS "primaryLanguage" TEXT NOT NULL DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS "gotra"           TEXT,
  ADD COLUMN IF NOT EXISTS "originVillage"   TEXT,
  ADD COLUMN IF NOT EXISTS "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS "deletedAt"       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS "username"        TEXT,
  ADD COLUMN IF NOT EXISTS "kinFamilyId"     TEXT,
  ADD COLUMN IF NOT EXISTS "isPublic"        BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "Person"
  ADD COLUMN IF NOT EXISTS "gender"          TEXT,
  ADD COLUMN IF NOT EXISTS "birthYear"       INTEGER,
  ADD COLUMN IF NOT EXISTS "isAnchor"        BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "generationIndex" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "deletedAt"       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS "city"            TEXT,
  ADD COLUMN IF NOT EXISTS "gotra"           TEXT,
  ADD COLUMN IF NOT EXISTS "isDeceased"      BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "privacyLevel"    TEXT NOT NULL DEFAULT 'family',
  ADD COLUMN IF NOT EXISTS "occupation"      TEXT,
  ADD COLUMN IF NOT EXISTS "notes"           TEXT,
  ADD COLUMN IF NOT EXISTS "sideOfFamily"    TEXT,
  ADD COLUMN IF NOT EXISTS "photoUrl"        TEXT,
  ADD COLUMN IF NOT EXISTS "photoThumb"      TEXT,
  ADD COLUMN IF NOT EXISTS "photoCard"       TEXT,
  ADD COLUMN IF NOT EXISTS "photoFull"       TEXT,
  ADD COLUMN IF NOT EXISTS "dateOfBirth"     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS "username"        TEXT,
  ADD COLUMN IF NOT EXISTS "bloodGroup"      TEXT,
  ADD COLUMN IF NOT EXISTS "education"       TEXT,
  ADD COLUMN IF NOT EXISTS "biography"       TEXT,
  ADD COLUMN IF NOT EXISTS "email"           TEXT,
  ADD COLUMN IF NOT EXISTS "phone"           TEXT,
  ADD COLUMN IF NOT EXISTS "address"         TEXT,
  ADD COLUMN IF NOT EXISTS "anniversaryDate" TIMESTAMPTZ;

ALTER TABLE "Relationship"
  ADD COLUMN IF NOT EXISTS "relationshipKey"  TEXT,
  ADD COLUMN IF NOT EXISTS "relationshipType" TEXT NOT NULL DEFAULT 'custom',
  ADD COLUMN IF NOT EXISTS "direction"        TEXT NOT NULL DEFAULT 'from',
  ADD COLUMN IF NOT EXISTS "isActive"         BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "label"            TEXT,
  ADD COLUMN IF NOT EXISTS "verifiedAt"       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS "createdAt"        TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS "updatedAt"        TIMESTAMPTZ NOT NULL DEFAULT now();

UPDATE "Relationship"
SET "relationshipKey" = "relationshipType"
WHERE "relationshipKey" IS NULL AND "relationshipType" IS NOT NULL;

-- SECTION 2: Constraints & Indexes
DO $$ BEGIN
  ALTER TABLE "Family" ADD CONSTRAINT "Family_familyCode_key" UNIQUE ("familyCode");
EXCEPTION WHEN duplicate_table OR duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Family" ADD CONSTRAINT "Family_username_key" UNIQUE ("username");
EXCEPTION WHEN duplicate_table OR duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Family" ADD CONSTRAINT "Family_kinFamilyId_key" UNIQUE ("kinFamilyId");
EXCEPTION WHEN duplicate_table OR duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FamilyMember" ADD CONSTRAINT "FamilyMember_familyId_userId_key" UNIQUE ("familyId", "userId");
EXCEPTION WHEN duplicate_table OR duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Relationship"
    ADD CONSTRAINT "Relationship_familyId_fkey"
    FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FamilyMember"
    ADD CONSTRAINT "FamilyMember_familyId_fkey"
    FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Person"
    ADD CONSTRAINT "Person_familyId_fkey"
    FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Relationship"
    ADD CONSTRAINT "Relationship_fromPersonId_fkey"
    FOREIGN KEY ("fromPersonId") REFERENCES "Person"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Relationship"
    ADD CONSTRAINT "Relationship_toPersonId_fkey"
    FOREIGN KEY ("toPersonId") REFERENCES "Person"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Family_name_idx"           ON "Family" ("name");
CREATE INDEX IF NOT EXISTS "Family_familyCode_idx"     ON "Family" ("familyCode");
CREATE INDEX IF NOT EXISTS "Family_username_idx"       ON "Family" ("username");
CREATE INDEX IF NOT EXISTS "Family_kinFamilyId_idx"    ON "Family" ("kinFamilyId");
CREATE INDEX IF NOT EXISTS "Family_deletedAt_idx"      ON "Family" ("deletedAt");
CREATE INDEX IF NOT EXISTS "Family_createdBy_idx"      ON "Family" ("createdBy");
CREATE INDEX IF NOT EXISTS "Family_gotra_idx"          ON "Family" ("gotra");
CREATE INDEX IF NOT EXISTS "Family_privacyMode_idx"    ON "Family" ("privacyMode");

CREATE INDEX IF NOT EXISTS "Person_familyId_name_idx"  ON "Person" ("familyId", "name");
CREATE INDEX IF NOT EXISTS "Person_deletedAt_idx"      ON "Person" ("deletedAt");
CREATE INDEX IF NOT EXISTS "Person_username_idx"       ON "Person" ("username");
CREATE INDEX IF NOT EXISTS "Person_name_idx"           ON "Person" ("name");
CREATE INDEX IF NOT EXISTS "Person_gotra_idx"          ON "Person" ("gotra");
CREATE INDEX IF NOT EXISTS "Person_privacyLevel_idx"   ON "Person" ("privacyLevel");

CREATE INDEX IF NOT EXISTS "Relationship_familyId_idx" ON "Relationship" ("familyId");
CREATE INDEX IF NOT EXISTS "Relationship_relationshipKey_idx"   ON "Relationship" ("relationshipKey");
CREATE INDEX IF NOT EXISTS "Relationship_familyId_isActive_idx" ON "Relationship" ("familyId", "isActive");
CREATE INDEX IF NOT EXISTS "Relationship_fromPersonId_toPersonId_idx"
  ON "Relationship" ("fromPersonId", "toPersonId");

CREATE INDEX IF NOT EXISTS "FamilyMember_familyId_idx"      ON "FamilyMember" ("familyId");
CREATE INDEX IF NOT EXISTS "FamilyMember_userId_idx"        ON "FamilyMember" ("userId");
CREATE INDEX IF NOT EXISTS "FamilyMember_familyId_userId_idx" ON "FamilyMember" ("familyId", "userId");
