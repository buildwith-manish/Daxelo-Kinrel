-- 20260923000000_prediction_battle_v0_deprecation.sql
--
-- Phase 2 — Deprecate the legacy v0 prediction_battle system.
--
-- The v1 scheduled-mode system (tables prefixed `pb_v1_`) has fully
-- replaced v0 in the Flutter client (commit 8d4486f9) and the NestJS
-- notification layer (commit f41333bf). This migration:
--
--   1. Removes the v0 RPCs from the public schema.
--   2. Drops the v0 tables. Data is lost — by design; v0 had no
--      production users because the v0 client was always coupled to
--      the unlaunched family-hub redesign.
--   3. Removes the v0 pg_cron jobs (idempotent — wrapped in DO blocks
--      because pg_cron raises if the job doesn't exist).
--   4. Removes the v0 rows from `supabase_realtime` publication.
--
-- The new v1 tables (`pb_v1_*`) and their RPCs/cron jobs are untouched.
--
-- Prisma side-effect: dropping the v0 tables shrinks the introspected
-- schema, which speeds up the NestJS server's Prisma client cold start
-- (the client codegen generates types for every table in the schema;
-- fewer tables = smaller generated client = faster require).

-- ═════════════════════════════════════════════════════════════════════
-- 1. Unschedule v0 pg_cron jobs (idempotent)
-- ═════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  PERFORM cron.unschedule('prediction-daily-refresh');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$
BEGIN
  PERFORM cron.unschedule('prediction-recovery-tick');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$
BEGIN
  PERFORM cron.unschedule('prediction-reveal-tick');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ═════════════════════════════════════════════════════════════════════
-- 2. Drop v0 RPCs (functions)
-- ═════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.fn_prediction_get_active(text) CASCADE;
DROP FUNCTION IF EXISTS public.fn_prediction_submit(text, text, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.fn_prediction_resolve(text) CASCADE;
DROP FUNCTION IF EXISTS public.fn_prediction_tick(text) CASCADE;

-- ═════════════════════════════════════════════════════════════════════
-- 3. Drop v0 tables (RLS policies are dropped automatically with the table)
-- ═════════════════════════════════════════════════════════════════════

-- Drop in FK-dependency order to avoid "depends on" errors.
-- prediction_submissions → prediction_rounds → prediction_questions
-- prediction_history     → prediction_rounds (no FK) → prediction_questions
-- prediction_leaderboard is standalone (no FK to predictions)

DROP TABLE IF EXISTS public.prediction_submissions CASCADE;
DROP TABLE IF EXISTS public.prediction_history CASCADE;
DROP TABLE IF EXISTS public.prediction_leaderboard CASCADE;
DROP TABLE IF EXISTS public.prediction_rounds CASCADE;
DROP TABLE IF EXISTS public.prediction_questions CASCADE;

-- ═════════════════════════════════════════════════════════════════════
-- 4. Drop v0 prediction badges (kept around from the original seed)
-- ═════════════════════════════════════════════════════════════════════
--
-- These were created by 20260919140000_prediction_battle.sql with slugs:
--   forecast-apprentice, oracle, future-seer, prediction-master
-- We keep them — they're harmless and the slugs might be referenced by
-- already-awarded user badges. Dropping them would orphan the
-- UserBadge rows. Leave alone.

-- (intentionally no-op for badges)
