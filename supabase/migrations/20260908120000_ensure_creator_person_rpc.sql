-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260908120000_ensure_creator_person_rpc
--
-- PURPOSE
-- Defensive backend RPC that ensures the family creator has a Person
-- node (isAnchor=true) in their family. This is a belt-and-suspenders
-- fallback for the case where the AFTER-INSERT trigger
-- `_fn_after_family_insert_create_anchor_person` (migration
-- 20260907120000) didn't fire or didn't create the Person for some
-- reason (e.g., the migration wasn't applied to a particular
-- environment, or the trigger errored silently).
--
-- The Flutter app calls this RPC from the family graph screen when it
-- detects a 0-member family AND the current user is the family creator.
-- The RPC is IDEMPOTENT — if the creator Person already exists, it
-- returns its ID without creating a duplicate.
--
-- BEHAVIOR
-- 1. Validates that the caller is authenticated (auth.uid() IS NOT NULL).
-- 2. Loads the Family row; validates that Family.createdBy == auth.uid().
--    (Only the creator can ensure their own anchor Person.)
-- 3. Checks if a Person with linkedUserId = auth.uid() AND familyId =
--    p_family_id already exists. If so, returns its ID (idempotent).
-- 4. Otherwise checks if ANY anchor Person exists for this family. If
--    so AND Family.createdBy == auth.uid(), returns that anchor ID
--    (the trigger created it but couldn't link it to the user — same
--    pattern as the v5.177 trigger and v5.177.1 RPC fix).
-- 5. Otherwise creates a new anchor Person with:
--    - name derived from auth.users metadata (same priority as the trigger)
--    - linkedUserId = auth.uid() IF the user has no other linked Person
--    - linkedUserId = NULL IF they already have a linked Person elsewhere
--      (respects the Person.linkedUserId UNIQUE-ish constraint — actually
--      the global unique index was dropped in v5.73, but we keep the
--      behavior for safety since the column still has a partial unique
--      index in some environments)
-- 6. Sets Family.anchorPersonId + memberCount (memberCount is also
--    maintained by _fn_sync_member_count trigger, but we set it
--    explicitly in case that trigger is also missing).
-- 7. Returns the Person ID + a flag indicating whether a NEW Person was
--    created (true) or an existing one was found (false).
--
-- SECURITY
-- SECURITY DEFINER + SET search_path = public — runs with the function
-- owner's privileges (postgres) so it can:
--   - Read auth.users for metadata
--   - INSERT into Person (bypassing RLS — the creator might not yet have
--     a FamilyMember row visible to RLS if the after-insert trigger
--     didn't fire)
--   - UPDATE Family.anchorPersonId / memberCount
--
-- The `p_family_id IS NULL` and `auth.uid() IS NULL` guards return a
-- clean error structure rather than throwing, so the Flutter app can
-- parse the response uniformly.
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_ensure_creator_person(p_family_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_user_id uuid;
  v_family_created_by text;
  v_existing_linked_id text;
  v_existing_anchor_id text;
  v_existing_anchor_linked uuid;
  v_already_linked_count int;
  v_can_link boolean;
  v_person_id text;
  v_meta jsonb;
  v_email text;
  v_creator_name text;
  v_creator_gender text;
  v_created boolean;
BEGIN
  -- ── Guard: authenticated caller ──
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Not authenticated',
      'personId', null,
      'created', false
    );
  END IF;

  -- ── Guard: family exists ──
  BEGIN
    SELECT "createdBy" INTO v_family_created_by
    FROM "Family"
    WHERE "id" = p_family_id;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Family not found',
      'personId', null,
      'created', false
    );
  END;

  IF v_family_created_by IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Family not found',
      'personId', null,
      'created', false
    );
  END IF;

  -- ── Guard: caller is the family creator ──
  IF v_family_created_by != v_user_id::text THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Only the family creator can ensure their anchor Person',
      'personId', null,
      'created', false
    );
  END IF;

  -- ── Step 1: Check if a Person with linkedUserId = caller already exists ──
  SELECT id INTO v_existing_linked_id
  FROM "Person"
  WHERE "familyId" = p_family_id
    AND "linkedUserId" = v_user_id
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_existing_linked_id IS NOT NULL THEN
    -- Person already exists and is linked — just ensure anchorPersonId is set
    UPDATE "Family"
    SET "anchorPersonId" = COALESCE("anchorPersonId", v_existing_linked_id),
        "lastActivityAt" = now()
    WHERE "id" = p_family_id;
    RETURN jsonb_build_object(
      'ok', true,
      'personId', v_existing_linked_id,
      'created', false,
      'source', 'linked'
    );
  END IF;

  -- ── Step 2: Check if an anchor Person already exists (linkedUserId might be NULL) ──
  SELECT id, "linkedUserId" INTO v_existing_anchor_id, v_existing_anchor_linked
  FROM "Person"
  WHERE "familyId" = p_family_id
    AND "isAnchor" = true
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_existing_anchor_id IS NOT NULL THEN
    -- Anchor exists. If its linkedUserId is NULL, try to link it to the caller
    -- (only if the caller has no other linked Person).
    IF v_existing_anchor_linked IS NULL THEN
      SELECT count(*) INTO v_already_linked_count
      FROM "Person"
      WHERE "linkedUserId" = v_user_id
        AND "familyId" != p_family_id
        AND "deletedAt" IS NULL;
      IF v_already_linked_count = 0 THEN
        UPDATE "Person"
        SET "linkedUserId" = v_user_id
        WHERE "id" = v_existing_anchor_id;
      END IF;
    END IF;
    -- Ensure Family.anchorPersonId is set
    UPDATE "Family"
    SET "anchorPersonId" = COALESCE("anchorPersonId", v_existing_anchor_id),
        "lastActivityAt" = now()
    WHERE "id" = p_family_id;
    RETURN jsonb_build_object(
      'ok', true,
      'personId', v_existing_anchor_id,
      'created', false,
      'source', 'anchor'
    );
  END IF;

  -- ── Step 3: No Person exists — create one from scratch ──
  -- Derive name + gender from auth.users metadata (same priority as the trigger)
  SELECT raw_user_meta_data, email INTO v_meta, v_email
  FROM auth.users
  WHERE id = v_user_id;

  v_creator_name := COALESCE(
    NULLIF(v_meta->>'full_name', ''),
    NULLIF(v_meta->>'name', ''),
    NULLIF(v_meta->>'user_name', ''),
    NULLIF(v_meta->>'username', ''),
    CASE WHEN v_email IS NOT NULL AND v_email != '' THEN split_part(v_email, '@', 1) END,
    'Family Member'
  );

  v_creator_gender := NULLIF(v_meta->>'gender', '');

  -- Check if the user already has a linked Person in ANOTHER family
  -- (same logic as the trigger — respects the link uniqueness intent)
  SELECT count(*) INTO v_already_linked_count
  FROM "Person"
  WHERE "linkedUserId" = v_user_id
    AND "familyId" != p_family_id
    AND "deletedAt" IS NULL;

  v_can_link := (v_already_linked_count = 0);

  v_person_id := gen_random_uuid()::text;

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
    p_family_id,
    v_creator_name,
    true,
    'family',
    0,
    CASE WHEN v_can_link THEN v_user_id ELSE NULL END,
    v_creator_gender
  );

  -- Set Family.anchorPersonId + memberCount
  UPDATE "Family"
  SET "anchorPersonId" = v_person_id,
      "memberCount" = GREATEST(COALESCE("memberCount", 0), 1),
      "lastActivityAt" = now()
  WHERE "id" = p_family_id;

  v_created := true;

  RETURN jsonb_build_object(
    'ok', true,
    'personId', v_person_id,
    'created', v_created,
    'source', 'created',
    'linkedToUser', v_can_link
  );
END;
$function$;

-- Permissions: any authenticated user can call this (the function self-
-- guards via the creator check). No GRANT needed — PUBLIC is the
-- default for SECURITY DEFINER functions in the public schema, but we
-- REVOKE then GRANT EXECUTE to be explicit and to avoid accidental
-- exposure to the anon role.
REVOKE EXECUTE ON FUNCTION public.fn_ensure_creator_person(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_ensure_creator_person(text) TO authenticated;

COMMENT ON FUNCTION public.fn_ensure_creator_person(text) IS
'v5.191: Defensive RPC that ensures the family creator has an anchor Person node. Idempotent. Called by the Flutter app when the graph screen detects a 0-member family and the current user is the family creator (the AFTER-INSERT trigger may not have fired — e.g., migration not applied). Returns {ok, personId, created, source}.';
