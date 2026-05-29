-- ============================================================
-- DAXELO KINREL — Production Indexes for Supabase/PostgreSQL
-- Run these AFTER the initial migration on production
-- Use CREATE INDEX CONCURRENTLY to avoid locking the table
-- ============================================================

-- ── Enable pg_trgm extension for fuzzy/trigram search ─────────────
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ── Person table indexes ──────────────────────────────────────────
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Person_username_idx" ON "Person"("username");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Person_name_idx" ON "Person"("name");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Person_gotra_idx" ON "Person"("gotra");

-- ── Family table indexes ─────────────────────────────────────────
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Family_kinFamilyId_idx" ON "Family"("kinFamilyId");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Family_username_idx" ON "Family"("username");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Family_name_idx" ON "Family"("name");

-- ── Relationship composite index ─────────────────────────────────
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Relationship_fromPersonId_toPersonId_idx"
  ON "Relationship"("fromPersonId", "toPersonId");

-- ── FamilyMember composite index ─────────────────────────────────
CREATE INDEX CONCURRENTLY IF NOT EXISTS "FamilyMember_familyId_userId_idx"
  ON "FamilyMember"("familyId", "userId");

-- ── GIN indexes for trigram (fuzzy) search ───────────────────────
-- These enable fast ILIKE '%query%' and similarity() searches
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Person_name_trgm_idx"
  ON "Person" USING GIN ("name" gin_trgm_ops);

CREATE INDEX CONCURRENTLY IF NOT EXISTS "User_username_trgm_idx"
  ON "User" USING GIN ("username" gin_trgm_ops);

CREATE INDEX CONCURRENTLY IF NOT EXISTS "User_name_trgm_idx"
  ON "User" USING GIN ("name" gin_trgm_ops);

-- ── Username uniqueness constraint at DB level ───────────────────
-- Note: Prisma already creates unique constraints via @unique annotation,
-- but this ensures it at the DB level for the UsernameChangeLog table
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "UsernameChangeLog_id_idx"
  ON "UsernameChangeLog"("id");

-- ── Additional useful indexes for production ─────────────────────
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Family_gotra_idx" ON "Family"("gotra");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Family_privacyMode_idx" ON "Family"("privacyMode");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "User_profileVisibility_idx" ON "User"("profileVisibility");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Person_privacyLevel_idx" ON "Person"("privacyLevel");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "Relationship_familyId_isActive_idx"
  ON "Relationship"("familyId", "isActive");

-- ============================================================
-- Instructions:
-- 1. Connect to your Supabase PostgreSQL database
-- 2. Run each CREATE INDEX CONCURRENTLY statement one at a time
--    (CONCURRENTLY cannot run inside a transaction block)
-- 3. CONCURRENTLY builds the index without locking the table for writes
-- 4. For trigram search queries, use:
--    SELECT * FROM "User" WHERE username % 'search_term';  -- similarity
--    SELECT * FROM "User" WHERE username ILIKE '%search%'; -- pattern
-- ============================================================
