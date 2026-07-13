-- ───────────────────────────────────────────────────────────────────────────
-- P10.1 — Create Place table for the Family Atlas
-- ───────────────────────────────────────────────────────────────────────────
-- A family place is a meaningful location tied to a family's story:
-- homes, birthplaces, wedding venues, memorials, family businesses,
-- schools, and other important places.
--
-- RLS: family-scoped. Only family members can read/write their own
-- family's places. Place addresses are family-private.
--
-- `validFrom` / `validTo` are time-window bounds used by the timeline
-- scrubber (P10.7). NULL on either side means "unbounded" on that side.
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "Place" (
    "id"          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"    TEXT NOT NULL,
    "name"        TEXT NOT NULL,
    "placeType"   TEXT NOT NULL, -- current_home | childhood_home | ancestral_home |
                                 -- birthplace | wedding | memorial |
                                 -- family_business | school | important_place
    "lat"         DOUBLE PRECISION NOT NULL,
    "lng"         DOUBLE PRECISION NOT NULL,
    "address"     TEXT,
    "personId"    TEXT,
    "description" TEXT,
    "validFrom"   TIMESTAMPTZ,
    "validTo"     TIMESTAMPTZ,
    "memoryCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt"   TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updatedAt"   TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "Place_familyId_fkey"
        FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE,
    CONSTRAINT "Place_personId_fkey"
        FOREIGN KEY ("personId") REFERENCES "Person"("id") ON DELETE SET NULL,
    CONSTRAINT "Place_lat_valid"  CHECK ("lat"  BETWEEN -90.0  AND 90.0),
    CONSTRAINT "Place_lng_valid"  CHECK ("lng"  BETWEEN -180.0 AND 180.0)
);

CREATE INDEX IF NOT EXISTS "Place_familyId_idx"  ON "Place"("familyId");
CREATE INDEX IF NOT EXISTS "Place_personId_idx"  ON "Place"("personId");
CREATE INDEX IF NOT EXISTS "Place_placeType_idx" ON "Place"("placeType");
CREATE INDEX IF NOT EXISTS "Place_validFrom_idx" ON "Place"("validFrom");
CREATE INDEX IF NOT EXISTS "Place_validTo_idx"   ON "Place"("validTo");

-- ───────────────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────────────
-- A user can read/write Place rows for any family they are a member of.
-- This mirrors the existing RLS pattern used by Person/FamilyPost etc.
-- ───────────────────────────────────────────────────────────────────────────

ALTER TABLE "Place" ENABLE ROW LEVEL SECURITY;

-- READ: user must be a member of the place's family.
DROP POLICY IF EXISTS "Place_select_family_members" ON "Place";
CREATE POLICY "Place_select_family_members" ON "Place"
    FOR SELECT
    USING (
        "familyId" IN (
            SELECT "familyId"
            FROM "FamilyMember"
            WHERE "userId" = auth.uid()
        )
    );

-- INSERT: user must be a member of the place's family (any role).
DROP POLICY IF EXISTS "Place_insert_family_members" ON "Place";
CREATE POLICY "Place_insert_family_members" ON "Place"
    FOR INSERT
    WITH CHECK (
        "familyId" IN (
            SELECT "familyId"
            FROM "FamilyMember"
            WHERE "userId" = auth.uid()
        )
    );

-- UPDATE: user must be a member of the place's family.
DROP POLICY IF EXISTS "Place_update_family_members" ON "Place";
CREATE POLICY "Place_update_family_members" ON "Place"
    FOR UPDATE
    USING (
        "familyId" IN (
            SELECT "familyId"
            FROM "FamilyMember"
            WHERE "userId" = auth.uid()
        )
    )
    WITH CHECK (
        "familyId" IN (
            SELECT "familyId"
            FROM "FamilyMember"
            WHERE "userId" = auth.uid()
        )
    );

-- DELETE: user must be a member of the place's family.
DROP POLICY IF EXISTS "Place_delete_family_members" ON "Place";
CREATE POLICY "Place_delete_family_members" ON "Place"
    FOR DELETE
    USING (
        "familyId" IN (
            SELECT "familyId"
            FROM "FamilyMember"
            WHERE "userId" = auth.uid()
        )
    );

-- ───────────────────────────────────────────────────────────────────────────
-- updatedAt trigger
-- ───────────────────────────────────────────────────────────────────────────
-- Mirror Prisma's @updatedAt behaviour at the database level so rows
-- touched by raw SQL or RLS-protected writes still get a fresh timestamp.
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "Place_touch_updatedAt"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."updatedAt" = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "Place_updatedAt_trigger" ON "Place";
CREATE TRIGGER "Place_updatedAt_trigger"
    BEFORE UPDATE ON "Place"
    FOR EACH ROW
    EXECUTE FUNCTION "Place_touch_updatedAt"();
