-- =============================================================================
-- Track C v2.0 — RLS on ALL Track C tables
-- =============================================================================
-- Implements Section 12.1 of the FINAL v2.0 spec.
-- ADR-008: NO service_role bypass from application code. Only system jobs
-- (pg-boss workers) use a separate service account with table-scoped grants.
--
-- Pattern (per Section 12.1):
--   * family_member_read  → SELECT for active family members
--   * family_member_write → INSERT/UPDATE/DELETE for active admin/elder/member
--   * service_role → bypass RLS (for pg-boss workers only)
-- =============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- Helper: family-member subquery
-- Returns the set of familyId values the current user is an active member of.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_trackc_user_family_ids()
RETURNS SETOF TEXT LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT "familyId" FROM public."FamilyMember"
  WHERE "userId" = auth.uid()::text
    AND "role" IN ('owner','admin','elder','member','viewer')
$$;

-- =============================================================================
-- FamilyConstitution
-- =============================================================================
ALTER TABLE public."FamilyConstitution" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_constitution_select" ON public."FamilyConstitution";
CREATE POLICY "trackc_constitution_select" ON public."FamilyConstitution"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_constitution_insert" ON public."FamilyConstitution";
CREATE POLICY "trackc_constitution_insert" ON public."FamilyConstitution"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_constitution_update" ON public."FamilyConstitution";
CREATE POLICY "trackc_constitution_update" ON public."FamilyConstitution"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- ConstitutionVersion
-- =============================================================================
ALTER TABLE public."ConstitutionVersion" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_version_select" ON public."ConstitutionVersion";
CREATE POLICY "trackc_version_select" ON public."ConstitutionVersion"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_version_insert" ON public."ConstitutionVersion";
CREATE POLICY "trackc_version_insert" ON public."ConstitutionVersion"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_version_update" ON public."ConstitutionVersion";
CREATE POLICY "trackc_version_update" ON public."ConstitutionVersion"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- ConstitutionArticle
-- =============================================================================
ALTER TABLE public."ConstitutionArticle" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_article_select" ON public."ConstitutionArticle";
CREATE POLICY "trackc_article_select" ON public."ConstitutionArticle"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_article_insert" ON public."ConstitutionArticle";
CREATE POLICY "trackc_article_insert" ON public."ConstitutionArticle"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_article_update" ON public."ConstitutionArticle";
CREATE POLICY "trackc_article_update" ON public."ConstitutionArticle"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_article_delete" ON public."ConstitutionArticle";
CREATE POLICY "trackc_article_delete" ON public."ConstitutionArticle"
  FOR DELETE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- ConstitutionClause
-- =============================================================================
ALTER TABLE public."ConstitutionClause" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_clause_select" ON public."ConstitutionClause";
CREATE POLICY "trackc_clause_select" ON public."ConstitutionClause"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_clause_insert" ON public."ConstitutionClause";
CREATE POLICY "trackc_clause_insert" ON public."ConstitutionClause"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_clause_update" ON public."ConstitutionClause";
CREATE POLICY "trackc_clause_update" ON public."ConstitutionClause"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_clause_delete" ON public."ConstitutionClause";
CREATE POLICY "trackc_clause_delete" ON public."ConstitutionClause"
  FOR DELETE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- FamilyDecision (partitioned; policy applies to parent + all partitions)
-- =============================================================================
ALTER TABLE public."FamilyDecision" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_decision_select" ON public."FamilyDecision";
CREATE POLICY "trackc_decision_select" ON public."FamilyDecision"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_decision_insert" ON public."FamilyDecision";
CREATE POLICY "trackc_decision_insert" ON public."FamilyDecision"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_decision_update" ON public."FamilyDecision";
CREATE POLICY "trackc_decision_update" ON public."FamilyDecision"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- DecisionVote
-- =============================================================================
ALTER TABLE public."DecisionVote" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_vote_select" ON public."DecisionVote";
CREATE POLICY "trackc_vote_select" ON public."DecisionVote"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_vote_insert" ON public."DecisionVote";
CREATE POLICY "trackc_vote_insert" ON public."DecisionVote"
  FOR INSERT WITH CHECK (
    "familyId" IN (SELECT public.fn_trackc_user_family_ids())
    AND "userId" = auth.uid()::text
  );

