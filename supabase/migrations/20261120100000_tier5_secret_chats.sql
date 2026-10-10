-- =============================================================================
-- Daxelo Kinrel — Tier 5 Feature 5.1: Secret Chats (end-to-end encrypted, self-destruct)
-- =============================================================================
-- Schema for E2E-encrypted 1:1 chats. The server stores ONLY ciphertext —
-- the key exchange happens client-side via X25519 (each user posts a public
-- key; the peer computes the shared secret locally; the secret never
-- leaves the device).
--
-- Schema:
--   • SecretChat — id, userA, userB, keyFingerprint (SHA-256 of the shared
--     secret, used by the client to verify the key exchange matched), status
--     (pending | active | rejected | closed), initiatorUserId, createdAt.
--   • SecretMessage — id, secretChatId, senderId, ciphertext (text —
--     base64 of AES-GCM ciphertext), iv (text — base64 nonce), messageType,
--     expiresAt (null = no self-destruct), createdAt.
--   • UserPublicKey — userId, keyType (e.g. 'x25519' | 'ed25519'),
--     publicKeyB64, createdAt. The Flutter client fetches the peer's
--     public key from here, computes the shared secret, and uses it to
--     AES-GCM encrypt messages.
--
-- RLS: SecretChat visible only to userA + userB. SecretMessage visible
-- only to the two participants. UserPublicKey is publicly readable (so
-- anyone can start a secret chat with anyone) but writable only by the
-- owner.
--
-- NOTE: This migration adds the SCHEMA only. The Flutter crypto layer
-- (X25519 key exchange + AES-GCM encryption + the SecretChatScreen UI)
-- is follow-up work. The server is a thin ciphertext-only passthrough.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "SecretChat" (
  "id"              text PRIMARY KEY,
  "userA"           text NOT NULL,                  -- the initiator
  "userB"           text NOT NULL,                  -- the invitee
  "initiatorUserId" text NOT NULL,                  -- equals userA or userB
  "keyFingerprint"  text NOT NULL,                  -- SHA-256 of the shared secret (hex)
  "status"          text NOT NULL DEFAULT 'pending', -- pending | active | rejected | closed
  "createdAt"       timestamptz NOT NULL DEFAULT now(),
  "acceptedAt"      timestamptz,
  "closedAt"        timestamptz,
  "updatedAt"       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "SecretChat_status_chk" CHECK (
    "status" IN ('pending', 'active', 'rejected', 'closed')
  ),
  -- userA and userB must be different users.
  CONSTRAINT "SecretChat_distinct_users_chk" CHECK ("userA" <> "userB")
);

CREATE UNIQUE INDEX IF NOT EXISTS "SecretChat_pair_uniq"
  ON "SecretChat" (LEAST("userA", "userB"), GREATEST("userA", "userB"))
  WHERE "status" IN ('pending', 'active');
