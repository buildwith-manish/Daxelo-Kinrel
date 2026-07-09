-- Rollback for 08 + 09 + 10 (SmartReminder + DecisionMemory/Impact + MeetingArtifact)
DROP TRIGGER IF EXISTS trg_trackc_meeting_artifact_updated_at ON public."MeetingArtifact";
DROP TRIGGER IF EXISTS trg_trackc_decision_impact_updated_at ON public."DecisionImpact";
DROP TRIGGER IF EXISTS trg_trackc_decision_memory_updated_at ON public."DecisionMemory";
DROP TRIGGER IF EXISTS trg_trackc_smart_reminder_updated_at ON public."SmartReminder";

DROP TABLE IF EXISTS public."MeetingArtifact";
DROP TABLE IF EXISTS public."DecisionImpact";
DROP TABLE IF EXISTS public."DecisionMemory";
DROP TABLE IF EXISTS public."SmartReminder";
