-- =============================================================================
-- Track C v2.0 — Fix: Add DEFAULT gen_random_uuid()::text to partitioned table IDs
-- =============================================================================
-- The partitioned tables (FamilyDecision, AURATimelineEvent, AIInsight,
-- LearningSignal) have id columns with NO default in the DB. The Prisma
-- schema says @default(cuid()) but that's a client-side generator.
--
-- When inserting via raw SQL (pg-boss workers, timeline emitter) or via
-- Prisma when the client doesn't generate the cuid, the id is NULL → error.
--
-- Fix: Add DEFAULT gen_random_uuid()::text to all partitioned table id columns.
-- Prisma's cuid() will still be used when Prisma generates it; the DB default
-- is a fallback for raw SQL inserts.
-- =============================================================================

-- FamilyDecision
ALTER TABLE public."FamilyDecision" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;

-- AURATimelineEvent
ALTER TABLE public."AURATimelineEvent" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;

-- AIInsight
ALTER TABLE public."AIInsight" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;

-- LearningSignal
ALTER TABLE public."LearningSignal" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;

-- Also fix the non-partitioned Track C tables that have the same issue
ALTER TABLE public."FamilyConstitution" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."ConstitutionVersion" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."ConstitutionArticle" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."ConstitutionClause" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."DecisionVote" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."FamilyBehaviorProfile" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."FamilyBehaviorProfileHistory" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."SmartReminder" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."DecisionMemory" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."DecisionImpact" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."MeetingArtifact" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."SearchIndex" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."FamilyAnalyticsSnapshot" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."AICostBudget" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
ALTER TABLE public."SyncWatermark" ALTER COLUMN "id" SET DEFAULT gen_random_uuid()::text;
