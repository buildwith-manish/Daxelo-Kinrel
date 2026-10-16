-- 20261016120000_enforce_graph_rpc_membership.sql
--
-- SECURITY FIX (audit F-01): The `get_family_graph` RPC is SECURITY DEFINER
-- and previously accepted any `p_member_id` without verifying that the
-- caller (auth.uid()) is a member of that member's family. Any authenticated
-- user could pass an arbitrary person ID from another family and read its
-- full graph (names, genders, photos, relationship structure, deceased
-- status, etc.).
--
-- This migration re-declares `get_family_graph` with the SAME signature
-- (p_member_id text, p_max_degree int DEFAULT 4, p_include_hidden boolean
-- DEFAULT false) and the SAME return shape (jsonb with nodes / edges /
-- isTruncated / totalCount) so the Flutter app and any other caller keep
-- working unchanged.
--
-- Authorisation model:
--   1. Resolve the `familyId` of the Person whose id = p_member_id.
--   2. Reuse the existing helper `fn_user_is_family_member_check(familyId,
--      auth.uid()::text)` (defined in migration 20260705181000_game_invites_and_push.sql
--      and already used by the `game_invites` RLS policies) to confirm the
--      caller is a FamilyMember of that family.
--   3. If the Person does not exist or the caller is not a member, return
--      an empty result with the SAME shape the function already returns
--      (`{ "nodes": [], "edges": [], "isTruncated": false, "totalCount": 0 }`).
--      Returning an empty result — instead of raising an exception — matches
--      how the Flutter `family_graph_provider.dart` already handles a failed
--      or empty `get_family_graph` RPC: it falls back to the direct query
--      path (`_fetchGraphDirectQuery`), which is itself RLS-scoped to the
--      caller's own family. Raising an exception here would surface as a
--      PostgREST error and force the client into the same fallback path,
--      but with worse UX (an error toast). The empty-result approach is
--      consistent with the existing `get_viewer_family_graph` behaviour
--      (see migration 20260909150000, which returns `{ "error": ... }`
--      with empty arrays for unauthorised callers).
--
-- F-18 verification (get_viewer_family_graph):
--   The latest definition of `get_viewer_family_graph` lives in
--   migration 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql.
--   It already verifies membership: it looks up the Person by
--   `(id = p_viewer_id, familyId = p_family_id)`, then requires either
--   `Person.linkedUserId = auth.uid()::text` OR that the caller is the
--   `Family.createdBy` of `p_family_id`. If neither holds, it returns an
--   empty result with an `error` key. An attacker cannot point it at
--   another family's data because the Person lookup is constrained to
--   `p_family_id` AND the auth check rejects everyone except the linked
--   user / family creator. F-18 is therefore a false positive and is NOT
--   modified by this migration.
--
-- Hardening applied to get_family_graph:
--   - `SET search_path TO public, public` — explicit, no untrusted path.
--   - `REVOKE EXECUTE ... FROM PUBLIC, anon` — only `authenticated` may call.
--   - `GRANT EXECUTE ... TO authenticated`.
--
-- No other SECURITY DEFINER function is modified by this migration. The
-- broader scan of other SECURITY DEFINER functions in the repo is reported
-- separately in the audit final report.

