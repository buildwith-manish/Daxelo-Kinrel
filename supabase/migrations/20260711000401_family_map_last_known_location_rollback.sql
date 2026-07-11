-- =============================================================================
-- ROLLBACK: Family Map — Last-Known Member Location table
-- =============================================================================
-- Reverses 20260711000401_family_map_last_known_location.sql
-- =============================================================================

DROP TRIGGER IF EXISTS "MemberLocation_set_updated_at" ON public."MemberLocation";
DROP FUNCTION IF EXISTS public."set_member_location_updated_at"();

DROP INDEX IF EXISTS "MemberLocation_userId_idx";
DROP INDEX IF EXISTS "MemberLocation_familyId_idx";

DROP POLICY IF EXISTS "MemberLocation_delete_owner_only" ON public."MemberLocation";
DROP POLICY IF EXISTS "MemberLocation_update_owner_only" ON public."MemberLocation";
DROP POLICY IF EXISTS "MemberLocation_insert_owner_only" ON public."MemberLocation";
DROP POLICY IF EXISTS "MemberLocation_select_family_members" ON public."MemberLocation";

DROP TABLE IF EXISTS public."MemberLocation";
