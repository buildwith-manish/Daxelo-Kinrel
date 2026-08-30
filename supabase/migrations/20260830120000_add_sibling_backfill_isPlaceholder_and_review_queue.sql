-- ============================================================
-- Migration: add_sibling_backfill_isPlaceholder_and_review_queue
-- Version:  20260830120000
--
-- Sibling Relationship Fix — Shared-Parent Backfill (Implementation
-- Prompt §1.1 + §3).
--
-- Two schema additions, both nullable-safe defaults so no backfill
-- is needed for existing rows:
--
--   1. Person.isPlaceholder  BOOLEAN NOT NULL DEFAULT false
--      true for auto-created "Unknown parent" stand-ins generated
--      when a brother/sister edge is added but neither sibling has a
--      recorded parent. The Tree view renders these with a neutral
--      silhouette + "Unknown parent" label.
--
--   2. RelationshipReviewFlag  (new table)
--      Lightweight review-queue flag for the ambiguous case (§1.2
--      last branch) where two siblings BOTH already have different
--      recorded parents. The system does NOT auto-merge parent records
--      in this case (that's a human decision). Instead it writes a
--      row here so an admin / family owner can review and confirm/merge
--      if appropriate.
--
-- No structural relationship-model changes — only a single new boolean
-- column on Person and one new review-queue table. The existing
-- Relationship model is unchanged.
-- ============================================================

-- ── §1.1: Person.isPlaceholder column ──────────────────────────────
ALTER TABLE "Person"
  ADD COLUMN IF NOT EXISTS "isPlaceholder" BOOLEAN NOT NULL DEFAULT false;

-- Index for the Tree view's WHERE isPlaceholder = false filter
-- (placeholders render with a distinct style, so the view often
-- wants to query non-placeholder persons separately).
CREATE INDEX IF NOT EXISTS "Person_familyId_isPlaceholder_idx"
  ON "Person" ("familyId", "isPlaceholder");

-- ── §3: RelationshipReviewFlag table ───────────────────────────────
CREATE TABLE IF NOT EXISTS "RelationshipReviewFlag" (
    "id" TEXT NOT NULL,
    "familyId" TEXT NOT NULL,
    "sourceRelationshipId" TEXT NOT NULL,
    "parentAPersonId" TEXT,
    "parentBPersonId" TEXT,
    "reason" TEXT NOT NULL DEFAULT 'sibling_parent_mismatch',
    "status" TEXT NOT NULL DEFAULT 'pending',
    "note" TEXT,
    "createdByUserId" TEXT,
    "resolvedByUserId" TEXT,
    "resolvedAt" TIMESTAMPTZ,
    "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "RelationshipReviewFlag_pkey" PRIMARY KEY ("id")
);

-- One flag per (edge, reason) — prevents duplicate flags for the
-- same ambiguous case on the same edge.
CREATE UNIQUE INDEX IF NOT EXISTS "RelationshipReviewFlag_sourceRelationshipId_reason_key"
  ON "RelationshipReviewFlag" ("sourceRelationshipId", "reason");

-- Index for the review queue's "pending flags for this family" query.
CREATE INDEX IF NOT EXISTS "RelationshipReviewFlag_familyId_status_idx"
  ON "RelationshipReviewFlag" ("familyId", "status");

-- Index for filtering by reason (e.g. "show me all sibling_parent_mismatch flags").
CREATE INDEX IF NOT EXISTS "RelationshipReviewFlag_familyId_reason_status_idx"
  ON "RelationshipReviewFlag" ("familyId", "reason", "status");

-- Index for "oldest unresolved first" ordering.
CREATE INDEX IF NOT EXISTS "RelationshipReviewFlag_resolvedAt_idx"
  ON "RelationshipReviewFlag" ("resolvedAt");

-- ── Foreign keys ───────────────────────────────────────────────────
-- All FKs use ON DELETE CASCADE for the source edge (deleting the edge
-- deletes its flags) and ON DELETE SET NULL for the parent/user refs
-- (deleting a person/user doesn't delete the flag — it just nulls the
-- reference, preserving the audit trail).

ALTER TABLE "RelationshipReviewFlag"
  ADD CONSTRAINT "RelationshipReviewFlag_familyId_fkey"
  FOREIGN KEY ("familyId") REFERENCES "Family"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "RelationshipReviewFlag"
  ADD CONSTRAINT "RelationshipReviewFlag_sourceRelationshipId_fkey"
  FOREIGN KEY ("sourceRelationshipId") REFERENCES "Relationship"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "RelationshipReviewFlag"
  ADD CONSTRAINT "RelationshipReviewFlag_parentAPersonId_fkey"
  FOREIGN KEY ("parentAPersonId") REFERENCES "Person"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "RelationshipReviewFlag"
  ADD CONSTRAINT "RelationshipReviewFlag_parentBPersonId_fkey"
  FOREIGN KEY ("parentBPersonId") REFERENCES "Person"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "RelationshipReviewFlag"
  ADD CONSTRAINT "RelationshipReviewFlag_createdByUserId_fkey"
  FOREIGN KEY ("createdByUserId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "RelationshipReviewFlag"
  ADD CONSTRAINT "RelationshipReviewFlag_resolvedByUserId_fkey"
  FOREIGN KEY ("resolvedByUserId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

-- ── Grant ──────────────────────────────────────────────────────────
-- The service_role already has full access; this is just for clarity
-- when reviewing the migration in the Supabase dashboard.
COMMENT ON TABLE "RelationshipReviewFlag" IS
  'v5.129 Sibling Backfill: review-queue flags for ambiguous relationship cases (e.g. sibling_parent_mismatch when two siblings have different recorded parents). See migration 20260830120000.';

COMMENT ON COLUMN "Person"."isPlaceholder" IS
  'v5.129 Sibling Backfill: true for auto-created "Unknown parent" stand-ins. See migration 20260830120000.';
