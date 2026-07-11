-- =============================================================================
-- Phase 1-14: All schema changes for the Family OS layer
-- =============================================================================
-- This migration adds all new columns and tables needed for the
-- remaining roadmap phases. Run this once on Supabase.
-- =============================================================================

-- ── Phase 1: Member management repair ────────────────────────────────
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "mergedIntoId" TEXT;
CREATE INDEX IF NOT EXISTS "Person_mergedIntoId_idx" ON public."Person"("mergedIntoId");
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "pendingChanges" JSONB;

-- ── Phase 2: Verification badge ─────────────────────────────────────
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "isVerified" BOOLEAN DEFAULT false;
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "verifiedAt" TIMESTAMPTZ;

-- ── Phase 4: Privacy additions ──────────────────────────────────────
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "hiddenFromPersonIds" TEXT[] DEFAULT '{}';
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "privateNotes" TEXT;

-- ── Phase 5: Shared lists & tasks (extends existing SharedList) ─────
-- SharedList and SharedListItem already created in migration 20260711000300.
-- Add FamilyTask for the generic task model.
CREATE TABLE IF NOT EXISTS public."FamilyTask" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    title                   TEXT NOT NULL,
    description             TEXT,
    listType                TEXT DEFAULT 'other',
    "assignedToPersonId"    TEXT,
    "createdByUserId"       TEXT NOT NULL,
    "dueDate"               TIMESTAMPTZ,
    status                  TEXT DEFAULT 'open',
    "completedAt"           TIMESTAMPTZ,
    "createdAt"             TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "FamilyTask_family_type_status_idx" ON public."FamilyTask"("familyId", "listType", "status");
ALTER TABLE public."FamilyTask" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "FamilyTask_select" ON public."FamilyTask" FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyTask"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "FamilyTask_insert" ON public."FamilyTask" FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyTask"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "FamilyTask_update" ON public."FamilyTask" FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyTask"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "FamilyTask_delete" ON public."FamilyTask" FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyTask"."familyId" AND fm."userId" = auth.uid())
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public."FamilyTask" TO authenticated;

-- ── Phase 6: Family Goals ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."FamilyGoal" (
    id                      TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"              TEXT NOT NULL,
    title                   TEXT NOT NULL,
    description             TEXT,
    "targetAmount"          DECIMAL(10, 2),
    "currentAmount"         DECIMAL(10, 2) DEFAULT 0,
    "targetDate"            TIMESTAMPTZ,
    "assignedPersonIds"     TEXT[] DEFAULT '{}',
    status                  TEXT DEFAULT 'active',
    "createdAt"             TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS "FamilyGoal_family_idx" ON public."FamilyGoal"("familyId");
ALTER TABLE public."FamilyGoal" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "FamilyGoal_select" ON public."FamilyGoal" FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyGoal"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "FamilyGoal_insert" ON public."FamilyGoal" FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyGoal"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "FamilyGoal_update" ON public."FamilyGoal" FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyGoal"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "FamilyGoal_delete" ON public."FamilyGoal" FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyGoal"."familyId" AND fm."userId" = auth.uid())
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public."FamilyGoal" TO authenticated;

-- ── Phase 7: Announcements & Polls ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public."FamilyAnnouncement" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"      TEXT NOT NULL,
    "authorUserId"  TEXT NOT NULL,
    body            TEXT NOT NULL,
    "isPinned"      BOOLEAN DEFAULT false,
    "isUrgent"      BOOLEAN DEFAULT false,
    "createdAt"     TIMESTAMPTZ DEFAULT now(),
    "expiresAt"     TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS "FamilyAnnouncement_family_idx" ON public."FamilyAnnouncement"("familyId");

CREATE TABLE IF NOT EXISTS public."AnnouncementReceipt" (
    id                  TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "announcementId"    TEXT NOT NULL REFERENCES public."FamilyAnnouncement"(id) ON DELETE CASCADE,
    "userId"            TEXT NOT NULL,
    "readAt"            TIMESTAMPTZ DEFAULT now(),
    UNIQUE("announcementId", "userId")
);

CREATE TABLE IF NOT EXISTS public."FamilyPoll" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "familyId"      TEXT NOT NULL,
    "authorUserId"  TEXT NOT NULL,
    question        TEXT NOT NULL,
    options         JSONB NOT NULL,
    "allowMultiple" BOOLEAN DEFAULT false,
    "closesAt"      TIMESTAMPTZ,
    "createdAt"     TIMESTAMPTZ DEFAULT now(),
    scope           TEXT DEFAULT 'casual'
);
CREATE INDEX IF NOT EXISTS "FamilyPoll_family_idx" ON public."FamilyPoll"("familyId");

