-- =============================================================================
-- Phase 3: Rename AURA → Kinrel across the database schema
-- =============================================================================
-- This is a HARD CUTOVER migration (pre-launch, no real user data).
-- All Aura-named tables, indexes, constraints, functions, triggers, and
-- RLS policies are renamed to their Kinrel equivalents.
--
-- The AURATimelineEvent table is PARTITIONED (32 hash partitions). Renaming
-- a partitioned table requires renaming the parent AND every partition child,
-- plus any partition-routing trigger/function that references the table name.
-- =============================================================================

-- ── 1. Rename tables ─────────────────────────────────────────────────────

-- Core AURA symbol feature tables
ALTER TABLE IF EXISTS public."FamilyAura" RENAME TO "FamilyKinrel";
ALTER TABLE IF EXISTS public."FamilyAuraHistory" RENAME TO "FamilyKinrelHistory";
ALTER TABLE IF EXISTS public."MemberAuraRole" RENAME TO "MemberKinrelRole";

-- Track C timeline table (partitioned — rename parent + all 32 children)
ALTER TABLE IF EXISTS public."AURATimelineEvent" RENAME TO "KinrelTimelineEvent";

-- Rename partition children: AURATimelineEvent_p00..p31 → KinrelTimelineEvent_p00..p31
DO $$
DECLARE
  i int;
  old_name text;
  new_name text;
BEGIN
  FOR i IN 0..31 LOOP
    old_name := format('AURATimelineEvent_p%02s', i);
    new_name := format('KinrelTimelineEvent_p%02s', i);
    EXECUTE format('ALTER TABLE IF EXISTS public.%I RENAME TO %I', old_name, new_name);
  END LOOP;
END $$;

-- ── 2. Rename indexes ────────────────────────────────────────────────────

-- FamilyKinrel (was FamilyAura)
ALTER INDEX IF EXISTS "FamilyAura_familyId_idx" RENAME TO "FamilyKinrel_familyId_idx";
ALTER INDEX IF EXISTS "FamilyAura_familyId_unique" RENAME TO "FamilyKinrel_familyId_unique";

-- FamilyKinrelHistory (was FamilyAuraHistory)
ALTER INDEX IF EXISTS "FamilyAuraHistory_family_time_idx" RENAME TO "FamilyKinrelHistory_family_time_idx";

-- MemberKinrelRole (was MemberAuraRole)
ALTER INDEX IF EXISTS "MemberAuraRole_family_idx" RENAME TO "MemberKinrelRole_family_idx";
ALTER INDEX IF EXISTS "MemberAuraRole_member_idx" RENAME TO "MemberKinrelRole_member_idx";
ALTER INDEX IF EXISTS "MemberAuraRole_family_member_unique" RENAME TO "MemberKinrelRole_family_member_unique";

-- KinrelTimelineEvent (was AURATimelineEvent) — indexes on partitioned parent
ALTER INDEX IF EXISTS "AURATimelineEvent_familyId_occurredAt_idx" RENAME TO "KinrelTimelineEvent_familyId_occurredAt_idx";
ALTER INDEX IF EXISTS "AURATimelineEvent_familyId_kind_occurredAt_idx" RENAME TO "KinrelTimelineEvent_familyId_kind_occurredAt_idx";
ALTER INDEX IF EXISTS "AURATimelineEvent_targetEntity_idx" RENAME TO "KinrelTimelineEvent_targetEntity_idx";
ALTER INDEX IF EXISTS "AURATimelineEvent_parentEventId_idx" RENAME TO "KinrelTimelineEvent_parentEventId_idx";

-- ── 3. Rename constraints ────────────────────────────────────────────────

-- FamilyKinrel valid_language_distribution constraint
ALTER TABLE IF EXISTS public."FamilyKinrel" RENAME CONSTRAINT "valid_language_distribution" TO "valid_language_distribution";  -- name stays the same (no aura in it)

-- KinrelTimelineEvent kind CHECK constraint (if it has aura in the name)
-- The CHECK constraint on 'kind' column is named inline — no rename needed.

-- Foreign key constraints (self-referential on KinrelTimelineEvent)
-- The FK name was AURATimelineEvent_parentEventId_fk → needs rename
ALTER TABLE IF EXISTS public."KinrelTimelineEvent" RENAME CONSTRAINT IF EXISTS "AURATimelineEvent_parentEventId_fk" TO "KinrelTimelineEvent_parentEventId_fk";

-- ── 4. Rename functions ──────────────────────────────────────────────────

-- fn_update_aura_timestamp → fn_update_kinrel_timestamp
ALTER FUNCTION IF EXISTS public.fn_update_aura_timestamp() RENAME TO fn_update_kinrel_timestamp;

-- enforce_timeline_append_only — no aura in the name, no rename needed.

-- ── 5. Rename triggers ───────────────────────────────────────────────────

