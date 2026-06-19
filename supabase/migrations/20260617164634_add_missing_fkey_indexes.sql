-- ============================================================
-- Migration: add_missing_fkey_indexes
-- Version:  20260617164634
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


CREATE INDEX IF NOT EXISTS "ContentReport_resolvedById_idx" ON public."ContentReport" ("resolvedById");
CREATE INDEX IF NOT EXISTS "EventRSVP_userId_idx" ON public."EventRSVP" ("userId");
CREATE INDEX IF NOT EXISTS "Incident_authorId_idx" ON public."Incident" ("authorId");
CREATE INDEX IF NOT EXISTS "Invitation_inviterId_idx" ON public."Invitation" ("inviterId");
CREATE INDEX IF NOT EXISTS "ModerationAppeal_reviewerId_idx" ON public."ModerationAppeal" ("reviewerId");
CREATE INDEX IF NOT EXISTS "Reaction_userId_idx" ON public."Reaction" ("userId");
CREATE INDEX IF NOT EXISTS "UserBadge_badgeId_idx" ON public."UserBadge" ("badgeId");
CREATE INDEX IF NOT EXISTS "graph_state_cache_member_id_idx" ON public.graph_state_cache (member_id);
