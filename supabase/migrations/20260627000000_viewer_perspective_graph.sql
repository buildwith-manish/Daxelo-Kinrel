-- v2.2: Viewer-perspective-aware family graph
--
-- Adds bidirectional label columns to the Relationship table and a
-- RelationshipInverse lookup table so every relationship stores BOTH
-- directions (e.g., "father" → "son"). A trigger auto-fills the
-- inverse label on every INSERT/UPDATE.
--
-- Also creates the get_viewer_family_graph RPC that returns the graph
-- with perspective-resolved labels for a given viewer Person ID.

-- ── Step 2: Add labelAtoB and labelBtoA columns ──────────────────────
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "labelAtoB" TEXT;
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "labelBtoA" TEXT;

-- Migrate existing data: labelAtoB = relationshipKey
UPDATE "Relationship"
  SET "labelAtoB" = "relationshipKey"
WHERE "labelAtoB" IS NULL AND "relationshipKey" IS NOT NULL;

-- ── Step 3: Create RelationshipInverse lookup table ───────────────────
CREATE TABLE IF NOT EXISTS "RelationshipInverse" (
  "relationshipType" TEXT PRIMARY KEY,
  "inverseType"      TEXT NOT NULL
);

-- Core relationships
INSERT INTO "RelationshipInverse" ("relationshipType", "inverseType") VALUES
  ('father', 'son'), ('mother', 'son'), ('son', 'father'), ('daughter', 'father'),
  ('brother', 'brother'), ('sister', 'sister'), ('husband', 'wife'), ('wife', 'husband'),
  ('parent', 'child'), ('child', 'parent'), ('sibling', 'sibling'), ('spouse', 'spouse'),
  ('elder_brother', 'younger_brother'), ('younger_brother', 'elder_brother'),
  ('elder_sister', 'younger_sister'), ('younger_sister', 'elder_sister'),
  ('elder_sibling', 'younger_sibling'), ('younger_sibling', 'elder_sibling')
ON CONFLICT DO NOTHING;

-- Grandparents
INSERT INTO "RelationshipInverse" ("relationshipType", "inverseType") VALUES
  ('grandfather', 'grandson'), ('grandmother', 'grandson'),
  ('grandson', 'grandfather'), ('granddaughter', 'grandfather'),
  ('grandparent', 'grandchild'), ('grandchild', 'grandparent'),
  ('paternal_grandfather', 'grandson'), ('paternal_grandmother', 'grandson'),
  ('maternal_grandfather', 'grandson'), ('maternal_grandmother', 'grandson')
ON CONFLICT DO NOTHING;

-- Aunt/Uncle/Cousin (Indian compound forms)
INSERT INTO "RelationshipInverse" ("relationshipType", "inverseType") VALUES
  ('uncle', 'nephew'), ('aunt', 'nephew'), ('nephew', 'uncle'), ('niece', 'uncle'),
  ('cousin', 'cousin'),
  ('fathers_elder_brother', 'nephew'), ('fathers_younger_brother', 'nephew'),
  ('fathers_sister', 'nephew'), ('mothers_brother', 'nephew'), ('mothers_sister', 'nephew'),
  ('fathers_elder_brothers_wife', 'nephew'), ('fathers_younger_brothers_wife', 'nephew'),
  ('fathers_sisters_husband', 'nephew'), ('mothers_brothers_wife', 'nephew'),
  ('mothers_sisters_husband', 'nephew'),
  ('brothers_son', 'uncle'), ('brothers_daughter', 'uncle'),
  ('sisters_son', 'uncle'), ('sisters_daughter', 'uncle')
ON CONFLICT DO NOTHING;

-- In-laws
INSERT INTO "RelationshipInverse" ("relationshipType", "inverseType") VALUES
  ('father_in_law', 'son_in_law'), ('mother_in_law', 'son_in_law'),
  ('son_in_law', 'father_in_law'), ('daughter_in_law', 'father_in_law'),
  ('brother_in_law', 'brother_in_law'), ('sister_in_law', 'sister_in_law'),
  ('husbands_father', 'son_in_law'), ('husbands_mother', 'son_in_law'),
  ('wifes_father', 'son_in_law'), ('wifes_mother', 'son_in_law'),
  ('husbands_elder_brother', 'brother_in_law'), ('husbands_younger_brother', 'brother_in_law'),
  ('husbands_sister', 'sister_in_law'), ('wifes_brother', 'brother_in_law'),
  ('wifes_sister', 'sister_in_law'),
  ('sons_wife', 'father_in_law'), ('daughters_husband', 'father_in_law')
ON CONFLICT DO NOTHING;

