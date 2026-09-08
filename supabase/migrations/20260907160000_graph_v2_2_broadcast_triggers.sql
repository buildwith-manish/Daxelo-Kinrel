-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260907160000_graph_v2_2_broadcast_triggers.sql
--
-- PURPOSE
-- Migrate realtime graph sync from postgres_changes (WAL-decode, per-
-- subscriber cost) to trigger-based Broadcast (single decode, fan-out
-- via Realtime Broadcast channel).
--
-- ARCHITECTURE
-- BEFORE (v2.1 step6):
--   Client → supabase_realtime publication → WAL decoder → postgres_changes
--   Cost: O(subscribers × writes) — each subscriber decodes WAL independently
--
-- AFTER (v2.2):
--   Trigger → realtime.broadcast_changes('family:{familyId}', ...)
--   Client → channel('family:{familyId}').onBroadcast('change', ...)
--   Cost: O(writes) — single decode in trigger, fan-out via Realtime pub/sub
--
-- WHAT THIS MIGRATION DOES
-- 1. Creates trigger functions that broadcast Person/Relationship changes
--    to topic 'family:{familyId}' using realtime.broadcast_changes().
-- 2. Adds RLS policies on realtime.messages so only family members can
--    subscribe to 'family:{familyId}' topics (Broadcast Authorization).
-- 3. Removes Person/Relationship from supabase_realtime publication
--    (WAL decoding no longer needed for these tables).
-- 4. Keeps Family/FamilyMember in the publication (they still use
--    postgres_changes for the Family-UPDATE + FamilyMember-INSERT
--    listeners — these are low-frequency and don't warrant broadcast).
-- 5. Creates a pg_cron job for batched graph_state_cache expiry
--    (replaces per-write expire_graph_cache() calls).
--
-- ROLLBACK
-- To revert: drop the triggers + functions, re-add Person/Relationship
-- to the supabase_realtime publication, drop the RLS policies, drop
-- the cron job. The client-side supabase_realtime_service.dart must
-- also be reverted to use onPostgresChanges.
-- ════════════════════════════════════════════════════════════════════

-- ── STEP 1A: Broadcast trigger function for Person ──
-- Fires AFTER INSERT/UPDATE/DELETE on Person, broadcasts to
-- 'family:{familyId}' topic with the full row payload.
CREATE OR REPLACE FUNCTION _fn_broadcast_person_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, realtime
AS $$
DECLARE
  v_family_id text;
  v_operation text;
  v_new_record record;
  v_old_record record;
BEGIN
  -- Determine familyId + operation + records
  IF (TG_OP = 'DELETE') THEN
    v_family_id := OLD."familyId";
    v_operation := 'DELETE';
    v_new_record := NULL;
    v_old_record := OLD;
  ELSIF (TG_OP = 'UPDATE') THEN
    v_family_id := NEW."familyId";
    v_operation := 'UPDATE';
    v_new_record := NEW;
    v_old_record := OLD;
  ELSIF (TG_OP = 'INSERT') THEN
    v_family_id := NEW."familyId";
    v_operation := 'INSERT';
    v_new_record := NEW;
    v_old_record := NULL;
  END IF;

  -- Skip if no familyId (shouldn't happen, but guard against NULL)
  IF v_family_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Broadcast the change to the family's Realtime topic.
  -- realtime.broadcast_changes() sends a structured payload to all
  -- subscribers of 'family:{familyId}' who pass RLS authorization.
  -- The payload includes: operation, table, schema, new_record, old_record.
  PERFORM realtime.broadcast_changes(
    topic_name := 'family:' || v_family_id,
    event_name := 'change',
    operation := v_operation,
    table_name := 'Person',
    table_schema := 'public',
    new := v_new_record,
    old := v_old_record,
    level := 'ROW'
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ── STEP 1B: Broadcast trigger function for Relationship ──
CREATE OR REPLACE FUNCTION _fn_broadcast_relationship_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, realtime
AS $$
DECLARE
  v_family_id text;
  v_operation text;
  v_new_record record;
  v_old_record record;
BEGIN
  IF (TG_OP = 'DELETE') THEN
    v_family_id := OLD."familyId";
    v_operation := 'DELETE';
    v_new_record := NULL;
    v_old_record := OLD;
  ELSIF (TG_OP = 'UPDATE') THEN
    v_family_id := NEW."familyId";
    v_operation := 'UPDATE';
    v_new_record := NEW;
    v_old_record := OLD;
  ELSIF (TG_OP = 'INSERT') THEN
    v_family_id := NEW."familyId";
    v_operation := 'INSERT';
    v_new_record := NEW;
    v_old_record := NULL;
  END IF;

  IF v_family_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  PERFORM realtime.broadcast_changes(
    topic_name := 'family:' || v_family_id,
    event_name := 'change',
    operation := v_operation,
    table_name := 'Relationship',
    table_schema := 'public',
    new := v_new_record,
    old := v_old_record,
    level := 'ROW'
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ── STEP 1C: Drop existing triggers (if any) + create new ones ──
DROP TRIGGER IF EXISTS trg_broadcast_person_change ON "Person";
CREATE TRIGGER trg_broadcast_person_change
  AFTER INSERT OR UPDATE OR DELETE ON "Person"
  FOR EACH ROW
  EXECUTE FUNCTION _fn_broadcast_person_change();

DROP TRIGGER IF EXISTS trg_broadcast_relationship_change ON "Relationship";
CREATE TRIGGER trg_broadcast_relationship_change
  AFTER INSERT OR UPDATE OR DELETE ON "Relationship"
  FOR EACH ROW
  EXECUTE FUNCTION _fn_broadcast_relationship_change();

-- ── STEP 2: RLS Broadcast Authorization on realtime.messages ──
-- NOTE: realtime.broadcast_changes() pushes directly via the Realtime
-- WebSocket server — it does NOT insert into realtime.messages.
-- Therefore, RLS on realtime.messages is only needed for the legacy
-- INSERT-based broadcast path (channel.send({type: 'broadcast'}) from
-- the client). Since we use broadcast_changes() from a SECURITY DEFINER
-- trigger (server-side), authorization is handled by the Realtime server
-- based on the topic + the caller's ability to subscribe to that topic.
--
-- For client-side topic subscription authorization, Supabase Realtime
-- uses the `private` flag on the broadcast message. By default,
-- broadcast_changes() sends with private=true, which means only
-- authenticated users can receive the message. For per-family
-- authorization (only family members can subscribe to 'family:{id}'),
-- the client-side subscription must pass an authorization check.
--
-- The RLS policies below are defined here for completeness and for the
-- case where client-side broadcasts (channel.send) are used in the
-- future. They may fail to apply if the current user doesn't have
-- ownership of realtime.messages (owned by supabase_realtime_admin).
-- In that case, they can be applied via the Supabase Dashboard SQL
-- Editor (which runs as the supabase_admin role).
--
-- To apply via Dashboard:
-- 1. Go to SQL Editor in Supabase Dashboard
-- 2. Run the policy statements below as supabase_admin

DO $$
BEGIN
  -- Enable RLS on realtime.messages (if not already enabled)
  BEGIN
    ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;
  EXCEPTION WHEN others THEN NULL;
  END;

  -- Policy: SELECT (subscribe) — allow if the topic is 'family:{familyId}'
  -- AND the authenticated user is a member of that family.
  BEGIN
    DROP POLICY IF EXISTS "family_broadcast_select" ON realtime.messages;
    CREATE POLICY "family_broadcast_select" ON realtime.messages
      FOR SELECT TO authenticated
      USING (
        (
          topic LIKE 'family:%'
          AND EXISTS (
            SELECT 1
            FROM public."FamilyMember"
            WHERE "FamilyMember"."familyId" = substring(topic from 8)
              AND "FamilyMember"."userId" = auth.uid()::text
          )
        )
        OR (
          topic LIKE 'user:%'
          AND substring(topic from 6) = auth.uid()::text
        )
      );
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping family_broadcast_select policy (insufficient privilege — apply via Dashboard SQL Editor as supabase_admin)';
  END;

  -- Policy: INSERT (broadcast) — allow authenticated users to send
  -- broadcast messages to family topics they're a member of.
  BEGIN
    DROP POLICY IF EXISTS "family_broadcast_insert" ON realtime.messages;
    CREATE POLICY "family_broadcast_insert" ON realtime.messages
      FOR INSERT TO authenticated
      WITH CHECK (
        (
          topic LIKE 'family:%'
          AND EXISTS (
            SELECT 1
            FROM public."FamilyMember"
            WHERE "FamilyMember"."familyId" = substring(topic from 8)
              AND "FamilyMember"."userId" = auth.uid()::text
          )
        )
        OR (
          topic LIKE 'user:%'
          AND substring(topic from 6) = auth.uid()::text
        )
      );
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping family_broadcast_insert policy (insufficient privilege — apply via Dashboard SQL Editor as supabase_admin)';
  END;
END;
$$;

-- ── STEP 3: Remove Person/Relationship from supabase_realtime publication ──
-- They no longer need WAL decoding — the broadcast triggers handle
-- real-time notifications. This removes the per-subscriber WAL cost.
DO $$
BEGIN
  -- Remove Person (case-sensitive identifier)
  BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE "Person";
  EXCEPTION WHEN others THEN
    -- already removed or not in publication — skip
    NULL;
  END;
  -- Remove Relationship (case-sensitive identifier)
  BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE "Relationship";
  EXCEPTION WHEN others THEN
    NULL;
  END;
END;
$$;

-- ── STEP 4: pg_cron job for batched graph_state_cache expiry ──
-- Replaces per-write expire_graph_cache() calls with a 2-second batched
-- sweep. This reduces write amplification on high-frequency graph changes.
-- The expire_graph_cache() function (created in migration
-- 20260612180545_graph_v2_1_step7_expire_cache_fn.sql) is reused as-is.

-- Drop existing cron job if this migration is re-run
DO $$
BEGIN
  -- Check if pg_cron extension is available
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Drop existing job if present
    PERFORM cron.unschedule(jobname) FROM cron.job WHERE jobname = 'expire-graph-cache-batched';
    -- Schedule: every 2 seconds (closest cron supports is '* * * * *' = every minute,
    -- but Supabase's pg_cron supports '*/2 * * * * *' via the 6-field extension).
    -- Use every-minute schedule as a safe default; the function itself is cheap.
    -- For sub-minute batching, the app-side debounce (500ms) handles it.
    PERFORM cron.schedule(
      jobname := 'expire-graph-cache-batched',
      schedule := '* * * * *',
      command := 'SELECT expire_graph_cache();'
    );
    RAISE NOTICE 'Scheduled expire-graph-cache-batched cron job (every minute)';
  ELSE
    RAISE NOTICE 'pg_cron not installed — skipping cron job creation';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron job creation skipped: %', SQLERRM;
END;
$$;

-- ── Verification ──
COMMENT ON FUNCTION _fn_broadcast_person_change() IS
'v2.2: Broadcasts Person changes to family:{familyId} Realtime topic via realtime.broadcast_changes(). Replaces WAL-decode postgres_changes path.';

COMMENT ON FUNCTION _fn_broadcast_relationship_change() IS
'v2.2: Broadcasts Relationship changes to family:{familyId} Realtime topic via realtime.broadcast_changes(). Replaces WAL-decode postgres_changes path.';

-- ── Summary log ──
DO $$
DECLARE
  v_person_in_pub boolean;
  v_rel_in_pub boolean;
  v_cron_count int;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'Person'
  ) INTO v_person_in_pub;

  SELECT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'Relationship'
  ) INTO v_rel_in_pub;

  SELECT count(*) INTO v_cron_count FROM cron.job WHERE jobname = 'expire-graph-cache-batched';

  RAISE NOTICE 'Migration v2.2 complete:';
  RAISE NOTICE '  Person in supabase_realtime pub: % (expected false)', NOT v_person_in_pub;
  RAISE NOTICE '  Relationship in supabase_realtime pub: % (expected false)', NOT v_rel_in_pub;
  RAISE NOTICE '  Cron job count for expire-graph-cache-batched: %', v_cron_count;
  RAISE NOTICE '  RLS policies on realtime.messages: %', (SELECT count(*) FROM pg_policy WHERE polrelid = 'realtime.messages'::regclass);
END;
$$;
