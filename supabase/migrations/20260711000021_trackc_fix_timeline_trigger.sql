-- =============================================================================
-- Track C v2.0 — Fix timeline append-only trigger to allow cascade deletes
-- =============================================================================
-- The original trigger blocked ALL DELETEs including cascade deletes from
-- parent tables (Family ON DELETE CASCADE). This made it impossible to
-- delete a family without first manually clearing the timeline.
--
-- Fix: Allow DELETE when it's triggered by a cascade from the parent table.
-- We detect this by checking if the DELETE is NOT issued directly by the
-- application (i.e., there's no explicit WHERE clause on the timeline table).
--
-- Actually, Postgres doesn't distinguish cascade vs direct DELETE in triggers.
-- The safest approach: allow DELETE only when the `session_user` is a
-- superuser or the `service_role` (which bypasses RLS anyway). Application
-- code uses the postgres user which is a superuser, so this would allow
-- all deletes — not what we want.
--
-- Best approach: Drop the DELETE trigger entirely. Keep only the UPDATE
-- trigger (which prevents mutation). Deletions are already controlled by
-- the application layer (no DELETE endpoint exists in the API).
-- Cascade deletes from Family deletion are expected to work.
-- =============================================================================

-- Drop the DELETE trigger (keep UPDATE trigger for append-only enforcement)
DROP TRIGGER IF EXISTS timeline_no_delete ON public."AURATimelineEvent";

-- Update the function to only block UPDATEs (not DELETEs)
CREATE OR REPLACE FUNCTION public.enforce_timeline_append_only()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'AURATimelineEvent is append-only. UPDATE is forbidden. Use a correction event instead.'
      USING ERRCODE = 'check_violation';
  END IF;
  -- Allow DELETE (cascade from parent tables, or explicit cleanup by admin)
  RETURN OLD;
END;
$$;

COMMENT ON FUNCTION public.enforce_timeline_append_only() IS 'Track C v2.0: Rejects UPDATE on AURATimelineEvent. DELETE is allowed (for cascade + admin cleanup). ADR-001 (updated).';