CREATE INDEX IF NOT EXISTS "SecretChat_userA_idx" ON "SecretChat"("userA", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "SecretChat_userB_idx" ON "SecretChat"("userB", "createdAt" DESC);

ALTER TABLE "SecretChat" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "SecretChat select participant" ON "SecretChat";
CREATE POLICY "SecretChat select participant" ON "SecretChat"
  FOR SELECT TO authenticated USING (
    "userA" = auth.uid()::text OR "userB" = auth.uid()::text
  );
DROP POLICY IF EXISTS "SecretChat insert initiator" ON "SecretChat";
CREATE POLICY "SecretChat insert initiator" ON "SecretChat"
  FOR INSERT TO authenticated WITH CHECK (
    "initiatorUserId" = auth.uid()::text
    AND ("userA" = auth.uid()::text OR "userB" = auth.uid()::text)
  );
DROP POLICY IF EXISTS "SecretChat update participant" ON "SecretChat";
CREATE POLICY "SecretChat update participant" ON "SecretChat"
  FOR UPDATE TO authenticated USING (
    "userA" = auth.uid()::text OR "userB" = auth.uid()::text
  );

CREATE TABLE IF NOT EXISTS "SecretMessage" (
  "id"           text PRIMARY KEY,
  "secretChatId" text NOT NULL REFERENCES "SecretChat"(id) ON DELETE CASCADE,
  "senderId"     text NOT NULL,
  "ciphertext"   text NOT NULL,                -- base64 AES-GCM ciphertext
  "iv"           text NOT NULL,                -- base64 nonce
  "messageType"  text NOT NULL DEFAULT 'text', -- text | photo | voiceNote | ...
  "expiresAt"    timestamptz,                  -- null = no self-destruct
  "isRead"       boolean NOT NULL DEFAULT false,
  "createdAt"    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "SecretMessage_chat_idx"     ON "SecretMessage"("secretChatId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "SecretMessage_expires_idx" ON "SecretMessage"("expiresAt") WHERE "expiresAt" IS NOT NULL;

ALTER TABLE "SecretMessage" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "SecretMessage select participant" ON "SecretMessage";
CREATE POLICY "SecretMessage select participant" ON "SecretMessage"
  FOR SELECT TO authenticated USING (
    "secretChatId" IN (
      SELECT id FROM "SecretChat"
      WHERE "userA" = auth.uid()::text OR "userB" = auth.uid()::text
    )
  );
DROP POLICY IF EXISTS "SecretMessage insert participant" ON "SecretMessage";
CREATE POLICY "SecretMessage insert participant" ON "SecretMessage"
  FOR INSERT TO authenticated WITH CHECK (
    "senderId" = auth.uid()::text
    AND "secretChatId" IN (
      SELECT id FROM "SecretChat"
      WHERE ("userA" = auth.uid()::text OR "userB" = auth.uid()::text)
        AND "status" = 'active'
    )
  );
DROP POLICY IF EXISTS "SecretMessage update participant" ON "SecretMessage";
CREATE POLICY "SecretMessage update participant" ON "SecretMessage"
  FOR UPDATE TO authenticated USING (
    "secretChatId" IN (
      SELECT id FROM "SecretChat"
      WHERE "userA" = auth.uid()::text OR "userB" = auth.uid()::text
    )
  );

CREATE TABLE IF NOT EXISTS "UserPublicKey" (
  "userId"       text NOT NULL,
  "keyType"      text NOT NULL,                -- 'x25519' | 'ed25519'
  "publicKeyB64" text NOT NULL,
  "createdAt"    timestamptz NOT NULL DEFAULT now(),
  "updatedAt"    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("userId", "keyType")
);

CREATE INDEX IF NOT EXISTS "UserPublicKey_key_idx" ON "UserPublicKey"("keyType");

ALTER TABLE "UserPublicKey" ENABLE ROW LEVEL SECURITY;
-- Publicly readable (anyone can fetch a peer's public key to start a
-- secret chat). Only the owner can write their own key.
DROP POLICY IF EXISTS "UserPublicKey select" ON "UserPublicKey";
CREATE POLICY "UserPublicKey select" ON "UserPublicKey"
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "UserPublicKey upsert own" ON "UserPublicKey";
CREATE POLICY "UserPublicKey upsert own" ON "UserPublicKey"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "UserPublicKey update own" ON "UserPublicKey";
CREATE POLICY "UserPublicKey update own" ON "UserPublicKey"
  FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);

-- Realtime on SecretMessage so the recipient sees new ciphertext in real-time
-- (the decryption happens client-side after the realtime payload arrives).
ALTER TABLE "SecretMessage" REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'SecretMessage'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE "SecretMessage";
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime setup: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_upsert_public_key — owner posts/refreshes their public key
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_upsert_public_key(
  p_key_type text,
  p_public_key_b64 text
)
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
  IF p_key_type NOT IN ('x25519', 'ed25519') THEN
    RETURN json_build_object('success', false, 'error', 'invalid_key_type');
  END IF;
  IF p_public_key_b64 IS NULL OR btrim(p_public_key_b64) = '' THEN
    RETURN json_build_object('success', false, 'error', 'invalid_public_key');
  END IF;

  INSERT INTO "UserPublicKey" ("userId", "keyType", "publicKeyB64", "createdAt", "updatedAt")
  VALUES (v_user_id, p_key_type, p_public_key_b64, now(), now())
  ON CONFLICT ("userId", "keyType")
  DO UPDATE SET
    "publicKeyB64" = p_public_key_b64,
    "updatedAt" = now();

  RETURN json_build_object('success', true, 'userId', v_user_id, 'keyType', p_key_type);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_upsert_public_key(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_initiate_secret_chat — caller creates a pending SecretChat with the
-- peer. The peer accepts/rejects via fn_respond_secret_chat. The caller
-- computes the keyFingerprint (SHA-256 of the shared secret) + sends it;
-- the peer re-derives + compares on accept (mismatch = reject).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_initiate_secret_chat(
  p_peer_user_id text,
  p_key_fingerprint text
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
  IF p_peer_user_id IS NULL OR p_peer_user_id = v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'invalid_peer');
  END IF;
  IF p_key_fingerprint IS NULL OR char_length(p_key_fingerprint) < 16 THEN
    RETURN json_build_object('success', false, 'error', 'invalid_fingerprint');
  END IF;

  -- Idempotent: if there's already an active or pending chat with this
  -- peer pair, return the existing one.
  SELECT id INTO v_existing FROM "SecretChat"
    WHERE ("userA" = v_user_id AND "userB" = p_peer_user_id
        OR "userA" = p_peer_user_id AND "userB" = v_user_id)
      AND "status" IN ('pending', 'active')
    LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN json_build_object('success', true, 'action', 'already_exists',
      'secretChatId', v_existing);
  END IF;

  v_id := 'sc_' || extract(epoch from now())::bigint::text || '_' || substring(v_user_id from 1 for 6) || '_' || substring(p_peer_user_id from 1 for 6);
  INSERT INTO "SecretChat" (
    "id", "userA", "userB", "initiatorUserId",
    "keyFingerprint", "status", "createdAt", "updatedAt"
  ) VALUES (
    v_id, v_user_id, p_peer_user_id, v_user_id,
    p_key_fingerprint, 'pending', now(), now()
  );

  RETURN json_build_object(
    'success', true,
    'action', 'created',
    'secretChatId', v_id,
    'status', 'pending'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_initiate_secret_chat(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_respond_secret_chat — peer accepts or rejects a pending chat
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_respond_secret_chat(
  p_secret_chat_id text,
  p_accept boolean,
  p_key_fingerprint text DEFAULT NULL  -- the peer's recomputed fingerprint (must match the caller's)
)
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

  SELECT * INTO v_row FROM "SecretChat" WHERE "id" = p_secret_chat_id;
  IF v_row IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_found');
  END IF;
  -- Only the non-initiator peer can respond.
  IF v_user_id = v_row."initiatorUserId" THEN
    RETURN json_build_object('success', false, 'error', 'initiator_cannot_respond');
  END IF;
  IF v_user_id <> v_row."userA" AND v_user_id <> v_row."userB" THEN
    RETURN json_build_object('success', false, 'error', 'not_participant');
  END IF;
  IF v_row."status" <> 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'not_pending',
      'currentStatus', v_row."status");
  END IF;

  IF NOT p_accept THEN
    UPDATE "SecretChat"
      SET "status" = 'rejected', "closedAt" = now(), "updatedAt" = now()
      WHERE "id" = p_secret_chat_id;
    RETURN json_build_object('success', true, 'action', 'rejected',
      'secretChatId', p_secret_chat_id);
  END IF;

  -- Accept: validate the key fingerprint matches (the peer recomputed
  -- the shared secret locally + sends the fingerprint; if it doesn't
  -- match the initiator's, the key exchange failed).
  IF p_key_fingerprint IS NOT NULL AND p_key_fingerprint <> v_row."keyFingerprint" THEN
    RETURN json_build_object('success', false, 'error', 'fingerprint_mismatch',
      'message', 'Key fingerprints do not match. The shared secret differs.');
  END IF;

  UPDATE "SecretChat"
    SET "status" = 'active', "acceptedAt" = now(), "updatedAt" = now()
    WHERE "id" = p_secret_chat_id;

  RETURN json_build_object('success', true, 'action', 'accepted',
    'secretChatId', p_secret_chat_id);
END;
$$;

GRANT EXECUTE ON FUNCTION fn_respond_secret_chat(text, boolean, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- fn_cleanup_expired_secret_messages — nightly cron to delete expired
-- ciphertext rows. The cron schedule is set up below.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_cleanup_expired_secret_messages()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  DELETE FROM "SecretMessage"
    WHERE "expiresAt" IS NOT NULL AND "expiresAt" < now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Secret message cleanup: deleted % expired rows', v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_cleanup_expired_secret_messages() TO authenticated;

DO $$
DECLARE
  v_job_name text := 'cleanup-expired-secret-messages';
  v_existing bigint;
BEGIN
  SELECT jobid INTO v_existing FROM cron.job WHERE jobname = v_job_name;
  IF v_existing IS NULL THEN
    PERFORM cron.schedule(
      v_job_name,
      '*/15 * * * *',  -- every 15 minutes — secret messages self-destruct quickly
      'SELECT fn_cleanup_expired_secret_messages();'
    );
    RAISE NOTICE 'Scheduled cron job %', v_job_name;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Cron schedule skipped: %', SQLERRM;
END $$;

-- Verification
SELECT 'SecretChat' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'SecretChat') AS exists;
SELECT 'SecretMessage' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'SecretMessage') AS exists;
SELECT 'UserPublicKey' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'UserPublicKey') AS exists;
SELECT 'fn_upsert_public_key' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_upsert_public_key') AS exists;
SELECT 'fn_initiate_secret_chat' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_initiate_secret_chat') AS exists;
SELECT 'fn_respond_secret_chat' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_respond_secret_chat') AS exists;
SELECT 'fn_cleanup_expired_secret_messages' AS fn,
       EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'fn_cleanup_expired_secret_messages') AS exists;
SELECT 'cron job' AS obj,
       EXISTS(SELECT 1 FROM cron.job WHERE jobname = 'cleanup-expired-secret-messages') AS exists;
