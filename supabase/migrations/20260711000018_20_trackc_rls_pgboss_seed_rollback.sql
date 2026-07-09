-- Rollback for 20260711000018 + 19 + 20 (RLS + pg-boss + seed)
-- WARNING: Drops all Track C tables. Use only for full uninstall.

-- Drop RLS policies (cascade handles most, but explicit is safer)
DROP POLICY IF EXISTS "trackc_analytics_select"     ON public."FamilyAnalyticsSnapshot";
DROP POLICY IF EXISTS "trackc_search_select"        ON public."SearchIndex";
DROP POLICY IF EXISTS "trackc_artifact_update"      ON public."MeetingArtifact";
DROP POLICY IF EXISTS "trackc_artifact_insert"      ON public."MeetingArtifact";
DROP POLICY IF EXISTS "trackc_artifact_select"      ON public."MeetingArtifact";
DROP POLICY IF EXISTS "trackc_impact_update"        ON public."DecisionImpact";
DROP POLICY IF EXISTS "trackc_impact_insert"        ON public."DecisionImpact";
DROP POLICY IF EXISTS "trackc_impact_select"        ON public."DecisionImpact";
DROP POLICY IF EXISTS "trackc_memory_update"        ON public."DecisionMemory";
DROP POLICY IF EXISTS "trackc_memory_insert"        ON public."DecisionMemory";
DROP POLICY IF EXISTS "trackc_memory_select"        ON public."DecisionMemory";
DROP POLICY IF EXISTS "trackc_reminder_update"      ON public."SmartReminder";
DROP POLICY IF EXISTS "trackc_reminder_select"      ON public."SmartReminder";
DROP POLICY IF EXISTS "trackc_profile_history_select" ON public."FamilyBehaviorProfileHistory";
DROP POLICY IF EXISTS "trackc_profile_select"       ON public."FamilyBehaviorProfile";
DROP POLICY IF EXISTS "trackc_signal_insert"        ON public."LearningSignal";
DROP POLICY IF EXISTS "trackc_signal_select"        ON public."LearningSignal";
DROP POLICY IF EXISTS "trackc_insight_update"       ON public."AIInsight";
DROP POLICY IF EXISTS "trackc_insight_insert"       ON public."AIInsight";
DROP POLICY IF EXISTS "trackc_insight_select"       ON public."AIInsight";
DROP POLICY IF EXISTS "trackc_timeline_insert"      ON public."AURATimelineEvent";
DROP POLICY IF EXISTS "trackc_timeline_select"      ON public."AURATimelineEvent";
DROP POLICY IF EXISTS "trackc_vote_insert"          ON public."DecisionVote";
DROP POLICY IF EXISTS "trackc_vote_select"          ON public."DecisionVote";
DROP POLICY IF EXISTS "trackc_decision_update"      ON public."FamilyDecision";
DROP POLICY IF EXISTS "trackc_decision_insert"      ON public."FamilyDecision";
DROP POLICY IF EXISTS "trackc_decision_select"      ON public."FamilyDecision";
DROP POLICY IF EXISTS "trackc_clause_delete"        ON public."ConstitutionClause";
DROP POLICY IF EXISTS "trackc_clause_update"        ON public."ConstitutionClause";
DROP POLICY IF EXISTS "trackc_clause_insert"        ON public."ConstitutionClause";
DROP POLICY IF EXISTS "trackc_clause_select"        ON public."ConstitutionClause";
DROP POLICY IF EXISTS "trackc_article_delete"       ON public."ConstitutionArticle";
DROP POLICY IF EXISTS "trackc_article_update"       ON public."ConstitutionArticle";
DROP POLICY IF EXISTS "trackc_article_insert"       ON public."ConstitutionArticle";
DROP POLICY IF EXISTS "trackc_article_select"       ON public."ConstitutionArticle";
DROP POLICY IF EXISTS "trackc_version_update"       ON public."ConstitutionVersion";
DROP POLICY IF EXISTS "trackc_version_insert"       ON public."ConstitutionVersion";
DROP POLICY IF EXISTS "trackc_version_select"       ON public."ConstitutionVersion";
DROP POLICY IF EXISTS "trackc_constitution_update"  ON public."FamilyConstitution";
DROP POLICY IF EXISTS "trackc_constitution_insert"  ON public."FamilyConstitution";
DROP POLICY IF EXISTS "trackc_constitution_select"  ON public."FamilyConstitution";

DROP TABLE IF EXISTS public."SyncWatermark";
DROP TABLE IF EXISTS public."AICostBudget";
DROP TABLE IF EXISTS public."GlobalLearningDefaults";

DROP FUNCTION IF EXISTS public.fn_trackc_user_family_ids();

-- pg-boss schema: leave it alone — pg-boss library manages its own tables.
-- Dropping the schema would break any running pg-boss instance.
-- DROP SCHEMA IF EXISTS pgboss CASCADE;
