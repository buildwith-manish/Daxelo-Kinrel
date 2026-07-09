-- Rollback for 20260711000002_trackc_create_family_decision.sql
DROP TRIGGER IF EXISTS trg_trackc_decision_updated_at ON public."FamilyDecision";
DROP TABLE IF EXISTS public."DecisionVote";
DROP TABLE IF EXISTS public."FamilyDecision";
