-- 20261016120000_test_graph_rpc_membership.sql
--
-- SECURITY TEST (audit F-01): Verify that the membership check added to
-- get_family_graph and get_member_branch by migration
-- 20261016120000_enforce_graph_rpc_membership.sql works correctly.
--
-- Three scenarios per function:
--   1. Caller IS a member of the family of p_member_id → returns graph data.
--   2. Caller is signed in but NOT a member of that family → returns an
--      empty {nodes, edges} result (same shape) — no data leaked.
--   3. Caller is signed in but p_member_id does not exist → returns an
--      empty {nodes, edges} result (same shape) — does not leak existence.
--
-- HOW TO RUN
-- ───────────
-- This is a MANUAL test script (the repo does not use pgTAP). To run it
-- against a staging or branch Supabase database:
--
--   1. Apply migration 20261016120000_enforce_graph_rpc_membership.sql
--      to the staging database first:
--
--        supabase db push --linked --local   (or whatever your staging workflow is)
--
--   2. Open the Supabase SQL editor (or psql) against the staging
--      database as a user with admin privileges.
--
--   3. Replace the two placeholders below with real auth.uid() values
--      from your staging auth.users table:
--        :caller_in_family_a  → UUID of a user who is a FamilyMember of
--                                test-fam-graph-A
--        :caller_in_family_b  → UUID of a different user who is NOT a
--                                FamilyMember of test-fam-graph-A
--      (You can create them via the Supabase dashboard → Auth → Users →
--       Add user, then copy the UID.)
--
--   4. Run this whole script. The SELECTs at the bottom should output
--      six rows, each with expected='PASS' if the membership check
--      behaves correctly.
--
--   5. Cleanup is at the bottom — the script deletes its own test data.

-- ── 1. Create test families ─────────────────────────────────────────

