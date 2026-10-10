-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.11: Group Description (rules / topic / links)
-- =============================================================================
-- Adds a 500-char description to the Family table (admin-editable, shown in
-- group info + on the chat header). Also adds a system message stream when
-- the description changes ("X changed the group description").
--
-- NOTE: The Family table already has a "description" column in the Prisma
-- schema, but we ADD it here idempotently in case the column was never
-- actually created in Postgres (some Family rows might pre-date the column
-- addition). We also raise the cap from the default varchar to text + add
-- a CHECK constraint capping at 500 chars.
-- =============================================================================

-- Ensure the column exists (idempotent).
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "description" text;

-- Cap at 500 chars (idempotent constraint add).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'Family_description_len_chk'
  ) THEN
    ALTER TABLE "Family"
      ADD CONSTRAINT "Family_description_len_chk"
      CHECK ("description" IS NULL OR char_length("description") <= 500);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Family_description_len_chk: %', SQLERRM;
END $$;

-- Add a column tracking who last edited the description + when, so the
-- group info screen can show "Edited by X at Y".
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "descriptionEditedBy" text;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "descriptionEditedAt" timestamptz;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_set_group_description — admin-only update + audit row + system message
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_set_group_description(
  p_family_id text,
  p_description text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_user_name text;
  v_is_admin boolean := false;
  v_old_description text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Resolve membership + admin role.
  SELECT role INTO v_user_name FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id;
  IF v_user_name IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;
  v_is_admin := (v_user_name = 'admin' OR v_user_name = 'creator');
  IF NOT v_is_admin THEN
    RETURN json_build_object('success', false, 'error', 'not_admin');
  END IF;

  -- Validate length.
  IF p_description IS NOT NULL AND char_length(p_description) > 500 THEN
    RETURN json_build_object('success', false, 'error', 'description_too_long',
      'message', 'Description must be at most 500 characters.');
  END IF;

  SELECT description INTO v_old_description FROM "Family" WHERE id = p_family_id;

  -- No-op if the new value equals the existing value.
  IF COALESCE(v_old_description, '') = COALESCE(p_description, '') THEN
    RETURN json_build_object('success', true, 'action', 'no_change');
  END IF;

  SELECT name INTO v_user_name FROM "User" WHERE id = v_user_id;
  IF v_user_name IS NULL OR v_user_name = '' THEN v_user_name := 'Admin'; END IF;

  UPDATE "Family"
    SET
      "description" = NULLIF(p_description, ''),
      "descriptionEditedBy" = v_user_id,
      "descriptionEditedAt" = now(),
      "updatedAt" = now()
    WHERE id = p_family_id;

  -- Insert a system message so members see "X changed the group description"
  -- in the chat. Matches WhatsApp behavior.
  INSERT INTO "ChatMessage" (
    "id", "familyId",
    "senderId", "senderName", "senderInitials",
    "content", "messageType", "messageSubType",
    "messageStatus", "createdAt", "updatedAt"
  ) VALUES (
    'cm_sysdesc_' || extract(epoch from now())::bigint::text || '_' || substring(p_family_id from 1 for 8),
    p_family_id,
    v_user_id, v_user_name, '',
    CASE
      WHEN p_description IS NULL OR p_description = '' THEN v_user_name || ' cleared the group description.'
      ELSE v_user_name || ' changed the group description.'
    END,
    'system', 'system',
    'sent', now(), now()
  );

  RETURN json_build_object(
    'success', true,
    'action', 'updated',
    'familyId', p_family_id,
    'description', NULLIF(p_description, ''),
    'editedBy', v_user_id,
    'editedAt', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_set_group_description(text, text) TO authenticated;

-- Verification
SELECT 'Family.descriptionEditedBy' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'Family' AND column_name = 'descriptionEditedBy'
       ) AS exists;
SELECT 'fn_set_group_description' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_set_group_description') AS exists;
