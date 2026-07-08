-- =============================================================================
-- Daxelo-Kinrel — PULSE: Daily Family Intelligence Brief
-- Migration: create_pulse_tables
-- =============================================================================
-- STATUS: Already applied live (this file is a record of the live schema).
-- Six tables that power the daily 7am personalized family brief:
--   1. "DailyBrief"           — one row per user per day (orchestrator output)
--   2. "BriefItem"            — items inside a brief (max 6 per brief)
--   3. "BriefInteraction"     — analytics: which item the user tapped + karma
--   4. "RelationshipWeather"  — per-pair emotional climate
--   5. "ConnectionStreak"     — daily-interaction streaks between pairs
--   6. "FamilyKarma"          — invisible social currency tied to AURA roles
--
-- Schema conventions (matches AURA migration):
--   - All table names PascalCase, double-quoted
--   - All column names camelCase, double-quoted
--   - FKs are TEXT (cuid), ON DELETE CASCADE ON UPDATE CASCADE (matching existing FKs)
--   - Nullable FKs to Person use ON DELETE SET NULL
--   - RLS: family-scoped SELECT, service_role-only writes (4 policies per table)
--   - Realtime: "DailyBrief" is in supabase_realtime publication
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "DailyBrief"
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."DailyBrief" (
  "id"               TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId"           TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "familyId"         TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "briefDate"        DATE NOT NULL,
  "greeting"         TEXT NOT NULL,
  "familyArchetype"  TEXT NOT NULL DEFAULT 'unknown',
  "languageCode"     TEXT NOT NULL DEFAULT 'en',
  "content"          JSONB NOT NULL DEFAULT '{}'::JSONB,
  "generatedAt"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deliveredAt"      TIMESTAMPTZ,
  "viewedAt"         TIMESTAMPTZ,
  "interactedAt"     TIMESTAMPTZ,
  "interactionCount" INTEGER NOT NULL DEFAULT 0,
  "callsInitiated"   INTEGER NOT NULL DEFAULT 0,
  "messagesSent"     INTEGER NOT NULL DEFAULT 0,
  "memoriesViewed"   INTEGER NOT NULL DEFAULT 0,
  "karmaEarned"      INTEGER NOT NULL DEFAULT 0,
  "createdAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "DailyBrief_user_briefDate_unique" UNIQUE ("userId", "briefDate")
);
CREATE INDEX IF NOT EXISTS "DailyBrief_family_briefDate_idx"  ON public."DailyBrief"("familyId", "briefDate");
CREATE INDEX IF NOT EXISTS "DailyBrief_user_briefDate_idx"    ON public."DailyBrief"("userId", "briefDate");
CREATE INDEX IF NOT EXISTS "DailyBrief_briefDate_idx"         ON public."DailyBrief"("briefDate");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "BriefItem"
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."BriefItem" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "briefId"         TEXT NOT NULL REFERENCES public."DailyBrief"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "userId"          TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "itemType"        TEXT NOT NULL,
  "priority"        INTEGER NOT NULL DEFAULT 50,
  "title"           TEXT NOT NULL,
  "body"            TEXT NOT NULL,
  "actionLabel"     TEXT NOT NULL,
  "actionType"      TEXT NOT NULL,
  "actionData"      JSONB NOT NULL DEFAULT '{}'::JSONB,
  "targetPersonId"  TEXT REFERENCES public."Person"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "targetUserId"    TEXT REFERENCES public."User"("id")  ON DELETE SET NULL ON UPDATE CASCADE,
  "targetSparqId"   TEXT,
  "targetPostId"    TEXT,
  "relevanceScore"  NUMERIC(4,3) NOT NULL DEFAULT 0.500,
  "interactedAt"    TIMESTAMPTZ,
  "interactionType" TEXT,
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "BriefItem_briefId_idx"          ON public."BriefItem"("briefId");
CREATE INDEX IF NOT EXISTS "BriefItem_user_created_idx"     ON public."BriefItem"("userId", "createdAt");
CREATE INDEX IF NOT EXISTS "BriefItem_family_created_idx"   ON public."BriefItem"("familyId", "createdAt");
CREATE INDEX IF NOT EXISTS "BriefItem_type_priority_idx"    ON public."BriefItem"("itemType", "priority");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "BriefInteraction"
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."BriefInteraction" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "briefItemId"     TEXT NOT NULL REFERENCES public."BriefItem"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "userId"          TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "interactionType" TEXT NOT NULL,
  "interactionData" JSONB NOT NULL DEFAULT '{}'::JSONB,
  "karmaAwarded"    INTEGER NOT NULL DEFAULT 0,
  "interactedAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "BriefInteraction_briefItem_idx"  ON public."BriefInteraction"("briefItemId");
