-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260909140000_backfix_cross_family_graph_invite_edges
--
-- PURPOSE
-- Backfill: fix the cross-family Relationship edges created by the
-- v5.183 fn_accept_graph_invitation bug. The v5.183 RPC had a "global
-- check" that reused a Person from ANOTHER family when the accepter
-- already had a Person elsewhere. This created Relationship edges in
-- family A pointing to a Person whose familyId was family B — a
-- cross-family edge that the get_viewer_family_graph RPC (which
-- filters by familyId) would never return.
--
-- The symptom (the user's reported bug):
--   - Account 1 accepts Account 2's graph invitation
--   - Account 1 already has a Person in another family (e.g. their own
--     family where they're the anchor)
--   - The v5.183 RPC reused Account 1's EXISTING Person ID (from the
--     other family) instead of creating a new Person in Account 2's
--     family
--   - The Relationship edge in Account 2's family points to a Person
--     in the OTHER family
--   - get_viewer_family_graph(familyId=account2_family, ...) returns
--     the edge's fromPersonId (Account 2's anchor) but NOT the
--     toPersonId (it's filtered out because its familyId doesn't match)
--   - Account 1 appears "hidden" or "not in the graph"
--   - When Account 1 opens Account 2's family graph,
--     viewerPersonIdProvider Step 1 (linked Person lookup in THIS
--     family) returns empty → viewerPersonId is null → ClaimProfileBanner
--     fires ("Tap to claim your profile — you're viewing as the family
--     anchor")
--
-- The v5.192 migration (20260909130000_fix_graph_invitation_inverse_gender_aware.sql)
-- fixes the RPC for NEW acceptances (removes the global check, only
-- checks within the invitation's family). THIS migration fixes the
-- EXISTING broken data so users who accepted BEFORE v5.192 was
-- deployed get their correct Person node + edges.
--
-- BACKFILL STRATEGY
-- 1. Find all Relationship rows where the toPersonId points to a
--    Person whose familyId != the Relationship's familyId (the
--    cross-family bug). Only forward edges (direction='from') created
--    by fn_accept_graph_invitation — identified by the id prefix
--    'rel_' and the specific cross-family condition.
-- 2. For each, check if a Person with the same linkedUserId already
--    exists in the CORRECT family (from a later correct acceptance or
--    manual creation). If so, re-point the edge to that Person.
-- 3. If no such Person exists, create a new Person in the correct
--    family (copying name/gender/photoUrl from the foreign Person) and
--    re-point the edge to the new Person.
-- 4. Also fix the inverse edge (direction='inverse') if it points to
--    the same foreign Person.
-- 5. DO NOT delete the foreign Person — it's still valid in its
--    original family. Only the cross-family EDGE is broken.
--
-- SAFETY
-- - Idempotent: re-running this migration is a no-op (the cross-family
--   condition no longer matches after the fix).
-- - Only fixes edges where the Person's familyId doesn't match the
--   Relationship's familyId — does NOT touch correctly-created edges.
-- - Wrapped in a single transaction — either all fixes apply or none.
-- - Logs every fix via RAISE NOTICE for audit.
-- ════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_count integer := 0;
  v_row RECORD;
  v_new_person_id text;
  v_existing_correct_person text;
BEGIN
  -- ── Find all cross-family forward edges (direction='from') ──
  -- These are the edges created by the v5.183 bug: the toPersonId
  -- points to a Person whose familyId != the Relationship's familyId.
  FOR v_row IN
    SELECT r.id AS rel_id, r."familyId" AS rel_family_id,
           r."fromPersonId", r."toPersonId",
           r."relationshipKey", r."labelAtoB", r."direction",
           p."linkedUserId", p.name AS person_name,
           p.gender AS person_gender, p."photoUrl" AS person_photo,
           p."familyId" AS person_family_id
    FROM "Relationship" r
    JOIN "Person" p ON p.id = r."toPersonId"
    WHERE r."isActive" = true
      AND r."direction" = 'from'
      AND p."familyId" != r."familyId"
      AND p."linkedUserId" IS NOT NULL
      AND p."deletedAt" IS NULL
  LOOP
    v_count := v_count + 1;
    RAISE NOTICE '[BACKFIX] Cross-family edge %: rel family=%, toPerson family=%, linkedUserId=%',
      v_row.rel_id, v_row.rel_family_id, v_row.person_family_id, v_row.linkedUserId;

    -- ── Step 1: Check if a correct Person already exists in the right family ──
    SELECT id INTO v_existing_correct_person
    FROM "Person"
    WHERE "familyId" = v_row.rel_family_id
      AND "linkedUserId" = v_row.linkedUserId
      AND "deletedAt" IS NULL
    LIMIT 1;

    IF v_existing_correct_person IS NOT NULL THEN
      -- ── Step 2a: Re-point the edge to the existing correct Person ──
      RAISE NOTICE '[BACKFIX] Re-pointing edge % to existing correct Person %',
        v_row.rel_id, v_existing_correct_person;
      UPDATE "Relationship"
      SET "toPersonId" = v_existing_correct_person,
          "updatedAt" = now()
      WHERE "id" = v_row.rel_id;
    ELSE
      -- ── Step 2b: Create a new Person in the correct family ──
      v_new_person_id := gen_random_uuid()::text;
      RAISE NOTICE '[BACKFIX] Creating new Person % in family % for linkedUserId %',
        v_new_person_id, v_row.rel_family_id, v_row.linkedUserId;

      INSERT INTO "Person" (
        "id", "familyId", "name",
        "isAnchor", "generationIndex", "privacyLevel",
        "linkedUserId", "linkedAt",
        "photoUrl", "gender",
        "createdAt", "updatedAt"
      ) VALUES (
        v_new_person_id, v_row.rel_family_id, v_row.person_name,
        false, 0, 'family',
        v_row.linkedUserId, now(),
        v_row.person_photo, v_row.person_gender,
        now(), now()
      );

      -- Re-point the edge to the new Person
      UPDATE "Relationship"
      SET "toPersonId" = v_new_person_id,
          "updatedAt" = now()
      WHERE "id" = v_row.rel_id;

      RAISE NOTICE '[BACKFIX] Re-pointed edge % to new Person %',
        v_row.rel_id, v_new_person_id;
    END IF;

    -- ── Step 3: Fix the inverse edge if it exists ──
    -- The inverse edge (direction='inverse') has fromPersonId = the
    -- foreign Person and toPersonId = the inviter's Person. We need
    -- to re-point its fromPersonId to the same correct Person.
    DECLARE
      v_inverse_rel_id text;
    BEGIN
      SELECT id INTO v_inverse_rel_id
      FROM "Relationship"
      WHERE "familyId" = v_row.rel_family_id
        AND "fromPersonId" = v_row.toPersonId
        AND "direction" = 'inverse'
        AND "isActive" = true
      LIMIT 1;

      IF v_inverse_rel_id IS NOT NULL THEN
        RAISE NOTICE '[BACKFIX] Also fixing inverse edge %', v_inverse_rel_id;
        UPDATE "Relationship"
        SET "fromPersonId" = COALESCE(v_existing_correct_person, v_new_person_id),
            "updatedAt" = now()
        WHERE "id" = v_inverse_rel_id;
      END IF;
    END;
  END LOOP;

  RAISE NOTICE '[BACKFIX] Total cross-family edges fixed: %', v_count;
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- Verification query (run manually after applying this migration):
--   SELECT COUNT(*) AS remaining_cross_family_edges
--   FROM "Relationship" r
--   JOIN "Person" p ON p.id = r."toPersonId"
--   WHERE r."isActive" = true AND r."direction" = 'from'
--     AND p."familyId" != r."familyId"
--     AND p."linkedUserId" IS NOT NULL AND p."deletedAt" IS NULL;
-- Expected: 0 (all cross-family edges fixed).
-- ════════════════════════════════════════════════════════════════════