CREATE TABLE IF NOT EXISTS public."PollVote" (
    id          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "pollId"    TEXT NOT NULL REFERENCES public."FamilyPoll"(id) ON DELETE CASCADE,
    "userId"    TEXT NOT NULL,
    "optionId"  TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ DEFAULT now(),
    UNIQUE("pollId", "userId", "optionId")
);

-- RLS for all Phase 7 tables
ALTER TABLE public."FamilyAnnouncement" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "FamilyAnnouncement_select" ON public."FamilyAnnouncement" FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyAnnouncement"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "FamilyAnnouncement_insert" ON public."FamilyAnnouncement" FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyAnnouncement"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "FamilyAnnouncement_delete" ON public."FamilyAnnouncement" FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyAnnouncement"."familyId" AND fm."userId" = auth.uid())
);
GRANT SELECT, INSERT, DELETE ON public."FamilyAnnouncement" TO authenticated;

ALTER TABLE public."AnnouncementReceipt" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "AnnouncementReceipt_all" ON public."AnnouncementReceipt" FOR ALL TO authenticated USING (auth.uid() = "userId");
GRANT SELECT, INSERT ON public."AnnouncementReceipt" TO authenticated;

ALTER TABLE public."FamilyPoll" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "FamilyPoll_select" ON public."FamilyPoll" FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyPoll"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "FamilyPoll_insert" ON public."FamilyPoll" FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "FamilyPoll"."familyId" AND fm."userId" = auth.uid())
);
GRANT SELECT, INSERT ON public."FamilyPoll" TO authenticated;

ALTER TABLE public."PollVote" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "PollVote_select" ON public."PollVote" FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyPoll" p
             JOIN public."FamilyMember" fm ON fm."familyId" = p."familyId"
             WHERE p.id = "PollVote"."pollId" AND fm."userId" = auth.uid())
);
CREATE POLICY "PollVote_insert" ON public."PollVote" FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public."FamilyPoll" p
             JOIN public."FamilyMember" fm ON fm."familyId" = p."familyId"
             WHERE p.id = "PollVote"."pollId" AND fm."userId" = auth.uid())
);
GRANT SELECT, INSERT ON public."PollVote" TO authenticated;

-- ── Phase 8: Wellness check-ins ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public."WellnessCheckIn" (
    id          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "personId"  TEXT NOT NULL,
    "familyId"  TEXT NOT NULL,
    status      TEXT NOT NULL,
    "moodEmoji" TEXT,
    note        TEXT,
    "createdAt" TIMESTAMPTZ DEFAULT now(),
    "expiresAt" TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS "WellnessCheckIn_family_idx" ON public."WellnessCheckIn"("familyId");
ALTER TABLE public."WellnessCheckIn" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "WellnessCheckIn_select" ON public."WellnessCheckIn" FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "WellnessCheckIn"."familyId" AND fm."userId" = auth.uid())
);
CREATE POLICY "WellnessCheckIn_insert" ON public."WellnessCheckIn" FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public."FamilyMember" fm WHERE fm."familyId" = "WellnessCheckIn"."familyId" AND fm."userId" = auth.uid())
);
GRANT SELECT, INSERT ON public."WellnessCheckIn" TO authenticated;

-- ── Phase 9: Family Vault security ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public."VaultCredential" (
    id              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "personId"      TEXT NOT NULL,
    "familyId"      TEXT NOT NULL,
    label           TEXT NOT NULL,
    "encryptedValue" TEXT NOT NULL,
    "createdAt"     TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public."VaultCredential" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "VaultCredential_select" ON public."VaultCredential" FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public."Person" p WHERE p.id = "VaultCredential"."personId" AND p."linkedUserId" = auth.uid())
);
CREATE POLICY "VaultCredential_insert" ON public."VaultCredential" FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public."Person" p WHERE p.id = "VaultCredential"."personId" AND p."linkedUserId" = auth.uid())
);
CREATE POLICY "VaultCredential_delete" ON public."VaultCredential" FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public."Person" p WHERE p.id = "VaultCredential"."personId" AND p."linkedUserId" = auth.uid())
);
GRANT SELECT, INSERT, DELETE ON public."VaultCredential" TO authenticated;

-- ── Phase 14: Emergency info card ───────────────────────────────────
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "emergencyContactName" TEXT;
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "emergencyContactPhone" TEXT;
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "medicalNotes" TEXT;
ALTER TABLE public."Person" ADD COLUMN IF NOT EXISTS "importantDocumentUrls" TEXT[] DEFAULT '{}';
