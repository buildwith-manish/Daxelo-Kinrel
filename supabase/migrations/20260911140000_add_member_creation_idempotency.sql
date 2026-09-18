-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260911140000_add_member_creation_idempotency
--
-- PURPOSE
-- Prevent duplicate member creation from rapid double-tap/retry
-- sequences on the "Add to Family" button. The client-side guard
-- (v5.205: early return if _isSubmitting) handles 99% of cases, but
-- a backend idempotency check is the defense-in-depth layer that
-- catches race conditions where two requests are in-flight
-- simultaneously.
--
-- STRATEGY
-- Add a UNIQUE INDEX on (familyId, name, "linkedUserId") that
-- only applies to persons created within the last 10 seconds.
-- This is implemented as a partial unique index using a
-- generated column approach: we add a "createdAtEpoch" column
-- (epoch seconds as bigint) and create a partial unique index
-- WHERE "createdAtEpoch" > extract(epoch from now())::bigint - 10.
--
-- Actually, PostgreSQL partial indexes can't use dynamic expressions
-- like now(). The standard pattern is to use a trigger that checks
-- for recent duplicates BEFORE insert and raises an exception.
--
-- SIMPLER APPROACH: Use a BEFORE INSERT trigger that checks for a
-- recent (within 10 seconds) duplicate by the same creator
-- (identified by linkedUserId or the family's createdBy) with the
-- same name + familyId. If found, silently skip the insert (return
-- NULL from the trigger, which suppresses the row insertion).
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────────
-- 1. Idempotency trigger: skip duplicate member creation within 10s
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_prevent_duplicate_member_creation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_recent_count integer;
BEGIN
  -- Check if a Person with the same (familyId, name, linkedUserId)
  -- was created in the last 10 seconds. If so, this is likely a
  -- double-submit from the client; silently skip the insert.
  --
  -- We check BOTH linkedUserId and name because:
  --   - For manually-added members (linkedUserId IS NULL), the name
  --     is the primary identifier.
  --   - For Kinrel-linked members (linkedUserId IS NOT NULL), the
  --     linkedUserId is the primary identifier — we don't want to
  --     block two different people with the same name.
  --
  -- The 10-second window is generous enough to catch rapid retries
  -- but short enough to allow legitimate re-addition after a delete.
  SELECT count(*) INTO v_recent_count
  FROM "Person"
  WHERE "familyId" = NEW."familyId"
    AND name = NEW.name
    AND COALESCE("linkedUserId"::text, '') = COALESCE(NEW."linkedUserId"::text, '')
    AND "deletedAt" IS NULL
    AND "createdAt" > now() - interval '10 seconds';

  IF v_recent_count > 0 THEN
    -- Silently skip the insert (return NULL from a BEFORE trigger
    -- suppresses the row insertion). The client's createPerson
    -- function will get a successful (empty) response, but no row
    -- will be created — which is the correct behavior for an
    -- idempotent duplicate.
    RAISE NOTICE '[DUPLICATE-PREVENT] Skipping duplicate member creation: familyId=%, name=%', NEW."familyId", NEW.name;
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$function$;

-- Drop the trigger if it already exists (idempotent migration)
DROP TRIGGER IF EXISTS trg_prevent_duplicate_member_creation ON "Person";

CREATE TRIGGER trg_prevent_duplicate_member_creation
BEFORE INSERT ON "Person"
FOR EACH ROW
EXECUTE FUNCTION public.fn_prevent_duplicate_member_creation();

COMMENT ON FUNCTION public.fn_prevent_duplicate_member_creation() IS
'v5.205: Idempotency guard — silently skips duplicate member creation (same familyId + name + linkedUserId) within a 10-second window. Prevents double-submit from rapid client retries.';

-- ────────────────────────────────────────────────────────────────────
-- 2. Notify PostgREST to reload schema cache
-- ────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