CREATE INDEX IF NOT EXISTS "BriefInteraction_user_interacted_idx" ON public."BriefInteraction"("userId", "interactedAt");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "RelationshipWeather"
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."RelationshipWeather" (
  "id"                     TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"               TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "userAId"                TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "personBId"              TEXT REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "userBId"                TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "weather"                TEXT NOT NULL DEFAULT 'sunny',
  "daysSinceLastContact"   INTEGER NOT NULL DEFAULT 0,
  "interactionCount30d"    INTEGER NOT NULL DEFAULT 0,
  "sentimentScore"         NUMERIC(4,3) NOT NULL DEFAULT 0.500,
  "streakDays"             INTEGER NOT NULL DEFAULT 0,
  "previousWeather"        TEXT,
  "weatherChangedAt"       TIMESTAMPTZ,
  "computedAt"             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "createdAt"              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "RelationshipWeather_pair_unique" UNIQUE ("familyId", "userAId", "personBId", "userBId")
);
CREATE INDEX IF NOT EXISTS "RelationshipWeather_family_userA_idx"  ON public."RelationshipWeather"("familyId", "userAId");
CREATE INDEX IF NOT EXISTS "RelationshipWeather_userA_idx"         ON public."RelationshipWeather"("userAId");
CREATE INDEX IF NOT EXISTS "RelationshipWeather_userB_idx"         ON public."RelationshipWeather"("userBId");
CREATE INDEX IF NOT EXISTS "RelationshipWeather_weather_idx"       ON public."RelationshipWeather"("weather");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "ConnectionStreak"
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."ConnectionStreak" (
  "id"                TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"          TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "userAId"           TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "personBId"         TEXT REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "userBId"           TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "currentStreak"     INTEGER NOT NULL DEFAULT 0,
  "longestStreak"     INTEGER NOT NULL DEFAULT 0,
  "lastInteractionAt" TIMESTAMPTZ,
  "streakStartedAt"   TIMESTAMPTZ,
  "streakBrokenAt"    TIMESTAMPTZ,
  "streakType"        TEXT NOT NULL DEFAULT 'any',
  "createdAt"         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "ConnectionStreak_pair_type_unique" UNIQUE ("familyId", "userAId", "personBId", "userBId", "streakType")
);
CREATE INDEX IF NOT EXISTS "ConnectionStreak_family_userA_idx"  ON public."ConnectionStreak"("familyId", "userAId");
CREATE INDEX IF NOT EXISTS "ConnectionStreak_userA_idx"         ON public."ConnectionStreak"("userAId");
CREATE INDEX IF NOT EXISTS "ConnectionStreak_current_idx"       ON public."ConnectionStreak"("currentStreak");

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "FamilyKarma"
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."FamilyKarma" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId"          TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "totalKarma"      INTEGER NOT NULL DEFAULT 0,
  "karmaThisWeek"   INTEGER NOT NULL DEFAULT 0,
  "karmaThisMonth"  INTEGER NOT NULL DEFAULT 0,
  "karmaTrend"      TEXT NOT NULL DEFAULT 'steady',
  "karmaAsRoot"     INTEGER NOT NULL DEFAULT 0,
  "karmaAsAnchor"   INTEGER NOT NULL DEFAULT 0,
  "karmaAsBridge"   INTEGER NOT NULL DEFAULT 0,
  "karmaAsWeaver"   INTEGER NOT NULL DEFAULT 0,
  "karmaAsLeaf"     INTEGER NOT NULL DEFAULT 0,
  "recentReasons"   JSONB NOT NULL DEFAULT '[]'::JSONB,
  "lastKarmaAt"     TIMESTAMPTZ,
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "FamilyKarma_user_family_unique" UNIQUE ("userId", "familyId")
);
CREATE INDEX IF NOT EXISTS "FamilyKarma_family_total_idx"  ON public."FamilyKarma"("familyId", "totalKarma");
CREATE INDEX IF NOT EXISTS "FamilyKarma_user_idx"           ON public."FamilyKarma"("userId");

