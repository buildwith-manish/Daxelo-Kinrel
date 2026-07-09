-- =============================================================================
-- Daxelo-Kinrel — fn_send_family_invite_notification
-- =============================================================================
-- Creates a Notification row for a direct family invite.
-- Uses SECURITY DEFINER so RLS doesn't block the insert (the caller is
-- the inviter, not the recipient — the recipient's RLS policy would
-- block a direct insert from another user).
--
-- This function exists to work around a PostgREST column ambiguity
-- error ("column reference 'id' is ambiguous") that occurs when
-- inserting into Notification via the Supabase REST API — the RLS
-- policy subquery (SELECT auth.uid() AS uid) conflicts with the
-- Notification table's "id" column in PostgREST's generated query.
-- Using an RPC bypasses PostgREST's query generation entirely.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_send_family_invite_notification(
  p_target_user_id text,
  p_family_id text,
  p_family_name text,
  p_invite_url text,
  p_inviter_name text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notif_id text;
BEGIN
  -- Validate the caller is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to send an invite';
  END IF;

  -- Generate a unique notification ID
  v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || p_target_user_id;

  -- Insert the notification for the target user
  INSERT INTO "Notification" (
    "id", "userId", "eventType", "title", "body",
    "familyId", "actionUrl", "priority", "read"
  ) VALUES (
    v_notif_id,
    p_target_user_id,
    'family_invite',
    COALESCE(p_inviter_name, 'Someone') || ' invited you to join ' || p_family_name,
    'You have been invited to join ' || p_family_name || ' on Daxelo Kinrel. Tap to accept.',
    p_family_id,
    p_invite_url,
    'high',
    false
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_send_family_invite_notification(text, text, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.fn_send_family_invite_notification(text, text, text, text, text) IS
  'Creates a Notification row for a direct family invite. SECURITY DEFINER so the inviter can create a notification for the recipient. Called from the Flutter Invite directly flow.';