-- Step/extended
INSERT INTO "RelationshipInverse" ("relationshipType", "inverseType") VALUES
  ('step_father', 'step_son'), ('step_mother', 'step_son'),
  ('step_son', 'step_father'), ('step_daughter', 'step_father'),
  ('step_brother', 'step_brother'), ('step_sister', 'step_sister'),
  ('half_brother', 'half_brother'), ('half_sister', 'half_sister'),
  ('stepfather', 'stepchild'), ('stepmother', 'stepchild'),
  ('stepchild', 'stepfather'), ('stepson', 'step_father'),
  ('stepdaughter', 'step_father'), ('stepbrother', 'stepbrother'),
  ('stepsister', 'stepsister'),
  ('related', 'related'), ('unknown', 'unknown')
ON CONFLICT DO NOTHING;

-- ── Step 4: Auto-populate labelBtoA ──────────────────────────────────
UPDATE "Relationship" r
  SET "labelBtoA" = ri."inverseType"
  FROM "RelationshipInverse" ri
  WHERE ri."relationshipType" = r."labelAtoB"
    AND r."labelBtoA" IS NULL;

-- ── Step 5: fill_inverse_label trigger ───────────────────────────────
CREATE OR REPLACE FUNCTION fill_inverse_label()
RETURNS TRIGGER AS $$
BEGIN
  -- If labelAtoB is null but relationshipKey exists, use it
  IF NEW."labelAtoB" IS NULL AND NEW."relationshipKey" IS NOT NULL THEN
    NEW."labelAtoB" := NEW."relationshipKey";
  END IF;
  -- If labelBtoA is null, look up the inverse
  IF NEW."labelBtoA" IS NULL AND NEW."labelAtoB" IS NOT NULL THEN
    SELECT "inverseType" INTO NEW."labelBtoA"
    FROM "RelationshipInverse"
    WHERE "relationshipType" = NEW."labelAtoB";
  END IF;
  -- If labelAtoB is null but labelBtoA exists, look up the inverse
  IF NEW."labelAtoB" IS NULL AND NEW."labelBtoA" IS NOT NULL THEN
    SELECT "inverseType" INTO NEW."labelAtoB"
    FROM "RelationshipInverse"
    WHERE "relationshipType" = NEW."labelBtoA";
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_fill_inverse_label ON "Relationship";
CREATE TRIGGER trg_fill_inverse_label
  BEFORE INSERT OR UPDATE ON "Relationship"
  FOR EACH ROW EXECUTE FUNCTION fill_inverse_label();

-- ── Step 6: get_viewer_family_graph RPC ──────────────────────────────
-- Returns the family graph with perspective-resolved labels for a
-- given viewer Person ID. Security: verifies the viewer is linked to
-- the authenticated user (auth.uid()) before returning data.
CREATE OR REPLACE FUNCTION get_viewer_family_graph(
  p_family_id  TEXT,
  p_viewer_id  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result JSONB;
  v_viewer_linked TEXT;
BEGIN
  -- Security: verify the viewer Person exists and is linked to auth.uid()
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

  IF v_viewer_linked != auth.uid()::text THEN
    RETURN jsonb_build_object(
      'nodes', '[]'::jsonb, 'edges', '[]'::jsonb,
      'isTruncated', false, 'totalCount', 0,
      'error', 'Access denied: viewer not linked to authenticated user'
    );
  END IF;

  SELECT jsonb_build_object(
    'nodes', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'username', p.username,
        'avatarUrl', p."photoUrl",
        'gender', p.gender,
        'isAnchor', p."isAnchor",
        'isDeceased', p."isDeceased",
        'visibility', p.visibility,
        'generationIndex', p."generationIndex",
        'isViewer', (p.id = p_viewer_id),
        'familyId', p."familyId"
      )), '[]'::jsonb)
      FROM "Person" p
      WHERE p."familyId" = p_family_id AND p."deletedAt" IS NULL
    ),
    'edges', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
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
          ELSE r."labelAtoB"
        END,
        'labelAtoB', r."labelAtoB",
        'labelBtoA', r."labelBtoA",
        'isPrivate', COALESCE(r.is_private, false),
        'isActive', r."isActive"
      )), '[]'::jsonb)
      FROM "Relationship" r
      WHERE r."familyId" = p_family_id AND r."isActive" = true
    ),
    'totalCount', (
      SELECT count(*) FROM "Person"
      WHERE "familyId" = p_family_id AND "deletedAt" IS NULL
    ),
    'isTruncated', false
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_viewer_family_graph(text, text) TO authenticated, anon;

-- ── Step 7: RLS on RelationshipInverse ───────────────────────────────
ALTER TABLE "RelationshipInverse" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "inverse_select_all" ON "RelationshipInverse";
CREATE POLICY "inverse_select_all" ON "RelationshipInverse"
  FOR SELECT USING (true);
GRANT SELECT ON "RelationshipInverse" TO authenticated, anon;
