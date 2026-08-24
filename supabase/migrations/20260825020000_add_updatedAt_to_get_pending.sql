-- =============================================================================
-- Daxelo Kinrel — Add updatedAt to fn_get_pending_graph_invitations (v5.96b)
-- =============================================================================
--
-- Updates fn_get_pending_graph_invitations to also return "updatedAt" and
-- "recipientUserId" in each invitation row, so the frontend can display
-- relative time ("Sent 5 minutes ago") and check for Find-on-Kinrel invites.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_get_pending_graph_invitations(
  p_family_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_result json;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Not a member of this family');
  END IF;

  SELECT COALESCE(json_agg(
    json_build_object(
      'id', gpi.id,
      'familyId', gpi."familyId",
      'inviterUserId', gpi."inviterUserId",
      'inviterName', u.name,
      'targetPersonId', gpi."targetPersonId",
      'targetPersonName', p.name,
      'relationshipKey', gpi."relationshipKey",
      'specificLabelAtoB', gpi."specificLabelAtoB",
      'recipientName', gpi."recipientName",
      'recipientEmail', gpi."recipientEmail",
      'recipientPhone', gpi."recipientPhone",
      'recipientUserId', gpi."recipientUserId",
      'status', gpi.status,
      'expiresAt', gpi."expiresAt",
      'createdAt', gpi."createdAt",
      'updatedAt', gpi."updatedAt",
      'inviteCode', gpi."inviteCode"
    )
    ORDER BY gpi."createdAt" DESC
  ), '[]'::json) INTO v_result
  FROM "GraphPendingInvitation" gpi
  LEFT JOIN "User" u ON u.id = gpi."inviterUserId"
  LEFT JOIN "Person" p ON p.id = gpi."targetPersonId"
  WHERE gpi."familyId" = p_family_id
    AND gpi.status = 'pending'
    AND gpi."expiresAt" > now();

  RETURN json_build_object('success', true, 'invitations', v_result);
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_pending_graph_invitations(text) TO authenticated;
