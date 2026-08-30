-- ============================================================
-- Migration: create_get_family_tree_rpc
-- Version:  20260829120000
--
-- Family Space: Graph ↔ Tree (↔ Map) — Implementation Prompt §3.
--
-- Adds a `get_family_tree` RPC that shares the SAME Person + Relationship
-- tables as the existing `get_viewer_family_graph` RPC (no new tables, no
-- duplicate write path). Differences vs. the graph RPC:
--
--   1. Generation-complete. There is NO `p_max_degree` cap — Tree must
--      show every generation structurally, even when individual members
--      are detail-restricted.
--   2. Restricted placeholders. For persons the viewer cannot see in
--      detail (`visibility = 'private'` and viewer not permitted), the
--      node is still returned with `id`, `generationIndex`, parent/spouse
--      edges, and a `restricted: true` flag — `name`/`avatarUrl`/`gender`
--      are masked to a placeholder so Tree rows never have a gap.
--   3. Branch-fetch support. Optional `p_branch_root_id` scopes the
--      traversal to that root's ancestor spine + descendants + spouses
--      — used by the client's progressive-load "▶ Uncle Ravi" branch
--      expand. When NULL, returns the entire family (generation-complete).
--
-- Return shape is identical to `get_viewer_family_graph` so the client
-- parses it with the existing `FlatGraphResult.fromRpc` factory:
--   { nodes: [...], edges: [...], isTruncated, totalCount, scopedBranchRootId }
--
-- Reuses existing columns:
--   - Person.visibility ('public' | 'private' | 'restricted')
--   - Person.generationIndex
--   - Relationship.is_private
--   - COALESCE(Relationship.isActive, true) = true  (v73 fix)
--
-- No new tables. No new columns. No new RLS policies.
--
-- This migration ALSO drops a previous untracked overload
-- `get_family_tree(p_member_id, p_include_hidden, p_branch_root_id)` that
-- was applied directly to the live DB without a migration file. We
-- consolidate to a single canonical signature.
-- ============================================================

-- Drop any previous overloads so the canonical signature below is the
-- ONLY one in the database. Postgres function overloading would
-- otherwise let stale signatures shadow the new one.
DROP FUNCTION IF EXISTS public.get_family_tree(text, boolean, text);
DROP FUNCTION IF EXISTS public.get_family_tree(text, text, text, boolean);

