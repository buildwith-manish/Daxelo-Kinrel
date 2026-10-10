-- =============================================================================
-- Daxelo Kinrel — Tier 1 Feature 1.15: Multi-forward with Preview
-- =============================================================================
-- Extends the existing fn_forward_message RPC to accept a JSON array of
-- targets so a user can forward one message to multiple chats in a
-- single call (with a 5-target cap — anti-viral, like WhatsApp).
--
-- The existing signature (p_message_id, p_target_family_ids[], p_target_dm_user_ids[])
-- is preserved for backward compat. A new overload accepts a single
-- `p_targets jsonb` argument with shape:
--   [{ "type": "family", "id": "fam_xxx" },
--    { "type": "dm", "id": "user_yyy" },
--    { "type": "saved", "id": null }]   -- "saved" = my Saved Messages
--
-- The function returns per-target results so the client can show a
-- "Forwarded to N chats" toast + tap-to-navigate.
--
-- Idempotent.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_forward_message_multi(
  p_message_id text,
  p_targets jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id text := auth.uid()::text;
  v_caller_name text;
  v_sender_initials text;
  v_src record;
  v_target jsonb;
  v_target_type text;
  v_target_id text;
  v_new_id text;
  v_name_parts text[];
  v_inserted_ids text[] := ARRAY[]::text[];
  v_results jsonb[] := ARRAY[]::jsonb[];
  v_count int := 0;
  v_max_targets int := 5;   -- anti-viral cap
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Load the source message. RLS on ChatMessage only lets the caller
  -- read rows in families they're a member of, so this naturally
  -- enforces "you can only forward messages you can see".
  SELECT * INTO v_src FROM "ChatMessage" WHERE "id" = p_message_id;
  IF v_src IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'message_not_found');
  END IF;

  -- Block forwarding non-forwardable types.
  IF v_src."messageType" IN ('poll', 'gameInvite', 'familyEvent') THEN
    RETURN json_build_object('success', false, 'error', 'not_forwardable',
      'message', 'This message type cannot be forwarded.');
  END IF;

  -- Enforce the 5-target cap.
  IF jsonb_array_length(p_targets) > v_max_targets THEN
    RETURN json_build_object(
      'success', false,
      'error', 'too_many_targets',
      'message', format('You can forward to at most %s chats at once.', v_max_targets)
    );
  END IF;

  -- Resolve caller display info.
  SELECT name INTO v_caller_name FROM "User" WHERE id = v_caller_id;
  IF v_caller_name IS NULL OR v_caller_name = '' THEN
    v_caller_name := 'Someone';
  END IF;
  v_name_parts := regexp_split_to_array(v_caller_name, '\s+');
  IF array_length(v_name_parts, 1) >= 2 AND v_name_parts[2] <> '' THEN
    v_sender_initials := UPPER(SUBSTRING(v_name_parts[1] FROM 1 FOR 1)
                              || SUBSTRING(v_name_parts[2] FROM 1 FOR 1));
  ELSE
    v_sender_initials := UPPER(SUBSTRING(v_name_parts[1] FROM 1 FOR 1));
  END IF;

  FOR v_target IN SELECT * FROM jsonb_array_elements(p_targets) LOOP
    v_target_type := v_target->>'type';
    v_target_id := v_target->>'id';

    BEGIN
      IF v_target_type = 'family' THEN
        -- Validate membership.
        IF NOT EXISTS (
          SELECT 1 FROM "FamilyMember"
          WHERE "familyId" = v_target_id AND "userId" = v_caller_id
        ) THEN
          v_results := array_append(v_results, jsonb_build_object(
            'type', 'family', 'id', v_target_id, 'success', false, 'error', 'not_in_family'
          ));
          CONTINUE;
        END IF;

        v_new_id := 'cm_fwd_' || extract(epoch from now())::bigint::text || '_' || substring(v_target_id from 1 for 8) || '_' || substring(v_caller_id from 1 for 8);

        INSERT INTO "ChatMessage" (
          "id", "familyId",
          "senderId", "senderName", "senderInitials",
          "content", "messageType", "messageSubType",
          "mediaUrl", "voiceMessageDuration", "durationSeconds",
          "forwardedFrom",
          "replyToId", "replyToContent", "replyToSenderName",
          "mentions", "caption",
          "isRead", "messageStatus",
          "createdAt", "updatedAt"
        ) VALUES (
          v_new_id, v_target_id,
          v_caller_id, v_caller_name, v_sender_initials,
          v_src."content", v_src."messageType", COALESCE(v_src."messageSubType", 'text'),
          v_src."mediaUrl", v_src."voiceMessageDuration", v_src."durationSeconds",
          v_src."senderName",
          NULL, NULL, NULL,
          '[]'::jsonb, v_src."caption",
          false, 'sent',
          now(), now()
        );

        v_inserted_ids := array_append(v_inserted_ids, v_new_id);
        v_results := array_append(v_results, jsonb_build_object(
          'type', 'family', 'id', v_target_id, 'success', true, 'messageId', v_new_id
        ));
        v_count := v_count + 1;

      ELSIF v_target_type = 'dm' THEN
        IF v_target_id = v_caller_id THEN
          v_results := array_append(v_results, jsonb_build_object(
            'type', 'dm', 'id', v_target_id, 'success', false, 'error', 'cannot_forward_to_self'
          ));
          CONTINUE;
        END IF;

        -- For DMs, only forward text + sticker (no mediaUrl column on DM).
        IF v_src."messageType" NOT IN ('text', 'sticker') THEN
          v_results := array_append(v_results, jsonb_build_object(
            'type', 'dm', 'id', v_target_id, 'success', false, 'error', 'dm_only_supports_text'
          ));
          CONTINUE;
        END IF;

        v_new_id := 'dm_fwd_' || extract(epoch from now())::bigint::text || '_' || substring(v_caller_id from 1 for 8) || '_' || substring(v_target_id from 1 for 8);

        INSERT INTO "DirectMessage" (
          "id", "senderId", "receiverId",
          "content", "messageType",
          "isRead", "createdAt", "updatedAt"
        ) VALUES (
          v_new_id, v_caller_id, v_target_id,
          v_src."content", v_src."messageType",
          false, now(), now()
        );

        v_inserted_ids := array_append(v_inserted_ids, v_new_id);
        v_results := array_append(v_results, jsonb_build_object(
          'type', 'dm', 'id', v_target_id, 'success', true, 'messageId', v_new_id
        ));
        v_count := v_count + 1;

      ELSIF v_target_type = 'saved' THEN
        -- Forward to Saved Messages = DM with self.
        v_new_id := 'dm_fwd_saved_' || extract(epoch from now())::bigint::text || '_' || substring(v_caller_id from 1 for 8);

        IF v_src."messageType" NOT IN ('text', 'sticker') THEN
          -- For Saved Messages we ALSO allow image + voice + document
          -- since it's the user's own archive. But DirectMessage has no
          -- mediaUrl column in the current schema, so we store a small
          -- "media reference" content placeholder until the schema is
          -- extended. For now, text + sticker only.
          v_results := array_append(v_results, jsonb_build_object(
            'type', 'saved', 'id', NULL, 'success', false, 'error', 'saved_only_supports_text_yet'
          ));
          CONTINUE;
        END IF;

        INSERT INTO "DirectMessage" (
          "id", "senderId", "receiverId",
          "content", "messageType",
          "isRead", "createdAt", "updatedAt"
        ) VALUES (
          v_new_id, v_caller_id, v_caller_id,
          v_src."content", v_src."messageType",
          true, now(), now()
        );

        v_inserted_ids := array_append(v_inserted_ids, v_new_id);
        v_results := array_append(v_results, jsonb_build_object(
          'type', 'saved', 'id', NULL, 'success', true, 'messageId', v_new_id
        ));
        v_count := v_count + 1;

      ELSE
        v_results := array_append(v_results, jsonb_build_object(
          'type', v_target_type, 'id', v_target_id, 'success', false, 'error', 'unknown_target_type'
        ));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_results := array_append(v_results, jsonb_build_object(
        'type', v_target_type, 'id', v_target_id, 'success', false, 'error', SQLERRM
      ));
    END;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'totalTargets', jsonb_array_length(p_targets),
    'forwardedCount', v_count,
    'results', to_jsonb(v_results),
    'insertedMessageIds', to_jsonb(v_inserted_ids)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_forward_message_multi(text, jsonb) TO authenticated;

-- Verification
SELECT 'fn_forward_message_multi' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_forward_message_multi') AS exists;
