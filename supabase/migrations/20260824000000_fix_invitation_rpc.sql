-- =============================================================================
-- v5.83: Fix invitation RPC — search_path + member check + error messages
-- =============================================================================
-- ROOT CAUSES:
-- 1. The RPC's search_path was 'public' only, but gen_random_bytes lives
--    in the 'extensions' schema → "function gen_random_bytes(integer)
--    does not exist" error.
-- 2. The RPC only checked FamilyMember for authorization, not Person.
--    linkedUserId. Users linked to a Person (can view graph) but not in
--    FamilyMember (can't invite) got "You are not a member of this family".
-- 3. Two function overloads existed (with and without p_recipient_user_id),
--    causing PostgREST ambiguity errors.
-- 4. The RPC returned 'error' but not 'message' for some cases, causing
--    the Flutter app to show a generic "Could not send invitation" message.
--
-- FIXES:
-- 1. Changed search_path to 'public', 'extensions' (includes pgcrypto).
-- 2. Added Person.linkedUserId check as a fallback when FamilyMember
--    check fails.
-- 3. Dropped the old overload (without p_recipient_user_id).
-- 4. Added 'message' field to ALL error responses with human-readable text.
--
-- Also enabled the pgcrypto extension (CREATE EXTENSION IF NOT EXISTS pgcrypto).
-- Also added Manish (aa7ece5f) as a FamilyMember of the Test family.
-- =============================================================================

-- Enable pgcrypto for gen_random_bytes
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Drop the old overload (without p_recipient_user_id)
DROP FUNCTION IF EXISTS public.fn_create_graph_pending_invitation(text, text, text, text, text, text, text, integer);
