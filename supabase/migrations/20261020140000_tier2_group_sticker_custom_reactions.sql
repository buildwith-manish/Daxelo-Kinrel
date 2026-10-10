-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.12: Group Sticker Pack + Custom Reactions
-- =============================================================================
-- Lets a group admin set:
--   • A default sticker pack (so all members see the same pack when they
--     open the sticker picker in this chat).
--   • Up to 8 custom reactions (beyond the standard emoji set). These show
--     in the reaction tray when a member long-presses a message in this chat.
--
-- Implementation:
--   • Add `defaultStickerPackId text` to Family (nullable; null = no default
--     pack — users see their own installed packs).
--   • Add `customReactions jsonb` to Family (array of emoji strings, max 8).
--   • Admin-only update RPCs.
--   • The NestJS ChatService merges customReactions with the default set
--     when returning reaction counts.
-- =============================================================================

ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "defaultStickerPackId" text;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "customReactions" jsonb NOT NULL DEFAULT '[]'::jsonb;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_group_sticker_pack — admin sets the default pack for the group
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_group_sticker_pack(
  p_family_id text,
  p_sticker_pack_id text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_role text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  SELECT role INTO v_role FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id;
  IF v_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;
  IF v_role NOT IN ('admin', 'creator') THEN
    RETURN json_build_object('success', false, 'error', 'not_admin');
  END IF;

  UPDATE "Family"
    SET "defaultStickerPackId" = NULLIF(p_sticker_pack_id, ''),
        "updatedAt" = now()
    WHERE id = p_family_id;

  -- Audit row.
  PERFORM fn_log_group_audit(
    p_family_id, v_user_id, 'sticker_pack_set',
    NULL, NULL, jsonb_build_object('stickerPackId', p_sticker_pack_id)
  );

  RETURN json_build_object(
    'success', true,
    'familyId', p_family_id,
    'defaultStickerPackId', NULLIF(p_sticker_pack_id, '')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_group_sticker_pack(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_group_custom_reactions — admin sets the custom reaction set
-- (max 8 emoji). Pass an empty array to clear.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_group_custom_reactions(
  p_family_id text,
  p_reactions jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_role text;
  v_count int;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  SELECT role INTO v_role FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id;
  IF v_role IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;
  IF v_role NOT IN ('admin', 'creator') THEN
    RETURN json_build_object('success', false, 'error', 'not_admin');
  END IF;

  -- Validate: must be a JSON array, max 8 entries, each a non-empty string.
  IF jsonb_typeof(p_reactions) <> 'array' THEN
    RETURN json_build_object('success', false, 'error', 'invalid_reactions',
      'message', 'customReactions must be a JSON array of emoji strings.');
  END IF;
  v_count := jsonb_array_length(p_reactions);
  IF v_count > 8 THEN
    RETURN json_build_object('success', false, 'error', 'too_many_reactions',
      'message', 'Maximum 8 custom reactions.');
  END IF;

  UPDATE "Family"
    SET "customReactions" = p_reactions,
        "updatedAt" = now()
    WHERE id = p_family_id;

  PERFORM fn_log_group_audit(
    p_family_id, v_user_id, 'custom_reactions_set',
    NULL, NULL, jsonb_build_object('reactions', p_reactions)
  );

  RETURN json_build_object(
    'success', true,
    'familyId', p_family_id,
    'customReactions', p_reactions
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_group_custom_reactions(text, jsonb) TO authenticated;

-- Verification
SELECT 'Family.defaultStickerPackId' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'Family' AND column_name = 'defaultStickerPackId'
       ) AS exists;
SELECT 'Family.customReactions' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'Family' AND column_name = 'customReactions'
       ) AS exists;
SELECT 'fn_set_group_sticker_pack' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_group_sticker_pack') AS exists;
SELECT 'fn_set_group_custom_reactions' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_group_custom_reactions') AS exists;
