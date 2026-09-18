-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260909150000_fix_inverse_label_target_gender_and_bfs_cap
--
-- PURPOSE
-- Fix three remaining bugs that the previous migrations
-- (20260909130000 and 20260909140000) did NOT fully address:
--
--   BUG A — Inverse label uses the WRONG gender variable.
--     The v5.192 migration (20260909130000) restored the gender-aware
--     inverse CASE that the v5.183 simplification had dropped, BUT
--     it used `v_accepter_gender` (the accepter's gender) to compute
--     the inverse label. Per the canonical convention:
--       Forward edge: from=target, to=newPerson, labelAtoB='father'
--         → "newPerson is target's father"
--       Inverse edge: from=newPerson, to=target, labelAtoB=?
--         → "target is newPerson's <inverse>"
--     The inverse label describes the TARGET's role relative to the
--     newPerson. It therefore depends on the TARGET's gender, NOT
--     the accepter's. The v5.192 migration has the variable mix-up
--     documented in its own comment but never corrected.
--     v_target_gender is declared (line 75 of the v5.192 function)
--     but NEVER assigned. This migration fetches it from the Person
--     table and uses it in the inverse CASE.
--
--   BUG B — No gender-neutral fallback.
--     When the target's gender is NULL (the common case for newly-
--     created anchor Persons), the v5.192 CASE falls through to the
--     'ELSE' branch and returns the male form ('son' for 'father',
--     'brother' for 'sibling', etc.). This stores a gender-assumption
--     that may be wrong. This migration adds a third branch that
--     returns the gender-neutral form ('child', 'parent', 'sibling',
--     'grandchild', 'grandparent', 'nibling') when the target's
--     gender is unknown.
--
--   BUG C — BFS depth cap of 3 hides eligible relatives.
--     `get_viewer_family_graph` (migration 20260907130000) caps the
--     proximity BFS at `bfs.bfs_depth < 3` — only persons within 3
--     hops of the viewer are candidates. The user's report:
--     "The node visibility rule should only apply when the graph
--     exceeds the configured limit (e.g., more than 50 visible
--     nodes); otherwise, all eligible nodes should remain visible
--     and connected correctly."
--     The 50-node LIMIT is the only cap that should bind on small
--     graphs. The depth cap silently hides relatives at distance 4+
--     (e.g., a cousin's child, a great-great-grandparent) even when
--     the family has only 20 members. This migration raises the
--     depth cap to 10 (effectively no cap for typical family trees,
--     but still prevents runaway recursion on cyclic graphs).
--
--   BUG D — Existing inverse labels are wrong.
--     The backfill migration 20260909140000 re-pointed cross-family
--     edges to the correct Person but did NOT recompute the inverse
--     `labelAtoB`. Existing accepted invitations still have the
--     v5.183/v5.192 wrong label ('son' when the target's gender is
--     unknown, should be 'child'). This migration recomputes the
--     inverse label for all edges created by
--     `fn_accept_graph_invitation` (id prefix 'rel_inv_') based on
--     the toPerson's (target's) gender.
--
-- STRATEGY
-- 1. CREATE OR REPLACE `fn_accept_graph_invitation` with:
--    - The v5.192 familyId-scoped Person lookup (no global fallback).
--    - A new `SELECT gender INTO v_target_gender FROM "Person"`
--      query near the top of the function.
--    - A rewritten inverse CASE that uses `v_target_gender` and has
--      a gender-neutral fallback.
--    - The v5.183 chat-message + notification + read-marking side
--      effects preserved verbatim.
-- 2. CREATE OR REPLACE `get_viewer_family_graph` with:
--    - `bfs.bfs_depth < 10` (was `< 3`).
--    - All other logic unchanged.
-- 3. Data backfill: for every `Relationship` row with `direction =
--    'inverse'` AND `id LIKE 'rel_inv_%'`, recompute `labelAtoB`
--    from the corresponding forward edge's `labelAtoB` and the
--    toPerson's gender, using the same CASE logic.
--
-- SECURITY
-- This is a CREATE OR REPLACE FUNCTION + a data UPDATE. No schema
-- changes. The data UPDATE is idempotent (re-running it produces
-- the same labels). The function is SECURITY DEFINER with the same
-- grants as before.
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────────
-- 1. Fixed fn_accept_graph_invitation
-- ────────────────────────────────────────────────────────────────────