-- ────────────────────────────────────────────────────────────────────
-- 1. Replace get_family_graph with a membership-checked version
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_family_graph(
  p_member_id text,
  p_max_degree int DEFAULT 4,
  p_include_hidden boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_family_id text;
  v_is_member boolean;
  result JSONB;
BEGIN
  -- SECURITY (audit F-01): resolve the family of the requested member, then
  -- verify the caller is a member of that family. If the Person does not
  -- exist OR the caller is not a member, return an empty graph with the
  -- same shape the function normally returns. We deliberately do NOT
  -- distinguish "person not found" from "not a member" — both return the
  -- same empty result so the endpoint does not leak existence.
  SELECT p."familyId" INTO v_family_id
  FROM "Person" p
  WHERE p.id = p_member_id
    AND p."deletedAt" IS NULL
  LIMIT 1;

  IF v_family_id IS NULL THEN
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb,
      'edges', '[]'::jsonb,
      'isTruncated', false,
      'totalCount', 0
    );
  END IF;

  v_is_member := public.fn_user_is_family_member_check(v_family_id, auth.uid()::text);

  IF v_is_member IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb,
      'edges', '[]'::jsonb,
      'isTruncated', false,
      'totalCount', 0
    );
  END IF;

  -- ── Authorisation passed — build the graph (unchanged logic) ──────
  WITH RECURSIVE graph_traversal AS (
    SELECT
      p.id, p.name AS display_name, p.username, p."photoUrl" AS avatar_url,
      p.gender, 0 AS degree, true AS is_anchor,
      p."isDeceased", p.visibility,
      p."generationIndex"
    FROM "Person" p
    WHERE p.id = p_member_id

    UNION ALL

    -- Branch 1: relationships where the current node is the FROM person
    -- (uses Relationship(familyId, fromPersonId) composite index)
    SELECT
      p.id, p.name, p.username, p."photoUrl",
      p.gender, gt.degree + 1, false,
      p."isDeceased", p.visibility,
      p."generationIndex"
    FROM graph_traversal gt
    JOIN "Relationship" r ON r."fromPersonId" = gt.id
    JOIN "Person" p ON p.id = r."toPersonId"
    WHERE gt.degree < p_max_degree
      AND p.id != p_member_id
      AND r."isActive" = true
      AND (p_include_hidden = true OR COALESCE(p.visibility, 'public') != 'private')

    UNION ALL

    -- Branch 2: relationships where the current node is the TO person
    -- (uses Relationship(familyId, toPersonId) composite index)
    SELECT
      p.id, p.name, p.username, p."photoUrl",
      p.gender, gt.degree + 1, false,
      p."isDeceased", p.visibility,
      p."generationIndex"
    FROM graph_traversal gt
    JOIN "Relationship" r ON r."toPersonId" = gt.id
    JOIN "Person" p ON p.id = r."fromPersonId"
    WHERE gt.degree < p_max_degree
      AND p.id != p_member_id
      AND r."isActive" = true
      AND (p_include_hidden = true OR COALESCE(p.visibility, 'public') != 'private')
  ),
  unique_members AS (
    SELECT DISTINCT ON (id)
      id, display_name, username, avatar_url, gender,
      MIN(degree) OVER (PARTITION BY id) AS degree,
      is_anchor, "isDeceased", visibility, "generationIndex"
    FROM graph_traversal
  ),
  visible_edges AS (
    SELECT
      r.id,
      r."fromPersonId" AS member_a_id,
      r."toPersonId" AS member_b_id,
      COALESCE(r."relationshipType", r."relationshipKey", 'unknown') AS relationship_type,
      r.is_private
    FROM "Relationship" r
    WHERE r."fromPersonId" IN (SELECT id FROM unique_members)
      AND r."toPersonId" IN (SELECT id FROM unique_members)
      AND r."isActive" = true
      AND (p_include_hidden = true OR COALESCE(r.is_private, false) = false)
  )
  SELECT jsonb_build_object(
    'nodes', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', um.id,
        'name', um.display_name,
        'username', um.username,
        'avatarUrl', um.avatar_url,
        'gender', um.gender,
        'generationIndex', COALESCE(um."generationIndex", -um.degree),
        'isAnchor', um.is_anchor,
        'isDeceased', um."isDeceased",
        'visibility', um.visibility
      )) FROM unique_members um),
      '[]'::jsonb
    ),
    'edges', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', ve.id,
        'sourceId', ve.member_a_id,
        'targetId', ve.member_b_id,
        'relationshipKey', ve.relationship_type,
        'isPrivate', ve.is_private
      )) FROM visible_edges ve),
      '[]'::jsonb
    ),
    'isTruncated', (SELECT COUNT(*) > 5000 FROM unique_members),
    'totalCount', (SELECT COUNT(*) FROM unique_members)
  ) INTO result;

  RETURN result;
END;
$$;

COMMENT ON FUNCTION public.get_family_graph(text, integer, boolean) IS
'SECURITY (2026-10-16, audit F-01): Verifies auth.uid() is a FamilyMember of the family of p_member_id before returning any graph data. Returns an empty {nodes, edges, isTruncated, totalCount} result (same shape) if the person does not exist or the caller is not a member. Only callable by authenticated users.';

