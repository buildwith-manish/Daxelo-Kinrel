-- =============================================================================
-- Daxelo Kinrel — Resend Invitation + Cancel Notification (v5.94)
-- =============================================================================
--
-- PURPOSE:
--   1. Add fn_resend_graph_invitation(p_invitation_id) — extends the
--      invitation's expiry and sends a reminder notification to the
--      recipient. Only the inviter or a family admin/owner can call it.
--      Only works if status = 'pending'.
--
--   2. Replace fn_cancel_graph_invitation with an updated version that
--      ALSO creates a notification for the recipient so any pending-invite
--      view on the receiver's side updates/removes itself. All existing
--      logic is kept identical; only the notification INSERT is added
--      before the final RETURN.
--
-- AUTHORIZATION (same as fn_cancel_graph_invitation):
--   • The inviter (inviterUserId = auth.uid())
--   • OR a family admin/owner (FamilyMember.role IN ('admin', 'owner'))
--
-- NOTIFICATION PATTERN:
--   Copied from fn_create_graph_pending_invitation's notification INSERT
--   in migration 20260818130000_graph_invitation_recipient_user_id.sql.
--   The recipient is looked up by:
--     1. If recipientUserId is set on the invitation → use it directly
--     2. Else if recipientEmail is set → look up User.id by email
--     3. Else if recipientPhone is set → look up User.id by phone
--   If no recipient user can be found, the notification is skipped
--   (best-effort — the invitation is still resent/cancelled).
--
-- This migration does NOT touch fn_accept_graph_invitation or
-- fn_decline_graph_invitation.
-- =============================================================================