-- v5.193: DROP first because the previous version (v5.183) had RETURNS json
-- and we're changing it to RETURNS jsonb. PostgreSQL doesn't allow changing
-- the return type via CREATE OR REPLACE alone.
DROP FUNCTION IF EXISTS public.fn_accept_graph_invitation(text) CASCADE;

CREATE OR REPLACE FUNCTION public.fn_accept_graph_invitation(p_invitation_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_invitation "GraphPendingInvitation"%ROWTYPE;
  v_user_id text := auth.uid()::text;
  v_existing_person text;
  v_person_id text;
  v_member_id text;
  v_relationship_id text;
  v_inverse_relationship_id text;
  v_inverse_key text;
  v_has_known_inverse boolean := false;
  v_inviter_name text;
  v_target_name text;
  v_accepter_name text;
  v_notif_id text;
  v_chat_msg_id text;
  v_target_gender text;
  v_accepter_gender text;
  v_accepter_avatar text;
BEGIN
  RAISE NOTICE '[INVITE] Accept started — invitationId=%', p_invitation_id;

  -- Step 0: Load the invitation
  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
    AND "expiresAt" > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE NOTICE '[INVITE ERROR] Invitation not found or expired';
    RETURN jsonb_build_object('success', false, 'error', 'Invitation not found or expired');
  END IF;

  IF v_invitation.status != 'pending' THEN
    RAISE NOTICE '[INVITE ERROR] Invitation already %', v_invitation.status;
    RETURN jsonb_build_object('success', false, 'error', 'Invitation already ' || v_invitation.status);
  END IF;

  IF v_user_id IS NULL THEN
    RAISE NOTICE '[INVITE ERROR] Not authenticated';
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- v5.43: If recipientUserId is set, verify the caller matches
  IF v_invitation."recipientUserId" IS NOT NULL
     AND v_invitation."recipientUserId" != '' THEN
    IF v_user_id != v_invitation."recipientUserId" THEN
      RAISE NOTICE '[INVITE ERROR] Caller % does not match recipientUserId %', v_user_id, v_invitation."recipientUserId";
      RETURN jsonb_build_object('success', false, 'error', 'This invitation was sent to a different user');
    END IF;
  END IF;

  RAISE NOTICE '[INVITE] Invitation loaded — familyId=%, targetPersonId=%, relationshipKey=%, specificLabelAtoB=%',
    v_invitation."familyId", v_invitation."targetPersonId", v_invitation."relationshipKey", v_invitation."specificLabelAtoB";

  -- v5.193 (BUG A FIX): Fetch the TARGET's gender up front. The
  -- inverse label describes the target's role relative to the
  -- newPerson, so it depends on the TARGET's gender, not the
  -- accepter's. v_target_gender is used in the inverse CASE below.
  -- The v5.192 version declared this variable but never assigned
  -- it — a dead-code bug that caused the CASE to use the wrong
  -- variable (v_accepter_gender).
  BEGIN
    SELECT gender INTO v_target_gender
    FROM "Person"
    WHERE id = v_invitation."targetPersonId"
      AND "deletedAt" IS NULL
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_target_gender := NULL;
  END;
  RAISE NOTICE '[INVITE] Target gender resolved: %', v_target_gender;

  -- Step 1: Create or reuse Person node — SCOPED to the invitation's
  -- family. The v5.183 "global fallback" (checking by linkedUserId
  -- alone, ignoring familyId) was the root cause of the cross-family
  -- edge bug — it reused a Person from ANOTHER family. The unique
  -- constraint is on (familyId, linkedUserId), so a user CAN have
  -- linked Persons in multiple families. This lookup MUST stay
  -- scoped to the invitation's family.
  SELECT id INTO v_existing_person
  FROM "Person"
  WHERE "familyId" = v_invitation."familyId"
    AND "linkedUserId" = v_user_id::uuid
    AND "deletedAt" IS NULL
  LIMIT 1;
  -- v5.193: REMOVED the global fallback that was here in v5.183.
  -- Do NOT re-add it — the unique constraint allows multi-family
  -- linked Persons, and the global fallback breaks cross-family
  -- invitation acceptance.

  IF v_existing_person IS NULL THEN
    v_person_id := 'person_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);

    SELECT name, "avatarUrl" INTO v_accepter_name, v_accepter_avatar
    FROM "User" WHERE id = v_user_id;
    IF v_accepter_name IS NULL OR v_accepter_name = '' THEN
      v_accepter_name := COALESCE(v_invitation."recipientName", 'New Member');
    END IF;

    -- Also get the accepter's gender (used for the Person INSERT
    -- below; NOT used for the inverse CASE — see BUG A above).
    BEGIN
      SELECT gender INTO v_accepter_gender FROM "User" WHERE id = v_user_id;
    EXCEPTION WHEN OTHERS THEN v_accepter_gender := NULL; END;

    INSERT INTO "Person" (
      "id", "familyId", "name",
      "isAnchor", "generationIndex", "privacyLevel",
      "linkedUserId", "linkedAt",
      "photoUrl", "gender",
      "createdAt", "updatedAt"
    ) VALUES (
      v_person_id, v_invitation."familyId", v_accepter_name,
      false, 0, 'family',
      v_user_id::uuid, now(),
      v_accepter_avatar, v_accepter_gender,
      now(), now()
    );
    RAISE NOTICE '[INVITE] Person created: %', v_person_id;
  ELSE
    v_person_id := v_existing_person;
    RAISE NOTICE '[INVITE] Person reused: %', v_person_id;
  END IF;

  -- Step 2: Create FamilyMember
  v_member_id := 'fm_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  INSERT INTO "FamilyMember" ("id", "familyId", "userId", "role", "joinedAt")
  VALUES (v_member_id, v_invitation."familyId", v_user_id, 'member', now())
  ON CONFLICT ("familyId", "userId") DO NOTHING;
  RAISE NOTICE '[INVITE] Family membership created: %', v_member_id;

  -- Step 3: Create forward Relationship edge
  -- FIX v5.183: Use v_invitation."relationshipKey" directly instead of
  -- deriving from specificLabelAtoB. The relationshipKey was validated at
  -- creation time by fn_create_graph_pending_invitation to be one of:
  -- 'parent', 'spouse', 'adoptive_parent', 'step_parent'. The CHECK
  -- constraint on the Relationship table only allows these four values.
  v_relationship_id := 'rel_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
  SELECT name INTO v_target_name FROM "Person" WHERE id = v_invitation."targetPersonId";
  IF v_target_name IS NULL THEN v_target_name := 'the person'; END IF;

  INSERT INTO "Relationship" (
    "id", "familyId",
    "fromPersonId", "toPersonId",
    "relationshipKey", "labelAtoB",
    "direction", "isActive",
    "createdAt", "updatedAt"
  ) VALUES (
    v_relationship_id, v_invitation."familyId",
    v_invitation."targetPersonId", v_person_id,
    v_invitation."relationshipKey",
    v_invitation."specificLabelAtoB",
    'from', true,
    now(), now()
  );
  RAISE NOTICE '[INVITE] Relationship created: % (fromPerson=% → toPerson=%, key=%, label=%)',
    v_relationship_id, v_invitation."targetPersonId", v_person_id,
    v_invitation."relationshipKey", v_invitation."specificLabelAtoB";

  -- Step 4: Inverse edge (best-effort, wrapped in BEGIN...EXCEPTION)
  -- v5.193 (BUG A + B FIX): Use v_target_gender (the TARGET's
  -- gender) for the inverse CASE, NOT v_accepter_gender. The
  -- inverse label describes the target's role relative to the
  -- newPerson, so it depends on the target's gender.
  --
  -- v5.193 (BUG B FIX): Add a gender-neutral fallback. When the
  -- target's gender is NULL (the common case for newly-created
  -- anchor Persons), use the gender-neutral form ('child' for
  -- 'parent', 'parent' for 'child', 'sibling' for 'brother'/'sister',
  -- etc.) instead of defaulting to the male form.
  v_inverse_key := CASE
    -- Forward: "newPerson is target's father/mother/parent"
    -- Inverse: "target is newPerson's child"
    WHEN v_invitation."specificLabelAtoB" IN ('father', 'mother', 'parent') THEN
      CASE WHEN v_target_gender = 'female' THEN 'daughter'
           WHEN v_target_gender = 'male' THEN 'son'
           ELSE 'child' END
    -- Forward: "newPerson is target's son/daughter/child"
    -- Inverse: "target is newPerson's parent"
    WHEN v_invitation."specificLabelAtoB" IN ('son', 'daughter', 'child') THEN
      CASE WHEN v_target_gender = 'female' THEN 'mother'
           WHEN v_target_gender = 'male' THEN 'father'
           ELSE 'parent' END
    -- Spouse is symmetric
    WHEN v_invitation."specificLabelAtoB" IN ('husband', 'wife', 'spouse') THEN
      v_invitation."specificLabelAtoB"
    -- Sibling — symmetric but gender-aware
    WHEN v_invitation."specificLabelAtoB" IN ('brother', 'sister', 'sibling') THEN
      CASE WHEN v_target_gender = 'female' THEN 'sister'
           WHEN v_target_gender = 'male' THEN 'brother'
           ELSE 'sibling' END
    -- Elder/younger sibling — the inverse of "accepter is target's
    -- elder_brother" is "target is accepter's younger_sibling".
    WHEN v_invitation."specificLabelAtoB" = 'elder_brother' THEN
      CASE WHEN v_target_gender = 'female' THEN 'younger_sister'
           WHEN v_target_gender = 'male' THEN 'younger_brother'
           ELSE 'younger_sibling' END
    WHEN v_invitation."specificLabelAtoB" = 'younger_brother' THEN
      CASE WHEN v_target_gender = 'female' THEN 'elder_sister'
           WHEN v_target_gender = 'male' THEN 'elder_brother'
           ELSE 'elder_sibling' END
    WHEN v_invitation."specificLabelAtoB" = 'elder_sister' THEN
      CASE WHEN v_target_gender = 'female' THEN 'younger_sister'
           WHEN v_target_gender = 'male' THEN 'younger_brother'
           ELSE 'younger_sibling' END
    WHEN v_invitation."specificLabelAtoB" = 'younger_sister' THEN
      CASE WHEN v_target_gender = 'female' THEN 'elder_sister'
           WHEN v_target_gender = 'male' THEN 'elder_brother'
           ELSE 'elder_sibling' END
    -- Grandparent ↔ grandchild
    WHEN v_invitation."specificLabelAtoB" IN ('grandfather', 'grandmother', 'grandparent') THEN
      CASE WHEN v_target_gender = 'female' THEN 'granddaughter'
           WHEN v_target_gender = 'male' THEN 'grandson'
           ELSE 'grandchild' END
    WHEN v_invitation."specificLabelAtoB" IN ('grandson', 'granddaughter', 'grandchild') THEN
      CASE WHEN v_target_gender = 'female' THEN 'grandmother'
           WHEN v_target_gender = 'male' THEN 'grandfather'
           ELSE 'grandparent' END
    -- Aunt/uncle ↔ niece/nephew
    WHEN v_invitation."specificLabelAtoB" IN ('uncle', 'aunt') THEN
      CASE WHEN v_target_gender = 'female' THEN 'niece'
           WHEN v_target_gender = 'male' THEN 'nephew'
           ELSE 'nibling' END
    WHEN v_invitation."specificLabelAtoB" IN ('nephew', 'niece') THEN
      CASE WHEN v_target_gender = 'female' THEN 'aunt'
           WHEN v_target_gender = 'male' THEN 'uncle'
           ELSE 'parent_sibling' END
    ELSE NULL
  END;

  IF v_inverse_key IS NOT NULL THEN
    v_has_known_inverse := true;
  END IF;

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
      RAISE NOTICE '[INVITE] Inverse relationship created: % (label=%)', v_inverse_relationship_id, v_inverse_key;
    EXCEPTION WHEN OTHERS THEN
      v_inverse_relationship_id := NULL;
      RAISE NOTICE '[INVITE] Inverse relationship failed (best-effort, continuing): %', SQLERRM;
    END;
  END IF;

  -- Step 5: Update GraphPendingInvitation status
  UPDATE "GraphPendingInvitation"
  SET status = 'accepted',
      "acceptedAt" = now(),
      "acceptedByUserId" = v_user_id,
      "createdPersonId" = v_person_id,
      "createdRelationshipId" = v_relationship_id,
      "updatedAt" = now()
  WHERE id = p_invitation_id;
  RAISE NOTICE '[INVITE] Invitation status updated to accepted';

  -- Step 6: System chat message
  BEGIN
    v_chat_msg_id := 'msg_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 8);
    INSERT INTO "ChatMessage" (
      "id", "familyId",
      "senderId", "senderName", "senderInitials",
      "content", "messageType", "messageSubType",
      "isRead", "messageStatus",
      "createdAt", "updatedAt"
    ) VALUES (
      v_chat_msg_id, v_invitation."familyId",
      v_user_id, v_accepter_name, UPPER(SUBSTRING(v_accepter_name FROM 1 FOR 1)),
      v_accepter_name || ' joined the family as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name || '.',
      'system', 'system',
      false, 'sent',
      now(), now()
    );
    RAISE NOTICE '[INVITE] System chat message created';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[INVITE] Chat message failed (best-effort): %', SQLERRM;
  END;

  -- Step 7: Notification to inviter
  BEGIN
    SELECT name INTO v_inviter_name FROM "User" WHERE id = v_invitation."inviterUserId";
    IF v_inviter_name IS NULL OR v_inviter_name = '' THEN
      v_inviter_name := 'Someone';
    END IF;

    v_notif_id := 'notif_accept_' || extract(epoch from now())::bigint::text || '_' || substring(v_invitation."inviterUserId" from 1 for 8);
    INSERT INTO "Notification" (
      "id", "userId", "eventType", "title", "body",
      "familyId", "channels", "priority", "read",
      "actionUrl", "createdAt", "updatedAt"
    ) VALUES (
      v_notif_id,
      v_invitation."inviterUserId",
      'invitation_accepted',
      'Invitation Accepted',
      v_accepter_name || ' accepted your invitation and joined as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
      v_invitation."familyId",
      'in_app',
      'normal',
      false,
      'accepted:' || v_invitation."familyId",
      now(), now()
    );
    RAISE NOTICE '[INVITE] Inviter notification created';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[INVITE] Inviter notification failed (best-effort): %', SQLERRM;
  END;

  -- Step 8: Mark original graph_invite notification as read
  UPDATE "Notification"
  SET "read" = true, "readAt" = now(),
      "title" = 'Invitation Accepted',
      "body" = 'You joined as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
      "actionUrl" = 'accepted:' || v_invitation."familyId",
      "updatedAt" = now()
  WHERE "userId" = v_user_id
    AND "eventType" = 'graph_invite'
    AND "familyId" = v_invitation."familyId"
    AND "actionUrl" = 'graph_invite:' || p_invitation_id;
  RAISE NOTICE '[INVITE] Original notification marked as read';

  RAISE NOTICE '[INVITE] Accept completed successfully';
  RETURN jsonb_build_object(
    'success', true,
    'message', v_accepter_name || ' joined as the ' || v_invitation."specificLabelAtoB" || ' of ' || v_target_name,
    'createdPersonId', v_person_id,
    'createdRelationshipId', v_relationship_id,
    'inverseRelationshipId', v_inverse_relationship_id
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[INVITE ERROR] Exception: %', SQLERRM;
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

COMMENT ON FUNCTION public.fn_accept_graph_invitation(text) IS
'v5.193: Fixes (A) inverse label uses v_target_gender (the TARGET person''s gender, fetched from the Person table), not v_accepter_gender; (B) gender-neutral fallback when target gender is NULL (child/parent/sibling/etc.); (C) BFS depth cap raised from 3 to 10 in get_viewer_family_graph; (D) backfill of existing inverse labels. The v5.183 global Person lookup fallback is REMOVED — the lookup is scoped to the invitation''s familyId only (the unique constraint is on familyId+linkedUserId, so a user can have linked Persons in multiple families).';

REVOKE EXECUTE ON FUNCTION public.fn_accept_graph_invitation(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_accept_graph_invitation(text) TO authenticated;

-- ────────────────────────────────────────────────────────────────────
-- 2. Fixed get_viewer_family_graph — raise BFS depth cap from 3 to 10
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_viewer_family_graph(
  p_family_id text,
  p_viewer_id text,
  p_max_nodes integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result JSONB;
  v_viewer_linked TEXT;
  v_total_count INT;
  v_is_creator boolean;
  v_family_created_by text;
BEGIN
  SELECT "linkedUserId" INTO v_viewer_linked
  FROM "Person"
  WHERE id = p_viewer_id
    AND "familyId" = p_family_id
    AND "deletedAt" IS NULL
  LIMIT 1;

  -- v5.177.1: If linkedUserId is NULL, the viewer might be a family
  -- creator whose Person was created without linkedUserId (because they
  -- already have a linked Person in another family). Check if they're
  -- the Family.createdBy — if so, allow access.
  IF v_viewer_linked IS NULL THEN
    -- Check if this viewer is the family creator
    SELECT "createdBy" INTO v_family_created_by
    FROM "Family"
    WHERE id = p_family_id;

    v_is_creator := (
      v_family_created_by IS NOT NULL
      AND v_family_created_by = auth.uid()::text
    );

    IF NOT v_is_creator THEN
      -- Not the creator, and no linkedUserId → can't verify access
      RETURN jsonb_build_object(
        'nodes', '[]'::jsonb, 'edges', '[]'::jsonb, 'allEdges', '[]'::jsonb,
        'isTruncated', false, 'totalCount', 0,
        'error', 'Viewer not found in family'
      );
    END IF;
    -- Else: fall through — creator is allowed to view even without linkedUserId
  ELSIF v_viewer_linked != auth.uid()::text THEN
    -- linkedUserId is set but doesn't match the current auth user
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb, 'edges', '[]'::jsonb, 'allEdges', '[]'::jsonb,
      'isTruncated', false, 'totalCount', 0,
      'error', 'Access denied: viewer not linked to authenticated user'
    );
  END IF;

  SELECT count(*) INTO v_total_count
  FROM "Person"
  WHERE "familyId" = p_family_id AND "deletedAt" IS NULL;

  WITH RECURSIVE proximity_bfs AS (
    SELECT p.id, 0 AS bfs_depth
    FROM "Person" p
    WHERE p.id = p_viewer_id
      AND p."familyId" = p_family_id
      AND p."deletedAt" IS NULL
    UNION ALL
    SELECT neighbor.id, bfs.bfs_depth + 1 AS bfs_depth
    FROM proximity_bfs bfs
    JOIN "Relationship" r ON (
      (r."fromPersonId" = bfs.id AND r."toPersonId" != bfs.id)
      OR (r."toPersonId" = bfs.id AND r."fromPersonId" != bfs.id)
    )
    JOIN "Person" neighbor ON (
      (neighbor.id = r."fromPersonId" AND r."toPersonId" = bfs.id)
      OR (neighbor.id = r."toPersonId" AND r."fromPersonId" = bfs.id)
    )
    -- v5.193 (BUG C FIX): Raised the BFS depth cap from < 3 to < 10.
    -- The previous cap of 3 silently excluded relatives at distance
    -- 4+ (cousin's child, great-great-grandparent, etc.) even when
    -- the family had only 20 members. The 50-node LIMIT below is the
    -- only cap that should bind on small graphs. The depth cap of 10
    -- is a safety net against runaway recursion on cyclic graphs;
    -- it's well beyond any realistic family-tree depth.
    WHERE bfs.bfs_depth < 10
      AND neighbor."familyId" = p_family_id
      AND neighbor."deletedAt" IS NULL
      AND r."familyId" = p_family_id
      AND r."isActive" = true
  ),
  proximity_dedup AS (
    SELECT DISTINCT ON (id) id, bfs_depth
    FROM proximity_bfs
    ORDER BY id, bfs_depth ASC
  ),
  proximity_capped AS (
    SELECT id, bfs_depth
    FROM proximity_dedup
    ORDER BY bfs_depth ASC, id ASC
    LIMIT GREATEST(p_max_nodes, 1)
  )
  SELECT
    jsonb_build_object(
      'nodes', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', p.id, 'name', p.name, 'username', p.username,
          'avatarUrl', p."photoUrl", 'gender', p.gender,
          'isAnchor', p."isAnchor", 'isDeceased', p."isDeceased",
          'visibility', p.visibility, 'generationIndex', p."generationIndex",
          'isViewer', (p.id = p_viewer_id), 'familyId', p."familyId",
          'dateOfBirth', p."dateOfBirth", 'bfsDepth', pc.bfs_depth
        ) ORDER BY pc.bfs_depth ASC, p.name ASC)
        FROM proximity_capped pc
        JOIN "Person" p ON p.id = pc.id
        WHERE p."deletedAt" IS NULL
      ), '[]'::jsonb),

      'edges', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', r.id,
          'sourceId', r."fromPersonId",
          'targetId', r."toPersonId",
          'relationshipKey', COALESCE(
            NULLIF(r."relationshipKey", ''),
            NULLIF(r."relationshipType", 'custom'),
            'unknown'
          ),
          'label', CASE
            WHEN r."fromPersonId" = p_viewer_id THEN r."labelAtoB"
            WHEN r."toPersonId" = p_viewer_id THEN r."labelBtoA"
            ELSE COALESCE(r."labelAtoB", r."labelBtoA")
          END,
          'labelAtoB', r."labelAtoB",
          'labelBtoA', r."labelBtoA"
        ))
        FROM "Relationship" r
        WHERE r."familyId" = p_family_id
          AND r."fromPersonId" IN (SELECT id FROM proximity_capped)
          AND r."toPersonId" IN (SELECT id FROM proximity_capped)
          AND r."isActive" = true
      ), '[]'::jsonb),

      'allEdges', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', r.id,
          'fromPersonId', r."fromPersonId",
          'toPersonId', r."toPersonId",
          'relationshipKey', COALESCE(
            NULLIF(r."relationshipKey", ''),
            'unknown'
          ),
          'labelAtoB', r."labelAtoB"
        ))
        FROM "Relationship" r
        WHERE r."familyId" = p_family_id
          AND r."isActive" = true
      ), '[]'::jsonb),

      'isTruncated', (SELECT count(*) FROM proximity_dedup) > GREATEST(p_max_nodes, 1),
      'totalCount', v_total_count,
      'proximityCount', (SELECT count(*) FROM proximity_capped)
    ) INTO v_result;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_viewer_family_graph(text, text, integer) IS
