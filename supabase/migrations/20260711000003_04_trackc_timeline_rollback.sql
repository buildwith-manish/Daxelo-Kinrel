-- Rollback for 20260711000003 + 20260711000004 (timeline + triggers)
DROP TRIGGER IF EXISTS timeline_no_delete ON public."AURATimelineEvent";
DROP TRIGGER IF EXISTS timeline_no_update ON public."AURATimelineEvent";
DROP FUNCTION IF EXISTS public.enforce_timeline_append_only();
DROP TABLE IF EXISTS public."AURATimelineEvent";
