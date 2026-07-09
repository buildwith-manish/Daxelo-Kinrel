-- Rollback for 20260711000005_trackc_create_ai_insight.sql
DROP TRIGGER IF EXISTS trg_trackc_ai_insight_updated_at ON public."AIInsight";
DROP TABLE IF EXISTS public."AIInsight";