-- ── 1. fn_resend_graph_invitation ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_resend_graph_invitation(
  p_invitation_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_invitation RECORD;
  v_recipient_user_id text;
  v_notif_id text;
  v_target_name text;
  v_family_name text;
  v_inviter_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Invitation not found');
  END IF;

  IF v_invitation.status <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'invitation_not_pending');
  END IF;

  -- Only the inviter or a family admin/owner can resend
  IF v_invitation.inviterUserId <> v_user_id THEN
    IF NOT EXISTS(
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = v_invitation.familyId
        AND "userId" = v_user_id
        AND "role" IN ('admin', 'owner')
    ) THEN
      RETURN json_build_object('success', false, 'error', 'Not authorized to resend this invitation');
    END IF;
  END IF;

  -- Extend expiry by 7 days (matching the original default in
  -- fn_create_graph_pending_invitation: now() + interval '7 days')
  UPDATE "GraphPendingInvitation"
  SET "updatedAt" = now(),
      "expiresAt" = now() + interval '7 days'
  WHERE id = p_invitation_id;

  -- Resolve the recipient's user ID for the notification
  v_recipient_user_id := v_invitation.recipientUserId;

  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    -- Try to look up by recipientEmail
    IF v_invitation.recipientEmail IS NOT NULL AND v_invitation.recipientEmail <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE email = v_invitation.recipientEmail
      LIMIT 1;
    END IF;
  END IF;

  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    -- Try to look up by recipientPhone
    IF v_invitation.recipientPhone IS NOT NULL AND v_invitation.recipientPhone <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE phone = v_invitation.recipientPhone
      LIMIT 1;
    END IF;
  END IF;

  -- Create a reminder notification (best-effort)
  IF v_recipient_user_id IS NOT NULL AND v_recipient_user_id <> '' THEN
    BEGIN
      -- Get names for a human-readable notification body
      SELECT name INTO v_target_name FROM "Person" WHERE id = v_invitation.targetPersonId LIMIT 1;
      SELECT name INTO v_family_name FROM "Family" WHERE id = v_invitation.familyId LIMIT 1;
      SELECT name INTO v_inviter_name FROM "User" WHERE id = v_invitation.inviterUserId LIMIT 1;
      IF v_family_name IS NULL THEN v_family_name := 'the family'; END IF;
      IF v_inviter_name IS NULL THEN v_inviter_name := 'Someone'; END IF;

      v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_recipient_user_id from 1 for 8);

      INSERT INTO "Notification" (
        "id", "userId", "eventType", "title", "body",
        "familyId", "channels", "priority", "read",
        "actionUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_notif_id,
        v_recipient_user_id,
        'graph_invite',
        'Family Tree Invitation Reminder',
        v_inviter_name || ' sent you a reminder to join ' || v_family_name || ' as the ' || v_invitation.specificLabelAtoB || ' of ' || COALESCE(v_target_name, 'a family member'),
        v_invitation.familyId,
        'in_app',
        'normal',
        false,
        'graph_invite:' || p_invitation_id,
        now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Notification is best-effort — don't fail the resend
      NULL;
    END;
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'Invitation resent',
    'expiresAt', now() + interval '7 days'
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_resend_graph_invitation(text) TO authenticated;

-- ── 2. Updated fn_cancel_graph_invitation (adds recipient notification) ────
--
-- This is a CREATE OR REPLACE of the function from
-- 20260818120000_graph_pending_invitations.sql. All existing logic is
-- kept identical. The ONLY change is: before the final RETURN
-- json_build_object('success', true, ...), a notification row is
-- inserted for the recipient with a message like "This family
-- invitation was cancelled by the sender."

CREATE OR REPLACE FUNCTION fn_cancel_graph_invitation(
  p_invitation_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_invitation RECORD;
  v_recipient_user_id text;
  v_notif_id text;
  v_family_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_invitation
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Invitation not found');
  END IF;

  IF v_invitation.status <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'invitation_not_pending');
  END IF;

  -- Only the inviter or a family admin can cancel
  IF v_invitation.inviterUserId <> v_user_id THEN
    IF NOT EXISTS(
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = v_invitation.familyId
        AND "userId" = v_user_id
        AND "role" IN ('admin', 'owner')
    ) THEN
      RETURN json_build_object('success', false, 'error', 'Not authorized to cancel this invitation');
    END IF;
  END IF;

  -- Mark as cancelled — NO Person node or Relationship is created
  UPDATE "GraphPendingInvitation"
  SET status = 'cancelled', "updatedAt" = now()
  WHERE id = p_invitation_id;

  -- v5.94: Notify the recipient so any pending-invite view on the
  -- receiver's side updates/removes itself.
  v_recipient_user_id := v_invitation.recipientUserId;

  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    IF v_invitation.recipientEmail IS NOT NULL AND v_invitation.recipientEmail <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE email = v_invitation.recipientEmail
      LIMIT 1;
    END IF;
  END IF;

  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    IF v_invitation.recipientPhone IS NOT NULL AND v_invitation.recipientPhone <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE phone = v_invitation.recipientPhone
      LIMIT 1;
    END IF;
  END IF;

  IF v_recipient_user_id IS NOT NULL AND v_recipient_user_id <> '' THEN
    BEGIN
      SELECT name INTO v_family_name FROM "Family" WHERE id = v_invitation.familyId LIMIT 1;
      IF v_family_name IS NULL THEN v_family_name := 'the family'; END IF;

      v_notif_id := 'notif_' || extract(epoch from now())::bigint::text || '_' || substring(v_recipient_user_id from 1 for 8);

      INSERT INTO "Notification" (
        "id", "userId", "eventType", "title", "body",
        "familyId", "channels", "priority", "read",
        "actionUrl", "createdAt", "updatedAt"
      ) VALUES (
        v_notif_id,
        v_recipient_user_id,
        'graph_invite_cancelled',
        'Family Invitation Cancelled',
        'This family invitation was cancelled by the sender.',
        v_invitation.familyId,
        'in_app',
        'normal',
        false,
        'graph_invite:' || p_invitation_id,
        now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      -- Notification is best-effort — don't fail the cancel
      NULL;
    END;
  END IF;

  RETURN json_build_object('success', true, 'message', 'Invitation cancelled');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cancel_graph_invitation(text) TO authenticated;
