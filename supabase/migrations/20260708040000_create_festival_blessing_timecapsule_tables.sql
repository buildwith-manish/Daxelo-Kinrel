-- =============================================================================
-- Daxelo-Kinrel — A-6 Festival Intelligence + A-1 Blessing Chain + A-2 Time Capsule
-- Migration: create_festival_blessing_timecapsule_tables
-- =============================================================================
-- Three addictiveness features in one migration (they share cultural timing logic):
--
--   1. "Festival"         — A-6: Indian festival calendar (7 languages, fixed + lunar)
--   2. "BlessingChain"    — A-1: elder blessings scheduled for delivery on birthdays/festivals
--   3. "TimeCapsule"      — A-2: text/photo messages locked until a future reveal date
--
-- Schema conventions (matches AURA + Pulse + Pitru migrations):
--   - All table names PascalCase, double-quoted
--   - All column names camelCase, double-quoted
--   - FKs are TEXT (cuid), ON DELETE CASCADE ON UPDATE CASCADE
--   - RLS: family-scoped SELECT, service_role-only writes
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "Festival" — A-6 Festival Intelligence
-- ────────────────────────────────────────────────────────────────────────────
-- Stores Indian festivals with dates for the next 3 years.
-- Two date types:
--   - FIXED: same Gregorian date every year (e.g., Republic Day = Jan 26)
--   - LUNAR: computed from Hindu lunar calendar (we store pre-computed dates
--            for the next 3 years to avoid runtime calendar math)
--
-- Each festival has names + greeting messages in 8 languages.
-- The `region` field tags festivals by where they're primarily celebrated
-- (north/south/east/west/all) so we can personalize by family region.
CREATE TABLE IF NOT EXISTS public."Festival" (
  "id"            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "festivalKey"   TEXT NOT NULL UNIQUE,  -- e.g. 'diwali', 'holi', 'onam'
  "dateType"      TEXT NOT NULL DEFAULT 'lunar', -- fixed | lunar
  "festivalDate"  DATE NOT NULL,         -- the upcoming occurrence date
  "region"        TEXT NOT NULL DEFAULT 'all', -- north | south | east | west | all

  -- ── Names + greetings in 8 languages (JSONB) ──
  -- Schema: { "en": {name, greeting}, "hi": {name, greeting}, ... }
  "names"         JSONB NOT NULL DEFAULT '{}'::JSONB,
  "greetings"     JSONB NOT NULL DEFAULT '{}'::JSONB,

  -- ── Cultural context (for AI-generated personalized messages) ──
  "description"   TEXT,        -- short description of the festival
  "themes"        JSONB NOT NULL DEFAULT '[]'::JSONB, -- ["lights","victory","harvest"]
  "rituals"       JSONB NOT NULL DEFAULT '[]'::JSONB, -- ["rangoli","puja","sweets"]

  -- ── Scheduling metadata ──
  "daysUntil"     INTEGER NOT NULL DEFAULT 0,  -- days until the next occurrence (precomputed)
  "isActive"      BOOLEAN NOT NULL DEFAULT true,

  "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "Festival_date_idx"        ON public."Festival"("festivalDate");
CREATE INDEX IF NOT EXISTS "Festival_daysUntil_idx"   ON public."Festival"("daysUntil");
CREATE INDEX IF NOT EXISTS "Festival_region_idx"      ON public."Festival"("region");
CREATE INDEX IF NOT EXISTS "Festival_active_idx"      ON public."Festival"("isActive") WHERE "isActive" = true;

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "BlessingChain" — A-1 Blessing Chain
-- ────────────────────────────────────────────────────────────────────────────
-- Elders record blessings (text/audio) that are SCHEDULED for delivery on a
-- specific recipient's birthday or a festival. The recipient gets a push
-- notification on the scheduled date: "Dadi left a blessing for your birthday 💜"
--
-- Lifecycle:
--   pending → delivered → viewed
--   pending → cancelled (elder or family cancels before delivery)
CREATE TABLE IF NOT EXISTS public."BlessingChain" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "elderPersonId"   TEXT NOT NULL REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "elderUserId"     TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  "recipientPersonId" TEXT REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "recipientUserId" TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,

  -- ── Blessing content ──
  "mediaType"       TEXT NOT NULL DEFAULT 'text', -- text | audio
  "textContent"     TEXT,                          -- for text blessings
  "mediaUrl"        TEXT,                          -- for audio blessings (Supabase Storage)
  "durationSec"     INTEGER NOT NULL DEFAULT 0,    -- for audio blessings

  -- ── Scheduling ──
  "triggerType"     TEXT NOT NULL, -- birthday | festival | anniversary | custom
  "triggerDate"     DATE NOT NULL, -- the date the blessing should be delivered
  "festivalKey"     TEXT,          -- set when triggerType=festival (FK to Festival.festivalKey, but no DB constraint to allow flexibility)

  -- ── Localization ──
  "language"        TEXT NOT NULL DEFAULT 'en', -- language of the blessing

  -- ── Lifecycle ──
  "status"          TEXT NOT NULL DEFAULT 'pending', -- pending | delivered | viewed | cancelled
  "deliveredAt"     TIMESTAMPTZ,  -- when the blessing was delivered to the recipient
  "viewedAt"        TIMESTAMPTZ,  -- when the recipient opened the blessing
  "cancelledAt"     TIMESTAMPTZ,
  "cancelledReason" TEXT,

  -- ── Recurrence ──
  "isRecurring"     BOOLEAN NOT NULL DEFAULT false, -- true = deliver every year on this date
  "lastDeliveredAt" TIMESTAMPTZ,  -- for recurring blessings, the last delivery timestamp

  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "BlessingChain_family_idx"          ON public."BlessingChain"("familyId");
CREATE INDEX IF NOT EXISTS "BlessingChain_elder_idx"           ON public."BlessingChain"("elderPersonId");
CREATE INDEX IF NOT EXISTS "BlessingChain_recipient_idx"       ON public."BlessingChain"("recipientPersonId", "recipientUserId");
CREATE INDEX IF NOT EXISTS "BlessingChain_trigger_idx"         ON public."BlessingChain"("triggerDate", "status");
CREATE INDEX IF NOT EXISTS "BlessingChain_status_idx"          ON public."BlessingChain"("status");
CREATE INDEX IF NOT EXISTS "BlessingChain_recurring_idx"       ON public."BlessingChain"("isRecurring") WHERE "isRecurring" = true;

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: "TimeCapsule" — A-2 Time Capsule
-- ────────────────────────────────────────────────────────────────────────────
-- Family members lock messages (text/photo/video) that will be revealed on a
-- future date. Use cases:
--   - A parent writes a letter to their child's 18th birthday
--   - A grandparent records a wedding wish for a grandchild not yet married
--   - A family member leaves a message to be opened after their passing
--
-- Unlike AncestralMemory (which is about preserving the past), TimeCapsule is
-- about sending a message to the FUTURE.
--
-- Lifecycle:
--   locked → revealed → viewed
--   locked → cancelled (creator cancels before reveal)
CREATE TABLE IF NOT EXISTS public."TimeCapsule" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"        TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "creatorId"       TEXT NOT NULL REFERENCES public."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "recipientPersonId" TEXT REFERENCES public."Person"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "recipientUserId" TEXT REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,

  -- ── Content ──
  "mediaType"       TEXT NOT NULL DEFAULT 'text', -- text | photo | video
  "textContent"     TEXT,
  "mediaUrl"        TEXT,
  "thumbnailUrl"    TEXT,

  -- ── The reveal ──
  "title"           TEXT NOT NULL,  -- e.g. "For your 18th birthday"
  "revealAt"        TIMESTAMPTZ NOT NULL, -- when the capsule unlocks
  "revealReason"    TEXT,           -- e.g. "Anaya's 18th birthday", "After I'm gone"

  -- ── Lifecycle ──
  "status"          TEXT NOT NULL DEFAULT 'locked', -- locked | revealed | viewed | cancelled
  "revealedAt"      TIMESTAMPTZ,  -- set when the capsule is auto-revealed (cron job)
  "viewedAt"        TIMESTAMPTZ,  -- set when the recipient first opens it
  "cancelledAt"     TIMESTAMPTZ,

  -- ── Notification ──
  "notifyOnReveal"  BOOLEAN NOT NULL DEFAULT true, -- send FCM push when revealed
  "notifiedAt"      TIMESTAMPTZ,

  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "TimeCapsule_family_idx"      ON public."TimeCapsule"("familyId");
CREATE INDEX IF NOT EXISTS "TimeCapsule_creator_idx"     ON public."TimeCapsule"("creatorId");
CREATE INDEX IF NOT EXISTS "TimeCapsule_recipient_idx"   ON public."TimeCapsule"("recipientPersonId", "recipientUserId");
CREATE INDEX IF NOT EXISTS "TimeCapsule_reveal_idx"      ON public."TimeCapsule"("revealAt") WHERE "status" = 'locked';
CREATE INDEX IF NOT EXISTS "TimeCapsule_status_idx"      ON public."TimeCapsule"("status");

-- ────────────────────────────────────────────────────────────────────────────
-- RLS: enable on all 3 tables
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public."Festival"       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."BlessingChain"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."TimeCapsule"    ENABLE ROW LEVEL SECURITY;

-- Festival: everyone can SELECT (it's reference data, no family scope)
DROP POLICY IF EXISTS "Festival_select" ON public."Festival";
CREATE POLICY "Festival_select" ON public."Festival"
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Festival_service_insert" ON public."Festival";
CREATE POLICY "Festival_service_insert" ON public."Festival"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "Festival_service_update" ON public."Festival";
CREATE POLICY "Festival_service_update" ON public."Festival"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "Festival_service_delete" ON public."Festival";
CREATE POLICY "Festival_service_delete" ON public."Festival"
  FOR DELETE USING (auth.role() = 'service_role');

-- BlessingChain: family members can SELECT (both elder's family and recipient's family)
DROP POLICY IF EXISTS "BlessingChain_member_select" ON public."BlessingChain";
CREATE POLICY "BlessingChain_member_select" ON public."BlessingChain"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "BlessingChain"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "BlessingChain_service_insert" ON public."BlessingChain";
CREATE POLICY "BlessingChain_service_insert" ON public."BlessingChain"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "BlessingChain_service_update" ON public."BlessingChain";
CREATE POLICY "BlessingChain_service_update" ON public."BlessingChain"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "BlessingChain_service_delete" ON public."BlessingChain";
CREATE POLICY "BlessingChain_service_delete" ON public."BlessingChain"
  FOR DELETE USING (auth.role() = 'service_role');

-- TimeCapsule: family members can SELECT
DROP POLICY IF EXISTS "TimeCapsule_member_select" ON public."TimeCapsule";
CREATE POLICY "TimeCapsule_member_select" ON public."TimeCapsule"
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public."FamilyMember" fm
      WHERE fm."familyId" = "TimeCapsule"."familyId"
        AND fm."userId" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "TimeCapsule_service_insert" ON public."TimeCapsule";
CREATE POLICY "TimeCapsule_service_insert" ON public."TimeCapsule"
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "TimeCapsule_service_update" ON public."TimeCapsule";
CREATE POLICY "TimeCapsule_service_update" ON public."TimeCapsule"
  FOR UPDATE USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS "TimeCapsule_service_delete" ON public."TimeCapsule";
CREATE POLICY "TimeCapsule_service_delete" ON public."TimeCapsule"
  FOR DELETE USING (auth.role() = 'service_role');

-- ────────────────────────────────────────────────────────────────────────────
-- GRANTS
-- ────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public."Festival"       TO anon, authenticated;
GRANT SELECT ON public."BlessingChain"  TO anon, authenticated;
GRANT SELECT ON public."TimeCapsule"    TO anon, authenticated;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."Festival"       FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."BlessingChain"  FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public."TimeCapsule"    FROM anon, authenticated;

GRANT ALL ON public."Festival"       TO service_role;
GRANT ALL ON public."BlessingChain"  TO service_role;
GRANT ALL ON public."TimeCapsule"    TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- COMMENTS
-- ────────────────────────────────────────────────────────────────────────────
COMMENT ON TABLE public."Festival" IS
  'A-6 Festival Intelligence: Indian festival calendar with 8-language names + greetings. Pre-computed dates for next 3 years. RLS: public SELECT, service_role ALL.';
COMMENT ON TABLE public."BlessingChain" IS
  'A-1 Blessing Chain: elder blessings scheduled for delivery on birthdays/festivals. Recurring support. RLS: family members SELECT, service_role ALL.';
COMMENT ON TABLE public."TimeCapsule" IS
  'A-2 Time Capsule: messages locked until a future reveal date. For 18th birthdays, weddings, after passing. RLS: family members SELECT, service_role ALL.';
