-- ============================================================
-- Migration: add_missing_cascade_and_composite_indexes
-- Version:  20260609111019
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ── Missing composite indexes on Relationship (hot cascade path) ──────
CREATE INDEX IF NOT EXISTS "Relationship_familyId_fromPersonId_idx"
  ON "Relationship"("familyId", "fromPersonId");

CREATE INDEX IF NOT EXISTS "Relationship_familyId_toPersonId_idx"
  ON "Relationship"("familyId", "toPersonId");

CREATE INDEX IF NOT EXISTS "Relationship_familyId_isActive_idx"
  ON "Relationship"("familyId", "isActive");

CREATE INDEX IF NOT EXISTS "Relationship_fromPersonId_toPersonId_idx"
  ON "Relationship"("fromPersonId", "toPersonId");

-- ── Missing composite indexes on Person ───────────────────────────────
CREATE INDEX IF NOT EXISTS "Person_familyId_deletedAt_idx"
  ON "Person"("familyId", "deletedAt");

CREATE INDEX IF NOT EXISTS "Person_familyId_generationIndex_idx"
  ON "Person"("familyId", "generationIndex");

CREATE INDEX IF NOT EXISTS "Person_familyId_isAnchor_idx"
  ON "Person"("familyId", "isAnchor");

-- ── Missing FK indexes (from earlier audit) ───────────────────────────
CREATE INDEX IF NOT EXISTS "FamilyInvite_invitedBy_idx"
  ON "FamilyInvite"("invitedBy");

CREATE INDEX IF NOT EXISTS "CommunityEvent_communityId_idx"
  ON "CommunityEvent"("communityId");

CREATE INDEX IF NOT EXISTS "EventReminder_eventId_idx"
  ON "EventReminder"("eventId");

CREATE INDEX IF NOT EXISTS "KBArticle_authorId_idx"
  ON "KBArticle"("authorId");

CREATE INDEX IF NOT EXISTS "KBArticle_lastEditedById_idx"
  ON "KBArticle"("lastEditedById");

CREATE INDEX IF NOT EXISTS "KBSearchLog_clickedArticleId_idx"
  ON "KBSearchLog"("clickedArticleId");

CREATE INDEX IF NOT EXISTS "SLATracking_ticketId_idx"
  ON "SLATracking"("ticketId");

CREATE INDEX IF NOT EXISTS "OAuthClient_userId_idx"
  ON "OAuthClient"("userId");

-- ── Family RLS fast-path index: createdBy lookup ──────────────────────
CREATE INDEX IF NOT EXISTS "Family_createdBy_deletedAt_idx"
  ON "Family"("createdBy", "deletedAt");

-- ── FamilyMember composite for RLS subquery ───────────────────────────
CREATE INDEX IF NOT EXISTS "FamilyMember_userId_familyId_idx"
  ON "FamilyMember"("userId", "familyId");
