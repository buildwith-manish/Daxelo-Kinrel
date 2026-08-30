-- supabase/tests/audit_labelAtoB_convention.sql
--
-- v5.17 STEP 4: READ-ONLY audit of existing relationships whose
-- labelAtoB may be stored backwards due to the add_person_sheet.dart
-- convention bug (fixed in v5.17).
--
-- This query flags relationships where:
--   - relationshipKey is 'parent' (fundamental edge)
--   - labelAtoB is a child-type label ('son', 'daughter', 'child')
--     instead of a parent-type label ('father', 'mother', 'parent')
--
-- Under the canonical convention:
--   labelAtoB = "toPerson is fromPerson's <labelAtoB>"
--   If relationshipKey='parent', labelAtoB should be 'father'/'mother'/'parent'
--   (toPerson is the parent). If labelAtoB is 'son'/'daughter'/'child',
--   it's backwards (toPerson is being described as the child, but
--   relationshipKey='parent' means toPerson IS the parent).
--
-- This is informational only — do NOT auto-correct. The flagged rows
-- need manual review because some may have been created by
-- relationship_picker_flow.dart (which was always correct) with
-- legitimate child-type labels.
--
-- Run manually in the Supabase SQL editor.

SELECT
    r.id as relationship_id,
    r."familyId",
    f.name as family_name,
    r."fromPersonId",
    p_from.name as from_person_name,
    r."toPersonId",
    p_to.name as to_person_name,
    r."relationshipKey",
    r."labelAtoB",
    r."labelBtoA",
    r."direction",
    r."createdAt",
    CASE
        WHEN r."relationshipKey" = 'parent'
            AND r."labelAtoB" IN ('son', 'daughter', 'child')
        THEN 'SUSPECT: parent edge with child-type label (possibly inverted)'
        WHEN r."relationshipKey" = 'parent'
            AND r."labelAtoB" IN ('grandson', 'granddaughter', 'grandchild')
        THEN 'SUSPECT: parent edge with grandchild-type label'
        WHEN r."relationshipKey" = 'parent'
            AND r."labelAtoB" IN ('nephew', 'niece', 'uncle', 'aunt', 'cousin')
        THEN 'SUSPECT: parent edge with extended-family label'
        ELSE 'OK'
    END as audit_status
FROM "Relationship" r
JOIN "Family" f ON r."familyId" = f.id
JOIN "Person" p_from ON r."fromPersonId" = p_from.id
JOIN "Person" p_to ON r."toPersonId" = p_to.id
WHERE r."isActive" = true
  AND r."direction" != 'inverse'  -- Only check forward edges
  AND r."relationshipKey" = 'parent'
  AND r."labelAtoB" IS NOT NULL
  AND r."labelAtoB" NOT IN ('father', 'mother', 'parent')
ORDER BY r."createdAt" DESC;
