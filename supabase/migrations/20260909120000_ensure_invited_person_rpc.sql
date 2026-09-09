-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260909120000_ensure_invited_person_rpc
--
-- PURPOSE
-- Defensive backend RPC that ensures an INVITED user (who accepted a
-- family invitation via the legacy NestJS `/api/invitations/:id/accept`
-- endpoint, which creates a FamilyMember row but NOT a Person row) has
-- a Person node in the family graph.
--
-- BACKGROUND
-- The legacy `invitations.service.ts:acceptInvitation` (NestJS) ONLY
-- creates a FamilyMember + increments Family.memberCount. It does NOT
-- create a Person row. So a user accepting via this legacy path has
-- NO Person node in the family graph — they're a FamilyMember but
-- not a graph node.
--
-- The consequence (the user's reported bug #3): when this user opens
-- the family graph, `viewerPersonIdProvider` Step 1 (linked Person
-- lookup) returns empty, Step 3 (anchor fallback) returns null (the
-- anchor belongs to the family creator, not them), and
-- `viewerPersonId` is null → `ClaimProfileBanner` fires ("Tap to
-- claim your profile — you're viewing as the family anchor") even
-- though the user has already accepted and is a family member.
--
-- The newer graph-invite path (`fn_accept_graph_invitation`) DOES
-- create a Person with `linkedUserId = auth.uid()`, so users who
-- accept via that path don't hit this bug. This RPC is the defensive
-- fallback for users who accepted via the legacy path.
--
-- BEHAVIOR
-- 1. Validates that the caller is authenticated (auth.uid() IS NOT NULL).
-- 2. Validates that the caller is a FamilyMember of p_family_id (the
--    legacy acceptance path creates this row; if it's missing, the
--    user hasn't accepted yet — return an error so we don't create a
--    Person for a non-member).
-- 3. Checks if a Person with linkedUserId = auth.uid() AND familyId =
--    p_family_id already exists. If so, returns its ID (idempotent).
-- 4. Otherwise creates a new Person with:
--    - isAnchor = FALSE (the family creator is the anchor; the invited
--      user is a regular member)
--    - name derived from auth.users metadata (same priority as the
--      v5.177 trigger: full_name → name → user_name → username →
--      email prefix → "Family Member")
--    - linkedUserId = auth.uid()
--    - linkedAt = now()
--    - gender from auth.users metadata if present
-- 5. Returns {ok, personId, created, source}.
--
-- SECURITY
-- SECURITY DEFINER + SET search_path = public — runs with the
-- function owner's privileges (postgres) so it can:
--   - Read auth.users (for metadata)
--   - Read FamilyMember (to verify membership)
--   - INSERT into Person (bypassing RLS — the caller's RLS check
--     might not yet see the FamilyMember row created by the legacy
--     NestJS path in a separate transaction)
--
-- Idempotent — safe to call multiple times. REVOKE from PUBLIC/anon,
-- GRANT to authenticated.
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_ensure_invited_person(p_family_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_user_id uuid;
  v_existing_id text;
  v_is_member boolean;
  v_meta jsonb;
  v_email text;
  v_name text;
  v_gender text;
  v_person_id text;
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

  -- ── Guard: caller is a FamilyMember of this family ──
  -- The legacy NestJS acceptance path creates this row; if it's
  -- missing, the user hasn't actually accepted — return an error so
  -- we don't create a Person for a non-member (which would let
  -- arbitrary authenticated users inject themselves into any family's
  -- graph).
  SELECT EXISTS(
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id
      AND "userId" = v_user_id::text
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Not a member of this family — accept the invitation first',
      'personId', null,
      'created', false
    );
  END IF;

  -- ── Step 1: Check if a Person with linkedUserId = caller already exists ──
  SELECT id INTO v_existing_id
  FROM "Person"
  WHERE "familyId" = p_family_id
    AND "linkedUserId" = v_user_id
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    -- Person already exists — idempotent return
    RETURN jsonb_build_object(
      'ok', true,
      'personId', v_existing_id,
      'created', false,
      'source', 'linked'
    );
  END IF;

  -- ── Step 2: No Person exists — create one ──
  -- Derive name + gender from auth.users metadata (same priority as
  -- the v5.177 trigger: full_name → name → user_name → username →
  -- email prefix → "Family Member")
  SELECT raw_user_meta_data, email INTO v_meta, v_email
  FROM auth.users
  WHERE id = v_user_id;

  v_name := COALESCE(
    NULLIF(v_meta->>'full_name', ''),
    NULLIF(v_meta->>'name', ''),
    NULLIF(v_meta->>'user_name', ''),
    NULLIF(v_meta->>'username', ''),
    CASE WHEN v_email IS NOT NULL AND v_email != '' THEN split_part(v_email, '@', 1) END,
    'Family Member'
  );

  v_gender := NULLIF(v_meta->>'gender', '');

  v_person_id := gen_random_uuid()::text;

  INSERT INTO "Person" (
    "id",
    "familyId",
    "name",
    "isAnchor",
    "privacyLevel",
    "generationIndex",
    "linkedUserId",
    "linkedAt",
    "gender",
    "createdAt",
    "updatedAt"
  ) VALUES (
    v_person_id,
    p_family_id,
    v_name,
    false,  -- invited users are NOT the anchor (the family creator is)
    'family',
    0,
    v_user_id,
    now(),
    v_gender,
    now(),
    now()
  );

  v_created := true;

  RETURN jsonb_build_object(
    'ok', true,
    'personId', v_person_id,
    'created', v_created,
    'source', 'created'
  );
END;
$function$;

-- Permissions: any authenticated user can call this (the function self-
-- guards via the FamilyMember check). REVOKE from PUBLIC/anon to avoid
-- accidental exposure to the anon role.
REVOKE EXECUTE ON FUNCTION public.fn_ensure_invited_person(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_ensure_invited_person(text) TO authenticated;

COMMENT ON FUNCTION public.fn_ensure_invited_person(text) IS
'v5.192: Defensive RPC that ensures an INVITED user (who accepted via the legacy NestJS /api/invitations/:id/accept endpoint, which creates a FamilyMember but NOT a Person) has a Person node with linkedUserId = auth.uid() in the family graph. Idempotent. Guards: authenticated + FamilyMember of p_family_id. Returns {ok, personId, created, source}.';
