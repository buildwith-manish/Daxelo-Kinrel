-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.6: Slow Mode in Groups
-- =============================================================================
-- Lets an admin set a per-family "slow mode" window — members (non-admins)
-- can only send N messages every X seconds. Prevents spam during heated
-- discussions. Admins bypass slow mode.
--
-- Implementation:
--   • Add `slowModeSeconds integer DEFAULT 0` to Family. 0 = off.
--     Valid values: 0 (off), 10, 30, 60, 300, 600, 3600 (1h).
--   • The NestJS ChatThrottlerService queries the family's slowModeSeconds
--     on the first message in a session + caches it for 60s. Admins bypass.
--   • The Flutter client renders a countdown timer on the send button
--     when throttled ("Wait 28s…").
-- =============================================================================

ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "slowModeSeconds" integer NOT NULL DEFAULT 0;

-- CHECK constraint enforcing only valid values.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'Family_slowModeSeconds_chk'
  ) THEN
    ALTER TABLE "Family"
      ADD CONSTRAINT "Family_slowModeSeconds_chk"
      CHECK ("slowModeSeconds" IN (0, 10, 30, 60, 300, 600, 3600));
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Family_slowModeSeconds_chk: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_slow_mode — admin-only update
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_slow_mode(
  p_family_id text,
  p_seconds integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_role text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT role INTO v_role FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id;
  IF v_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;
  IF v_role NOT IN ('admin', 'creator') THEN
    RETURN json_build_object('success', false, 'error', 'not_admin');
  END IF;

  IF p_seconds NOT IN (0, 10, 30, 60, 300, 600, 3600) THEN
    RETURN json_build_object('success', false, 'error', 'invalid_value',
      'message', 'Allowed: 0 (off), 10, 30, 60, 300, 600, 3600.');
  END IF;

  UPDATE "Family"
    SET "slowModeSeconds" = p_seconds, "updatedAt" = now()
    WHERE id = p_family_id;

  RETURN json_build_object('success', true, 'familyId', p_family_id, 'slowModeSeconds', p_seconds);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_slow_mode(text, integer) TO authenticated;

-- Verification
SELECT 'Family.slowModeSeconds' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'Family' AND column_name = 'slowModeSeconds'
       ) AS exists;
SELECT 'fn_set_slow_mode' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_slow_mode') AS exists;
