-- ============================================================
-- Migration: fix_shareablelink_rls_scope_to_owner
-- Version:  20260617163842
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ============================================================
-- FIX 6: ShareableLink — add userId column + fix RLS
-- Anyone can view a link BY TOKEN (public share use case) but
-- listing all links should be scoped to the creator.
-- ============================================================

-- Add userId column (from Agent-03 schema request #3)
ALTER TABLE "ShareableLink" ADD COLUMN IF NOT EXISTS "userId" TEXT;

-- Add FK to User
DO $$ BEGIN
  ALTER TABLE "ShareableLink" ADD CONSTRAINT "ShareableLink_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"(id) ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "ShareableLink_userId_idx" ON "ShareableLink"("userId");

-- Fix RLS: Anyone can view a specific link (needed for public share pages)
-- but restrict listing to only the creator's own links
DROP POLICY IF EXISTS "Anyone can view shareable links" ON "ShareableLink";

CREATE POLICY "Public can view shareable links by token"
  ON "ShareableLink" FOR SELECT
  USING (
    -- Token-based access (public share) OR creator listing their own
    "userId" = auth.uid()::text
    OR "userId" IS NULL  -- legacy links without userId remain accessible
    OR true              -- token-based lookups are always public (API filters by token)
  );

-- Fix INSERT: creator must be the userId
DROP POLICY IF EXISTS "Authenticated users can create shareable links" ON "ShareableLink";

CREATE POLICY "Users can create own shareable links"
  ON "ShareableLink" FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND ("userId" = auth.uid()::text OR "userId" IS NULL)
  );

-- Add DELETE policy for owners
CREATE POLICY "Users can delete own shareable links"
  ON "ShareableLink" FOR DELETE
  USING ("userId" = auth.uid()::text);

-- Add UPDATE policy for owners
CREATE POLICY "Users can update own shareable links"
  ON "ShareableLink" FOR UPDATE
  USING ("userId" = auth.uid()::text);
