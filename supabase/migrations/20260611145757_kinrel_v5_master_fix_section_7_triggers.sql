-- ============================================================
-- Migration: kinrel_v5_master_fix_section_7_triggers
-- Version:  20260611145757
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- SECTION 7: Triggers

-- [FIX-08] Auto-create FamilyMember when a Family is inserted
CREATE OR REPLACE FUNCTION _fn_after_family_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW."createdBy" IS NOT NULL THEN
    INSERT INTO "FamilyMember" ("id", "familyId", "userId", "role", "joinedAt")
    VALUES (
      gen_random_uuid()::text,
      NEW."id",
      NEW."createdBy",
      'owner',
      now()
    )
    ON CONFLICT ("familyId", "userId") DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "after_family_insert" ON "Family";
CREATE TRIGGER "after_family_insert"
  AFTER INSERT ON "Family"
  FOR EACH ROW
  EXECUTE FUNCTION _fn_after_family_insert();

-- [FIX-09] Atomic memberCount maintenance via trigger
CREATE OR REPLACE FUNCTION _fn_sync_member_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_family_id TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_family_id := OLD."familyId";
  ELSE
    v_family_id := NEW."familyId";
  END IF;

  UPDATE "Family"
  SET
    "memberCount"    = (
      SELECT COUNT(*) FROM "Person"
      WHERE "familyId" = v_family_id
        AND "deletedAt" IS NULL
    ),
    "lastActivityAt" = now(),
    "updatedAt"      = now()
  WHERE "id" = v_family_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "person_member_count" ON "Person";
CREATE TRIGGER "person_member_count"
  AFTER INSERT OR DELETE ON "Person"
  FOR EACH ROW
  EXECUTE FUNCTION _fn_sync_member_count();

CREATE OR REPLACE FUNCTION _fn_sync_member_count_on_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD."deletedAt" IS DISTINCT FROM NEW."deletedAt" THEN
    UPDATE "Family"
    SET
      "memberCount"    = (
        SELECT COUNT(*) FROM "Person"
        WHERE "familyId" = NEW."familyId"
          AND "deletedAt" IS NULL
      ),
      "lastActivityAt" = now(),
      "updatedAt"      = now()
    WHERE "id" = NEW."familyId";
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "person_member_count_update" ON "Person";
CREATE TRIGGER "person_member_count_update"
  AFTER UPDATE ON "Person"
  FOR EACH ROW
  EXECUTE FUNCTION _fn_sync_member_count_on_update();

-- [FIX-11] Auto-create public."User" row when Supabase Auth creates a new user
CREATE OR REPLACE FUNCTION _fn_handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO "User" (
    "id",
    "email",
    "name",
    "authProvider",
    "profileVisibility",
    "preferredLanguage",
    "role",
    "createdAt",
    "updatedAt"
  )
  VALUES (
    NEW.id::text,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_app_meta_data->>'provider', 'email'),
    'public',
    COALESCE(NEW.raw_user_meta_data->>'preferred_language', 'en'),
    'user',
    now(),
    now()
  )
  ON CONFLICT ("id") DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "on_auth_user_created" ON auth.users;
CREATE TRIGGER "on_auth_user_created"
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION _fn_handle_new_auth_user();
