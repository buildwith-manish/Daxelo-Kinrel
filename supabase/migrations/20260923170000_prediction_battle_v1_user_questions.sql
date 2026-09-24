-- 20260923170000_prediction_battle_v1_user_questions.sql
--
-- Phase 3.9 — User-submitted questions for the Prediction Battle.
--
-- The 50 seed questions will run out after ~50 days per family (then
-- the 6-month cooldown kicks in and questions start repeating).
-- This migration adds a user-submitted questions flow:
--
--   1. Any family member can submit a question via the Flutter client.
--   2. Submissions land in pb_v1_user_questions with status='pending'.
--   3. An admin (via the existing /admin endpoints) approves or
--      rejects each submission. Approved submissions are inserted
--      into pb_v1_questions with a generated id (so they participate
--      in the normal rotation). Rejected submissions stay in
--      pb_v1_user_questions with status='rejected' for audit.
--   4. The submitter gets a small coin reward (5 coins) when their
--      question is approved + used in a round, via fn_award_coins
--      with reason='question_accepted' and idempotency_key=
--      '<question_id>'.
--
-- Why moderation
--   User-submitted questions could be inappropriate, too easy, too
--   hard, or have a wrong "correct_answer". An admin reviews each
--   submission before it goes live. The admin can also edit the
--   question_text / correct_answer / unit_label / fun_fact_text /
--   category during approval.
--
-- Why a separate table (vs. just inserting into pb_v1_questions)
--   - The submitter is tracked (for the coin reward + to give credit
--     in the future "submitted by X" UI).
--   - Rejected submissions are kept for audit (so we can see what
--     kind of questions users are submitting even if they don't get
--     approved).
--   - The status column makes moderation queue management easy.