INSERT INTO "Family" (id, name, "createdBy", "memberCount", "createdAt", "updatedAt")
VALUES
  ('test-fam-graph-A', 'Test Family A (graph rpc membership)', null, 2, now(), now()),
  ('test-fam-graph-B', 'Test Family B (graph rpc membership)', null, 1, now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── 2. Create test persons ──────────────────────────────────────────
--    person_A1 is the "anchor" of family A.
--    person_A2 is a child of person_A1 in family A.
--    person_B1 is the anchor of family B (the cross-family intruder's family).

INSERT INTO "Person" (id, "familyId", name, gender, "isAnchor", "linkedUserId", "createdAt", "updatedAt")
VALUES
  ('test-person-A1', 'test-fam-graph-A', 'TestPersonA1', 'male',   true,
    :'caller_in_family_a', now(), now()),
  ('test-person-A2', 'test-fam-graph-A', 'TestPersonA2', 'female', false,
    null, now(), now()),
  ('test-person-B1', 'test-fam-graph-B', 'TestPersonB1', 'male',   true,
    :'caller_in_family_b', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── 3. Create test relationships ───────────────────────────────────

INSERT INTO "Relationship" (id, "familyId", "fromPersonId", "toPersonId",
    "relationshipKey", "relationshipType", "labelAtoB", "direction", "isActive", "createdAt", "updatedAt")
VALUES
  ('test-rel-graph-A1A2', 'test-fam-graph-A',
    'test-person-A1', 'test-person-A2',
    'parent', 'parent', 'daughter', 'from', true, now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── 4. Create FamilyMember rows ────────────────────────────────────
--    caller_in_family_a is a member of family A.
--    caller_in_family_b is a member of family B (NOT family A).

INSERT INTO "FamilyMember" (id, "familyId", "userId", "role", "createdAt", "updatedAt")
VALUES
  ('test-fm-a1', 'test-fam-graph-A', :'caller_in_family_a'::text, 'admin',  now(), now()),
  ('test-fm-b1', 'test-fam-graph-B', :'caller_in_family_b'::text, 'admin',  now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── 5. Test get_family_graph ───────────────────────────────────────
--    We impersonate each caller with SET LOCAL ROLE + JWT request.jwt.claim.sub.
--    In a staging SQL editor that already runs as the authenticated user,
--    you can also just use `auth.uid()` directly — but the explicit SET
--    ROLE pattern below makes the test reproducible across users.

-- 5a. Member of family A calling get_family_graph on a person in family A
--     → expect 2 nodes (A1 + A2), 1 edge.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub": ":'caller_in_family_a'", "role": "authenticated"}';

SELECT
  'get_family_graph: member-of-A reads A → expects 2 nodes / 1 edge' AS test,
  jsonb_array_length(get_family_graph('test-person-A1')->'nodes') AS got_nodes,
  jsonb_array_length(get_family_graph('test-person-A1')->'edges') AS got_edges,
  'PASS' AS expected
WHERE jsonb_array_length(get_family_graph('test-person-A1')->'nodes') = 2;

-- 5b. Member of family B calling get_family_graph on a person in family A
--     → expect 0 nodes / 0 edges (membership check fails, empty result returned).
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub": ":'caller_in_family_b'", "role": "authenticated"}';

SELECT
  'get_family_graph: member-of-B reads A → expects 0 nodes / 0 edges' AS test,
  jsonb_array_length(get_family_graph('test-person-A1')->'nodes') AS got_nodes,
  jsonb_array_length(get_family_graph('test-person-A1')->'edges') AS got_edges,
  'PASS' AS expected
WHERE jsonb_array_length(get_family_graph('test-person-A1')->'nodes') = 0
  AND jsonb_array_length(get_family_graph('test-person-A1')->'edges') = 0;

-- 5c. Member of family A calling get_family_graph with a non-existent person_id
--     → expect 0 nodes / 0 edges (no existence leak).
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub": ":'caller_in_family_a'", "role": "authenticated"}';

SELECT
  'get_family_graph: caller passes non-existent person_id → expects 0 nodes / 0 edges' AS test,
  jsonb_array_length(get_family_graph('does-not-exist')->'nodes') AS got_nodes,
  jsonb_array_length(get_family_graph('does-not-exist')->'edges') AS got_edges,
  'PASS' AS expected
WHERE jsonb_array_length(get_family_graph('does-not-exist')->'nodes') = 0;

-- ── 6. Test get_member_branch ──────────────────────────────────────

-- 6a. Member of family A calling get_member_branch on a person in family A
--     → expect at least 1 node (the connected child).
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub": ":'caller_in_family_a'", "role": "authenticated"}';

SELECT
  'get_member_branch: member-of-A reads branch of A → expects >= 1 node' AS test,
  jsonb_array_length(get_member_branch('test-person-A1', 'generic', 2)->'nodes') AS got_nodes,
  'PASS' AS expected
WHERE jsonb_array_length(get_member_branch('test-person-A1', 'generic', 2)->'nodes') >= 1;

-- 6b. Member of family B calling get_member_branch on a person in family A
--     → expect 0 nodes / 0 edges.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub": ":'caller_in_family_b'", "role": "authenticated"}';

SELECT
  'get_member_branch: member-of-B reads branch of A → expects 0 nodes / 0 edges' AS test,
  jsonb_array_length(get_member_branch('test-person-A1', 'generic', 2)->'nodes') AS got_nodes,
  jsonb_array_length(get_member_branch('test-person-A1', 'generic', 2)->'edges') AS got_edges,
  'PASS' AS expected
WHERE jsonb_array_length(get_member_branch('test-person-A1', 'generic', 2)->'nodes') = 0
  AND jsonb_array_length(get_member_branch('test-person-A1', 'generic', 2)->'edges') = 0;

-- 6c. Member of family A calling get_member_branch with a non-existent person_id
--     → expect 0 nodes / 0 edges.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub": ":'caller_in_family_a'", "role": "authenticated"}';

SELECT
  'get_member_branch: caller passes non-existent person_id → expects 0 nodes / 0 edges' AS test,
  jsonb_array_length(get_member_branch('does-not-exist', 'generic', 2)->'nodes') AS got_nodes,
  'PASS' AS expected
WHERE jsonb_array_length(get_member_branch('does-not-exist', 'generic', 2)->'nodes') = 0;

-- ── 7. Reset role and cleanup ──────────────────────────────────────

RESET ROLE;
RESET request.jwt.claims;

DELETE FROM "Relationship" WHERE id = 'test-rel-graph-A1A2';
DELETE FROM "FamilyMember" WHERE id IN ('test-fm-a1', 'test-fm-b1');
DELETE FROM "Person" WHERE id IN ('test-person-A1', 'test-person-A2', 'test-person-B1');
DELETE FROM "Family" WHERE id IN ('test-fam-graph-A', 'test-fam-graph-B');
