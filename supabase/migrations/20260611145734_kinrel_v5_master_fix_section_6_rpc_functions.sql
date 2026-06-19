-- ============================================================
-- Migration: kinrel_v5_master_fix_section_6_rpc_functions
-- Version:  20260611145734
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- Drop existing functions first to allow return type changes
DROP FUNCTION IF EXISTS add_family_member(TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS restore_family(TEXT);
DROP FUNCTION IF EXISTS delete_family_forever(TEXT);
DROP FUNCTION IF EXISTS has_family_role(TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION add_family_member(
  p_family_id TEXT,
  p_user_id   TEXT,
  p_role      TEXT DEFAULT 'member'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO "FamilyMember" ("id", "familyId", "userId", "role", "joinedAt")
  VALUES (
    gen_random_uuid()::text,
    p_family_id,
    p_user_id,
    p_role,
    now()
  )
  ON CONFLICT ("familyId", "userId")
  DO UPDATE SET "role" = EXCLUDED."role";

  UPDATE "Family"
  SET
    "memberCount"    = (SELECT COUNT(*) FROM "FamilyMember" WHERE "familyId" = p_family_id),
    "lastActivityAt" = now(),
    "updatedAt"      = now()
  WHERE "id" = p_family_id;
END;
$$;

CREATE OR REPLACE FUNCTION restore_family(p_family_id TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "Family"
    WHERE "id" = p_family_id
      AND (
        "createdBy" = auth.uid()::text
        OR "id" IN (
          SELECT "familyId" FROM "FamilyMember"
          WHERE "userId" = auth.uid()::text
            AND "role" IN ('owner', 'admin')
        )
      )
  ) THEN
    RAISE EXCEPTION 'Permission denied: not the owner or admin of this family';
  END IF;

  UPDATE "Family"
  SET
    "deletedAt"      = NULL,
    "lastActivityAt" = now(),
    "updatedAt"      = now()
  WHERE "id" = p_family_id;

  UPDATE "Person"
  SET
    "deletedAt"  = NULL,
    "updatedAt"  = now()
  WHERE "familyId" = p_family_id
    AND "deletedAt" IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION delete_family_forever(p_family_id TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "Family"
    WHERE "id" = p_family_id
      AND (
        "createdBy" = auth.uid()::text
        OR "id" IN (
          SELECT "familyId" FROM "FamilyMember"
          WHERE "userId" = auth.uid()::text
            AND "role" = 'owner'
        )
      )
  ) THEN
    RAISE EXCEPTION 'Permission denied: only the owner can permanently delete a family';
  END IF;

  DELETE FROM "Family" WHERE "id" = p_family_id;
END;
$$;

CREATE OR REPLACE FUNCTION has_family_role(
  p_user_id      TEXT,
  p_family_id    TEXT,
  p_minimum_role TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role       TEXT;
  v_user_w     INT;
  v_min_w      INT;
BEGIN
  v_min_w := CASE p_minimum_role
    WHEN 'owner'  THEN 4
    WHEN 'admin'  THEN 3
    WHEN 'member' THEN 2
    WHEN 'viewer' THEN 1
    ELSE 0
  END;

  SELECT "role" INTO v_role
  FROM "FamilyMember"
  WHERE "userId" = p_user_id AND "familyId" = p_family_id
  LIMIT 1;

  IF v_role IS NULL THEN
    IF EXISTS (SELECT 1 FROM "Family" WHERE "id" = p_family_id AND "createdBy" = p_user_id) THEN
      v_role := 'owner';
    ELSE
      RETURN FALSE;
    END IF;
  END IF;

  v_user_w := CASE v_role
    WHEN 'owner'  THEN 4
    WHEN 'admin'  THEN 3
    WHEN 'member' THEN 2
    WHEN 'viewer' THEN 1
    ELSE 0
  END;

  RETURN v_user_w >= v_min_w;
END;
$$;
