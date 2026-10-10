-- =============================================================================
-- Daxelo Kinrel — Tier 5 Feature 5.5: Cloud backup (Google Drive / iCloud)
-- =============================================================================
-- Tracks the user's cloud backup metadata so they can restore on a new
-- device. The actual upload happens Flutter-side (using googleapis /
-- sign_in_with_google for Drive + a native plugin for iCloud). The
-- server just records the metadata so the user can see "last backup"
-- timestamp + restore from a previous backup.
--
-- Schema:
--   • CloudBackupRecord — id, userId, provider ('google_drive' | 'icloud'),
--     backupKey (the user-side encrypted blob's key identifier — the
--     server never sees the plaintext backup), sizeBytes, messageCount,
--     mediaCount, deviceLabel, createdAt.
--   • RLS: only the owner can SELECT/INSERT.
--   • User.lastCloudBackupAt timestamptz — denormalized cache for the
--     settings screen "Last backup: 2 hours ago" label.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "CloudBackupRecord" (
  "id"           text PRIMARY KEY,
  "userId"       text NOT NULL,
  "provider"     text NOT NULL,                  -- 'google_drive' | 'icloud'
  "backupKey"    text NOT NULL,                  -- identifier for the encrypted blob (the server doesn't decrypt)
  "sizeBytes"    bigint NOT NULL,
  "messageCount" integer NOT NULL DEFAULT 0,
  "mediaCount"   integer NOT NULL DEFAULT 0,
  "deviceLabel"  text,                           -- e.g. "Manish's iPhone 15"
  "fileId"       text,                            -- the provider-side file ID (Drive fileId / iCloud record name)
  "createdAt"    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "CloudBackupRecord_provider_chk" CHECK ("provider" IN ('google_drive', 'icloud'))
);

CREATE INDEX IF NOT EXISTS "CloudBackupRecord_user_idx" ON "CloudBackupRecord"("userId", "createdAt" DESC);

ALTER TABLE "CloudBackupRecord" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "CloudBackupRecord select own" ON "CloudBackupRecord";
CREATE POLICY "CloudBackupRecord select own" ON "CloudBackupRecord"
  FOR SELECT TO authenticated USING ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "CloudBackupRecord insert own" ON "CloudBackupRecord";
CREATE POLICY "CloudBackupRecord insert own" ON "CloudBackupRecord"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "CloudBackupRecord delete own" ON "CloudBackupRecord";
CREATE POLICY "CloudBackupRecord delete own" ON "CloudBackupRecord"
  FOR DELETE TO authenticated USING ("userId" = auth.uid()::text);

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "lastCloudBackupAt" timestamptz;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_record_cloud_backup — caller records a backup just-completed by the
-- Flutter client. Updates the denormalized lastCloudBackupAt cache on User.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_record_cloud_backup(
  p_provider text,
  p_backup_key text,
  p_size_bytes bigint,
  p_message_count integer DEFAULT 0,
  p_media_count integer DEFAULT 0,
  p_device_label text DEFAULT NULL,
  p_file_id text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id text := auth.uid()::text;
  v_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_provider NOT IN ('google_drive', 'icloud') THEN
    RETURN json_build_object('success', false, 'error', 'invalid_provider');
  END IF;
  IF p_backup_key IS NULL OR btrim(p_backup_key) = '' THEN
    RETURN json_build_object('success', false, 'error', 'invalid_backup_key');
  END IF;
  IF p_size_bytes IS NULL OR p_size_bytes < 0 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_size');
  END IF;

  v_id := 'cbr_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6);
  INSERT INTO "CloudBackupRecord" (
    "id", "userId", "provider", "backupKey",
    "sizeBytes", "messageCount", "mediaCount",
    "deviceLabel", "fileId", "createdAt"
  ) VALUES (
    v_id, v_user_id, p_provider, p_backup_key,
    p_size_bytes, p_message_count, p_media_count,
    p_device_label, p_file_id, now()
  );

  -- Update the denormalized cache.
  UPDATE "User" SET "lastCloudBackupAt" = now(), "updatedAt" = now()
    WHERE id = v_user_id;

  RETURN json_build_object(
    'success', true,
    'backupId', v_id,
    'userId', v_user_id,
    'provider', p_provider,
    'createdAt', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_record_cloud_backup(
  text, text, bigint, integer, integer, text, text
) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_list_my_cloud_backups — list the caller's recent backups (for the
-- restore picker on a new device).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_list_my_cloud_backups(p_limit int DEFAULT 20)
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
      'backupId', b."id",
      'provider', b."provider",
      'backupKey', b."backupKey",
      'sizeBytes', b."sizeBytes",
      'messageCount', b."messageCount",
      'mediaCount', b."mediaCount",
      'deviceLabel', b."deviceLabel",
      'fileId', b."fileId",
      'createdAt', to_char(b."createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    ) ORDER BY b."createdAt" DESC)
    FROM "CloudBackupRecord" b
    WHERE b."userId" = v_user_id
    LIMIT GREATEST(LEAST(p_limit, 50), 1)
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_list_my_cloud_backups(int) TO authenticated;

-- Verification
SELECT 'CloudBackupRecord' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'CloudBackupRecord') AS exists;
SELECT 'User.lastCloudBackupAt' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'User' AND column_name = 'lastCloudBackupAt'
       ) AS exists;
SELECT 'fn_record_cloud_backup' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_record_cloud_backup') AS exists;
SELECT 'fn_list_my_cloud_backups' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_list_my_cloud_backups') AS exists;
