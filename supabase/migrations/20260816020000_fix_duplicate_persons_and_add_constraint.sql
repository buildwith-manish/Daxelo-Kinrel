-- 20260816020000_fix_duplicate_persons_and_add_constraint.sql
--
-- v5.12: Fix duplicate Person rows and add a hard DB constraint.
--
-- PART 1: Clean up existing duplicates
-- For each (familyId, linkedUserId) group with more than one row,
-- keep the oldest and soft-delete the newer duplicates.
-- Before soft-deleting, reassign any relationships from the duplicate
-- to the surviving Person.

-- Find and fix duplicates where linkedUserId is set
DO $$
DECLARE
    dup_record RECORD;
    surviving_id TEXT;
BEGIN
    FOR dup_record IN
        SELECT "familyId", "linkedUserId",
               array_agg(id ORDER BY "createdAt" ASC) as ids,
               count(*) as cnt
        FROM "Person"
        WHERE "linkedUserId" IS NOT NULL
          AND "deletedAt" IS NULL
        GROUP BY "familyId", "linkedUserId"
        HAVING count(*) > 1
    LOOP
        surviving_id := dup_record.ids[1];
        RAISE NOTICE 'Duplicates found for familyId=%, linkedUserId=%: keeping %, soft-deleting %',
            dup_record."familyId", dup_record."linkedUserId",
            surviving_id, dup_record.ids[2:];

        -- Reassign relationships from duplicates to surviving person
        UPDATE "Relationship"
        SET "fromPersonId" = surviving_id,
            "updatedAt" = now()
        WHERE "fromPersonId" = ANY(dup_record.ids[2:])
          AND "familyId" = dup_record."familyId";

        UPDATE "Relationship"
        SET "toPersonId" = surviving_id,
            "updatedAt" = now()
        WHERE "toPersonId" = ANY(dup_record.ids[2:])
          AND "familyId" = dup_record."familyId";

        -- Soft-delete the duplicate Person rows
        UPDATE "Person"
        SET "deletedAt" = now(),
            "linkedUserId" = NULL,
            "updatedAt" = now()
        WHERE id = ANY(dup_record.ids[2:]);
    END LOOP;
END $$;

-- PART 2: Clean up duplicates in the "Perspective" family where
-- linkedUserId is NULL but name + familyId match
DO $$
DECLARE
    dup_record RECORD;
    surviving_id TEXT;
BEGIN
    FOR dup_record IN
        SELECT "familyId", name,
               array_agg(id ORDER BY "createdAt" ASC) as ids,
               count(*) as cnt
        FROM "Person"
        WHERE "linkedUserId" IS NULL
          AND "deletedAt" IS NULL
          AND "isAnchor" = false
        GROUP BY "familyId", name
        HAVING count(*) > 1
    LOOP
        surviving_id := dup_record.ids[1];
        RAISE NOTICE 'Name duplicates found for familyId=%, name=%: keeping %, soft-deleting %',
            dup_record."familyId", dup_record.name,
            surviving_id, dup_record.ids[2:];

        -- Reassign relationships
        UPDATE "Relationship"
        SET "fromPersonId" = surviving_id,
            "updatedAt" = now()
        WHERE "fromPersonId" = ANY(dup_record.ids[2:])
          AND "familyId" = dup_record."familyId";

        UPDATE "Relationship"
        SET "toPersonId" = surviving_id,
            "updatedAt" = now()
        WHERE "toPersonId" = ANY(dup_record.ids[2:])
          AND "familyId" = dup_record."familyId";

        -- Soft-delete duplicates
        UPDATE "Person"
        SET "deletedAt" = now(),
            "updatedAt" = now()
        WHERE id = ANY(dup_record.ids[2:]);
    END LOOP;
END $$;

-- PART 3: Add partial unique index to prevent future duplicates
-- This ensures only ONE Person per (familyId, linkedUserId) can exist
-- at a time. The DB itself rejects the second insert, making this
-- class of bug structurally impossible.
CREATE UNIQUE INDEX IF NOT EXISTS "Person_familyId_linkedUserId_unique"
ON "Person" ("familyId", "linkedUserId")
WHERE "linkedUserId" IS NOT NULL AND "deletedAt" IS NULL;

-- Verify the constraint was created
SELECT 'Constraint created' as status,
       indexname as index_name
FROM pg_indexes
WHERE indexname = 'Person_familyId_linkedUserId_unique';