'v5.193: BFS depth cap raised from 3 to 10 so relatives at distance 4+ (cousin''s child, great-great-grandparent, etc.) are included on small graphs. The 50-node LIMIT remains the only binding cap when the graph exceeds 50 reachable members.';

REVOKE EXECUTE ON FUNCTION public.get_viewer_family_graph(text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_viewer_family_graph(text, text, integer) TO authenticated;

-- ────────────────────────────────────────────────────────────────────
-- 3. Data backfill: recompute inverse labelAtoB for edges created by
--    fn_accept_graph_invitation. This fixes the v5.183/v5.192 wrong
--    labels ('son' for 'father' when target gender is null → 'child').
-- ────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_row RECORD;
  v_target_gender text;
  v_new_label text;
  v_count integer := 0;
BEGIN
  -- For each inverse edge created by fn_accept_graph_invitation
  -- (id prefix 'rel_inv_'), find the corresponding forward edge
  -- (same familyId, fromPersonId = inverse.toPersonId,
  -- toPersonId = inverse.fromPersonId, direction = 'from') and
  -- use its labelAtoB to recompute the inverse label.
  FOR v_row IN
    SELECT inv.id AS inv_id,
           inv."familyId" AS family_id,
           inv."fromPersonId" AS inv_from,
           inv."toPersonId" AS inv_to,
           fwd."labelAtoB" AS forward_label
    FROM "Relationship" inv
    LEFT JOIN "Relationship" fwd
      ON fwd."familyId" = inv."familyId"
     AND fwd."fromPersonId" = inv."toPersonId"
     AND fwd."toPersonId" = inv."fromPersonId"
     AND fwd."direction" = 'from'
     AND fwd."isActive" = true
    WHERE inv."direction" = 'inverse'
      AND inv."isActive" = true
      AND inv.id LIKE 'rel_inv_%'
      AND fwd."labelAtoB" IS NOT NULL
  LOOP
    -- Fetch the target's (toPerson's) gender
    SELECT gender INTO v_target_gender
    FROM "Person"
    WHERE id = v_row.inv_to
      AND "deletedAt" IS NULL
    LIMIT 1;

    -- Recompute the inverse label using the SAME CASE logic as the
    -- new fn_accept_graph_invitation function.
    v_new_label := CASE
      WHEN v_row.forward_label IN ('father', 'mother', 'parent') THEN
        CASE WHEN v_target_gender = 'female' THEN 'daughter'
             WHEN v_target_gender = 'male' THEN 'son'
             ELSE 'child' END
      WHEN v_row.forward_label IN ('son', 'daughter', 'child') THEN
        CASE WHEN v_target_gender = 'female' THEN 'mother'
             WHEN v_target_gender = 'male' THEN 'father'
             ELSE 'parent' END
      WHEN v_row.forward_label IN ('husband', 'wife', 'spouse') THEN
        v_row.forward_label
      WHEN v_row.forward_label IN ('brother', 'sister', 'sibling') THEN
        CASE WHEN v_target_gender = 'female' THEN 'sister'
             WHEN v_target_gender = 'male' THEN 'brother'
             ELSE 'sibling' END
      WHEN v_row.forward_label = 'elder_brother' THEN
        CASE WHEN v_target_gender = 'female' THEN 'younger_sister'
             WHEN v_target_gender = 'male' THEN 'younger_brother'
             ELSE 'younger_sibling' END
      WHEN v_row.forward_label = 'younger_brother' THEN
        CASE WHEN v_target_gender = 'female' THEN 'elder_sister'
             WHEN v_target_gender = 'male' THEN 'elder_brother'
             ELSE 'elder_sibling' END
      WHEN v_row.forward_label = 'elder_sister' THEN
        CASE WHEN v_target_gender = 'female' THEN 'younger_sister'
             WHEN v_target_gender = 'male' THEN 'younger_brother'
             ELSE 'younger_sibling' END
      WHEN v_row.forward_label = 'younger_sister' THEN
        CASE WHEN v_target_gender = 'female' THEN 'elder_sister'
             WHEN v_target_gender = 'male' THEN 'elder_brother'
             ELSE 'elder_sibling' END
      WHEN v_row.forward_label IN ('grandfather', 'grandmother', 'grandparent') THEN
        CASE WHEN v_target_gender = 'female' THEN 'granddaughter'
             WHEN v_target_gender = 'male' THEN 'grandson'
             ELSE 'grandchild' END
      WHEN v_row.forward_label IN ('grandson', 'granddaughter', 'grandchild') THEN
        CASE WHEN v_target_gender = 'female' THEN 'grandmother'
             WHEN v_target_gender = 'male' THEN 'grandfather'
             ELSE 'grandparent' END
      WHEN v_row.forward_label IN ('uncle', 'aunt') THEN
        CASE WHEN v_target_gender = 'female' THEN 'niece'
             WHEN v_target_gender = 'male' THEN 'nephew'
             ELSE 'nibling' END
      WHEN v_row.forward_label IN ('nephew', 'niece') THEN
        CASE WHEN v_target_gender = 'female' THEN 'aunt'
             WHEN v_target_gender = 'male' THEN 'uncle'
             ELSE 'parent_sibling' END
      ELSE NULL
    END;

    IF v_new_label IS NOT NULL AND v_new_label != v_row.forward_label THEN
      -- Also update labelBtoA on the inverse edge to match the
      -- forward label (since the inverse's labelBtoA describes
      -- the fromPerson's role relative to the toPerson, which is
      -- the forward label).
      UPDATE "Relationship"
      SET "labelAtoB" = v_new_label,
          "labelBtoA" = v_row.forward_label,
          "updatedAt" = now()
      WHERE "id" = v_row.inv_id;

      -- Also fix the forward edge's labelBtoA (it should be the
      -- inverse label, describing the toPerson's role relative to
      -- the fromPerson).
      UPDATE "Relationship"
      SET "labelBtoA" = v_new_label,
          "updatedAt" = now()
      WHERE "familyId" = v_row.family_id
        AND "fromPersonId" = v_row.inv_to
        AND "toPersonId" = v_row.inv_from
        AND "direction" = 'from'
        AND "isActive" = true;

      v_count := v_count + 1;
      RAISE NOTICE '[BACKFILL] Fixed inverse edge %: labelAtoB → %, labelBtoA → %',
        v_row.inv_id, v_new_label, v_row.forward_label;
    END IF;
  END LOOP;

  RAISE NOTICE '[BACKFILL] Total inverse labels fixed: %', v_count;
