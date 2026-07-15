-- =============================================================================
-- ROLLBACK: Revert Kinrel archetype / inner-pattern column defaults
-- =============================================================================
-- Reverses the changes from 20260711000300_kinrel_neutral_archetype_defaults.sql
-- Restores the old defaults ('lotus' for both columns).
--
-- NOTE: This rollback restores the culturally-loaded defaults. It should
-- only be used if the global-launch fix needs to be reverted in an
-- emergency. The app-level fallback fixes (in archetype-classifier.service.ts,
-- kinrel-query.service.ts, and kinrel_model.dart) are NOT reverted by
-- this SQL — they would need separate code reverts.
-- =============================================================================

ALTER TABLE public."FamilyKinrel"
  ALTER COLUMN "archetypeKey" SET DEFAULT 'lotus';

ALTER TABLE public."FamilyKinrel"
  ALTER COLUMN "innerPatternType" SET DEFAULT 'lotus';
