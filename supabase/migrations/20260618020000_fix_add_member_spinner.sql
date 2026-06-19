-- ============================================================
-- Migration: fix_add_member_spinner
-- Date:      2026-06-18
-- Source:    Super Z audit — "Add Member" spinner never stops
--
-- Root cause analysis:
--   1. Two duplicate triggers (_fn_after_family_insert AND
--      enroll_family_creator) both insert a FamilyMember row
--      with role='owner' when a Family is created. This is
--      redundant — only one trigger is needed.
--
--   2. The add_family_member() RPC uses
--      ON CONFLICT (familyId, userId) DO UPDATE SET role = EXCLUDED.role
--      which OVERWRITES the role. If called with role='admin'
--      after the trigger already inserted with role='owner',
--      it demotes the owner to admin.
--
--   3. The NestJS backend's families.service.ts creates a
--      FamilyMember with role='admin' (should be 'owner').
--      This is being fixed in the same PR.
--
--   4. Existing FamilyMember rows have role='admin' instead
--      of 'owner' for family creators. This migration backfills
--      them to 'owner' so the relationship_insert RLS policy
--      (which allows owner/admin/member) works correctly.
--
--   5. The Relationship table was empty because the Flutter
--      app's createRelationship() was hanging due to missing
--      timeouts on Supabase operations. That's being fixed in
--      the Flutter code in the same PR.
--
-- This migration:
--   A. Drops the duplicate enroll_family_creator trigger
--      (keeps _fn_after_family_insert which does the same thing)
--   B. Drops the enroll_family_creator function
--   C. Fixes add_family_member() to use ON CONFLICT DO NOTHING
--      (preserves the existing role instead of overwriting)
--   D. Backfills existing FamilyMember rows: family creators
--      get role='owner' (was incorrectly set to 'admin')
-- ============================================================

-- ============================================================
-- A. Drop duplicate trigger (keep _fn_after_family_insert)
-- ============================================================
-- Both triggers do the exact same thing (insert FamilyMember
-- with role='owner' after Family insert). Having both wastes
-- a write per family creation and can confuse debugging.
-- _fn_after_family_insert is the older one, keep it.
-- ============================================================
DROP TRIGGER IF EXISTS trg_enroll_family_creator ON public."Family";

-- ============================================================
-- B. Drop the now-unused function
-- ============================================================
DROP FUNCTION IF EXISTS public.enroll_family_creator();

-- ============================================================
-- C. Fix add_family_member() RPC
-- ============================================================
-- Old behavior: ON CONFLICT DO UPDATE SET role = EXCLUDED.role
--   → demotes an existing 'owner' to whatever role is passed
--     (typically 'admin' from the NestJS backend)
-- New behavior: ON CONFLICT DO NOTHING
--   → preserves the existing role. If the FamilyMember already
--     exists (e.g. created by the trigger with 'owner'), the
--     RPC call is a no-op. This is the correct behavior for
--     idempotent "ensure this user is a member" operations.
--
-- Callers that genuinely need to change a member's role should
-- use a dedicated role-change RPC (not this one).
-- ============================================================
CREATE OR REPLACE FUNCTION public.add_family_member(
  p_family_id text,
  p_user_id   text,
  p_role      text DEFAULT 'member'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO "FamilyMember" ("id", "familyId", "userId", "role", "joinedAt")
  VALUES (
    gen_random_uuid()::text,
    p_family_id,
    p_user_id,
    p_role,
    now()
  )
  ON CONFLICT ("familyId", "userId") DO NOTHING;

  -- Recount members for the family (always up-to-date after the upsert)
  UPDATE "Family"
  SET
    "memberCount"    = (SELECT COUNT(*) FROM "FamilyMember" WHERE "familyId" = p_family_id),
    "lastActivityAt" = now(),
    "updatedAt"      = now()
  WHERE "id" = p_family_id;
END;
$function$;

-- ============================================================
-- D. Backfill: family creators get role='owner'
-- ============================================================
-- The NestJS backend was creating FamilyMember rows with
-- role='admin' for family creators (should be 'owner').
-- This UPDATE corrects existing rows so the family creator
-- has the 'owner' role, matching the trigger's intent.
--
-- Only updates rows where the user IS the family creator AND
-- their current role is 'admin' (we don't downgrade 'owner'
-- to 'owner', and we don't touch non-creator members).
-- ============================================================
UPDATE public."FamilyMember" fm
SET role = 'owner',
    "joinedAt" = LEAST(fm."joinedAt", f."createdAt")
FROM public."Family" f
WHERE fm."familyId" = f.id
  AND fm."userId" = f."createdBy"
  AND fm.role = 'admin';

-- Verification (commented out — uncomment to run manually):
-- SELECT
--   (SELECT COUNT(*) FROM "FamilyMember" WHERE role = 'owner') AS owners,
--   (SELECT COUNT(*) FROM "FamilyMember" WHERE role = 'admin') AS admins,
--   (SELECT COUNT(*) FROM "FamilyMember" WHERE role = 'member') AS members;
-- Expected after migration: owners > 0, admins = 0 (for creator rows),
-- members = 0 or more (for invited members).