-- =============================================================================
-- AURATimelineEvent (partitioned)
-- Read for all family members. INSERT only via service_role OR family members.
-- (UPDATE/DELETE already forbidden by trigger.)
-- =============================================================================
ALTER TABLE public."AURATimelineEvent" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_timeline_select" ON public."AURATimelineEvent";
CREATE POLICY "trackc_timeline_select" ON public."AURATimelineEvent"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_timeline_insert" ON public."AURATimelineEvent";
CREATE POLICY "trackc_timeline_insert" ON public."AURATimelineEvent"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- AIInsight (partitioned)
-- =============================================================================
ALTER TABLE public."AIInsight" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_insight_select" ON public."AIInsight";
CREATE POLICY "trackc_insight_select" ON public."AIInsight"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_insight_insert" ON public."AIInsight";
CREATE POLICY "trackc_insight_insert" ON public."AIInsight"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_insight_update" ON public."AIInsight";
CREATE POLICY "trackc_insight_update" ON public."AIInsight"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- LearningSignal (partitioned)
-- Clients may INSERT signals about their own actions.
-- =============================================================================
ALTER TABLE public."LearningSignal" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_signal_select" ON public."LearningSignal";
CREATE POLICY "trackc_signal_select" ON public."LearningSignal"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_signal_insert" ON public."LearningSignal";
CREATE POLICY "trackc_signal_insert" ON public."LearningSignal"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- FamilyBehaviorProfile (read-only from client perspective)
-- =============================================================================
ALTER TABLE public."FamilyBehaviorProfile" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_profile_select" ON public."FamilyBehaviorProfile";
CREATE POLICY "trackc_profile_select" ON public."FamilyBehaviorProfile"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

ALTER TABLE public."FamilyBehaviorProfileHistory" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_profile_history_select" ON public."FamilyBehaviorProfileHistory";
CREATE POLICY "trackc_profile_history_select" ON public."FamilyBehaviorProfileHistory"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- SmartReminder
-- Read only own reminders; UPDATE only own (snooze/dismiss/act).
-- =============================================================================
ALTER TABLE public."SmartReminder" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_reminder_select" ON public."SmartReminder";
CREATE POLICY "trackc_reminder_select" ON public."SmartReminder"
  FOR SELECT USING (
    "familyId" IN (SELECT public.fn_trackc_user_family_ids())
    AND "targetUserId" = auth.uid()::text
  );

DROP POLICY IF EXISTS "trackc_reminder_update" ON public."SmartReminder";
CREATE POLICY "trackc_reminder_update" ON public."SmartReminder"
  FOR UPDATE USING (
    "familyId" IN (SELECT public.fn_trackc_user_family_ids())
    AND "targetUserId" = auth.uid()::text
  );

-- =============================================================================
-- DecisionMemory, DecisionImpact
-- =============================================================================
ALTER TABLE public."DecisionMemory" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_memory_select" ON public."DecisionMemory";
CREATE POLICY "trackc_memory_select" ON public."DecisionMemory"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_memory_insert" ON public."DecisionMemory";
CREATE POLICY "trackc_memory_insert" ON public."DecisionMemory"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_memory_update" ON public."DecisionMemory";
CREATE POLICY "trackc_memory_update" ON public."DecisionMemory"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

ALTER TABLE public."DecisionImpact" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_impact_select" ON public."DecisionImpact";
CREATE POLICY "trackc_impact_select" ON public."DecisionImpact"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_impact_insert" ON public."DecisionImpact";
CREATE POLICY "trackc_impact_insert" ON public."DecisionImpact"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_impact_update" ON public."DecisionImpact";
CREATE POLICY "trackc_impact_update" ON public."DecisionImpact"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- MeetingArtifact
-- =============================================================================
ALTER TABLE public."MeetingArtifact" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_artifact_select" ON public."MeetingArtifact";
CREATE POLICY "trackc_artifact_select" ON public."MeetingArtifact"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_artifact_insert" ON public."MeetingArtifact";
CREATE POLICY "trackc_artifact_insert" ON public."MeetingArtifact"
  FOR INSERT WITH CHECK ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

DROP POLICY IF EXISTS "trackc_artifact_update" ON public."MeetingArtifact";
CREATE POLICY "trackc_artifact_update" ON public."MeetingArtifact"
  FOR UPDATE USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- SearchIndex
-- Read for all family members. INSERT/UPDATE/DELETE only via service_role.
-- =============================================================================
ALTER TABLE public."SearchIndex" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_search_select" ON public."SearchIndex";
CREATE POLICY "trackc_search_select" ON public."SearchIndex"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

-- =============================================================================
-- FamilyAnalyticsSnapshot
-- Read-only for family members. Writes only via pg-boss worker.
-- =============================================================================
ALTER TABLE public."FamilyAnalyticsSnapshot" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trackc_analytics_select" ON public."FamilyAnalyticsSnapshot";
CREATE POLICY "trackc_analytics_select" ON public."FamilyAnalyticsSnapshot"
  FOR SELECT USING ("familyId" IN (SELECT public.fn_trackc_user_family_ids()));

COMMENT ON FUNCTION public.fn_trackc_user_family_ids() IS 'Track C v2.0: Returns the set of familyId values the current user is an active member of. Used by all Track C RLS policies.';
