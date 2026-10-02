-- 20260923100000_truth_streak_deprecation.sql
--
-- Phase 3 — Deprecate Truth Streak entirely.
--
-- Truth Streak has been replaced in the Flutter client by the v1
-- Prediction Battle (scheduled numeric-estimation game with backend-
-- enforced reveal timing). The v1 system uses its own `pb_v1_*`
-- tables + NestJS push notification scheduler — it has zero
-- dependency on Truth Streak.
--
-- This migration:
--
--   1. Drops the four truth_streak_* tables (questions, daily_assignments,
--      answers, user_stats). All data is lost — by design; Truth Streak
--      was never launched outside of internal testing.
--   2. Removes the `whoCanCreateTruthStreak` column from
--      `FamilyManagementSettings`. The Flutter client keeps the field
--      in the model for JSON-deserialization backward-compat (the
--      column was a JSON-stored string, not a SQL column on the row
--      — see the `family_management_permissions` migration), so this
--      is a no-op for SQL. We document the intent here.
--   3. Removes any truth_streak_* entries from the supabase_realtime
--      publication (idempotent — ALTER PUBLICATION DROP raises if
--      the table isn't in the publication).
--
-- No user-visible Truth Streak data ever existed in production. The
-- v1 Prediction Battle tables (`pb_v1_*`) are untouched.

-- ═════════════════════════════════════════════════════════════════════
-- 1. Drop truth_streak_* tables (FK order: answers → assignments → questions)
-- ═════════════════════════════════════════════════════════════════════

DROP TABLE IF EXISTS public.truth_streak_answers CASCADE;
DROP TABLE IF EXISTS public.truth_streak_daily_assignments CASCADE;
DROP TABLE IF EXISTS public.truth_streak_user_stats CASCADE;
DROP TABLE IF EXISTS public.truth_streak_questions CASCADE;

-- ═════════════════════════════════════════════════════════════════════
-- 2. Remove truth_streak_* from the realtime publication (idempotent)
-- ═════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE public.truth_streak_answers;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ═════════════════════════════════════════════════════════════════════
-- 3. `whoCanCreateTruthStreak` column — NOT dropped
-- ═════════════════════════════════════════════════════════════════════
--
-- The `whoCanCreateTruthStreak` value is NOT a SQL column on the
-- `FamilySettings` table — it is a KEY inside a JSONB column
-- (`settings` JSON). Dropping it would require a JSONB update
-- across all existing rows, which is risky and provides no benefit
-- (the JSON value is now ignored by both client and server).
--
-- We leave the JSON keys alone. The Flutter client still defines the
-- field in its `FamilyManagementSettings` model for backward-compat
-- deserialization, but no longer surfaces it in the UI (the
-- permission tile was removed in Phase 3).
