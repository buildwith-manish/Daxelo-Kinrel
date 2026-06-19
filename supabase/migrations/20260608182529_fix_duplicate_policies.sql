-- ============================================================
-- Migration: fix_duplicate_policies
-- Version:  20260608182529
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ══════════════════════════════════════════════
-- FIX 1: Drop duplicate/conflicting policies
-- Keep the stronger FamilyMember-based policies
-- ══════════════════════════════════════════════

-- Family SELECT: had 3 overlapping — keep "Family members can read family data"
DROP POLICY IF EXISTS "Users can view their families" ON "Family";
DROP POLICY IF EXISTS "Users see own families" ON "Family";

-- Family INSERT: had 2 — keep "Authenticated users can create families"
DROP POLICY IF EXISTS "Users create families" ON "Family";

-- Family UPDATE: had 2 — keep "Only owners and admins can update family settings"
DROP POLICY IF EXISTS "Creators can update families" ON "Family";

-- Person SELECT: had 2 — keep "Members can see persons in their families"
DROP POLICY IF EXISTS "Users can view family persons" ON "Person";

-- Person INSERT: had 2 — keep "Members can insert persons in their families"
DROP POLICY IF EXISTS "Users can insert family persons" ON "Person";

-- Person UPDATE: had 2 — keep "Members can update persons in their families"
DROP POLICY IF EXISTS "Users can update family persons" ON "Person";

-- Relationship SELECT: had 2 — keep "Members can see relationships in their families"
DROP POLICY IF EXISTS "Users can view family relationships" ON "Relationship";

-- Relationship INSERT: had 2 — keep "Members can insert relationships in their families"
DROP POLICY IF EXISTS "Users can insert family relationships" ON "Relationship";

-- Relationship ALL: overlaps with specific INSERT/SELECT/UPDATE/DELETE policies — remove broad one
DROP POLICY IF EXISTS "Family relationships are private" ON "Relationship";
