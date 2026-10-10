-- =============================================================================
-- Daxelo Kinrel — Tier 2 Feature 2.1: Voice & Video Calls — SCHEMA ONLY
-- =============================================================================
-- This migration adds the Call + CallParticipant tables so the schema is
-- ready for future LiveKit / mediasoup integration. No NestJS code yet —
-- implementing real-time WebRTC requires a signaling server (LiveKit or
-- mediasoup) which is a separate infrastructure piece + ~$30-80/mo hosting.
--
-- Schema:
--   • Call — id, type (audio|video), scope (dm|family), familyId?, startedBy,
--     startedAt, endedAt, status (active|ended|missed|cancelled|failed).
--   • CallParticipant — callId, userId, joinedAt, leftAt, deviceInfo.
--
-- The NestJS calls/ module + Flutter CallScreen + signaling gateway are
-- tracked as follow-up work in the WORKLOG.
-- =============================================================================

CREATE TABLE IF NOT EXISTS "Call" (
  "id"            text PRIMARY KEY,
  "type"          text NOT NULL,         -- audio | video
  "scope"         text NOT NULL,         -- dm | family
  "familyId"      text,                  -- null when scope=dm
  "startedBy"     text NOT NULL,
  "startedAt"     timestamptz NOT NULL DEFAULT now(),
  "endedAt"       timestamptz,
  "status"        text NOT NULL DEFAULT 'active',  -- active | ended | missed | cancelled | failed
  "failureReason" text,
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "Call_type_chk"    CHECK ("type" IN ('audio', 'video')),
  CONSTRAINT "Call_scope_chk"  CHECK ("scope" IN ('dm', 'family')),
  CONSTRAINT "Call_status_chk" CHECK ("status" IN ('active', 'ended', 'missed', 'cancelled', 'failed'))
);

CREATE INDEX IF NOT EXISTS "Call_family_idx"      ON "Call"("familyId", "startedAt" DESC) WHERE "familyId" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "Call_startedBy_idx"  ON "Call"("startedBy");
CREATE INDEX IF NOT EXISTS "Call_active_idx"     ON "Call"("startedAt" DESC) WHERE "status" = 'active';

CREATE TABLE IF NOT EXISTS "CallParticipant" (
  "id"          text PRIMARY KEY,
  "callId"      text NOT NULL REFERENCES "Call"(id) ON DELETE CASCADE,
  "userId"      text NOT NULL,
  "joinedAt"    timestamptz NOT NULL DEFAULT now(),
  "leftAt"      timestamptz,
  "deviceInfo"  jsonb NOT NULL DEFAULT '[]'::jsonb,
  UNIQUE("callId", "userId")
);

CREATE INDEX IF NOT EXISTS "CallParticipant_call_idx" ON "CallParticipant"("callId");
CREATE INDEX IF NOT EXISTS "CallParticipant_user_idx" ON "CallParticipant"("userId");

-- RLS — visibility matches the call scope (DM = only participants;
-- family = any family member can see call records).
ALTER TABLE "Call" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Call select" ON "Call";
CREATE POLICY "Call select" ON "Call"
  FOR SELECT TO authenticated USING (
    "startedBy" = auth.uid()::text
    OR ("scope" = 'dm' AND "id" IN (
      SELECT "callId" FROM "CallParticipant" WHERE "userId" = auth.uid()::text
    ))
    OR ("scope" = 'family' AND "familyId" IN (
      SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text
    ))
  );

DROP POLICY IF EXISTS "Call insert" ON "Call";
CREATE POLICY "Call insert" ON "Call"
  FOR INSERT TO authenticated WITH CHECK ("startedBy" = auth.uid()::text);

DROP POLICY IF EXISTS "Call update starter" ON "Call";
CREATE POLICY "Call update starter" ON "Call"
  FOR UPDATE TO authenticated USING ("startedBy" = auth.uid()::text);

ALTER TABLE "CallParticipant" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "CallParticipant select" ON "CallParticipant";
CREATE POLICY "CallParticipant select" ON "CallParticipant"
  FOR SELECT TO authenticated USING (
    "userId" = auth.uid()::text
    OR "callId" IN (SELECT id FROM "Call" WHERE "startedBy" = auth.uid()::text)
  );
DROP POLICY IF EXISTS "CallParticipant insert own" ON "CallParticipant";
CREATE POLICY "CallParticipant insert own" ON "CallParticipant"
  FOR INSERT TO authenticated WITH CHECK ("userId" = auth.uid()::text);
DROP POLICY IF EXISTS "CallParticipant update own" ON "CallParticipant";
CREATE POLICY "CallParticipant update own" ON "CallParticipant"
  FOR UPDATE TO authenticated USING ("userId" = auth.uid()::text);

-- Verification
SELECT 'Call' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'Call') AS exists;
SELECT 'CallParticipant' AS obj,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'CallParticipant') AS exists;
