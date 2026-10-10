-- =============================================================================
-- Daxelo Kinrel — Tier 5 Feature 5.4: Chat export (text + media)
-- =============================================================================
-- Lets a user request an export of a chat as plain text (emailed as .txt)
-- or full (zipped with media). The export runs as a background job — the
-- user is notified when it's ready.
--
-- Schema:
--   • ChatExportJob — id, requesterId, familyId, scope ('text'|'full'),
--     status ('pending'|'running'|'completed'|'failed'), resultUrl,
--     resultSizeBytes, failureReason, createdAt, completedAt.
--   • RLS: only the requester can SELECT their own jobs.
--
-- The actual export-building (SELECTing messages, formatting as text or
-- zipping media, uploading to storage) is a follow-up NestJS service
-- (ChatExportRunner). This migration just creates the job table + the
-- RPC to enqueue a job + a status endpoint.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "ChatExportJob" (
  "id"               text PRIMARY KEY,
  "requesterId"      text NOT NULL,
  "familyId"         text NOT NULL,
  "scope"            text NOT NULL,   -- 'text' | 'full'
  "status"           text NOT NULL DEFAULT 'pending',  -- pending | running | completed | failed
  "resultUrl"        text,            -- set when status=completed; signed storage URL
  "resultSizeBytes"  bigint,
  "resultFormat"     text,            -- 'txt' | 'zip'
  "messageCount"     integer,         -- populated when the job runs
  "failureReason"    text,
  "expiresAt"        timestamptz,     -- the result URL expires after 7 days
  "createdAt"        timestamptz NOT NULL DEFAULT now(),
  "completedAt"      timestamptz,
  "updatedAt"        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "ChatExportJob_scope_chk"  CHECK ("scope" IN ('text', 'full')),
  CONSTRAINT "ChatExportJob_status_chk" CHECK ("status" IN ('pending', 'running', 'completed', 'failed'))
);

CREATE INDEX IF NOT EXISTS "ChatExportJob_requester_idx" ON "ChatExportJob"("requesterId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ChatExportJob_pending_idx"   ON "ChatExportJob"("createdAt") WHERE "status" IN ('pending', 'running');

ALTER TABLE "ChatExportJob" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ChatExportJob select own" ON "ChatExportJob";
CREATE POLICY "ChatExportJob select own" ON "ChatExportJob"
  FOR SELECT TO authenticated USING ("requesterId" = auth.uid()::text);
-- INSERT/UPDATE/DELETE only via SECURITY DEFINER RPC.

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_create_chat_export_job — validates membership + inserts a pending job.
-- Returns the job ID so the client can poll fn_get_chat_export_job status.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_create_chat_export_job(
  p_family_id text,
  p_scope text DEFAULT 'text'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
  v_existing text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_scope NOT IN ('text', 'full') THEN
    RETURN json_build_object('success', false, 'error', 'invalid_scope');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM "FamilyMember"
    WHERE "familyId" = p_family_id AND "userId" = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'not_in_family');
  END IF;

  -- Idempotent: if there's already a pending or running job for this
  -- (requester, family, scope) tuple, return it.
  SELECT id INTO v_existing FROM "ChatExportJob"
    WHERE "requesterId" = v_user_id
      AND "familyId" = p_family_id
      AND "scope" = p_scope
      AND "status" IN ('pending', 'running')
    LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', true, 'action', 'already_pending',
      'jobId', v_existing);
  END IF;

  v_id := 'cej_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6);
  INSERT INTO "ChatExportJob" (
    "id", "requesterId", "familyId", "scope",
    "status", "createdAt", "updatedAt"
  ) VALUES (
    v_id, v_user_id, p_family_id, p_scope,
    'pending', now(), now()
  );

  RETURN json_build_object(
    'success', true,
    'action', 'created',
    'jobId', v_id,
    'scope', p_scope,
    'status', 'pending'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_create_chat_export_job(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_get_chat_export_job — status poll for a single job (must be owned by caller).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_get_chat_export_job(p_job_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_row record;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_row FROM "ChatExportJob" WHERE "id" = p_job_id;
  IF v_row IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_row."requesterId" <> v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'not_owner');
  END IF;

  RETURN json_build_object(
    'success', true,
    'jobId', v_row."id",
    'familyId', v_row."familyId",
    'scope', v_row."scope",
    'status', v_row."status",
    'resultUrl', v_row."resultUrl",
    'resultSizeBytes', v_row."resultSizeBytes",
    'resultFormat', v_row."resultFormat",
    'messageCount', v_row."messageCount",
    'failureReason', v_row."failureReason",
    'expiresAt', CASE WHEN v_row."expiresAt" IS NULL THEN NULL
                      ELSE to_char(v_row."expiresAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') END,
    'createdAt', to_char(v_row."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'completedAt', CASE WHEN v_row."completedAt" IS NULL THEN NULL
                        ELSE to_char(v_row."completedAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_get_chat_export_job(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_list_my_chat_exports — list the caller's recent export jobs.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_list_my_chat_exports(p_limit int DEFAULT 20)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'jobId', j."id",
      'familyId', j."familyId",
      'scope', j."scope",
      'status', j."status",
      'resultUrl', j."resultUrl",
      'resultSizeBytes', j."resultSizeBytes",
      'resultFormat', j."resultFormat",
      'messageCount', j."messageCount",
      'failureReason', j."failureReason",
      'expiresAt', CASE WHEN j."expiresAt" IS NULL THEN NULL
                        ELSE to_char(j."expiresAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') END,
      'createdAt', to_char(j."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'completedAt', CASE WHEN j."completedAt" IS NULL THEN NULL
                          ELSE to_char(j."completedAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') END
    ) ORDER BY j."createdAt" DESC)
    FROM "ChatExportJob" j
    WHERE j."requesterId" = v_user_id
    LIMIT GREATEST(LEAST(p_limit, 100), 1)
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_list_my_chat_exports(int) TO authenticated;

-- Verification
SELECT 'ChatExportJob' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'ChatExportJob') AS exists;
SELECT 'fn_create_chat_export_job' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_create_chat_export_job') AS exists;
SELECT 'fn_get_chat_export_job' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_get_chat_export_job') AS exists;
SELECT 'fn_list_my_chat_exports' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_list_my_chat_exports') AS exists;
