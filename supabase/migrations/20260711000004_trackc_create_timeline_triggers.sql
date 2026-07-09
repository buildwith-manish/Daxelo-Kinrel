-- =============================================================================
-- Track C v2.0 — AURA Timeline Triggers
-- Migration 04: Append-only enforcement (UPDATE + DELETE rejected)
-- =============================================================================
-- Implements Section 5.4 of the FINAL v2.0 spec.
-- ADR-001: Append-only timeline enforced by DB trigger.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_timeline_append_only()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'AURATimelineEvent is append-only. UPDATE and DELETE are forbidden. Use a correction event instead.'
    USING ERRCODE = 'check_violation';
END;
$$;

DROP TRIGGER IF EXISTS timeline_no_update ON public."AURATimelineEvent";
CREATE TRIGGER timeline_no_update
  BEFORE UPDATE ON public."AURATimelineEvent"
  FOR EACH ROW EXECUTE FUNCTION public.enforce_timeline_append_only();

DROP TRIGGER IF EXISTS timeline_no_delete ON public."AURATimelineEvent";
CREATE TRIGGER timeline_no_delete
  BEFORE DELETE ON public."AURATimelineEvent"
  FOR EACH ROW EXECUTE FUNCTION public.enforce_timeline_append_only();

COMMENT ON FUNCTION public.enforce_timeline_append_only() IS 'Track C v2.0: Rejects UPDATE/DELETE on AURATimelineEvent. ADR-001.';
