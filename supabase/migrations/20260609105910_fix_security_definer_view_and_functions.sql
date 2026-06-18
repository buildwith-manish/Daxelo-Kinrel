-- ============================================================
-- Migration: fix_security_definer_view_and_functions
-- Version:  20260609105910
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- 1. Fix relationships view: use SECURITY INVOKER so RLS is respected per caller
DROP VIEW IF EXISTS "relationships";
CREATE VIEW "relationships"
  WITH (security_invoker = true)
AS
  SELECT id, "familyId", "fromPersonId", "toPersonId",
         "relationshipKey", "relationshipType", direction,
         "isActive", label, "verifiedAt", "createdAt", "updatedAt"
  FROM "Relationship";

-- 2. Fix get_my_family_ids: switch to SECURITY INVOKER + fixed search_path
CREATE OR REPLACE FUNCTION public.get_my_family_ids()
  RETURNS SETOF text
  LANGUAGE sql
  STABLE
  SECURITY INVOKER
  SET search_path = public
AS $$
  SELECT "familyId" FROM "FamilyMember" WHERE "userId" = (auth.uid())::text;
$$;

-- 3. Fix is_family_admin: switch to SECURITY INVOKER + fixed search_path
CREATE OR REPLACE FUNCTION public.is_family_admin(p_family_id text)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY INVOKER
  SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id
      AND "userId" = (auth.uid())::text
      AND role IN ('owner', 'admin')
  );
$$;

-- 4. Fix sync_family_photo_url trigger: add fixed search_path
CREATE OR REPLACE FUNCTION public.sync_family_photo_url()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public
AS $$
BEGIN
  IF NEW."avatarUrl" IS NOT NULL AND NEW."photoUrl" IS NULL THEN
    NEW."photoUrl" = NEW."avatarUrl";
  END IF;
  IF NEW."photoUrl" IS NOT NULL AND NEW."avatarUrl" IS NULL THEN
    NEW."avatarUrl" = NEW."photoUrl";
  END IF;
  RETURN NEW;
END;
$$;

-- 5. Revoke anon EXECUTE on the helper functions (authenticated users still work via SECURITY INVOKER)
REVOKE EXECUTE ON FUNCTION public.get_my_family_ids() FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_family_admin(text) FROM anon;
