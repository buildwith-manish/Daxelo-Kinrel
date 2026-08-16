-- 20260816010000_test_viewer_perspective_rpc.sql
--
-- v5.8 TEST: Verify the get_viewer_family_graph RPC returns correct
-- perspective-based labels when called with different viewer IDs.

-- Step 1: Create test data
INSERT INTO "Family" (id, name, "createdBy", "memberCount", "createdAt", "updatedAt")
VALUES (
    'test-fam-vp-run1',
    'Test Viewer Perspective',
    null, 2, now(), now()
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO "Person" (id, "familyId", name, gender, "isAnchor", "linkedUserId", "createdAt", "updatedAt")
VALUES
    ('test-parent-run1', 'test-fam-vp-run1', 'TestParent', 'male', true,
     '00000000-0000-0000-0000-000000000001'::uuid, now(), now()),
    ('test-child-run1', 'test-fam-vp-run1', 'TestChild', 'male', false,
     '00000000-0000-0000-0000-000000000002'::uuid, now(), now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO "Relationship" (id, "familyId", "fromPersonId", "toPersonId",
    "relationshipKey", "relationshipType", "labelAtoB", "direction", "isActive", "createdAt", "updatedAt")
VALUES (
    'test-rel-run1', 'test-fam-vp-run1',
    'test-parent-run1', 'test-child-run1',
    'parent', 'parent', 'son', 'from', true, now(), now()
)
ON CONFLICT (id) DO NOTHING;

-- Step 2: Call RPC with viewer = Parent → expect child labeled 'son'
-- Step 3: Call RPC with viewer = Child → expect parent labeled 'parent'
SELECT
    'Viewer=Parent, ChildLabel' AS test,
    (
        SELECT e->>'label'
        FROM jsonb_array_elements(
            get_viewer_family_graph('test-fam-vp-run1', 'test-parent-run1')->'edges'
        ) AS e
        WHERE e->>'sourceId' = 'test-child-run1'
           OR e->>'targetId' = 'test-child-run1'
        LIMIT 1
    ) AS expected_son
UNION ALL
SELECT
    'Viewer=Child, ParentLabel' AS test,
    (
        SELECT e->>'label'
        FROM jsonb_array_elements(
            get_viewer_family_graph('test-fam-vp-run1', 'test-child-run1')->'edges'
        ) AS e
        WHERE e->>'sourceId' = 'test-parent-run1'
           OR e->>'targetId' = 'test-parent-run1'
        LIMIT 1
    ) AS expected_parent;

-- Step 4: Cleanup
DELETE FROM "Relationship" WHERE id = 'test-rel-run1';
DELETE FROM "Person" WHERE id IN ('test-parent-run1', 'test-child-run1');
DELETE FROM "Family" WHERE id = 'test-fam-vp-run1';
