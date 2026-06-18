-- ============================================================
-- Migration: fix_family_creator_membership_and_sparq_rls
-- Version:  20260616162005
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- 1) Backfill: ensure every Family.createdBy who still exists as a User
--    has a corresponding FamilyMember row (role=owner), so graph/RLS access
--    does not depend solely on the createdBy fallback clause.
INSERT INTO "FamilyMember" (id, "familyId", "userId", role, "joinedAt")
SELECT
  gen_random_uuid()::text,
  f.id,
  f."createdBy",
  'owner',
  now()
FROM "Family" f
JOIN "User" u ON u.id = f."createdBy"
WHERE f."createdBy" IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM "FamilyMember" fm
    WHERE fm."familyId" = f.id AND fm."userId" = f."createdBy"
  );

-- 2) Trigger: auto-enroll the creator as an owner FamilyMember whenever a
--    new Family row is inserted, so this gap cannot reopen going forward.
CREATE OR REPLACE FUNCTION public.enroll_family_creator()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW."createdBy" IS NOT NULL THEN
    INSERT INTO "FamilyMember" (id, "familyId", "userId", role, "joinedAt")
    VALUES (gen_random_uuid()::text, NEW.id, NEW."createdBy", 'owner', now())
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enroll_family_creator ON "Family";
CREATE TRIGGER trg_enroll_family_creator
AFTER INSERT ON "Family"
FOR EACH ROW
EXECUTE FUNCTION public.enroll_family_creator();

-- 3) Security: enable RLS on SparqEcho (currently fully exposed) and add
--    policies matching the access pattern used by the related Sparq table.
ALTER TABLE public."SparqEcho" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sparq_echo_select_all_authenticated"
ON public."SparqEcho"
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "sparq_echo_insert_own"
ON public."SparqEcho"
FOR INSERT
TO authenticated
WITH CHECK ("userId" = (auth.uid())::text);

CREATE POLICY "sparq_echo_delete_own"
ON public."SparqEcho"
FOR DELETE
TO authenticated
USING ("userId" = (auth.uid())::text);

-- 4) Cleanup: remove the redundant/narrower "_family_member" policy set on
--    Relationship that duplicates relationship_select/insert/update/delete
--    but omits the createdBy fallback (confusing, not a security hole since
--    policies are OR'd, but a maintenance hazard flagged in the audit).
DROP POLICY IF EXISTS "relationship_select_family_member" ON "Relationship";
DROP POLICY IF EXISTS "relationship_insert_family_member" ON "Relationship";
DROP POLICY IF EXISTS "relationship_update_family_member" ON "Relationship";
DROP POLICY IF EXISTS "relationship_delete_family_member" ON "Relationship";
