-- ============================================================
-- Migration: fix_familyinvite_invitedby_fk_target
-- Version:  20260612020549
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================

-- FamilyInvite.invitedBy should reference FamilyMember.id per Prisma schema (inviterMember relation),
-- but it incorrectly referenced User.id
ALTER TABLE "FamilyInvite" DROP CONSTRAINT "FamilyInvite_invitedBy_fkey";
ALTER TABLE "FamilyInvite" ADD CONSTRAINT "FamilyInvite_invitedBy_fkey" FOREIGN KEY ("invitedBy") REFERENCES "FamilyMember"("id") ON DELETE CASCADE ON UPDATE CASCADE;
