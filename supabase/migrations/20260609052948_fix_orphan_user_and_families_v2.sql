-- ============================================================
-- Migration: fix_orphan_user_and_families_v2
-- Version:  20260609052948
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Insert missing User row with all required fields
INSERT INTO "User" (id, email, username, "preferredLanguage", role, "createdAt", "updatedAt",
  "profileVisibility", "invitePermission", "authProvider", "blockedUserIds",
  "twoFactorEnabled", "isPrivate", "isFamilyGraphPublic")
VALUES (
  'b8a432ed-e577-46a5-8e77-a5a1b5ff130c',
  'debug@kinrel.app',
  'debug',
  'en', 'user', NOW(), NOW(),
  'public', 'anyone', 'email', '[]',
  false, false, true
)
ON CONFLICT (id) DO NOTHING;

-- Insert missing FamilyMember rows for orphan families
INSERT INTO "FamilyMember" (id, "familyId", "userId", role, "joinedAt")
SELECT 
  'fm_' || f.id,
  f.id,
  f."createdBy",
  'owner',
  f."createdAt"
FROM "Family" f
WHERE f."deletedAt" IS NULL
  AND f."createdBy" = 'b8a432ed-e577-46a5-8e77-a5a1b5ff130c'
  AND NOT EXISTS (
    SELECT 1 FROM "FamilyMember" fm WHERE fm."familyId" = f.id
  )
ON CONFLICT DO NOTHING;

-- Update memberCount
UPDATE "Family"
SET "memberCount" = (
  SELECT COUNT(*) FROM "FamilyMember" fm WHERE fm."familyId" = "Family".id
)
WHERE "createdBy" = 'b8a432ed-e577-46a5-8e77-a5a1b5ff130c';

NOTIFY pgrst, 'reload schema';
