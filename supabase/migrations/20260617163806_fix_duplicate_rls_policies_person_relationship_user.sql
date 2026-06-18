-- ============================================================
-- Migration: fix_duplicate_rls_policies_person_relationship_user
-- Version:  20260617163806
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ============================================================
-- FIX 1: Remove old weak duplicate RLS policies on Person
-- The newer person_select/insert/update/delete policies are
-- correct (role-aware + createdBy). The old "Members can..."
-- policies are weaker and cause confusion. Drop them.
-- ============================================================

DROP POLICY IF EXISTS "Members can see persons in their families" ON "Person";
DROP POLICY IF EXISTS "Members can insert persons in their families" ON "Person";
DROP POLICY IF EXISTS "Members can update persons in their families" ON "Person";
DROP POLICY IF EXISTS "Members can delete persons in their families" ON "Person";

-- ============================================================
-- FIX 2: Remove old weak duplicate RLS policies on Relationship
-- ============================================================

DROP POLICY IF EXISTS "Members can see relationships in their families" ON "Relationship";
DROP POLICY IF EXISTS "Members can insert relationships in their families" ON "Relationship";
DROP POLICY IF EXISTS "Members can update relationships in their families" ON "Relationship";
DROP POLICY IF EXISTS "Members can delete relationships in their families" ON "Relationship";

-- ============================================================
-- FIX 3: Remove duplicate ALL policy on User table
-- "Users manage own profile" (ALL) overlaps with the explicit
-- INSERT/SELECT/UPDATE policies. The ALL policy also doesn't
-- have a WITH CHECK on INSERT, which is a security gap.
-- Keep the explicit per-command policies which are stricter.
-- ============================================================

DROP POLICY IF EXISTS "Users manage own profile" ON "User";
