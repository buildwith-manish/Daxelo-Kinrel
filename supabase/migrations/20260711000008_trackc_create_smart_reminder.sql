-- =============================================================================
-- Track C v2.0 — Smart Reminder
-- Migration 08: SmartReminder
-- =============================================================================
-- Implements Section 5.7 of the FINAL v2.0 spec.
-- leadHoursSnapshot + profileVersionSnapshot snapshot the Learning profile at
-- creation, so reminders remain explainable even after the profile recompute.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public."SmartReminder" (
  "id"                       TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId"                 TEXT NOT NULL REFERENCES public."Family"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "decisionId"               TEXT REFERENCES public."FamilyDecision"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "targetUserId"             TEXT NOT NULL,
  "type"                     TEXT NOT NULL CHECK ("type" IN (
                               'decision_deadline','vote_pending','meeting_upcoming',
                               'action_item_due','governance_dormant'
                             )),
  "scheduledFor"             TIMESTAMPTZ NOT NULL,
  "status"                   TEXT NOT NULL DEFAULT 'scheduled' CHECK ("status" IN ('scheduled','sent','snoozed','dismissed','acted')),
  "snoozeCount"              INTEGER NOT NULL DEFAULT 0,
  "snoozedUntil"             TIMESTAMPTZ,

  "leadHoursSnapshot"        NUMERIC(10,2) NOT NULL DEFAULT 24.0,
  "profileVersionSnapshot"   INTEGER NOT NULL DEFAULT 0,

  "insightId"                TEXT REFERENCES public."AIInsight"("id") ON DELETE SET NULL,

  "sentAt"                   TIMESTAMPTZ,
  "actedAt"                  TIMESTAMPTZ,
  "dismissedAt"              TIMESTAMPTZ,

  "createdAt"                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "SmartReminder_familyId_status_scheduledFor_idx" ON public."SmartReminder"("familyId", "status", "scheduledFor");
CREATE INDEX IF NOT EXISTS "SmartReminder_targetUserId_status_scheduledFor_idx" ON public."SmartReminder"("targetUserId", "status", "scheduledFor");
CREATE INDEX IF NOT EXISTS "SmartReminder_decisionId_idx"                    ON public."SmartReminder"("decisionId") WHERE "decisionId" IS NOT NULL;

DROP TRIGGER IF EXISTS trg_trackc_smart_reminder_updated_at ON public."SmartReminder";
CREATE TRIGGER trg_trackc_smart_reminder_updated_at
  BEFORE UPDATE ON public."SmartReminder"
  FOR EACH ROW EXECUTE FUNCTION public.fn_trackc_monotonic_updated_at();

GRANT SELECT ON public."SmartReminder" TO anon, authenticated;
COMMENT ON TABLE public."SmartReminder" IS 'Track C v2.0: AURA smart reminder. leadHoursSnapshot records Learning profile at creation for explainability.';
