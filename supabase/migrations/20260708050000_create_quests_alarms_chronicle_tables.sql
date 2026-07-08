-- =============================================================================
-- Daxelo-Kinrel — A-3 Family Quests + A-4 Silent Alarms + A-7 Family Chronicle
-- Migration: create_quests_alarms_chronicle_tables
-- =============================================================================
-- Three more addictiveness features:
--
--   1. "FamilyQuest"      — A-3: weekly AI-generated quests targeting weak relationships
--   2. "SilentAlarm"      — A-4: inactivity detection + private nudges to the bridge role
--   3. "FamilyChronicle"  — A-7: AI-written family history, monthly auto-update
--
-- Schema conventions (matches all prior migrations).
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "FamilyQuest" — A-3 Family Quests
-- ────────────────────────────────────────────────────────────────────────────
-- Weekly AI-generated "quests" that target weak relationships in the family graph.
-- Examples:
--   "Call Dadi this week — you haven't spoken in 23 days"
--   "Send a photo to Anil bhai — your relationship is feeling stormy"
--   "Wish Priya a happy birthday (in 3 days) — she's turning 25"
--
-- Quests are generated every Monday at 7am IST by a cron job.
-- Each quest has:
--   - questType: call | message | share_photo | wish_birthday | visit | ritual
--   - targetPersonId / targetUserId: who the quest is about
--   - deadline: when the quest expires (end of week)
--   - karmaReward: karma awarded on completion
--   - status: active | completed | expired | skipped
CREATE TABLE IF NOT EXISTS public."FamilyQuest" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "userId"          TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "targetPersonId"  TEXT REFERENCES public."Person"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "targetUserId"    TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,

  -- ── Quest content ──
  "questType"       TEXT NOT NULL, -- call | message | share_photo | wish_birthday | visit | ritual
  "title"           TEXT NOT NULL,  -- e.g. "Call Dadi this week"
  "description"     TEXT NOT NULL,  -- e.g. "You haven't spoken in 23 days. She mentioned knee pain."
  "actionType"      TEXT NOT NULL,  -- call | message | view_post | view_sparq | contribute | listen_memory
  "actionData"      JSONB NOT NULL DEFAULT '{}'::JSONB,

  -- ── Scheduling ──
  "weekOf"          DATE NOT NULL,   -- the Monday of the week this quest is for
  "deadline"        TIMESTAMPTZ NOT NULL, -- when the quest expires

  -- ── Reward ──
  "karmaReward"     INTEGER NOT NULL DEFAULT 10,
  "karmaAwarded"    INTEGER NOT NULL DEFAULT 0,

  -- ── Lifecycle ──
  "status"          TEXT NOT NULL DEFAULT 'active', -- active | completed | expired | skipped
  "completedAt"     TIMESTAMPTZ,
  "expiredAt"       TIMESTAMPTZ,
  "skippedAt"       TIMESTAMPTZ,

  -- ── AI generation metadata ──
  "generatedBy"     TEXT NOT NULL DEFAULT 'graph_weak_point', -- graph_weak_point | birthday | festival | weather | manual
  "questScore"      NUMERIC(4,3) NOT NULL DEFAULT 0.500, -- how good a quest this was (0-1)

  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "FamilyQuest_family_week_idx"      ON public."FamilyQuest"("familyId", "weekOf");
