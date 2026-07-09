-- Rollback for 06 + 07 (LearningSignal + FamilyBehaviorProfile)
DROP TRIGGER IF EXISTS trg_trackc_behavior_profile_updated_at ON public."FamilyBehaviorProfile";
DROP TABLE IF EXISTS public."FamilyBehaviorProfileHistory";
DROP TABLE IF EXISTS public."FamilyBehaviorProfile";
DROP TABLE IF EXISTS public."LearningSignal";
