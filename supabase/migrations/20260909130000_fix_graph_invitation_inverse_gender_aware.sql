-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260909130000_fix_graph_invitation_inverse_gender_aware
--
-- PURPOSE
-- Restore the gender-aware inverse-edge label in
-- `fn_accept_graph_invitation` that was dropped in the v5.183 fix
-- (migration 20260907190000_fix_fn_accept_graph_invitation.sql).
--
-- BACKGROUND
-- The v5.96 version (20260825010000_fix_invitation_rpc_record_case.sql)
-- had a gender-aware CASE for the inverse label:
--   CASE WHEN v_user_gender = 'female' THEN 'daughter' ELSE 'son' END
--   CASE WHEN v_user_gender = 'female' THEN 'mother' ELSE 'father' END
--   ... etc.
--
-- The v5.183 fix simplified the CASE to be gender-IGNORANT:
--   WHEN 'father' THEN 'son'   -- wrong for female accepters (should be 'daughter')
--   WHEN 'son' THEN 'father'   -- wrong for female accepters (should be 'mother')
--   ... etc.
--
-- The user's reported bug #2: "If Account 2 invites Account 1 and
-- Account 1 accepts, then when viewing the graph from Account 1,
-- Account 1 must be the anchor node ('You') and Account 2 must appear
-- as the connected relative. The graph should always render from the
-- perspective of the currently logged-in user."
--
-- When a female accepter accepts a 'father' invitation, the forward
-- edge is correct (labelAtoB='father'), but the inverse edge gets
-- labelAtoB='son' (should be 'daughter'). From the accepter's
-- perspective, the inviter appears as 'son' instead of 'father' —
-- wrong perspective for the inverse direction.
--
-- FIX
-- Replace the gender-ignorant CASE with the gender-aware version,
-- using `v_accepter_gender` (which is ALREADY declared and populated
-- in the v5.183 function at lines 57, 122-125, 137 — used for the
-- Person INSERT but NOT for the inverse-edge CASE).
--
-- The new CASE:
--   father/mother/parent → CASE WHEN female THEN 'daughter' ELSE 'son'
--   son/daughter/child   → CASE WHEN female THEN 'mother' ELSE 'father'
--   grandson/granddaughter/grandchild → CASE WHEN female THEN 'granddaughter' ELSE 'grandson'
--   grandfather/grandmother/grandparent → CASE WHEN female THEN 'grandmother' ELSE 'grandfather'
--   nephew/niece         → CASE WHEN female THEN 'niece' ELSE 'nephew'
--   uncle/aunt           → CASE WHEN female THEN 'aunt' ELSE 'uncle'
--   elder_brother/younger_brother → CASE WHEN female THEN ('elder_sister'/'younger_sister') ELSE same
--   elder_sister/younger_sister → CASE WHEN female THEN same ELSE ('elder_brother'/'younger_brother')
--   husband/wife/spouse → same (gender-symmetric)
--   brother/sister/sibling → CASE WHEN female THEN 'sister' ELSE 'brother'
--
-- SECURITY
-- This is a CREATE OR REPLACE FUNCTION — no schema changes, no data
-- migration. Existing accepted invitations are NOT retroactively
-- fixed (their inverse edges still have the gender-ignorant label);
-- only NEW acceptances get the correct gender-aware label. A
-- separate backfill script would be needed to fix historical data,
-- which is out of scope for this fix.
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_accept_graph_invitation(p_invitation_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_user_id uuid;
  v_invitation RECORD;
  v_person_id text;
  v_relationship_id text;
  v_inverse_relationship_id text;
  v_accepter_name text;
  v_accepter_avatar text;
  v_accepter_gender text;
  v_target_gender text;
  v_existing_person_id text;
  v_already_in_family boolean;
  v_inverse_key text;
  v_has_known_inverse boolean := false;
BEGIN
  -- ── Guard: authenticated caller ──
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Not authenticated'
    );
  END IF;

  -- ── Load invitation with row lock ──
  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE "id" = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Invitation not found'
    );
  END IF;

  -- ── Validate invitation state ──
  IF v_invitation."status" != 'pending' THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Invitation is not pending'
    );
  END IF;

  IF v_invitation."expiresAt" IS NOT NULL AND v_invitation."expiresAt" < now() THEN
    UPDATE "GraphPendingInvitation"
    SET "status" = 'expired'
    WHERE "id" = p_invitation_id;
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Invitation has expired'
    );
  END IF;

  -- ── Validate recipient ──
  IF v_invitation."recipientUserId" IS NULL OR
     v_invitation."recipientUserId"::text != v_user_id::text THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'This invitation is not for you'
    );
  END IF;

  -- ── Step 1: Person creation ──
  -- Check if a Person already exists for this user in this family
  SELECT id INTO v_existing_person_id
  FROM "Person"
  WHERE "familyId" = v_invitation."familyId"
    AND "linkedUserId" = v_user_id
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_existing_person_id IS NOT NULL THEN
    v_person_id := v_existing_person_id;
  ELSE
    -- Derive accepter name + avatar + gender from User table
    BEGIN
      SELECT name, "avatarUrl", gender
      INTO v_accepter_name, v_accepter_avatar, v_accepter_gender
      FROM "User" WHERE id = v_user_id;
    EXCEPTION WHEN OTHERS THEN
      v_accepter_name := 'Family Member';
      v_accepter_avatar := NULL;
    END;

    -- Also get gender if available
    BEGIN
      SELECT gender INTO v_accepter_gender FROM "User" WHERE id = v_user_id;
    EXCEPTION WHEN OTHERS THEN v_accepter_gender := NULL; END;

    IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
      v_accepter_name := 'Family Member';
    END IF;

    v_person_id := gen_random_uuid()::text;

    INSERT INTO "Person" (
      "id", "familyId", "name",
      "isAnchor", "generationIndex", "privacyLevel",
      "linkedUserId", "linkedAt",
      "photoUrl", "gender",
      "createdAt", "updatedAt"
    ) VALUES (
      v_person_id, v_invitation."familyId", v_accepter_name,
      false, 0, 'family',
      v_user_id, now(),
      v_accepter_avatar, v_accepter_gender,
      now(), now()
    );
  END IF;

  -- ── Step 2: FamilyMember (idempotent) ──
  INSERT INTO "FamilyMember" ("familyId", "userId", "role", "joinedAt")
  VALUES (v_invitation."familyId", v_user_id::text, 'member', now())
  ON CONFLICT ("familyId", "userId") DO NOTHING;

  -- ── Step 3: Forward Relationship (inviter → accepter) ──
  v_relationship_id := 'rel_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

  INSERT INTO "Relationship" (
    "id", "familyId",
    "fromPersonId", "toPersonId",
    "relationshipKey", "labelAtoB",
    "direction", "isActive",
    "createdAt", "updatedAt"
  ) VALUES (
    v_relationship_id, v_invitation."familyId",
    v_invitation."targetPersonId", v_person_id,
    v_invitation."relationshipKey", v_invitation."specificLabelAtoB",
    'from', true,
    now(), now()
  );

  -- ── Step 4: Inverse edge (best-effort, wrapped in BEGIN...EXCEPTION) ──
  -- v5.192: RESTORE gender-aware inverse label (was dropped in v5.183).
  -- `v_accepter_gender` is already populated above (from the User table).
  -- When the accepter's gender is female, use the female form of the
  -- inverse label; otherwise use the male form. NULL gender falls
  -- back to the male form (same as the v5.96 default).
  v_inverse_key := CASE
    WHEN v_invitation."specificLabelAtoB" IN ('father', 'mother', 'parent') THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'daughter' ELSE 'son' END
    WHEN v_invitation."specificLabelAtoB" IN ('son', 'daughter', 'child') THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'mother' ELSE 'father' END
    WHEN v_invitation."specificLabelAtoB" IN ('husband', 'wife', 'spouse') THEN
      v_invitation."specificLabelAtoB"
    WHEN v_invitation."specificLabelAtoB" IN ('brother', 'sister', 'sibling') THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'sister' ELSE 'brother' END
    WHEN v_invitation."specificLabelAtoB" = 'elder_brother' THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'elder_sister' ELSE 'younger_brother' END
    WHEN v_invitation."specificLabelAtoB" = 'younger_brother' THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'younger_sister' ELSE 'elder_brother' END
    WHEN v_invitation."specificLabelAtoB" = 'elder_sister' THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'younger_sister' ELSE 'elder_brother' END
    WHEN v_invitation."specificLabelAtoB" = 'younger_sister' THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'elder_sister' ELSE 'younger_brother' END
    WHEN v_invitation."specificLabelAtoB" IN ('grandfather', 'grandmother', 'grandparent') THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'granddaughter' ELSE 'grandson' END
    WHEN v_invitation."specificLabelAtoB" IN ('grandson', 'granddaughter', 'grandchild') THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'grandmother' ELSE 'grandfather' END
    WHEN v_invitation."specificLabelAtoB" IN ('uncle', 'aunt') THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'niece' ELSE 'nephew' END
    WHEN v_invitation."specificLabelAtoB" IN ('nephew', 'niece') THEN
      CASE WHEN v_accepter_gender = 'female' THEN 'aunt' ELSE 'uncle' END
    ELSE NULL
  END;

  IF v_inverse_key IS NOT NULL THEN
    v_has_known_inverse := true;
  END IF;

  -- FIX v5.183: Re-wrap in BEGIN...EXCEPTION so inverse-edge failure
  -- doesn't roll back the whole acceptance (best-effort, same as original)
  IF v_has_known_inverse THEN
    BEGIN
      v_inverse_relationship_id := 'rel_inv_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
      INSERT INTO "Relationship" (
        "id", "familyId",
        "fromPersonId", "toPersonId",
        "relationshipKey", "labelAtoB",
        "direction", "isActive",
        "createdAt", "updatedAt"
      ) VALUES (
        v_inverse_relationship_id, v_invitation."familyId",
        v_person_id, v_invitation."targetPersonId",
        v_invitation."relationshipKey",
        v_inverse_key,
        'inverse', true,
        now(), now()
      );
      RAISE NOTICE '[INVITE] Inverse relationship created: %', v_inverse_relationship_id;
    EXCEPTION WHEN OTHERS THEN
      v_inverse_relationship_id := NULL;
      RAISE NOTICE '[INVITE] Inverse relationship failed (best-effort, continuing): %', SQLERRM;
    END;
  END IF;

  -- ── Step 5: Update GraphPendingInvitation status ──
  UPDATE "GraphPendingInvitation"
  SET status = 'accepted',
      "acceptedAt" = now(),
      "acceptedByUserId" = v_user_id,
      "createdPersonId" = v_person_id,
      "createdRelationshipId" = v_relationship_id
  WHERE "id" = p_invitation_id;

  -- ── Step 6: Post a system chat message ──
  BEGIN
    INSERT INTO "ChatMessage" (
      "familyId", "senderId", "type", "message", "createdAt"
    ) VALUES (
      v_invitation."familyId", v_user_id, 'system',
      COALESCE(v_accepter_name, 'A family member') || ' joined the family.',
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[INVITE] Chat message insert failed (non-fatal): %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Invitation accepted successfully',
    'createdPersonId', v_person_id,
    'createdRelationshipId', v_relationship_id,
    'inverseRelationshipId', v_inverse_relationship_id
  );
END;
$function$;

COMMENT ON FUNCTION public.fn_accept_graph_invitation(text) IS
'v5.192: Restores gender-aware inverse-edge label (was dropped in v5.183). When the accepter is female, the inverse label uses the female form (daughter/mother/sister/etc.); otherwise the male form. v_accepter_gender is already populated from the User table at the top of the function.';

REVOKE EXECUTE ON FUNCTION public.fn_accept_graph_invitation(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_accept_graph_invitation(text) TO authenticated;
