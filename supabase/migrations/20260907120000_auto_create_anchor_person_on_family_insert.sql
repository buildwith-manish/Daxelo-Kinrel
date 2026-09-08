-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260907120000_auto_create_anchor_person_on_family_insert
--
-- PURPOSE
-- When a user creates a new family, atomically create the creator's
-- Person record (isAnchor=true) so the family graph never starts empty.
-- This eliminates the "silent failure" window where the Flutter app's
-- post-INSERT Person creation could fail (timeout, RLS, network) and
-- leave the family with 0 Person records, triggering the
-- "Start your family tree" empty state.
--
-- BEHAVIOR
-- 1. Fires AFTER INSERT on "Family" (runs after _fn_after_family_insert
--    which creates the FamilyMember with role='owner').
-- 2. Idempotent: if a Person with linkedUserId=NEW.createdBy AND
--    familyId=NEW.id already exists, does nothing (just ensures
--    anchorPersonId is set).
-- 3. Derives the creator's display name from auth.users metadata:
--    full_name → name → user_name → username → email prefix → "Family Member"
-- 4. Checks if the user already has a linked Person in ANOTHER family
--    (Person.linkedUserId has a UNIQUE constraint). If so, creates the
--    new Person WITHOUT linkedUserId (still the anchor, just not "claimed"
--    as the user's primary identity — the user can claim it later via
--    the Person Link flow).
-- 5. Sets Family.anchorPersonId to the new Person's ID.
--    (Family.memberCount is maintained by _fn_sync_member_count trigger
--    which fires on Person INSERT.)
--
-- SECURITY
-- SECURITY DEFINER + SET search_path = public — runs with the function
-- owner's privileges (postgres), so it can:
--   - Read auth.users (to get the creator's metadata)
--   - INSERT into Person (bypassing RLS — the creator's RLS check
--     might not yet see the FamilyMember row created by the prior
--     trigger in the same transaction)
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION _fn_after_family_insert_create_anchor_person()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_creator_id text;
  -- v_creator_id is text (from Family.createdBy which is text), but
  -- Person.linkedUserId is uuid. We need to cast when comparing.
  v_creator_uuid uuid;
  v_person_id text;
  v_existing_person_id text;
  v_meta jsonb;
  v_email text;
  v_creator_name text;
  v_creator_gender text;
  v_already_linked_count int;
  v_can_link boolean;
BEGIN
  -- Only proceed if createdBy is set
  IF NEW."createdBy" IS NULL THEN
    RETURN NEW;
  END IF;

  v_creator_id := NEW."createdBy";

  -- Cast text → uuid for comparisons with linkedUserId
  -- (Family.createdBy is text, Person.linkedUserId is uuid)
  BEGIN
    v_creator_uuid := v_creator_id::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    -- createdBy is not a valid UUID — can't link to auth user
    RETURN NEW;
  END;

  -- ── Idempotency check: does a Person already exist for this user
  -- in this family? ──
  SELECT id INTO v_existing_person_id
  FROM "Person"
  WHERE "familyId" = NEW."id"
    AND "linkedUserId" = v_creator_uuid
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_existing_person_id IS NOT NULL THEN
    -- Person already exists — just ensure anchorPersonId is set
    IF NEW."anchorPersonId" IS NULL THEN
      UPDATE "Family"
      SET "anchorPersonId" = v_existing_person_id,
          "lastActivityAt" = now()
      WHERE "id" = NEW."id";
    END IF;
    RETURN NEW;
  END IF;

  -- ── Derive name + gender from auth.users metadata ──
  SELECT raw_user_meta_data, email INTO v_meta, v_email
  FROM auth.users
  WHERE id = v_creator_id::uuid;

  -- Name priority: full_name → name → user_name → username → email prefix → default
  v_creator_name := COALESCE(
    NULLIF(v_meta->>'full_name', ''),
    NULLIF(v_meta->>'name', ''),
    NULLIF(v_meta->>'user_name', ''),
    NULLIF(v_meta->>'username', ''),
    CASE WHEN v_email IS NOT NULL AND v_email != '' THEN split_part(v_email, '@', 1) END,
    'Family Member'
  );

  v_creator_gender := NULLIF(v_meta->>'gender', '');

  -- ── Check if user already has a linked Person in ANOTHER family ──
  -- Person.linkedUserId has a UNIQUE constraint — a user can only be
  -- "linked" to ONE Person across ALL families. If they already have
  -- a linked Person elsewhere, we create the new Person WITHOUT
  -- linkedUserId (still the anchor, just not "claimed").
  SELECT count(*) INTO v_already_linked_count
  FROM "Person"
  WHERE "linkedUserId" = v_creator_uuid
    AND "familyId" != NEW."id"
    AND "deletedAt" IS NULL;

  v_can_link := (v_already_linked_count = 0);

  -- ── Generate Person ID ──
  v_person_id := gen_random_uuid()::text;

  -- ── Insert the anchor Person ──
  -- linkedUserId is uuid, so we pass v_creator_uuid (not v_creator_id text)
  INSERT INTO "Person" (
    "id",
    "familyId",
    "name",
    "isAnchor",
    "privacyLevel",
    "generationIndex",
    "linkedUserId",
    "gender"
  ) VALUES (
    v_person_id,
    NEW."id",
    v_creator_name,
    true,
    'family',
    0,
    CASE WHEN v_can_link THEN v_creator_uuid ELSE NULL END,
    v_creator_gender
  );

  -- ── Set Family.anchorPersonId ──
  -- (memberCount is maintained by _fn_sync_member_count trigger
  -- which fires on Person INSERT — no need to set it here.)
  UPDATE "Family"
  SET "anchorPersonId" = v_person_id,
      "lastActivityAt" = now()
  WHERE "id" = NEW."id";

  RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists (idempotent migration)
DROP TRIGGER IF EXISTS "after_family_insert_create_anchor_person" ON "Family";

-- Create the trigger — AFTER INSERT so it runs after _fn_after_family_insert
-- (which creates the FamilyMember). Trigger name starts with 'after_family_insert_create_'
-- which sorts AFTER 'after_family_insert' alphabetically, ensuring the
-- FamilyMember is created first (though order doesn't strictly matter
-- since this function uses SECURITY DEFINER and bypasses RLS).
CREATE TRIGGER "after_family_insert_create_anchor_person"
  AFTER INSERT ON "Family"
  FOR EACH ROW
  EXECUTE FUNCTION _fn_after_family_insert_create_anchor_person();

-- ── Verification comment ──
-- After this migration:
-- 1. User creates a family → Family INSERT fires
-- 2. _fn_after_family_insert trigger creates FamilyMember (role='owner')
-- 3. _fn_after_family_insert_create_anchor_person trigger creates Person (isAnchor=true)
-- 4. Person INSERT fires _fn_sync_member_count → Family.memberCount = 1
-- 5. Family.anchorPersonId is set to the new Person's ID
--
-- Result: family starts with 1 member (the creator), graph shows the
-- creator as the anchor node, empty state is never shown for a freshly
-- created family.
