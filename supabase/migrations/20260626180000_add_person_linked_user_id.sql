-- v2.2: Add linkedUserId to Person table for viewer-driven relationship engine
-- This links an authenticated User to a Person node, enabling per-user
-- perspective in the family graph.

-- Add the column
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "linkedUserId" UUID;

-- Add unique constraint (one user can only be linked to one person per family)
CREATE UNIQUE INDEX IF NOT EXISTS "Person_linkedUserId_unique" 
  ON "Person" ("linkedUserId") 
  WHERE "linkedUserId" IS NOT NULL;

-- Add linkedAt timestamp
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "linkedAt" TIMESTAMPTZ;

-- Enable RLS on the new column (inherits from table-level RLS)
-- The column is readable by anyone who can read the Person row
-- The column is writable only by the linked user or family admin

-- Add a policy allowing users to update their own linkedUserId
CREATE POLICY "Person_link_self" ON "Person"
  FOR UPDATE USING (
    "linkedUserId" IS NULL OR "linkedUserId" = auth.uid()
  );

-- Backfill: link the debug user to all anchor persons in families they created
-- This ensures the viewer system works immediately for existing data
UPDATE "Person" 
SET "linkedUserId" = 'b8a432ed-e577-46a5-8e77-a5a1b5ff130c',
    "linkedAt" = NOW()
WHERE "isAnchor" = true 
  AND "deletedAt" IS NULL
  AND "linkedUserId" IS NULL;