-- ────────────────────────────────────────────────────────────────────────────
-- RLS: enable on all 6 Pulse tables + family-scoped SELECT policies.
-- Defense-in-depth: service_role ALL, anon/authenticated SELECT only.
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."DailyBrief"           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."BriefItem"            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."BriefInteraction"     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."RelationshipWeather"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."ConnectionStreak"     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."FamilyKarma"          ENABLE ROW LEVEL SECURITY;

-- DailyBrief: family members can SELECT their own briefs
DROP POLICY IF EXISTS "DailyBrief_member_select" ON public."DailyBrief";
CREATE POLICY "DailyBrief_member_select" ON public."DailyBrief"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "DailyBrief"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "DailyBrief_service_insert" ON public."DailyBrief";
CREATE POLICY "DailyBrief_service_insert" ON public."DailyBrief"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "DailyBrief_service_update" ON public."DailyBrief";
CREATE POLICY "DailyBrief_service_update" ON public."DailyBrief"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "DailyBrief_service_delete" ON public."DailyBrief";
CREATE POLICY "DailyBrief_service_delete" ON public."DailyBrief"
  FOR DELETE USING (auth.role() = 'service_role');

-- BriefItem: family members can SELECT
DROP POLICY IF EXISTS "BriefItem_member_select" ON public."BriefItem";
CREATE POLICY "BriefItem_member_select" ON public."BriefItem"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "BriefItem"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "BriefItem_service_insert" ON public."BriefItem";
CREATE POLICY "BriefItem_service_insert" ON public."BriefItem"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "BriefItem_service_update" ON public."BriefItem";
CREATE POLICY "BriefItem_service_update" ON public."BriefItem"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "BriefItem_service_delete" ON public."BriefItem";
CREATE POLICY "BriefItem_service_delete" ON public."BriefItem"
  FOR DELETE USING (auth.role() = 'service_role');

-- BriefInteraction: user can SELECT their own interactions
DROP POLICY IF EXISTS "BriefInteraction_user_select" ON public."BriefInteraction";
CREATE POLICY "BriefInteraction_user_select" ON public."BriefInteraction"
  FOR SELECT USING ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "BriefInteraction_service_insert" ON public."BriefInteraction";
CREATE POLICY "BriefInteraction_service_insert" ON public."BriefInteraction"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "BriefInteraction_service_update" ON public."BriefInteraction";
CREATE POLICY "BriefInteraction_service_update" ON public."BriefInteraction"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "BriefInteraction_service_delete" ON public."BriefInteraction";
CREATE POLICY "BriefInteraction_service_delete" ON public."BriefInteraction"
  FOR DELETE USING (auth.role() = 'service_role');

-- RelationshipWeather: family members can SELECT
DROP POLICY IF EXISTS "RelationshipWeather_member_select" ON public."RelationshipWeather";
CREATE POLICY "RelationshipWeather_member_select" ON public."RelationshipWeather"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "RelationshipWeather"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "RelationshipWeather_service_insert" ON public."RelationshipWeather";
CREATE POLICY "RelationshipWeather_service_insert" ON public."RelationshipWeather"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "RelationshipWeather_service_update" ON public."RelationshipWeather";
CREATE POLICY "RelationshipWeather_service_update" ON public."RelationshipWeather"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "RelationshipWeather_service_delete" ON public."RelationshipWeather";
CREATE POLICY "RelationshipWeather_service_delete" ON public."RelationshipWeather"
  FOR DELETE USING (auth.role() = 'service_role');