-- trg_family_aura_updated_at → trg_family_kinrel_updated_at
ALTER TRIGGER IF EXISTS trg_family_aura_updated_at ON public."FamilyKinrel" RENAME TO trg_family_kinrel_updated_at;

-- trg_member_aura_role_updated_at → trg_member_kinrel_role_updated_at
ALTER TRIGGER IF EXISTS trg_member_aura_role_updated_at ON public."MemberKinrelRole" RENAME TO trg_member_kinrel_role_updated_at;

-- timeline_no_update / timeline_no_delete — no aura in the name, no rename needed.
-- But they reference enforce_timeline_append_only() which is fine.

-- ── 6. Drop and recreate RLS policies (Postgres doesn't support ALTER POLICY RENAME) ─────────

-- FamilyKinrel (was FamilyAura)
DROP POLICY IF EXISTS "FamilyAura_select" ON public."FamilyKinrel";
DROP POLICY IF EXISTS "FamilyAura_service_insert" ON public."FamilyKinrel";
DROP POLICY IF EXISTS "FamilyAura_service_update" ON public."FamilyKinrel";
DROP POLICY IF EXISTS "FamilyAura_service_delete" ON public."FamilyKinrel";

CREATE POLICY "FamilyKinrel_select" ON public."FamilyKinrel" FOR SELECT TO authenticated USING (true);
CREATE POLICY "FamilyKinrel_service_insert" ON public."FamilyKinrel" FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY "FamilyKinrel_service_update" ON public."FamilyKinrel" FOR UPDATE TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "FamilyKinrel_service_delete" ON public."FamilyKinrel" FOR DELETE TO service_role USING (true);

-- FamilyKinrelHistory (was FamilyAuraHistory)
DROP POLICY IF EXISTS "FamilyAuraHistory_select" ON public."FamilyKinrelHistory";
DROP POLICY IF EXISTS "FamilyAuraHistory_service_insert" ON public."FamilyKinrelHistory";
DROP POLICY IF EXISTS "FamilyAuraHistory_service_update" ON public."FamilyKinrelHistory";
DROP POLICY IF EXISTS "FamilyAuraHistory_service_delete" ON public."FamilyKinrelHistory";

CREATE POLICY "FamilyKinrelHistory_select" ON public."FamilyKinrelHistory" FOR SELECT TO authenticated USING (true);
CREATE POLICY "FamilyKinrelHistory_service_insert" ON public."FamilyKinrelHistory" FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY "FamilyKinrelHistory_service_update" ON public."FamilyKinrelHistory" FOR UPDATE TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "FamilyKinrelHistory_service_delete" ON public."FamilyKinrelHistory" FOR DELETE TO service_role USING (true);

-- MemberKinrelRole (was MemberAuraRole)
DROP POLICY IF EXISTS "MemberAuraRole_select" ON public."MemberKinrelRole";
DROP POLICY IF EXISTS "MemberAuraRole_service_insert" ON public."MemberKinrelRole";
DROP POLICY IF EXISTS "MemberAuraRole_service_update" ON public."MemberKinrelRole";
DROP POLICY IF EXISTS "MemberAuraRole_service_delete" ON public."MemberKinrelRole";

CREATE POLICY "MemberKinrelRole_select" ON public."MemberKinrelRole" FOR SELECT TO authenticated USING (true);
CREATE POLICY "MemberKinrelRole_service_insert" ON public."MemberKinrelRole" FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY "MemberKinrelRole_service_update" ON public."MemberKinrelRole" FOR UPDATE TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "MemberKinrelRole_service_delete" ON public."MemberKinrelRole" FOR DELETE TO service_role USING (true);

-- ── 7. Update Realtime publication ───────────────────────────────────────
-- The old names are in supabase_realtime publication. Remove old, add new.

ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public."FamilyAura", public."MemberAuraRole";
ALTER PUBLICATION supabase_realtime ADD TABLE public."FamilyKinrel", public."MemberKinrelRole";

-- ── 8. Update column comments ────────────────────────────────────────────

COMMENT ON TABLE public."FamilyKinrel" IS 'Kinrel — family relationship intelligence snapshot (one per family)';
COMMENT ON TABLE public."FamilyKinrelHistory" IS 'Kinrel — historical snapshots of the family intelligence over time';
COMMENT ON TABLE public."MemberKinrelRole" IS 'Kinrel — per-member role classification within the family intelligence';

-- ── 9. Update the partition routing function if it exists ────────────────
-- The partitioning is HASH-based (not a routing function), so no function
-- to update — Postgres automatically routes inserts to the correct partition
-- based on the hash of familyId. The partition children were renamed in step 1.

-- ── 10. Verify no Aura objects remain ────────────────────────────────────
-- (This is a query for manual verification, not an executable statement)
-- SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename ILIKE '%aura%';
-- SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND indexname ILIKE '%aura%';
-- SELECT tgname FROM pg_trigger WHERE tgname ILIKE '%aura%';
-- SELECT proname FROM pg_proc WHERE proname ILIKE '%aura%';