REVOKE EXECUTE ON FUNCTION public.get_family_graph(text, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_family_graph(text, integer, boolean) TO authenticated;

-- ────────────────────────────────────────────────────────────────────
-- 2. Replace get_member_branch with a membership-checked version
--
-- Same bug class as F-01: SECURITY DEFINER, takes p_member_id, no
-- auth check, returns names/usernames/avatars/gender/relationships
-- for ANY p_member_id (any family). Used by the Flutter graph client
-- (FamilyGraphNotifier branch chips) — same feature, same fix.
-- Signature and {nodes, edges} return shape are unchanged.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_member_branch(
  p_member_id TEXT,
  p_branch_type TEXT,
  p_depth INT DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $func$
DECLARE
  v_family_id text;
  v_is_member boolean;
  result JSONB;
  target_member_ids TEXT[];
  -- 'generic' mode: collect ALL persons connected to p_member_id
  -- within p_depth hops, regardless of relationship type.
  current_front TEXT[];
  next_front TEXT[];
  visited TEXT[];
  hop INT := 0;
BEGIN
  -- SECURITY (audit F-01 sibling): verify auth.uid() is a FamilyMember
  -- of the family of p_member_id BEFORE doing any graph traversal.
  -- Empty {nodes, edges} on miss — same shape the function already
  -- returns on no-match, so the Flutter client's "+N" chip tap stays
  -- a silent no-op for cross-family callers.
  SELECT p."familyId" INTO v_family_id
  FROM "Person" p
  WHERE p.id = p_member_id
    AND p."deletedAt" IS NULL
  LIMIT 1;

  IF v_family_id IS NULL THEN
    RETURN '{"nodes":[],"edges":[]}'::jsonb;
  END IF;

  v_is_member := public.fn_user_is_family_member_check(v_family_id, auth.uid()::text);

  IF v_is_member IS NOT TRUE THEN
    RETURN '{"nodes":[],"edges":[]}'::jsonb;
  END IF;

  CASE p_branch_type
    WHEN 'maternal' THEN
      SELECT ARRAY_AGG(p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."toPersonId" = p_member_id AND r."relationshipType" IN ('mother','maternal_grandmother','maternal_grandfather')
        UNION
        SELECT r."toPersonId" FROM "Relationship" r
        WHERE r."fromPersonId" = p_member_id AND r."relationshipType" IN ('mother','maternal_grandmother','maternal_grandfather')
      );
    WHEN 'paternal' THEN
      SELECT ARRAY_AGG(p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."toPersonId" = p_member_id AND r."relationshipType" IN ('father','paternal_grandmother','paternal_grandfather')
        UNION
        SELECT r."toPersonId" FROM "Relationship" r
        WHERE r."fromPersonId" = p_member_id AND r."relationshipType" IN ('father','paternal_grandmother','paternal_grandfather')
      );
    WHEN 'cousins' THEN
      SELECT ARRAY_AGG(DISTINCT p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."relationshipType" IN ('cousin','niece','nephew')
          AND (r."fromPersonId" = p_member_id OR r."toPersonId" = p_member_id)
      );
    WHEN 'inLaws' THEN
      SELECT ARRAY_AGG(DISTINCT p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."relationshipType" IN ('father_in_law','mother_in_law','brother_in_law','sister_in_law')
          AND (r."fromPersonId" = p_member_id OR r."toPersonId" = p_member_id)
      );
    WHEN 'grandchildren' THEN
      SELECT ARRAY_AGG(DISTINCT p.id) INTO target_member_ids
      FROM "Person" p
      WHERE p.id IN (
        SELECT r."fromPersonId" FROM "Relationship" r
        WHERE r."relationshipType" IN ('grandson','granddaughter')
          AND (r."fromPersonId" = p_member_id OR r."toPersonId" = p_member_id)
      );
    WHEN 'generic' THEN
      -- ── v5.131 (Bug 1 fix): universal neighborhood fetch ──────
      -- BFS over the relationship graph from p_member_id up to
      -- p_depth hops. Returns EVERY person reachable within that
      -- radius (any relationship type — blood, step, adoptive,
      -- in-law, custom). The client uses this as the fallback
      -- when branchTypeForRelationshipKey cannot classify the
      -- chip's relationship key, so "+N" taps always bring in the
      -- hidden members instead of no-op'ing.
      --
      -- Capped at p_depth hops to avoid scanning the whole family
      -- for very large graphs. Default depth = 2 mirrors the other
      -- branch types.
      visited := ARRAY[p_member_id]::TEXT[];
      current_front := ARRAY[p_member_id]::TEXT[];
      hop := 0;
      WHILE hop < p_depth AND array_length(current_front, 1) > 0 LOOP
        SELECT array_agg(DISTINCT x) INTO next_front
        FROM (
          SELECT r."fromPersonId" AS x
          FROM "Relationship" r
          WHERE r."toPersonId" = ANY(current_front)
            AND r."fromPersonId" <> ALL(visited)
            AND COALESCE(r.is_private, false) = false
          UNION
          SELECT r."toPersonId" AS x
          FROM "Relationship" r
          WHERE r."fromPersonId" = ANY(current_front)
            AND r."toPersonId" <> ALL(visited)
            AND COALESCE(r.is_private, false) = false
        ) t;
        IF next_front IS NULL OR array_length(next_front, 1) IS NULL THEN
          next_front := ARRAY[]::TEXT[];
        END IF;
        visited := visited || next_front;
        current_front := next_front;
        hop := hop + 1;
      END LOOP;
      -- Exclude the root itself from the "target" set — the
      -- client already has the root, we only want its neighbors.
      -- NOTE: PL/pgSQL requires `SELECT v FROM unnest(arr) AS v`
      -- to reference the column; `SELECT unnest WHERE unnest <> x`
      -- is invalid SQL and throws "column unnest does not exist".
      target_member_ids := ARRAY(
        SELECT v FROM unnest(visited) AS v WHERE v <> p_member_id
      );
      -- Edge case: if the BFS visited only the root itself (no
      -- neighbors within p_depth hops), target_member_ids will
      -- be empty — that's fine, the CTEs below will return
      -- empty nodes/edges which the client handles gracefully.
      IF target_member_ids IS NULL THEN
        target_member_ids := ARRAY[]::TEXT[];
      END IF;
    ELSE
      target_member_ids := ARRAY[]::TEXT[];
  END CASE;

  WITH branch_members AS (
    SELECT p.id, p.name AS display_name, p.username, p."photoUrl" AS avatar_url,
      p.gender, p."isDeceased", p.visibility, p."generationIndex"
    FROM "Person" p
    WHERE p.id = ANY(COALESCE(target_member_ids, ARRAY[]::TEXT[]))
      AND COALESCE(p.visibility, 'public') != 'private'
  ),
  branch_edges AS (
    SELECT r.id, r."fromPersonId" AS member_a_id, r."toPersonId" AS member_b_id,
      r."relationshipType" AS relationship_type, r.is_private
    FROM "Relationship" r
    WHERE (r."fromPersonId" = ANY(COALESCE(target_member_ids, ARRAY[]::TEXT[]))
        OR r."toPersonId" = ANY(COALESCE(target_member_ids, ARRAY[]::TEXT[])))
      AND COALESCE(r.is_private, false) = false
  )
  SELECT jsonb_build_object(
    'nodes', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', bm.id, 'name', bm.display_name, 'username', bm.username,
        'avatarUrl', bm.avatar_url, 'gender', bm.gender,
        'isDeceased', bm."isDeceased", 'visibility', bm.visibility,
        'generationIndex', COALESCE(bm."generationIndex", 0)
      )) FROM branch_members bm),
      '[]'::jsonb
    ),
    'edges', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'id', be.id, 'sourceId', be.member_a_id, 'targetId', be.member_b_id,
        'relationshipKey', be.relationship_type, 'isPrivate', be.is_private
      )) FROM branch_edges be),
      '[]'::jsonb
    )
  ) INTO result;

  RETURN COALESCE(result, '{"nodes":[],"edges":[]}'::jsonb);
END;
$func$;

COMMENT ON FUNCTION public.get_member_branch(TEXT, TEXT, INT) IS
'SECURITY (2026-10-16, audit F-01 sibling): Verifies auth.uid() is a FamilyMember of the family of p_member_id before returning any branch data. Returns an empty {nodes, edges} result (same shape) if the person does not exist or the caller is not a member. Only callable by authenticated users.';

REVOKE EXECUTE ON FUNCTION public.get_member_branch(TEXT, TEXT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_member_branch(TEXT, TEXT, INT) TO authenticated;