-- ConnectionStreak: family members can SELECT
DROP POLICY IF EXISTS "ConnectionStreak_member_select" ON public."ConnectionStreak";
CREATE POLICY "ConnectionStreak_member_select" ON public."ConnectionStreak"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "ConnectionStreak"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "ConnectionStreak_service_insert" ON public."ConnectionStreak";
CREATE POLICY "ConnectionStreak_service_insert" ON public."ConnectionStreak"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "ConnectionStreak_service_update" ON public."ConnectionStreak";
CREATE POLICY "ConnectionStreak_service_update" ON public."ConnectionStreak"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "ConnectionStreak_service_delete" ON public."ConnectionStreak";
CREATE POLICY "ConnectionStreak_service_delete" ON public."ConnectionStreak"
  FOR DELETE USING (auth.role() = 'service_role');

-- FamilyKarma: family members can SELECT
DROP POLICY IF EXISTS "FamilyKarma_member_select" ON public."FamilyKarma";
CREATE POLICY "FamilyKarma_member_select" ON public."FamilyKarma"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "FamilyKarma"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "FamilyKarma_service_insert" ON public."FamilyKarma";
CREATE POLICY "FamilyKarma_service_insert" ON public."FamilyKarma"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "FamilyKarma_service_update" ON public."FamilyKarma";
CREATE POLICY "FamilyKarma_service_update" ON public."FamilyKarma"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "FamilyKarma_service_delete" ON public."FamilyKarma";
CREATE POLICY "FamilyKarma_service_delete" ON public."FamilyKarma"
  FOR DELETE USING (auth.role() = 'service_role');

-- ────────────────────────────────────────────────────────────────────────────
-- REALTIME: DailyBrief broadcast (so clients get the new brief pushed at 7am).
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."DailyBrief" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'DailyBrief'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public."DailyBrief";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not add DailyBrief to supabase_realtime: %', SQLERRM;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- GRANTS (defense-in-depth: anon/authenticated SELECT only; service_role ALL)
-- ────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public."DailyBrief"           TO anon, authenticated;
GRANT SELECT ON public."BriefItem"            TO anon, authenticated;
GRANT SELECT ON public."BriefInteraction"     TO anon, authenticated;
GRANT SELECT ON public."RelationshipWeather"  TO anon, authenticated;
GRANT SELECT ON public."ConnectionStreak"     TO anon, authenticated;
GRANT SELECT ON public."FamilyKarma"          TO anon, authenticated;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."DailyBrief"          FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."BriefItem"           FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."BriefInteraction"    FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."RelationshipWeather" FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."ConnectionStreak"    FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."FamilyKarma"         FROM anon, authenticated;

GRANT ALL ON public."DailyBrief"           TO service_role;
GRANT ALL ON public."BriefItem"            TO service_role;
GRANT ALL ON public."BriefInteraction"     TO service_role;
GRANT ALL ON public."RelationshipWeather"  TO service_role;
GRANT ALL ON public."ConnectionStreak"     TO service_role;
GRANT ALL ON public."FamilyKarma"          TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- COMMENTS
-- ────────────────────────────────────────────────────────────────────────────
COMMENT ON TABLE public."DailyBrief" IS
  'PULSE: one daily brief per user. Generated at 7am. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."BriefItem" IS
  'PULSE: a single item inside a DailyBrief. Max 6 per brief. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."BriefInteraction" IS
  'PULSE: records each tap on a BriefItem. Used for analytics + karma. RLS: owner SELECT, service_role ALL.';
COMMENT ON TABLE public."RelationshipWeather" IS
  'PULSE: per-pair emotional climate. Computed nightly at 1am. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."ConnectionStreak" IS
  'PULSE: per-pair connection streak. Hooked into chat/call events. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."FamilyKarma" IS
  'PULSE: invisible social currency per user per family. Tied to AURA roles. RLS: family members SELECT, service_role ALL.';