CREATE INDEX IF NOT EXISTS "FamilyQuest_user_week_idx"        ON public."FamilyQuest"("userId", "weekOf");
CREATE INDEX IF NOT EXISTS "FamilyQuest_status_idx"           ON public."FamilyQuest"("status");
CREATE INDEX IF NOT EXISTS "FamilyQuest_deadline_idx"         ON public."FamilyQuest"("deadline") WHERE "status" = 'active';

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "SilentAlarm" — A-4 Silent Alarms
-- ────────────────────────────────────────────────────────────────────────────
-- When a family member goes quiet for 7+ days, a SilentAlarm is created and
-- sent PRIVATELY to the family's "bridge" role (from AURA). The bridge is the
-- person most connected to both sides of the family — they're best positioned
-- to reach out discreetly.
--
-- The alarm is NOT shown to the inactive person (to avoid guilt/shame).
-- It's only visible to the bridge + family admins.
--
-- Lifecycle:
--   triggered → acknowledged → resolved (when the inactive person becomes active again)
--   triggered → escalated (if still inactive after 14 days → notify all family admins)
CREATE TABLE IF NOT EXISTS public."SilentAlarm" (
  "id"                TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"          TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "inactivePersonId"  TEXT NOT NULL REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "inactiveUserId"    TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "bridgeUserId"      TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,

  -- ── Alarm details ──
  "daysInactive"      INTEGER NOT NULL,
  "lastActiveAt"      TIMESTAMPTZ,
  "severity"          TEXT NOT NULL DEFAULT 'gentle', -- gentle | moderate | urgent
  "alarmMessage"      TEXT NOT NULL, -- the human-readable message for the bridge

  -- ── Lifecycle ──
  "status"            TEXT NOT NULL DEFAULT 'triggered', -- triggered | acknowledged | resolved | escalated
  "acknowledgedAt"    TIMESTAMPTZ,
  "acknowledgedById"  TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "resolvedAt"        TIMESTAMPTZ,
  "escalatedAt"       TIMESTAMPTZ,

  -- ── Suggestions for the bridge ──
  "suggestions"       JSONB NOT NULL DEFAULT '[]'::JSONB, -- ["Call them directly", "Send a voice note", "Ask their sibling to check in"]

  "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "SilentAlarm_family_idx"          ON public."SilentAlarm"("familyId");
CREATE INDEX IF NOT EXISTS "SilentAlarm_inactive_idx"        ON public."SilentAlarm"("inactivePersonId");
CREATE INDEX IF NOT EXISTS "SilentAlarm_bridge_idx"          ON public."SilentAlarm"("bridgeUserId");
CREATE INDEX IF NOT EXISTS "SilentAlarm_status_idx"          ON public."SilentAlarm"("status");
CREATE UNIQUE INDEX IF NOT EXISTS "SilentAlarm_inactive_unique" ON public."SilentAlarm"("inactivePersonId") WHERE "status" IN ('triggered', 'acknowledged');

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "FamilyChronicle" — A-7 Family Chronicle
-- ────────────────────────────────────────────────────────────────────────────
-- An AI-written family history book that auto-updates monthly.
-- Each family has ONE chronicle (upserted). Each update creates a new "chapter"
-- stored in the chapters JSONB array.
--
-- Chapter structure:
--   {
--     chapterNumber: 1,
--     title: "The Founding Generation",
--     content: "The story of how...",
--     generatedAt: "2026-01-01T00:00:00Z",
--     sourceData: { memberCount, generationDepth, ... }
--   }
--
-- The chronicle is generated from:
--   - Family graph topology (AURA archetypes, generations, lineages)
--   - Member biographies (Person.biography fields)
--   - Key events (weddings, births, deaths — from FamilyPost + Person dates)
--   - Sparqs (curated moments)
--   - Ancestral memories (Pitru — with consent)
CREATE TABLE IF NOT EXISTS public."FamilyChronicle" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,

  -- ── Chronicle metadata ──
  "title"           TEXT NOT NULL, -- e.g. "The Chronicle of the Sharma Family"
  "subtitle"        TEXT,           -- e.g. "A story spanning 4 generations, from 1947 to today"

  -- ── Chapters (JSONB array of chapter objects) ──
  "chapters"        JSONB NOT NULL DEFAULT '[]'::JSONB,

  -- ── Current generation state ──
  "chapterCount"    INTEGER NOT NULL DEFAULT 0,
  "lastGeneratedAt" TIMESTAMPTZ,
  "nextGenerationAt" TIMESTAMPTZ, -- scheduled next monthly update

  -- ── AI processing ──
  "aiModel"         TEXT,  -- which AI model generated this
  "aiProcessingError" TEXT,

  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS "FamilyChronicle_family_unique" ON public."FamilyChronicle"("familyId");

-- ────────────────────────────────────────────────────────────────────────────
-- RLS
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."FamilyQuest"      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."SilentAlarm"      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."FamilyChronicle"  ENABLE ROW LEVEL SECURITY;

-- FamilyQuest: user can SELECT their own quests; family members can see all
DROP POLICY IF EXISTS "FamilyQuest_member_select" ON public."FamilyQuest";
CREATE POLICY "FamilyQuest_member_select" ON public."FamilyQuest"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "FamilyQuest"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "FamilyQuest_service_insert" ON public."FamilyQuest";
CREATE POLICY "FamilyQuest_service_insert" ON public."FamilyQuest"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "FamilyQuest_service_update" ON public."FamilyQuest";
CREATE POLICY "FamilyQuest_service_update" ON public."FamilyQuest"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "FamilyQuest_service_delete" ON public."FamilyQuest";
CREATE POLICY "FamilyQuest_service_delete" ON public."FamilyQuest"
  FOR DELETE USING (auth.role() = 'service_role');

-- SilentAlarm: ONLY the bridge user + family admins can SELECT (private)
DROP POLICY IF EXISTS "SilentAlarm_bridge_select" ON public."SilentAlarm";
CREATE POLICY "SilentAlarm_bridge_select" ON public."SilentAlarm"
  FOR SELECT
  USING (
    "bridgeUserId" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "SilentAlarm"."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm."role" IN ('owner', 'admin')
    )
  );
