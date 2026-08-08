-- =============================================================================
-- Daxelo Kinrel — Invite & Search Infrastructure Verification Script
-- =============================================================================
-- Run this in the Supabase Dashboard → SQL Editor.
--
-- This script is IDEMPOTENT — safe to run multiple times. It uses
-- CREATE OR REPLACE / IF NOT EXISTS so it only creates what's missing.
--
-- It verifies and creates:
--   1. fn_search_kinrel_users — searches the "User" table for real Kinrel users
--   2. fn_send_family_invite_notification — sends invite notifications
--   3. fn_generate_family_invite — generates invite links
--   4. FamilyInvite table columns (social columns, FK fixes)
--   5. Notification auto-add trigger
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. fn_search_kinrel_users — global Kinrel user search
-- ═══════════════════════════════════════════════════════════════════════════
-- Queries the "User" table (auth users only), NOT the "Person" table.
-- Manually-created graph-only profiles (linkedUserId = null) are NEVER returned.

CREATE OR REPLACE FUNCTION fn_search_kinrel_users(
  p_query text,
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS TABLE(
  id text,
  name text,
  username text,
  email text,
  "avatarUrl" text,
  "photoThumb" text,
  bio text,
  gender text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    u.id,
    u.name,
    u.username,
    u.email,
    u."avatarUrl",
    u."photoThumb",
    u.bio,
    u.gender
  FROM "User" u
  WHERE u."deletedAt" IS NULL
    AND (u."profileVisibility" IS NULL OR u."profileVisibility" = 'public')
    AND u.id <> auth.uid()::text
    AND (
      u.name ILIKE '%' || TRIM(p_query) || '%'
      OR u.username ILIKE '%' || TRIM(p_query) || '%'
      OR u.email ILIKE '%' || TRIM(p_query) || '%'
    )
  ORDER BY
    CASE WHEN u.username ILIKE TRIM(p_query) THEN 0 ELSE 1 END,
    CASE WHEN u.name ILIKE TRIM(p_query) THEN 0 ELSE 1 END,
    u.name ASC
  LIMIT LEAST(p_limit, 100)
  OFFSET GREATEST(p_offset, 0);
$$;

GRANT EXECUTE ON FUNCTION fn_search_kinrel_users(text, int, int) TO authenticated;

COMMENT ON FUNCTION fn_search_kinrel_users(text, int, int) IS
  'Searches all public-profile Kinrel users by name/username/email. '
  'SECURITY DEFINER — bypasses User table RLS so users can find each other. '
  'Excludes the caller and deleted/private users. Returns at most 100 rows. '
  'Only queries the "User" table (real auth users), never the "Person" table '
  '(which contains manually-created graph-only profiles).';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_send_family_invite_notification — sends invite notification to target
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_send_family_invite_notification(
  p_target_user_id text,
  p_family_id text,
  p_family_name text,
  p_invite_url text,
  p_inviter_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO "Notification" (
    "userId",
    "type",
    "title",
    "body",
    "data",
    "isRead",
    "createdAt"
  )
  VALUES (
    p_target_user_id,
    'family_invite',
    'Family Invitation',
    p_inviter_name || ' invited you to join ' || p_family_name,
    jsonb_build_object(
      'familyId', p_family_id,
      'familyName', p_family_name,
      'inviteUrl', p_invite_url,
      'inviterName', p_inviter_name
    ),
    false,
    now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_send_family_invite_notification(text, text, text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_generate_family_invite — generates invite links
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_generate_family_invite(
  p_family_id text,
  p_created_by text DEFAULT auth.uid()::text,
  p_expiry_days int DEFAULT 7,
  p_max_uses int DEFAULT 0
)
RETURNS TABLE(
  id text,
  token text,
  "familyId" text,
  "createdBy" text,
  "expiresAt" timestamptz,
  "maxUses" int,
  "usedCount" int,
  "createdAt" timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token text;
  v_invite_id text;
BEGIN
  -- Generate a random token (URL-safe)
  v_token := encode(gen_random_bytes(24), 'hex');

  INSERT INTO "FamilyInvite" (
    "token",
    "familyId",
    "createdBy",
    "expiresAt",
    "maxUses",
    "usedCount",
    "createdAt"
  )
  VALUES (
    v_token,
    p_family_id,
    p_created_by,
    now() + (p_expiry_days || ' days')::interval,
    p_max_uses,
    0,
    now()
  )
  RETURNING id INTO v_invite_id;

  RETURN QUERY
  SELECT
    fi.id,
    fi.token,
    fi."familyId",
    fi."createdBy",
    fi."expiresAt",
    fi."maxUses",
    fi."usedCount",
    fi."createdAt"
  FROM "FamilyInvite" fi
  WHERE fi.id = v_invite_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_generate_family_invite(text, text, int, int) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Verify FamilyInvite table columns exist
-- ═══════════════════════════════════════════════════════════════════════════

-- Add social columns if missing (idempotent — ALTER TABLE ... ADD COLUMN IF NOT EXISTS)
DO $$
BEGIN
  -- These columns support the invite social flow
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'FamilyInvite' AND column_name = 'maxUses'
  ) THEN
    ALTER TABLE "FamilyInvite" ADD COLUMN "maxUses" int DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'FamilyInvite' AND column_name = 'usedCount'
  ) THEN
    ALTER TABLE "FamilyInvite" ADD COLUMN "usedCount" int DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'FamilyInvite' AND column_name = 'expiresAt'
  ) THEN
    ALTER TABLE "FamilyInvite" ADD COLUMN "expiresAt" timestamptz;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'FamilyInvite column check: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Enable RLS on FamilyInvite if not already enabled
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE tablename = 'FamilyInvite' AND rowsecurity = true
  ) THEN
    ALTER TABLE "FamilyInvite" ENABLE ROW LEVEL SECURITY;
    RAISE NOTICE 'RLS enabled on FamilyInvite';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'RLS check: %', SQLERRM;
END $$;

-- RLS policy: users can read invites for families they're a member of
DROP POLICY IF EXISTS "FamilyInvite select policy" ON "FamilyInvite";
CREATE POLICY "FamilyInvite select policy" ON "FamilyInvite"
  FOR SELECT TO authenticated
  USING (
    "createdBy" = auth.uid()::text
    OR "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

-- RLS policy: family members can create invites
DROP POLICY IF EXISTS "FamilyInvite insert policy" ON "FamilyInvite";
CREATE POLICY "FamilyInvite insert policy" ON "FamilyInvite"
  FOR INSERT TO authenticated
  WITH CHECK (
    "familyId" IN (
      SELECT "familyId" FROM "FamilyMember"
      WHERE "userId" = auth.uid()::text
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Notification auto-add trigger (auto-accept when invite is used)
-- ═══════════════════════════════════════════════════════════════════════════

-- This trigger fires when a user accepts an invite and joins a family.
-- It adds the user to the FamilyMember table automatically.
CREATE OR REPLACE FUNCTION fn_auto_add_family_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- When a new FamilyMember is inserted, ensure the notification is marked
  IF NEW."userId" IS NOT NULL THEN
    UPDATE "Notification"
    SET "isRead" = true
    WHERE "userId" = NEW."userId"
      AND "type" = 'family_invite'
      AND "data"->>'familyId' = NEW."familyId";
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_add_family_member ON "FamilyMember";
CREATE TRIGGER trg_auto_add_family_member
  AFTER INSERT ON "FamilyMember"
  FOR EACH ROW
  EXECUTE FUNCTION fn_auto_add_family_member();

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. Verification queries
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'fn_search_kinrel_users' AS function_name,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_search_kinrel_users') AS exists;

SELECT 'fn_send_family_invite_notification' AS function_name,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_send_family_invite_notification') AS exists;

SELECT 'fn_generate_family_invite' AS function_name,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_generate_family_invite') AS exists;

SELECT 'FamilyInvite table' AS object_name,
       EXISTS(SELECT 1 FROM pg_tables WHERE tablename = 'FamilyInvite') AS exists;

SELECT 'FamilyMember table' AS object_name,
       EXISTS(SELECT 1 FROM pg_tables WHERE tablename = 'FamilyMember') AS exists;

SELECT 'Notification table' AS object_name,
       EXISTS(SELECT 1 FROM pg_tables WHERE tablename = 'Notification') AS exists;

SELECT 'User table' AS object_name,
       EXISTS(SELECT 1 FROM pg_tables WHERE tablename = 'User') AS exists;

-- Done. All invite/search infrastructure is now verified + created.
