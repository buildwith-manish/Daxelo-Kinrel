-- ============================================
-- DAXELO KINREL — Row Level Security Policies
-- Run these in Supabase SQL Editor
-- ============================================

-- Enable RLS on all tables
ALTER TABLE "User" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Family" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "FamilyMember" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Relationship" ENABLE ROW LEVEL SECURITY;

-- Users can only see/edit their own profile
CREATE POLICY "Users manage own profile"
ON "User"
FOR ALL
USING (id = auth.uid()::text)
WITH CHECK (id = auth.uid()::text);

-- Users can only see families they belong to
CREATE POLICY "Users see own families"
ON "Family"
FOR SELECT
USING (
  id IN (
    SELECT "familyId" FROM "FamilyMember"
    WHERE "userId" = auth.uid()::text
  )
);

-- Users can create families
CREATE POLICY "Users create families"
ON "Family"
FOR INSERT
WITH CHECK (true);

-- Family members visible to family members only
CREATE POLICY "Family members see own family"
ON "FamilyMember"
FOR ALL
USING (
  "familyId" IN (
    SELECT "familyId" FROM "FamilyMember"
    WHERE "userId" = auth.uid()::text
  )
);

-- Relationships visible to family members only
CREATE POLICY "Family relationships are private"
ON "Relationship"
FOR ALL
USING (
  "familyId" IN (
    SELECT "familyId" FROM "FamilyMember"
    WHERE "userId" = auth.uid()::text
  )
);

-- ============================================
-- Instructions:
-- 1. Go to supabase.com → your project
-- 2. Click SQL Editor
-- 3. Paste and run these policies
-- 4. Verify in Authentication → Policies
-- ============================================