END;
$$;

-- ────────────────────────────────────────────────────────────────────
-- Verification queries (run manually after applying this migration):
--
--   -- Verify no inverse edge still has the wrong label:
--   SELECT inv.id, inv."labelAtoB" AS inverse_label,
--          fwd."labelAtoB" AS forward_label,
--          p.gender AS target_gender
--   FROM "Relationship" inv
--   JOIN "Relationship" fwd
--     ON fwd."familyId" = inv."familyId"
--    AND fwd."fromPersonId" = inv."toPersonId"
--    AND fwd."toPersonId" = inv."fromPersonId"
--    AND fwd."direction" = 'from'
--   JOIN "Person" p ON p.id = inv."toPersonId"
--   WHERE inv."direction" = 'inverse'
--     AND inv.id LIKE 'rel_inv_%'
--     AND inv."labelAtoB" != fwd."labelBtoA";
--   -- Expected: 0 rows (labels should be consistent).
--
--   -- Verify the BFS now reaches depth 4+:
--   WITH RECURSIVE bfs AS (
--     SELECT id, 0 AS d FROM "Person" WHERE id = '<viewer_id>'
--     UNION ALL
--     SELECT n.id, b.d + 1 FROM bfs b
--     JOIN "Relationship" r ON r."fromPersonId" = b.id OR r."toPersonId" = b.id
--     JOIN "Person" n ON n.id = r."fromPersonId" OR n.id = r."toPersonId"
--     WHERE b.d < 10 AND n."deletedAt" IS NULL AND r."isActive" = true
--   ) SELECT max(d) FROM bfs;
--   -- Expected: >= 4 for graphs that have depth-4+ relatives.
-- ────────────────────────────────────────────────────────────────────
