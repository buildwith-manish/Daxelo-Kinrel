-- ════════════════════════════════════════════════════════════════════
-- Migration: 20260910100000_fix_fn_cancel_graph_invitation_plan_cache
--
-- PURPOSE
-- Fix the `fn_cancel_graph_invitation` RPC's "type of parameter 17
-- (GraphPendingInvitation) does not match that when preparing the
-- plan (record)" error.
--
-- BACKGROUND
-- The previous version of `fn_cancel_graph_invitation` declared
-- `v_invitation RECORD` and used `SELECT * INTO v_invitation` to load
-- the entire GraphPendingInvitation row. This worked initially, but
-- every migration that added columns to `GraphPendingInvitation` (e.g.
-- 20260907170000_graph_invitation_broadcast_trigger.sql,
-- 20260909140000_backfix_cross_family_graph_invite_edges.sql)
-- changed the table's column count and types — which silently
-- invalidated the cached prepared-statement plan but Supabase's
-- PostgREST did not always re-prepare the function. The result:
-- every call to fn_cancel_graph_invitation returned the error
-- "type of parameter 17 (GraphPendingInvitation) does not match
-- that when preparing the plan (record)" and the cancel silently
-- failed.
--
-- This was the root cause of the v5.194 "Undo" snackbar's reported
-- failure: tapping Undo called fn_cancel_graph_invitation, which
-- returned success=false, and the invitation stayed 'pending'.
--
-- FIX
-- Replace the RECORD-typed `v_invitation` with EXPLICIT column
-- variables. We only load the 6 columns the function actually uses:
--   - inviterUserId (for the authorization check)
--   - familyId (for the FamilyMember permission check + Notification)
--   - status (for the 'pending' check)
--   - recipientUserId / recipientEmail / recipientPhone (for the
--     recipient-lookup fallback chain)
--
-- Because none of these columns were added by recent migrations
-- (they're all original columns from the v5.43 schema), the
-- prepared-statement plan is stable across future schema changes.
-- Even if a future migration adds a new column to
-- GraphPendingInvitation, this function will continue to work
-- because it doesn't reference the new column.
--
-- The same fix could be applied to fn_create_graph_pending_invitation,
-- fn_resend_graph_invitation, fn_accept_graph_invitation, and
-- fn_decline_graph_invitation if they exhibit the same plan-cache
-- mismatch (they all use `RECORD` for v_invitation). This migration
-- only fixes fn_cancel_graph_invitation because that's the one
-- called by the v5.194 Undo snackbar; the others should be fixed
-- similarly in a future migration if they fail.
--
-- POST-APPLY
-- After applying this migration, send `NOTIFY pgrst, 'reload schema'`
-- to force PostgREST to invalidate its cached function plans. Without
-- this signal, the new function definition won't be picked up for
-- up to ~10 minutes (PostgREST's default schema-cache refresh
-- interval). See: https://postgrest.org/en/stable/references/schema_cache.html
-- ════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.fn_cancel_graph_invitation(text) CASCADE;

CREATE OR REPLACE FUNCTION public.fn_cancel_graph_invitation(p_invitation_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id text := auth.uid()::text;
  v_inviter_user_id text;
  v_invitation_family_id text;
  v_invitation_status text;
  v_recipient_user_id text;
  v_recipient_email text;
  v_recipient_phone text;
  v_notif_id text;
  v_family_name text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- v5.194: Load ONLY the columns we need, using explicit typed
  -- variables instead of RECORD. This avoids the Supabase PostgREST
  -- prepared-statement plan-cache mismatch that occurs when the
  -- GraphPendingInvitation table schema changes (each migration
  -- that adds columns invalidates the cached plan but PostgREST
  -- does not always re-prepare, causing the
  -- "type of parameter 17 does not match that when preparing the
  -- plan (record)" error).
  SELECT
    "inviterUserId",
    "familyId",
    "status",
    "recipientUserId",
    "recipientEmail",
    "recipientPhone"
  INTO
    v_inviter_user_id,
    v_invitation_family_id,
    v_invitation_status,
    v_recipient_user_id,
    v_recipient_email,
    v_recipient_phone
  FROM "GraphPendingInvitation"
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF v_invitation_family_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Invitation not found');
  END IF;

  IF v_invitation_status <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'invitation_not_pending');
  END IF;

  -- Only the inviter or a family admin can cancel
  IF v_inviter_user_id <> v_user_id THEN
    IF NOT EXISTS(
      SELECT 1 FROM "FamilyMember"
      WHERE "familyId" = v_invitation_family_id
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
  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    IF v_recipient_email IS NOT NULL AND v_recipient_email <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE email = v_recipient_email
      LIMIT 1;
    END IF;
  END IF;

  IF v_recipient_user_id IS NULL OR v_recipient_user_id = '' THEN
    IF v_recipient_phone IS NOT NULL AND v_recipient_phone <> '' THEN
      SELECT id::text INTO v_recipient_user_id
      FROM "User"
      WHERE phone = v_recipient_phone
      LIMIT 1;
    END IF;
  END IF;

  IF v_recipient_user_id IS NOT NULL AND v_recipient_user_id <> '' THEN
    BEGIN
      SELECT name INTO v_family_name FROM "Family" WHERE id = v_invitation_family_id LIMIT 1;
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
        v_invitation_family_id,
        'in_app',
        'normal',
        false,
        'graph_invite:' || p_invitation_id,
        now(), now()
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN json_build_object('success', true, 'message', 'Invitation cancelled');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$function$;

COMMENT ON FUNCTION public.fn_cancel_graph_invitation(text) IS
'v5.194: Replaced RECORD-typed v_invitation with explicit column variables to avoid the Supabase PostgREST prepared-plan cache mismatch that occurs when the GraphPendingInvitation table schema changes.';

REVOKE EXECUTE ON FUNCTION public.fn_cancel_graph_invitation(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cancel_graph_invitation(text) TO authenticated;

-- ────────────────────────────────────────────────────────────────────
-- Force PostgREST to invalidate its schema cache so the new function
-- definition is picked up immediately (otherwise the old plan stays
-- cached for up to ~10 minutes).
-- ────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