DROP POLICY IF EXISTS "SilentAlarm_service_insert" ON public."SilentAlarm";
CREATE POLICY "SilentAlarm_service_insert" ON public."SilentAlarm"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "SilentAlarm_service_update" ON public."SilentAlarm";
CREATE POLICY "SilentAlarm_service_update" ON public."SilentAlarm"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "SilentAlarm_service_delete" ON public."SilentAlarm";
CREATE POLICY "SilentAlarm_service_delete" ON public."SilentAlarm"
  FOR DELETE USING (auth.role() = 'service_role');

-- FamilyChronicle: family members can SELECT
DROP POLICY IF EXISTS "FamilyChronicle_member_select" ON public."FamilyChronicle";
CREATE POLICY "FamilyChronicle_member_select" ON public."FamilyChronicle"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "FamilyChronicle"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "FamilyChronicle_service_insert" ON public."FamilyChronicle";
CREATE POLICY "FamilyChronicle_service_insert" ON public."FamilyChronicle"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "FamilyChronicle_service_update" ON public."FamilyChronicle";
CREATE POLICY "FamilyChronicle_service_update" ON public."FamilyChronicle"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "FamilyChronicle_service_delete" ON public."FamilyChronicle";
CREATE POLICY "FamilyChronicle_service_delete" ON public."FamilyChronicle"
  FOR DELETE USING (auth.role() = 'service_role');

-- ────────────────────────────────────────────────────────────────────────────
-- GRANTS
-- ────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public."FamilyQuest"      TO anon, authenticated;
GRANT SELECT ON public."SilentAlarm"      TO anon, authenticated;
GRANT SELECT ON public."FamilyChronicle"  TO anon, authenticated;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."FamilyQuest"      FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."SilentAlarm"      FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."FamilyChronicle"  FROM anon, authenticated;

GRANT ALL ON public."FamilyQuest"      TO service_role;
GRANT ALL ON public."SilentAlarm"      TO service_role;
GRANT ALL ON public."FamilyChronicle"  TO service_role;

COMMENT ON TABLE public."FamilyQuest" IS
  'A-3 Family Quests: weekly AI-generated quests from graph weak points. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."SilentAlarm" IS
  'A-4 Silent Alarms: inactivity nudges sent PRIVATELY to the family bridge role. RLS: bridge + admins only SELECT, service_role ALL.';
COMMENT ON TABLE public."FamilyChronicle" IS
  'A-7 Family Chronicle: AI-written family history book, monthly auto-update. RLS: family members SELECT, service_role ALL.';