CREATE TABLE IF NOT EXISTS "pb_v1_user_questions" (
  "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "submittedByUserId" TEXT NOT NULL,
  "familyId"        TEXT,                  -- NULL if submitted for global pool; family-scoped otherwise
  "questionText"    TEXT NOT NULL,
  "correctAnswer"   NUMERIC NOT NULL,
  "unitLabel"       TEXT NOT NULL DEFAULT '',
  "category"        TEXT NOT NULL DEFAULT 'general',
  "funFactText"     TEXT NOT NULL DEFAULT '',
  "minBound"        NUMERIC,
  "maxBound"        NUMERIC,
  "status"          TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'approved' | 'rejected'
  "reviewerUserId"  TEXT,
  "reviewedAt"      TIMESTAMPTZ,
  "approvedQuestionId" TEXT,                -- the id in pb_v1_questions after approval
  "rejectionReason" TEXT,
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pb_v1_uq_status_created
  ON "pb_v1_user_questions" ("status", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS idx_pb_v1_uq_submitter
  ON "pb_v1_user_questions" ("submittedByUserId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS idx_pb_v1_uq_family
  ON "pb_v1_user_questions" ("familyId", "createdAt" DESC)
  WHERE "familyId" IS NOT NULL;

ALTER TABLE "pb_v1_user_questions" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pb_v1_uq_select_self_or_admin ON "pb_v1_user_questions";
-- A user can read their own submissions. Admins can read all.
-- Family members can read submissions for their family (so they can
-- see "questions from your family" in a future UI).
CREATE POLICY pb_v1_uq_select_self_or_admin ON "pb_v1_user_questions"
  FOR SELECT TO authenticated
  USING (
    "submittedByUserId" = auth.uid()::text
    OR public.fn_user_is_family_member("familyId")
  );
DROP POLICY IF EXISTS pb_v1_uq_insert_self ON "pb_v1_user_questions";
CREATE POLICY pb_v1_uq_insert_self ON "pb_v1_user_questions"
  FOR INSERT TO authenticated
  WITH CHECK ("submittedByUserId" = auth.uid()::text);

-- ═════════════════════════════════════════════════════════════════════
-- RPC: fn_pb_v1_submit_user_question
-- ═════════════════════════════════════════════════════════════════════
--
-- Inserts a new pending submission. Validates that the question text
-- is non-empty, the correct_answer is a valid number, and the unit
-- label is at most 30 chars (to keep the card UI clean).

CREATE OR REPLACE FUNCTION public.fn_pb_v1_submit_user_question(
  p_user_id text,
  p_family_id text,
  p_question_text text,
  p_correct_answer numeric,
  p_unit_label text DEFAULT '',
  p_category text DEFAULT 'general',
  p_fun_fact_text text DEFAULT '',
  p_min_bound numeric DEFAULT NULL,
  p_max_bound numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text;
BEGIN
  -- Basic validation
  IF p_question_text IS NULL OR length(trim(p_question_text)) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'question_too_short');
  END IF;
  IF p_question_text IS NULL OR length(p_question_text) > 200 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'question_too_long');
  END IF;
  IF p_unit_label IS NOT NULL AND length(p_unit_label) > 30 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unit_label_too_long');
  END IF;
  IF p_correct_answer IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_correct_answer');
  END IF;

  v_id := gen_random_uuid()::text;
  INSERT INTO "pb_v1_user_questions" (
    "id", "submittedByUserId", "familyId",
    "questionText", "correctAnswer", "unitLabel", "category", "funFactText",
    "minBound", "maxBound", "status", "createdAt"
  ) VALUES (
    v_id, p_user_id, p_family_id,
    p_question_text, p_correct_answer, p_unit_label, p_category, p_fun_fact_text,
    p_min_bound, p_max_bound, 'pending', now()
  );

  RETURN jsonb_build_object('ok', true, 'submission_id', v_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_submit_user_question(text, text, text, numeric, text, text, text, numeric, numeric) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- RPC: fn_pb_v1_get_my_submissions
-- Returns the user's submissions (paginated). Useful for a
-- "My submitted questions" screen so the user can track what they
-- submitted and the status of each.
-- ═════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_pb_v1_get_my_submissions(
  p_user_id text,
  p_limit integer DEFAULT 30,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'family_id', "familyId",
    'question_text', "questionText",
    'correct_answer', "correctAnswer",
    'unit_label', "unitLabel",
    'category', "category",
    'fun_fact_text', "funFactText",
    'status', status,
    'reviewer_user_id', "reviewerUserId",
    'reviewed_at', "reviewedAt",
    'approved_question_id', "approvedQuestionId",
    'rejection_reason', "rejectionReason",
    'created_at', "createdAt"
  ) ORDER BY "createdAt" DESC), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT * FROM "pb_v1_user_questions"
    WHERE "submittedByUserId" = p_user_id
    ORDER BY "createdAt" DESC
    LIMIT p_limit OFFSET p_offset
  ) sub;

  RETURN jsonb_build_object('ok', true, 'rows', v_rows);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_get_my_submissions(text, integer, integer) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- RPC: fn_pb_v1_admin_review_user_question
-- Admin-only. Approves or rejects a pending submission.
--   - On approve: inserts a new row into pb_v1_questions with the
--     submitted text/answer/etc., updates the submission's status
--     to 'approved' with the approved_question_id, and awards the
--     submitter 5 coins (idempotent via question_id).
--   - On reject: updates the submission's status to 'rejected'
--     with the rejection reason.
-- ═════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_pb_v1_admin_review_user_question(
  p_admin_user_id text,
  p_submission_id text,
  p_action text,                  -- 'approve' | 'reject'
  p_rejection_reason text DEFAULT NULL,
  -- Optional overrides for the approved question (admin can edit
  -- the question_text / correct_answer / etc. during approval):
  p_question_text_override text DEFAULT NULL,
  p_correct_answer_override numeric DEFAULT NULL,
  p_unit_label_override text DEFAULT NULL,
  p_fun_fact_text_override text DEFAULT NULL,
  p_category_override text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_submission record;
  v_question_id text;
  v_question_text text;
  v_correct_answer numeric;
  v_unit_label text;
  v_fun_fact text;
  v_category text;
BEGIN
  -- Admin check
  IF NOT EXISTS (SELECT 1 FROM "User" WHERE id = p_admin_user_id AND role = 'admin') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
  END IF;

  SELECT * INTO v_submission FROM "pb_v1_user_questions" WHERE id = p_submission_id;
  IF v_submission IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'submission_not_found');
  END IF;
  IF v_submission.status != 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_reviewed');
  END IF;

  IF p_action = 'approve' THEN
    -- Use overrides if provided, else fall back to the submission's
    -- original values. This lets the admin fix typos / adjust the
    -- correct_answer without losing the original submission.
    v_question_text := COALESCE(p_question_text_override, v_submission."questionText");
    v_correct_answer := COALESCE(p_correct_answer_override, v_submission."correctAnswer");
    v_unit_label := COALESCE(p_unit_label_override, v_submission."unitLabel");
    v_fun_fact := COALESCE(p_fun_fact_text_override, v_submission."funFactText");
    v_category := COALESCE(p_category_override, v_submission."category");

    -- Insert the approved question into pb_v1_questions. Use a
    -- 'uq-' prefix on the id so we can tell user-submitted questions
    -- apart from the seed 'pq-NNN' ones in the future.
    v_question_id := 'uq-' || v_submission.id;
    INSERT INTO "pb_v1_questions" (
      "id", "question_text", "correct_answer", "unit_label", "category",
      "fun_fact_text", "min_bound", "max_bound", "is_active", "created_at"
    ) VALUES (
      v_question_id, v_question_text, v_correct_answer, v_unit_label, v_category,
      v_fun_fact, v_submission."minBound", v_submission."maxBound", true, now()
    )
    ON CONFLICT ("id") DO NOTHING;

    -- Update the submission
    UPDATE "pb_v1_user_questions" SET
      "status" = 'approved',
      "reviewerUserId" = p_admin_user_id,
      "reviewedAt" = now(),
      "approvedQuestionId" = v_question_id
    WHERE id = p_submission_id;

    -- Award the submitter 5 coins. Idempotent via the question id.
    -- Only award if the submission was family-scoped (familyId is
    -- not null); global-pool submissions don't have a family to
    -- credit in.
    IF v_submission."familyId" IS NOT NULL THEN
      PERFORM public.fn_award_coins(
        v_submission."submittedByUserId",
        v_submission."familyId",
        5,
        'question_accepted',
        v_question_id,
        jsonb_build_object('question_id', v_question_id, 'submission_id', p_submission_id)
      );
    END IF;

    RETURN jsonb_build_object('ok', true, 'action', 'approved', 'question_id', v_question_id);
  ELSIF p_action = 'reject' THEN
    UPDATE "pb_v1_user_questions" SET
      "status" = 'rejected',
      "reviewerUserId" = p_admin_user_id,
      "reviewedAt" = now(),
      "rejectionReason" = p_rejection_reason
    WHERE id = p_submission_id;
    RETURN jsonb_build_object('ok', true, 'action', 'rejected');
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_action');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_admin_review_user_question(text, text, text, text, text, numeric, text, text, text) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- RPC: fn_pb_v1_admin_list_pending_questions
-- Admin-only. Returns the pending moderation queue (paginated).
-- ═════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_pb_v1_admin_list_pending_questions(
  p_admin_user_id text,
  p_limit integer DEFAULT 30,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "User" WHERE id = p_admin_user_id AND role = 'admin') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'submitted_by_user_id', "submittedByUserId",
    'family_id', "familyId",
    'question_text', "questionText",
    'correct_answer', "correctAnswer",
    'unit_label', "unitLabel",
    'category', "category",
    'fun_fact_text', "funFactText",
    'min_bound', "minBound",
    'max_bound', "maxBound",
    'created_at', "createdAt"
  ) ORDER BY "createdAt" ASC), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT * FROM "pb_v1_user_questions"
    WHERE status = 'pending'
    ORDER BY "createdAt" ASC
    LIMIT p_limit OFFSET p_offset
  ) sub;

  RETURN jsonb_build_object('ok', true, 'rows', v_rows);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_pb_v1_admin_list_pending_questions(text, integer, integer) TO authenticated;