CREATE OR REPLACE FUNCTION public.get_family_tree(
  p_family_id        TEXT,
  p_viewer_id        TEXT,
  p_branch_root_id   TEXT DEFAULT NULL,
  p_include_hidden   BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_viewer_linked     TEXT;
  v_auth_uid          TEXT := auth.uid()::text;
  v_result             JSONB;
  v_total_count       INT;
  v_is_branch_scoped  BOOLEAN := FALSE;
BEGIN
  -- ── Security: same check as get_viewer_family_graph, plus an
  --    explicit NULL-guard on auth.uid() (the existing RPC has a
  --    latent bug: 'string' != NULL evaluates to NULL in Postgres,
  --    so the access-denied IF doesn't fire when no JWT is present).
  --    See: https://github.com/buildwith-manish/Daxelo-Kinrel/security
  -- -----------------------------------------------------------------
  IF v_auth_uid IS NULL THEN
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb, 'edges', '[]'::jsonb,
      'isTruncated', false, 'totalCount', 0,
      'error', 'Authentication required'
    );
  END IF;

  -- Validates the viewer Person exists in the family AND is linked to
  -- the calling auth.uid().
  SELECT "linkedUserId" INTO v_viewer_linked
  FROM "Person"
  WHERE id = p_viewer_id
    AND "familyId" = p_family_id
    AND "deletedAt" IS NULL
  LIMIT 1;

  IF v_viewer_linked IS NULL THEN
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb, 'edges', '[]'::jsonb,
      'isTruncated', false, 'totalCount', 0,
      'error', 'Viewer not found in family'
    );
  END IF;

  IF v_viewer_linked != v_auth_uid THEN
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb, 'edges', '[]'::jsonb,
      'isTruncated', false, 'totalCount', 0,
      'error', 'Access denied: viewer not linked to authenticated user'
    );
  END IF;

  v_is_branch_scoped := p_branch_root_id IS NOT NULL
    AND p_branch_root_id <> '';

  -- ── Compute the visible node-id set ──────────────────────────────
  -- TEMP table shared between nodes + edges queries (avoids re-running
  -- the recursive CTE twice).
  --
  -- When NOT branch-scoped: every non-deleted person in the family.
  --   (generation-complete by definition)
  --
  -- When branch-scoped: ancestor spine of (and including) the root +
  --   all descendants of the root + spouses of any in-scope member.
  --   The ancestor spine is essential so the Tree has structural context
  --   above the branch root (great-grandparents → root) even when
  --   expanding a late-generation member.
  CREATE TEMP TABLE _tree_node_ids ON COMMIT DROP AS
  WITH RECURSIVE
    -- ── Ancestors: root + parent-spine (walk up) ──────────────────
    -- Postgres only allows ONE recursive arm per CTE, so we use two
    -- separate recursive CTEs (ancestors + descendants) and UNION them
    -- in the final all_node_ids CTE. This avoids the OR-based JOIN
    -- `r.fromPersonId = bs.id OR r.toPersonId = bs.id` that prevented
    -- index usage and caused statement timeouts on families with
    -- hundreds of relationships.
    ancestors AS (
      SELECT b.id
      FROM "Person" b
      WHERE v_is_branch_scoped
        AND b.id = p_branch_root_id
        AND b."familyId" = p_family_id
        AND b."deletedAt" IS NULL

      UNION ALL

      -- Walk UP: r.from = current AND key ∈ {parent,...} → next = r.to
      SELECT r."toPersonId"
      FROM ancestors a
      JOIN "Relationship" r ON r."fromPersonId" = a.id
      JOIN "Person" pp ON pp.id = r."toPersonId"
      WHERE pp."familyId" = p_family_id
        AND pp."deletedAt" IS NULL
        AND COALESCE(r."isActive", true) = true
        AND r."relationshipKey" IN (
          'parent','father','mother',
          'grandparent','grandfather','grandmother'
        )
    ),
    -- ── Descendants: root + child-tree (walk down) ────────────────
    -- Same seed as ancestors (the branch root). Walks down to all
    -- descendants. Postgres's `WITH RECURSIVE` does not let a CTE
    -- reference another CTE in its seed, so we re-seed with the same
    -- filter instead of `SELECT id FROM ancestors`.
    descendants AS (
      SELECT b.id
      FROM "Person" b
      WHERE v_is_branch_scoped
        AND b.id = p_branch_root_id
        AND b."familyId" = p_family_id
        AND b."deletedAt" IS NULL

      UNION ALL

      -- Walk DOWN: r.to = current AND key='parent' → next = r.from
      -- (since to is parent of from, from is child of to). This is
      -- the common case for families that store only 'parent' rows
      -- (the convention used by Kinrel's createRelationshipBetween flow).
      SELECT r."fromPersonId"
      FROM descendants d
      JOIN "Relationship" r ON r."toPersonId" = d.id
      JOIN "Person" pc ON pc.id = r."fromPersonId"
      WHERE pc."familyId" = p_family_id
        AND pc."deletedAt" IS NULL
        AND COALESCE(r."isActive", true) = true
        AND r."relationshipKey" IN (
          'parent','father','mother',
          'grandparent','grandfather','grandmother',
          'child','son','daughter','grandchild'
        )
    ),
    -- ── Branch scope (ancestor spine + descendant tree) ───────────
    branch_scope AS (
      SELECT id FROM ancestors
      UNION
      SELECT id FROM descendants
    ),
    -- ── Spouses of any branch-scope member (either edge direction) ─
    branch_spouses AS (
      SELECT r."toPersonId" AS id
      FROM "Relationship" r
      JOIN "Person" ps ON ps.id = r."toPersonId"
      WHERE v_is_branch_scoped
        AND ps."familyId" = p_family_id
        AND ps."deletedAt" IS NULL
        AND COALESCE(r."isActive", true) = true
        AND r."relationshipKey" IN ('spouse','husband','wife','partner')
        AND r."fromPersonId" IN (SELECT id FROM branch_scope)

      UNION

      SELECT r."fromPersonId" AS id
      FROM "Relationship" r
      JOIN "Person" ps2 ON ps2.id = r."fromPersonId"
      WHERE v_is_branch_scoped
        AND ps2."familyId" = p_family_id
        AND ps2."deletedAt" IS NULL
        AND COALESCE(r."isActive", true) = true
        AND r."relationshipKey" IN ('spouse','husband','wife','partner')
        AND r."toPersonId" IN (SELECT id FROM branch_scope)
    ),
    -- ── Combined node-id set ─────────────────────────────────────
    -- branch-scope + spouses + (when NOT branch-scoped) the entire
    -- family as a generation-complete fallback.
    all_node_ids AS (
      SELECT id FROM branch_scope
      UNION
      SELECT id FROM branch_spouses
      UNION ALL
      SELECT p.id
      FROM "Person" p
      WHERE v_is_branch_scoped = FALSE
        AND p."familyId" = p_family_id
        AND p."deletedAt" IS NULL
    )
    SELECT id FROM all_node_ids;

  -- Cache the total family member count (used in the response payload).
  SELECT count(*) INTO v_total_count
  FROM "Person"
  WHERE "familyId" = p_family_id AND "deletedAt" IS NULL;

  -- ── Build the response object in one pass ───────────────────────
  -- Nodes: every id in _tree_node_ids, with detail fields masked to a
  -- 'Restricted member' placeholder when the viewer cannot see private
  -- persons (and p_include_hidden is false, and the row is not the
  -- viewer's own Person — the viewer can always see their own row).
  --
  -- Edges: every active relationship whose BOTH endpoints are present
  -- in the node-id set above. Spouse / sibling / extended edges are
  -- preserved so the Tree can route connectors between same-generation
  -- spouses and between siblings sharing parents.
  SELECT jsonb_build_object(
    'nodes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',              p.id,
        'name',            CASE
                             WHEN p.visibility = 'private'
                                  AND NOT p_include_hidden
                                  AND COALESCE(p."linkedUserId"::text, '') <> v_viewer_linked
                           THEN 'Restricted member'
                           ELSE p.name
                           END,
        'username',        CASE
                             WHEN p.visibility = 'private'
                                  AND NOT p_include_hidden
                                  AND COALESCE(p."linkedUserId"::text, '') <> v_viewer_linked
                           THEN NULL
                           ELSE p.username
                           END,
        'avatarUrl',       CASE
                             WHEN p.visibility = 'private'
                                  AND NOT p_include_hidden
                                  AND COALESCE(p."linkedUserId"::text, '') <> v_viewer_linked
                           THEN NULL
                           ELSE p."photoUrl"
                           END,
        'gender',          CASE
                             WHEN p.visibility = 'private'
                                  AND NOT p_include_hidden
                                  AND COALESCE(p."linkedUserId"::text, '') <> v_viewer_linked
                           THEN NULL
                           ELSE p.gender
                           END,
        'isAnchor',        p."isAnchor",
        'isDeceased',      p."isDeceased",
        'visibility',      p.visibility,
        'generationIndex', p."generationIndex",
        'isViewer',        (p.id = p_viewer_id),
        'familyId',        p."familyId",
        'restricted',      (p.visibility = 'private'
                             AND NOT p_include_hidden
                             AND COALESCE(p."linkedUserId"::text, '') <> v_viewer_linked)
      ) ORDER BY p."generationIndex" ASC NULLS LAST, p.name ASC)
      FROM "Person" p
      WHERE p.id IN (SELECT id FROM _tree_node_ids)
    ), '[]'::jsonb),
    'edges', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',               r.id,
        'sourceId',         r."fromPersonId",
        'targetId',         r."toPersonId",
        'relationshipKey', COALESCE(
                              NULLIF(r."relationshipKey", ''),
                              NULLIF(r."relationshipType", 'custom'),
                              'unknown'
                            ),
        'label',            CASE
                              WHEN r."fromPersonId" = p_viewer_id THEN r."labelAtoB"
                              WHEN r."toPersonId"   = p_viewer_id THEN r."labelBtoA"
                              ELSE r."labelAtoB"
                            END,
        'labelAtoB',        r."labelAtoB",
        'labelBtoA',        r."labelBtoA",
        'isPrivate',        COALESCE(r.is_private, false),
        'isActive',         COALESCE(r."isActive", true)
      ))
      FROM "Relationship" r
      WHERE r."familyId" = p_family_id
        AND COALESCE(r."isActive", true) = true
        AND r."fromPersonId" IN (SELECT id FROM _tree_node_ids)
        AND r."toPersonId"   IN (SELECT id FROM _tree_node_ids)
    ), '[]'::jsonb),
    'isTruncated', false,
    'totalCount', v_total_count,
    'scopedBranchRootId', p_branch_root_id
  ) INTO v_result;

  DROP TABLE _tree_node_ids;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_family_tree(text, text, text, boolean) TO authenticated, anon;

COMMENT ON FUNCTION public.get_family_tree(text, text, text, boolean) IS
  'Generation-complete family tree view. Same Person+Relationship tables as get_viewer_family_graph, but no degree cap and masked restricted placeholders for private members. Optional p_branch_root_id scopes to ancestor-spine + descendants + spouses for lazy branch expand.';
