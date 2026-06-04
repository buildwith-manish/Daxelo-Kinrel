-- ══════════════════════════════════════════════════════════════════════════
-- KINREL: Full Production Schema Sync (Idempotent)
-- Generated: 2025-03-04
-- Purpose: Sync Prisma schema to production Supabase database
-- Safety: 100% additive — no DROPs, only CREATE/ADD IF NOT EXISTS
-- Run: Paste into Supabase SQL Editor and click Run
-- ══════════════════════════════════════════════════════════════════════════

-- ── STEP 1: "User" table — add missing columns ───────────────────────
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "username" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "passwordHash" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "avatarUrl" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "photoThumb" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "photoCard" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "photoFull" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "bio" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "dateOfBirth" TIMESTAMPTZ;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "gender" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "profileVisibility" TEXT NOT NULL DEFAULT 'public';
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "invitePermission" TEXT NOT NULL DEFAULT 'anyone';
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "authProvider" TEXT NOT NULL DEFAULT 'email';
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "blockedUserIds" TEXT NOT NULL DEFAULT '[]';
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoFactorEnabled" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "twoFactorSecret" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "preferredLanguage" TEXT NOT NULL DEFAULT 'en';
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "role" TEXT NOT NULL DEFAULT 'user';
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "phone" TEXT;

-- Add unique constraint on username (safe if already exists)
DO $$ BEGIN
  ALTER TABLE "User" ADD CONSTRAINT "User_username_key" UNIQUE ("username");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

-- ── STEP 2: "Subscription" table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS "Subscription" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "plan" TEXT NOT NULL DEFAULT 'free',
  "status" TEXT NOT NULL DEFAULT 'active',
  "supportTier" TEXT NOT NULL DEFAULT 'basic',
  "startDate" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "endDate" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "Subscription" ADD CONSTRAINT "Subscription_userId_key" UNIQUE ("userId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Subscription" ADD CONSTRAINT "Subscription_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Subscription_userId_status_idx" ON "Subscription" ("userId", "status");
CREATE INDEX IF NOT EXISTS "Subscription_supportTier_idx" ON "Subscription" ("supportTier");

-- ── STEP 3: "SupportAgent" table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS "SupportAgent" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "phone" TEXT,
  "status" TEXT NOT NULL DEFAULT 'offline',
  "queues" TEXT NOT NULL DEFAULT '[]',
  "minTier" INTEGER NOT NULL DEFAULT 1,
  "languages" TEXT NOT NULL DEFAULT '[]',
  "currentLoad" INTEGER NOT NULL DEFAULT 0,
  "maxLoad" INTEGER NOT NULL DEFAULT 10,
  "onCallUntil" TIMESTAMPTZ,
  "nextShift" TIMESTAMPTZ,
  "avgResponseTime" INTEGER NOT NULL DEFAULT 0,
  "avgResolutionTime" INTEGER NOT NULL DEFAULT 0,
  "satisfactionScore" DOUBLE PRECISION NOT NULL DEFAULT 0,
  "ticketsResolved" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "SupportAgent" ADD CONSTRAINT "SupportAgent_userId_key" UNIQUE ("userId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SupportAgent" ADD CONSTRAINT "SupportAgent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "SupportAgent_status_currentLoad_idx" ON "SupportAgent" ("status", "currentLoad");

-- ── STEP 4: "SupportTicket" table ───────────────────────────────────
CREATE TABLE IF NOT EXISTS "SupportTicket" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "ticketNumber" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "category" TEXT NOT NULL DEFAULT 'general',
  "subcategory" TEXT,
  "severity" TEXT NOT NULL DEFAULT 'medium',
  "priority" INTEGER NOT NULL DEFAULT 1,
  "subject" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "attachments" TEXT NOT NULL DEFAULT '[]',
  "appVersion" TEXT,
  "platform" TEXT,
  "deviceInfo" TEXT,
  "status" TEXT NOT NULL DEFAULT 'open',
  "resolution" TEXT,
  "resolutionType" TEXT,
  "assignedAgentId" TEXT,
  "queue" TEXT NOT NULL DEFAULT 'general',
  "slaTier" TEXT NOT NULL DEFAULT 'basic',
  "firstResponseAt" TIMESTAMPTZ,
  "firstResponseDeadline" TIMESTAMPTZ,
  "resolutionDeadline" TIMESTAMPTZ,
  "slaBreached" BOOLEAN NOT NULL DEFAULT false,
  "language" TEXT NOT NULL DEFAULT 'en',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "resolvedAt" TIMESTAMPTZ,
  "closedAt" TIMESTAMPTZ
);

DO $$ BEGIN
  ALTER TABLE "SupportTicket" ADD CONSTRAINT "SupportTicket_ticketNumber_key" UNIQUE ("ticketNumber");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SupportTicket" ADD CONSTRAINT "SupportTicket_user_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SupportTicket" ADD CONSTRAINT "SupportTicket_assignedAgent_fkey" FOREIGN KEY ("assignedAgentId") REFERENCES "SupportAgent"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SupportTicket" ADD CONSTRAINT "SupportTicket_subscription_fkey" FOREIGN KEY ("userId") REFERENCES "Subscription"("userId") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "SupportTicket_userId_status_idx" ON "SupportTicket" ("userId", "status");
CREATE INDEX IF NOT EXISTS "SupportTicket_assignedAgentId_status_idx" ON "SupportTicket" ("assignedAgentId", "status");
CREATE INDEX IF NOT EXISTS "SupportTicket_status_priority_idx" ON "SupportTicket" ("status", "priority");
CREATE INDEX IF NOT EXISTS "SupportTicket_category_status_idx" ON "SupportTicket" ("category", "status");
CREATE INDEX IF NOT EXISTS "SupportTicket_slaBreached_idx" ON "SupportTicket" ("slaBreached");
CREATE INDEX IF NOT EXISTS "SupportTicket_createdAt_idx" ON "SupportTicket" ("createdAt");

-- ── STEP 5: "SupportMessage" table ──────────────────────────────────
CREATE TABLE IF NOT EXISTS "SupportMessage" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "ticketId" TEXT NOT NULL,
  "senderType" TEXT NOT NULL DEFAULT 'user',
  "senderId" TEXT,
  "senderName" TEXT NOT NULL,
  "content" TEXT NOT NULL,
  "attachments" TEXT NOT NULL DEFAULT '[]',
  "isInternal" BOOLEAN NOT NULL DEFAULT false,
  "channel" TEXT NOT NULL DEFAULT 'in_app',
  "language" TEXT NOT NULL DEFAULT 'en',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "SupportMessage" ADD CONSTRAINT "SupportMessage_ticketId_fkey" FOREIGN KEY ("ticketId") REFERENCES "SupportTicket"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "SupportMessage_ticketId_createdAt_idx" ON "SupportMessage" ("ticketId", "createdAt");

-- ── STEP 6: "SupportEscalation" table ───────────────────────────────
CREATE TABLE IF NOT EXISTS "SupportEscalation" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "ticketId" TEXT NOT NULL,
  "fromAgentId" TEXT,
  "toAgentId" TEXT,
  "reason" TEXT NOT NULL,
  "notes" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "SupportEscalation" ADD CONSTRAINT "SupportEscalation_ticketId_fkey" FOREIGN KEY ("ticketId") REFERENCES "SupportTicket"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "SupportEscalation_ticketId_idx" ON "SupportEscalation" ("ticketId");

-- ── STEP 7: "SupportCSAT" table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS "SupportCSAT" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "ticketId" TEXT NOT NULL,
  "rating" INTEGER NOT NULL,
  "comment" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "SupportCSAT" ADD CONSTRAINT "SupportCSAT_ticketId_key" UNIQUE ("ticketId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SupportCSAT" ADD CONSTRAINT "SupportCSAT_ticketId_fkey" FOREIGN KEY ("ticketId") REFERENCES "SupportTicket"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── STEP 8: "SLATracking" table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS "SLATracking" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "ticketId" TEXT,
  "type" TEXT NOT NULL,
  "tier" TEXT NOT NULL,
  "deadline" TIMESTAMPTZ NOT NULL,
  "metAt" TIMESTAMPTZ,
  "breached" BOOLEAN NOT NULL DEFAULT false,
  "breachDuration" INTEGER,
  "downtimeStart" TIMESTAMPTZ,
  "downtimeEnd" TIMESTAMPTZ,
  "downtimeMinutes" INTEGER,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "SLATracking" ADD CONSTRAINT "SLATracking_ticketId_fkey" FOREIGN KEY ("ticketId") REFERENCES "SupportTicket"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "SLATracking_type_tier_breached_idx" ON "SLATracking" ("type", "tier", "breached");
CREATE INDEX IF NOT EXISTS "SLATracking_deadline_idx" ON "SLATracking" ("deadline");

-- ── STEP 9: "OnCallSchedule" table ─────────────────────────────────
CREATE TABLE IF NOT EXISTS "OnCallSchedule" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "role" TEXT NOT NULL,
  "weekStart" TIMESTAMPTZ NOT NULL,
  "weekEnd" TIMESTAMPTZ NOT NULL,
  "incidentsHandled" INTEGER NOT NULL DEFAULT 0,
  "avgAckTime" INTEGER NOT NULL DEFAULT 0,
  "avgResolveTime" INTEGER NOT NULL DEFAULT 0,
  "compensationPaid" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "OnCallSchedule" ADD CONSTRAINT "OnCallSchedule_userId_weekStart_role_key" UNIQUE ("userId", "weekStart", "role");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "OnCallSchedule" ADD CONSTRAINT "OnCallSchedule_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "OnCallSchedule_weekStart_role_idx" ON "OnCallSchedule" ("weekStart", "role");

-- ── STEP 10: "Incident" table ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS "Incident" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "incidentNumber" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'investigating',
  "severity" TEXT NOT NULL,
  "affectedComponents" TEXT NOT NULL DEFAULT '[]',
  "startedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "identifiedAt" TIMESTAMPTZ,
  "monitoringAt" TIMESTAMPTZ,
  "resolvedAt" TIMESTAMPTZ,
  "initialNotificationSent" BOOLEAN NOT NULL DEFAULT false,
  "resolutionNotificationSent" BOOLEAN NOT NULL DEFAULT false,
  "authorId" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "Incident" ADD CONSTRAINT "Incident_incidentNumber_key" UNIQUE ("incidentNumber");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Incident" ADD CONSTRAINT "Incident_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Incident_status_startedAt_idx" ON "Incident" ("status", "startedAt");
CREATE INDEX IF NOT EXISTS "Incident_severity_status_idx" ON "Incident" ("severity", "status");

-- ── STEP 11: "IncidentUpdate" table ────────────────────────────────
CREATE TABLE IF NOT EXISTS "IncidentUpdate" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "incidentId" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "message" TEXT NOT NULL,
  "authorId" TEXT NOT NULL,
  "authorName" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "IncidentUpdate" ADD CONSTRAINT "IncidentUpdate_incidentId_fkey" FOREIGN KEY ("incidentId") REFERENCES "Incident"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "IncidentUpdate_incidentId_createdAt_idx" ON "IncidentUpdate" ("incidentId", "createdAt");

-- ── STEP 12: "PostMortem" table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS "PostMortem" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "incidentId" TEXT NOT NULL,
  "summary" TEXT NOT NULL,
  "timeline" TEXT NOT NULL,
  "rootCause" TEXT NOT NULL,
  "impact" TEXT NOT NULL,
  "whatWentWell" TEXT NOT NULL,
  "whatWentWrong" TEXT NOT NULL,
  "actionItems" TEXT NOT NULL DEFAULT '[]',
  "authorId" TEXT NOT NULL,
  "completedAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "PostMortem" ADD CONSTRAINT "PostMortem_incidentId_key" UNIQUE ("incidentId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "PostMortem" ADD CONSTRAINT "PostMortem_incidentId_fkey" FOREIGN KEY ("incidentId") REFERENCES "Incident"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "PostMortem_completedAt_idx" ON "PostMortem" ("completedAt");

-- ── STEP 13: "IncidentSubscriber" table ────────────────────────────
CREATE TABLE IF NOT EXISTS "IncidentSubscriber" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "email" TEXT,
  "phone" TEXT,
  "userId" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "IncidentSubscriber_email_idx" ON "IncidentSubscriber" ("email");
CREATE INDEX IF NOT EXISTS "IncidentSubscriber_phone_idx" ON "IncidentSubscriber" ("phone");

-- ── STEP 14: "KBArticle" table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS "KBArticle" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "slug" TEXT NOT NULL,
  "category" TEXT NOT NULL DEFAULT 'general',
  "subcategory" TEXT,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "title" TEXT NOT NULL DEFAULT '{}',
  "content" TEXT NOT NULL DEFAULT '{}',
  "excerpt" TEXT NOT NULL DEFAULT '{}',
  "tags" TEXT NOT NULL DEFAULT '[]',
  "relatedArticleIds" TEXT NOT NULL DEFAULT '[]',
  "status" TEXT NOT NULL DEFAULT 'draft',
  "featured" BOOLEAN NOT NULL DEFAULT false,
  "views" INTEGER NOT NULL DEFAULT 0,
  "helpfulYes" INTEGER NOT NULL DEFAULT 0,
  "helpfulNo" INTEGER NOT NULL DEFAULT 0,
  "searchAppearances" INTEGER NOT NULL DEFAULT 0,
  "clickThroughs" INTEGER NOT NULL DEFAULT 0,
  "authorId" TEXT NOT NULL,
  "lastEditedById" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "publishedAt" TIMESTAMPTZ
);

DO $$ BEGIN
  ALTER TABLE "KBArticle" ADD CONSTRAINT "KBArticle_slug_key" UNIQUE ("slug");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "KBArticle" ADD CONSTRAINT "KBArticle_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "KBArticle" ADD CONSTRAINT "KBArticle_lastEditedById_fkey" FOREIGN KEY ("lastEditedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "KBArticle_category_status_sortOrder_idx" ON "KBArticle" ("category", "status", "sortOrder");
CREATE INDEX IF NOT EXISTS "KBArticle_status_publishedAt_idx" ON "KBArticle" ("status", "publishedAt");

-- ── STEP 15: "KBSearchLog" table ───────────────────────────────────
CREATE TABLE IF NOT EXISTS "KBSearchLog" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "query" TEXT NOT NULL,
  "language" TEXT NOT NULL DEFAULT 'en',
  "userId" TEXT,
  "resultsCount" INTEGER NOT NULL,
  "clickedArticleId" TEXT,
  "ledToTicket" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "KBSearchLog" ADD CONSTRAINT "KBSearchLog_clickedArticleId_fkey" FOREIGN KEY ("clickedArticleId") REFERENCES "KBArticle"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "KBSearchLog_query_language_idx" ON "KBSearchLog" ("query", "language");
CREATE INDEX IF NOT EXISTS "KBSearchLog_createdAt_idx" ON "KBSearchLog" ("createdAt");
CREATE INDEX IF NOT EXISTS "KBSearchLog_ledToTicket_idx" ON "KBSearchLog" ("ledToTicket");

-- ── STEP 16: "Family" table — add missing columns ──────────────────
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "kinFamilyId" TEXT;
ALTER TABLE "Family" ADD COLUMN IF NOT EXISTS "username" TEXT;

DO $$ BEGIN
  ALTER TABLE "Family" ADD CONSTRAINT "Family_kinFamilyId_key" UNIQUE ("kinFamilyId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Family" ADD CONSTRAINT "Family_username_key" UNIQUE ("username");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Family_username_idx" ON "Family" ("username");
CREATE INDEX IF NOT EXISTS "Family_kinFamilyId_idx" ON "Family" ("kinFamilyId");

-- ── STEP 17: "Person" table — add missing columns ──────────────────
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "photoThumb" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "photoCard" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "photoFull" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "username" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "bloodGroup" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "education" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "biography" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "email" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "phone" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "address" TEXT;
ALTER TABLE "Person" ADD COLUMN IF NOT EXISTS "anniversaryDate" TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS "Person_username_idx" ON "Person" ("username");
CREATE INDEX IF NOT EXISTS "Person_familyId_idx" ON "Person" ("familyId");
CREATE INDEX IF NOT EXISTS "Person_updatedAt_idx" ON "Person" ("updatedAt");

-- ── STEP 18: "WhatsAppTemplate" table ──────────────────────────────
CREATE TABLE IF NOT EXISTS "WhatsAppTemplate" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "name" TEXT NOT NULL,
  "category" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "whatsappId" TEXT,
  "languages" TEXT NOT NULL DEFAULT '[]',
  "components" TEXT NOT NULL DEFAULT '{}',
  "rejectionReason" TEXT,
  "lastSyncedAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "WhatsAppTemplate" ADD CONSTRAINT "WhatsAppTemplate_name_key" UNIQUE ("name");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "WhatsAppTemplate_status_idx" ON "WhatsAppTemplate" ("status");
CREATE INDEX IF NOT EXISTS "WhatsAppTemplate_category_idx" ON "WhatsAppTemplate" ("category");

-- ── STEP 19: "WhatsAppConsent" table ───────────────────────────────
CREATE TABLE IF NOT EXISTS "WhatsAppConsent" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "phone" TEXT NOT NULL,
  "optedIn" BOOLEAN NOT NULL DEFAULT false,
  "optInMethod" TEXT,
  "optInAt" TIMESTAMPTZ,
  "optOutAt" TIMESTAMPTZ,
  "optOutMethod" TEXT,
  "optOutReason" TEXT,
  "consentVersion" TEXT NOT NULL DEFAULT 'v1',
  "messageCategories" TEXT NOT NULL DEFAULT '[]',
  "marketingConsent" BOOLEAN NOT NULL DEFAULT false,
  "marketingOptInAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "WhatsAppConsent" ADD CONSTRAINT "WhatsAppConsent_userId_key" UNIQUE ("userId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "WhatsAppConsent" ADD CONSTRAINT "WhatsAppConsent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "WhatsAppConsent_phone_idx" ON "WhatsAppConsent" ("phone");
CREATE INDEX IF NOT EXISTS "WhatsAppConsent_optedIn_idx" ON "WhatsAppConsent" ("optedIn");

-- ── STEP 20: "WhatsAppOptIn" table ─────────────────────────────────
CREATE TABLE IF NOT EXISTS "WhatsAppOptIn" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "phone" TEXT NOT NULL,
  "templateType" TEXT NOT NULL,
  "optedIn" BOOLEAN NOT NULL DEFAULT false,
  "optedInAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "WhatsAppOptIn" ADD CONSTRAINT "WhatsAppOptIn_phone_templateType_key" UNIQUE ("phone", "templateType");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "WhatsAppOptIn_phone_idx" ON "WhatsAppOptIn" ("phone");

-- ── STEP 21: "WhatsAppAnalytics" table ─────────────────────────────
CREATE TABLE IF NOT EXISTS "WhatsAppAnalytics" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "event" TEXT NOT NULL,
  "userId" TEXT,
  "familyId" TEXT,
  "messageId" TEXT,
  "templateId" TEXT,
  "metadata" TEXT NOT NULL DEFAULT '{}',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "WhatsAppAnalytics_event_createdAt_idx" ON "WhatsAppAnalytics" ("event", "createdAt");
CREATE INDEX IF NOT EXISTS "WhatsAppAnalytics_userId_createdAt_idx" ON "WhatsAppAnalytics" ("userId", "createdAt");
CREATE INDEX IF NOT EXISTS "WhatsAppAnalytics_templateId_createdAt_idx" ON "WhatsAppAnalytics" ("templateId", "createdAt");

-- ── STEP 22: "NotificationPreference" table ────────────────────────
CREATE TABLE IF NOT EXISTS "NotificationPreference" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "eventType" TEXT NOT NULL,
  "whatsapp" BOOLEAN NOT NULL DEFAULT true,
  "push" BOOLEAN NOT NULL DEFAULT true,
  "inApp" BOOLEAN NOT NULL DEFAULT true,
  "email" BOOLEAN NOT NULL DEFAULT false,
  "quietHoursStart" TEXT,
  "quietHoursEnd" TEXT,
  "quietHoursTimezone" TEXT NOT NULL DEFAULT 'Asia/Kolkata',
  "maxPerDay" INTEGER NOT NULL DEFAULT 10,
  "digestMode" TEXT NOT NULL DEFAULT 'immediate',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "NotificationPreference" ADD CONSTRAINT "NotificationPreference_userId_eventType_key" UNIQUE ("userId", "eventType");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "NotificationPreference" ADD CONSTRAINT "NotificationPreference_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "NotificationPreference_userId_idx" ON "NotificationPreference" ("userId");

-- ── STEP 23: "Notification" table ──────────────────────────────────
CREATE TABLE IF NOT EXISTS "Notification" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "eventType" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "familyId" TEXT,
  "personId" TEXT,
  "channels" TEXT NOT NULL DEFAULT '[]',
  "priority" TEXT NOT NULL DEFAULT 'normal',
  "read" BOOLEAN NOT NULL DEFAULT false,
  "readAt" TIMESTAMPTZ,
  "actionUrl" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "Notification" ADD CONSTRAINT "Notification_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Notification_userId_read_createdAt_idx" ON "Notification" ("userId", "read", "createdAt");
CREATE INDEX IF NOT EXISTS "Notification_userId_createdAt_idx" ON "Notification" ("userId", "createdAt");

-- ── STEP 24: "NotificationUpdate" table ────────────────────────────
CREATE TABLE IF NOT EXISTS "NotificationUpdate" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "notificationId" TEXT NOT NULL,
  "channel" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "error" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "NotificationUpdate" ADD CONSTRAINT "NotificationUpdate_notificationId_fkey" FOREIGN KEY ("notificationId") REFERENCES "Notification"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "NotificationUpdate_notificationId_idx" ON "NotificationUpdate" ("notificationId");
CREATE INDEX IF NOT EXISTS "NotificationUpdate_channel_status_idx" ON "NotificationUpdate" ("channel", "status");

-- ── STEP 25: "Invitation" table — add missing columns ──────────────
ALTER TABLE "Invitation" ADD COLUMN IF NOT EXISTS "whatsappSentAt" TIMESTAMPTZ;
ALTER TABLE "Invitation" ADD COLUMN IF NOT EXISTS "whatsappReminderCount" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Invitation" ADD COLUMN IF NOT EXISTS "whatsappLastRemindedAt" TIMESTAMPTZ;
ALTER TABLE "Invitation" ADD COLUMN IF NOT EXISTS "deepLinkPath" TEXT;

-- ── STEP 26: "ShareableLink" table ─────────────────────────────────
CREATE TABLE IF NOT EXISTS "ShareableLink" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "token" TEXT NOT NULL,
  "cardType" TEXT NOT NULL,
  "familyId" TEXT,
  "personId" TEXT,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "deepLinkUrl" TEXT NOT NULL,
  "viewCount" INTEGER NOT NULL DEFAULT 0,
  "shareCount" INTEGER NOT NULL DEFAULT 0,
  "expiresAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "ShareableLink" ADD CONSTRAINT "ShareableLink_token_key" UNIQUE ("token");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "ShareableLink_token_idx" ON "ShareableLink" ("token");
CREATE INDEX IF NOT EXISTS "ShareableLink_cardType_idx" ON "ShareableLink" ("cardType");

-- ── STEP 27: "ApiKey" table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "ApiKey" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "name" TEXT NOT NULL,
  "keyPrefix" TEXT NOT NULL,
  "keyHash" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "scopes" TEXT NOT NULL DEFAULT '[]',
  "tier" TEXT NOT NULL DEFAULT 'free',
  "rateLimitPerMinute" INTEGER NOT NULL DEFAULT 30,
  "allowedOrigins" TEXT NOT NULL DEFAULT '[]',
  "allowedIps" TEXT NOT NULL DEFAULT '[]',
  "lastUsedAt" TIMESTAMPTZ,
  "expiresAt" TIMESTAMPTZ,
  "revokedAt" TIMESTAMPTZ,
  "revokeReason" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "ApiKey" ADD CONSTRAINT "ApiKey_keyPrefix_keyHash_key" UNIQUE ("keyPrefix", "keyHash");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ApiKey" ADD CONSTRAINT "ApiKey_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "ApiKey_userId_idx" ON "ApiKey" ("userId");
CREATE INDEX IF NOT EXISTS "ApiKey_keyPrefix_idx" ON "ApiKey" ("keyPrefix");
CREATE INDEX IF NOT EXISTS "ApiKey_tier_idx" ON "ApiKey" ("tier");

-- ── STEP 28: "OAuthClient" table ───────────────────────────────────
CREATE TABLE IF NOT EXISTS "OAuthClient" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "clientId" TEXT NOT NULL,
  "clientSecret" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "description" TEXT,
  "redirectUris" TEXT NOT NULL DEFAULT '[]',
  "scopes" TEXT NOT NULL DEFAULT '[]',
  "userId" TEXT NOT NULL,
  "logoUrl" TEXT,
  "websiteUrl" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "OAuthClient" ADD CONSTRAINT "OAuthClient_clientId_key" UNIQUE ("clientId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "OAuthClient" ADD CONSTRAINT "OAuthClient_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "OAuthClient_clientId_idx" ON "OAuthClient" ("clientId");

-- ── STEP 29: "OAuthAuthorizationCode" table ───────────────────────
CREATE TABLE IF NOT EXISTS "OAuthAuthorizationCode" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "code" TEXT NOT NULL,
  "clientId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "scopes" TEXT NOT NULL DEFAULT '[]',
  "redirectUri" TEXT NOT NULL,
  "expiresAt" TIMESTAMPTZ NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "OAuthAuthorizationCode" ADD CONSTRAINT "OAuthAuthorizationCode_code_key" UNIQUE ("code");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "OAuthAuthorizationCode_code_idx" ON "OAuthAuthorizationCode" ("code");
CREATE INDEX IF NOT EXISTS "OAuthAuthorizationCode_expiresAt_idx" ON "OAuthAuthorizationCode" ("expiresAt");

-- ── STEP 30: "IdempotencyKey" table ───────────────────────────────
CREATE TABLE IF NOT EXISTS "IdempotencyKey" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "key" TEXT NOT NULL,
  "responseBody" TEXT NOT NULL,
  "responseStatus" INTEGER NOT NULL,
  "responseHeaders" TEXT NOT NULL DEFAULT '{}',
  "expiresAt" TIMESTAMPTZ NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "IdempotencyKey" ADD CONSTRAINT "IdempotencyKey_key_key" UNIQUE ("key");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "IdempotencyKey_key_idx" ON "IdempotencyKey" ("key");
CREATE INDEX IF NOT EXISTS "IdempotencyKey_expiresAt_idx" ON "IdempotencyKey" ("expiresAt");

-- ── STEP 31: "WebhookSubscription" table ───────────────────────────
CREATE TABLE IF NOT EXISTS "WebhookSubscription" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "url" TEXT NOT NULL,
  "secret" TEXT NOT NULL,
  "events" TEXT NOT NULL DEFAULT '[]',
  "active" BOOLEAN NOT NULL DEFAULT true,
  "description" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "WebhookSubscription_userId_idx" ON "WebhookSubscription" ("userId");
CREATE INDEX IF NOT EXISTS "WebhookSubscription_active_idx" ON "WebhookSubscription" ("active");

-- ── STEP 32: "WebhookDelivery" table ──────────────────────────────
CREATE TABLE IF NOT EXISTS "WebhookDelivery" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "webhookId" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "eventType" TEXT NOT NULL,
  "payload" TEXT NOT NULL,
  "signature" TEXT NOT NULL,
  "attemptCount" INTEGER NOT NULL DEFAULT 0,
  "maxAttempts" INTEGER NOT NULL DEFAULT 5,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "lastAttemptAt" TIMESTAMPTZ,
  "nextAttemptAt" TIMESTAMPTZ,
  "responseStatusCode" INTEGER,
  "responseBody" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "WebhookDelivery" ADD CONSTRAINT "WebhookDelivery_webhookId_fkey" FOREIGN KEY ("webhookId") REFERENCES "WebhookSubscription"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "WebhookDelivery_webhookId_idx" ON "WebhookDelivery" ("webhookId");
CREATE INDEX IF NOT EXISTS "WebhookDelivery_status_idx" ON "WebhookDelivery" ("status");
CREATE INDEX IF NOT EXISTS "WebhookDelivery_nextAttemptAt_idx" ON "WebhookDelivery" ("nextAttemptAt");

-- ── STEP 33: "AuditLog" table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS "AuditLog" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT,
  "action" TEXT NOT NULL,
  "resource" TEXT NOT NULL,
  "resourceId" TEXT,
  "details" TEXT NOT NULL DEFAULT '{}',
  "ipAddress" TEXT,
  "userAgent" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "AuditLog_userId_createdAt_idx" ON "AuditLog" ("userId", "createdAt");
CREATE INDEX IF NOT EXISTS "AuditLog_action_createdAt_idx" ON "AuditLog" ("action", "createdAt");
CREATE INDEX IF NOT EXISTS "AuditLog_resource_resourceId_idx" ON "AuditLog" ("resource", "resourceId");

-- ── STEP 34: "Relationship" — add missing columns ──────────────────
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "relationshipType" TEXT NOT NULL DEFAULT 'custom';
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "label" TEXT;
ALTER TABLE "Relationship" ADD COLUMN IF NOT EXISTS "verifiedAt" TIMESTAMPTZ;

-- ── STEP 35: "FamilyPost" table ───────────────────────────────────
CREATE TABLE IF NOT EXISTS "FamilyPost" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "authorId" TEXT NOT NULL,
  "postType" TEXT NOT NULL,
  "content" TEXT NOT NULL DEFAULT '{}',
  "reactions" TEXT NOT NULL DEFAULT '{}',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "FamilyPost" ADD CONSTRAINT "FamilyPost_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FamilyPost" ADD CONSTRAINT "FamilyPost_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "Person"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "FamilyPost_familyId_createdAt_idx" ON "FamilyPost" ("familyId", "createdAt");
CREATE INDEX IF NOT EXISTS "FamilyPost_postType_idx" ON "FamilyPost" ("postType");
CREATE INDEX IF NOT EXISTS "FamilyPost_authorId_idx" ON "FamilyPost" ("authorId");
CREATE INDEX IF NOT EXISTS "FamilyPost_updatedAt_idx" ON "FamilyPost" ("updatedAt");

-- ── STEP 36: "ModerationCase" table ───────────────────────────────
CREATE TABLE IF NOT EXISTS "ModerationCase" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "contentType" TEXT NOT NULL,
  "contentId" TEXT NOT NULL,
  "contentPreview" TEXT,
  "contentHash" TEXT,
  "authorId" TEXT NOT NULL,
  "familyId" TEXT,
  "category" TEXT NOT NULL DEFAULT 'safe',
  "confidence" DOUBLE PRECISION NOT NULL DEFAULT 0.0,
  "autoAction" TEXT NOT NULL DEFAULT 'allow',
  "flaggedCategories" TEXT NOT NULL DEFAULT '[]',
  "status" TEXT NOT NULL DEFAULT 'pending',
  "priority" TEXT NOT NULL DEFAULT 'normal',
  "reviewerId" TEXT,
  "reviewedAt" TIMESTAMPTZ,
  "reviewDecision" TEXT,
  "reviewNotes" TEXT,
  "source" TEXT NOT NULL DEFAULT 'auto',
  "reporterId" TEXT,
  "reportReason" TEXT,
  "reportDetails" TEXT,
  "contentAction" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "ModerationCase_status_priority_idx" ON "ModerationCase" ("status", "priority");
CREATE INDEX IF NOT EXISTS "ModerationCase_contentType_contentId_idx" ON "ModerationCase" ("contentType", "contentId");
CREATE INDEX IF NOT EXISTS "ModerationCase_authorId_idx" ON "ModerationCase" ("authorId");
CREATE INDEX IF NOT EXISTS "ModerationCase_createdAt_idx" ON "ModerationCase" ("createdAt");
CREATE INDEX IF NOT EXISTS "ModerationCase_reviewerId_idx" ON "ModerationCase" ("reviewerId");

-- ── STEP 37: "ModerationActionItem" table ─────────────────────────
CREATE TABLE IF NOT EXISTS "ModerationActionItem" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "caseId" TEXT NOT NULL,
  "actionType" TEXT NOT NULL,
  "actorId" TEXT,
  "details" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "ModerationActionItem" ADD CONSTRAINT "ModerationActionItem_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "ModerationCase"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "ModerationActionItem_caseId_idx" ON "ModerationActionItem" ("caseId");

-- ── STEP 38: "ModerationRule" table ───────────────────────────────
CREATE TABLE IF NOT EXISTS "ModerationRule" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "name" TEXT NOT NULL,
  "description" TEXT,
  "contentType" TEXT,
  "category" TEXT NOT NULL,
  "condition" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "priority" TEXT NOT NULL DEFAULT 'normal',
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdBy" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "ModerationRule_isActive_category_idx" ON "ModerationRule" ("isActive", "category");

-- ── STEP 39: "ModerationAppeal" table ─────────────────────────────
CREATE TABLE IF NOT EXISTS "ModerationAppeal" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "caseId" TEXT NOT NULL,
  "appellantId" TEXT NOT NULL,
  "appealReason" TEXT NOT NULL,
  "appealTier" INTEGER NOT NULL DEFAULT 1,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "reviewerId" TEXT,
  "reviewedAt" TIMESTAMPTZ,
  "reviewDecision" TEXT,
  "reviewNotes" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "ModerationAppeal" ADD CONSTRAINT "ModerationAppeal_caseId_fkey" FOREIGN KEY ("caseId") REFERENCES "ModerationCase"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ModerationAppeal" ADD CONSTRAINT "ModerationAppeal_appellantId_fkey" FOREIGN KEY ("appellantId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ModerationAppeal" ADD CONSTRAINT "ModerationAppeal_reviewerId_fkey" FOREIGN KEY ("reviewerId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "ModerationAppeal_caseId_idx" ON "ModerationAppeal" ("caseId");
CREATE INDEX IF NOT EXISTS "ModerationAppeal_appellantId_idx" ON "ModerationAppeal" ("appellantId");
CREATE INDEX IF NOT EXISTS "ModerationAppeal_status_idx" ON "ModerationAppeal" ("status");

-- ── STEP 40: "ContentReport" table ────────────────────────────────
CREATE TABLE IF NOT EXISTS "ContentReport" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "reporterId" TEXT NOT NULL,
  "targetType" TEXT NOT NULL,
  "targetId" TEXT NOT NULL,
  "reason" TEXT NOT NULL,
  "description" TEXT,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "resolvedById" TEXT,
  "resolution" TEXT,
  "resolutionNote" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "resolvedAt" TIMESTAMPTZ
);

DO $$ BEGIN
  ALTER TABLE "ContentReport" ADD CONSTRAINT "ContentReport_reporterId_fkey" FOREIGN KEY ("reporterId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ContentReport" ADD CONSTRAINT "ContentReport_resolvedById_fkey" FOREIGN KEY ("resolvedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "ContentReport_status_createdAt_idx" ON "ContentReport" ("status", "createdAt");
CREATE INDEX IF NOT EXISTS "ContentReport_targetType_targetId_idx" ON "ContentReport" ("targetType", "targetId");
CREATE INDEX IF NOT EXISTS "ContentReport_reporterId_idx" ON "ContentReport" ("reporterId");

-- ── STEP 41: "ModerationAction" table ─────────────────────────────
CREATE TABLE IF NOT EXISTS "ModerationAction" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "moderatorId" TEXT NOT NULL,
  "targetType" TEXT NOT NULL,
  "targetId" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "reason" TEXT NOT NULL,
  "duration" INTEGER,
  "reportId" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "expiresAt" TIMESTAMPTZ
);

DO $$ BEGIN
  ALTER TABLE "ModerationAction" ADD CONSTRAINT "ModerationAction_moderatorId_fkey" FOREIGN KEY ("moderatorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "ModerationAction_targetType_targetId_idx" ON "ModerationAction" ("targetType", "targetId");
CREATE INDEX IF NOT EXISTS "ModerationAction_moderatorId_idx" ON "ModerationAction" ("moderatorId");
CREATE INDEX IF NOT EXISTS "ModerationAction_expiresAt_idx" ON "ModerationAction" ("expiresAt");

-- ── STEP 42: "UserModerationStatus" table ─────────────────────────
CREATE TABLE IF NOT EXISTS "UserModerationStatus" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'active',
  "warningCount" INTEGER NOT NULL DEFAULT 0,
  "suspendedUntil" TIMESTAMPTZ,
  "banReason" TEXT,
  "lastWarnedAt" TIMESTAMPTZ,
  "lastActionAt" TIMESTAMPTZ
);

DO $$ BEGIN
  ALTER TABLE "UserModerationStatus" ADD CONSTRAINT "UserModerationStatus_userId_key" UNIQUE ("userId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "UserModerationStatus" ADD CONSTRAINT "UserModerationStatus_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "UserModerationStatus_status_idx" ON "UserModerationStatus" ("status");

-- ── STEP 43: "ModerationAuditLog" table ───────────────────────────
CREATE TABLE IF NOT EXISTS "ModerationAuditLog" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "action" TEXT NOT NULL,
  "contentType" TEXT NOT NULL,
  "contentId" TEXT NOT NULL,
  "actorType" TEXT NOT NULL,
  "actorId" TEXT,
  "result" TEXT NOT NULL,
  "reason" TEXT,
  "confidence" DOUBLE PRECISION,
  "metadata" TEXT NOT NULL DEFAULT '{}',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "ModerationAuditLog_contentId_createdAt_idx" ON "ModerationAuditLog" ("contentId", "createdAt");
CREATE INDEX IF NOT EXISTS "ModerationAuditLog_actorType_actorId_idx" ON "ModerationAuditLog" ("actorType", "actorId");
CREATE INDEX IF NOT EXISTS "ModerationAuditLog_createdAt_idx" ON "ModerationAuditLog" ("createdAt");

-- ── STEP 44: "ParentalConsent" table ──────────────────────────────
CREATE TABLE IF NOT EXISTS "ParentalConsent" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "childPersonId" TEXT NOT NULL,
  "guardianUserId" TEXT NOT NULL,
  "consentType" TEXT NOT NULL,
  "consented" BOOLEAN NOT NULL DEFAULT false,
  "consentMethod" TEXT NOT NULL,
  "consentGivenAt" TIMESTAMPTZ,
  "ipAddress" TEXT,
  "userAgent" TEXT,
  "revokedAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "ParentalConsent" ADD CONSTRAINT "ParentalConsent_guardianUserId_fkey" FOREIGN KEY ("guardianUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "ParentalConsent_childPersonId_idx" ON "ParentalConsent" ("childPersonId");
CREATE INDEX IF NOT EXISTS "ParentalConsent_guardianUserId_idx" ON "ParentalConsent" ("guardianUserId");

-- ── STEP 45: "Community" table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS "Community" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "type" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "slug" TEXT NOT NULL,
  "description" TEXT,
  "coverImageUrl" TEXT,
  "iconUrl" TEXT,
  "isVerified" BOOLEAN NOT NULL DEFAULT false,
  "isPrivate" BOOLEAN NOT NULL DEFAULT false,
  "memberCount" INTEGER NOT NULL DEFAULT 0,
  "postCount" INTEGER NOT NULL DEFAULT 0,
  "gotraName" TEXT,
  "villageName" TEXT,
  "surname" TEXT,
  "region" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "Community" ADD CONSTRAINT "Community_slug_key" UNIQUE ("slug");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Community_type_name_idx" ON "Community" ("type", "name");

-- ── STEP 46: "CommunityMember" table ──────────────────────────────
CREATE TABLE IF NOT EXISTS "CommunityMember" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "communityId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "role" TEXT NOT NULL DEFAULT 'member',
  "joinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "joinedVia" TEXT,
  "lastReadAt" TIMESTAMPTZ
);

DO $$ BEGIN
  ALTER TABLE "CommunityMember" ADD CONSTRAINT "CommunityMember_communityId_userId_key" UNIQUE ("communityId", "userId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "CommunityMember" ADD CONSTRAINT "CommunityMember_communityId_fkey" FOREIGN KEY ("communityId") REFERENCES "Community"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "CommunityMember" ADD CONSTRAINT "CommunityMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "CommunityMember_userId_idx" ON "CommunityMember" ("userId");

-- ── STEP 47: "CommunityPost" table ────────────────────────────────
CREATE TABLE IF NOT EXISTS "CommunityPost" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "communityId" TEXT,
  "familyId" TEXT,
  "authorId" TEXT NOT NULL,
  "type" TEXT NOT NULL DEFAULT 'text',
  "title" TEXT,
  "body" TEXT NOT NULL,
  "mediaUrls" TEXT NOT NULL DEFAULT '[]',
  "visibility" TEXT NOT NULL DEFAULT 'members',
  "isPinned" BOOLEAN NOT NULL DEFAULT false,
  "isLocked" BOOLEAN NOT NULL DEFAULT false,
  "isHidden" BOOLEAN NOT NULL DEFAULT false,
  "hiddenReason" TEXT,
  "metadata" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "CommunityPost" ADD CONSTRAINT "CommunityPost_communityId_fkey" FOREIGN KEY ("communityId") REFERENCES "Community"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "CommunityPost" ADD CONSTRAINT "CommunityPost_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "CommunityPost_communityId_createdAt_idx" ON "CommunityPost" ("communityId", "createdAt");
CREATE INDEX IF NOT EXISTS "CommunityPost_familyId_createdAt_idx" ON "CommunityPost" ("familyId", "createdAt");
CREATE INDEX IF NOT EXISTS "CommunityPost_authorId_idx" ON "CommunityPost" ("authorId");
CREATE INDEX IF NOT EXISTS "CommunityPost_visibility_createdAt_idx" ON "CommunityPost" ("visibility", "createdAt");

-- ── STEP 48: "Reaction" table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS "Reaction" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "postId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "emoji" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "Reaction" ADD CONSTRAINT "Reaction_postId_userId_emoji_key" UNIQUE ("postId", "userId", "emoji");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Reaction" ADD CONSTRAINT "Reaction_postId_fkey" FOREIGN KEY ("postId") REFERENCES "CommunityPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Reaction" ADD CONSTRAINT "Reaction_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Reaction_postId_idx" ON "Reaction" ("postId");

-- ── STEP 49: "Comment" table ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS "Comment" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "postId" TEXT NOT NULL,
  "authorId" TEXT NOT NULL,
  "parentId" TEXT,
  "body" TEXT NOT NULL,
  "isHidden" BOOLEAN NOT NULL DEFAULT false,
  "hiddenReason" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "Comment" ADD CONSTRAINT "Comment_postId_fkey" FOREIGN KEY ("postId") REFERENCES "CommunityPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "Comment" ADD CONSTRAINT "Comment_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Comment_postId_createdAt_idx" ON "Comment" ("postId", "createdAt");
CREATE INDEX IF NOT EXISTS "Comment_parentId_idx" ON "Comment" ("parentId");
CREATE INDEX IF NOT EXISTS "Comment_authorId_idx" ON "Comment" ("authorId");

-- ── STEP 50: "FamilyConnection" table ─────────────────────────────
CREATE TABLE IF NOT EXISTS "FamilyConnection" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "fromFamilyId" TEXT NOT NULL,
  "toFamilyId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "connectionType" TEXT,
  "requestedById" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "FamilyConnection" ADD CONSTRAINT "FamilyConnection_fromFamilyId_toFamilyId_key" UNIQUE ("fromFamilyId", "toFamilyId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "FamilyConnection_toFamilyId_status_idx" ON "FamilyConnection" ("toFamilyId", "status");
CREATE INDEX IF NOT EXISTS "FamilyConnection_fromFamilyId_status_idx" ON "FamilyConnection" ("fromFamilyId", "status");

-- ── STEP 51: "CommunityEvent" table ───────────────────────────────
CREATE TABLE IF NOT EXISTS "CommunityEvent" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT,
  "communityId" TEXT,
  "creatorId" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT,
  "eventType" TEXT NOT NULL DEFAULT 'custom',
  "startDate" TIMESTAMPTZ NOT NULL,
  "endDate" TIMESTAMPTZ,
  "isAllDay" BOOLEAN NOT NULL DEFAULT false,
  "isRecurring" BOOLEAN NOT NULL DEFAULT false,
  "recurrenceRule" TEXT,
  "location" TEXT,
  "locationUrl" TEXT,
  "meetingUrl" TEXT,
  "visibility" TEXT NOT NULL DEFAULT 'family',
  "isCancelled" BOOLEAN NOT NULL DEFAULT false,
  "coverImageUrl" TEXT,
  "metadata" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "CommunityEvent" ADD CONSTRAINT "CommunityEvent_communityId_fkey" FOREIGN KEY ("communityId") REFERENCES "Community"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "CommunityEvent_familyId_startDate_idx" ON "CommunityEvent" ("familyId", "startDate");
CREATE INDEX IF NOT EXISTS "CommunityEvent_startDate_idx" ON "CommunityEvent" ("startDate");

-- ── STEP 52: "EventRSVP" table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS "EventRSVP" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "eventId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "plusOne" BOOLEAN NOT NULL DEFAULT false,
  "note" TEXT,
  "respondedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "EventRSVP" ADD CONSTRAINT "EventRSVP_eventId_userId_key" UNIQUE ("eventId", "userId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "EventRSVP" ADD CONSTRAINT "EventRSVP_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "CommunityEvent"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "EventRSVP" ADD CONSTRAINT "EventRSVP_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "EventRSVP_eventId_idx" ON "EventRSVP" ("eventId");

-- ── STEP 53: "EventReminder" table ────────────────────────────────
CREATE TABLE IF NOT EXISTS "EventReminder" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "eventId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "remindAt" TIMESTAMPTZ NOT NULL,
  "isSent" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "EventReminder" ADD CONSTRAINT "EventReminder_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "CommunityEvent"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "EventReminder_remindAt_isSent_idx" ON "EventReminder" ("remindAt", "isSent");

-- ── STEP 54: "CommunityRule" table ────────────────────────────────
CREATE TABLE IF NOT EXISTS "CommunityRule" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "communityId" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "CommunityRule" ADD CONSTRAINT "CommunityRule_communityId_fkey" FOREIGN KEY ("communityId") REFERENCES "Community"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "CommunityRule_communityId_sortOrder_idx" ON "CommunityRule" ("communityId", "sortOrder");

-- ── STEP 55: "UserContribution" table ─────────────────────────────
CREATE TABLE IF NOT EXISTS "UserContribution" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "familyId" TEXT NOT NULL,
  "personsAdded" INTEGER NOT NULL DEFAULT 0,
  "relationshipsAdded" INTEGER NOT NULL DEFAULT 0,
  "photosAdded" INTEGER NOT NULL DEFAULT 0,
  "eventsCreated" INTEGER NOT NULL DEFAULT 0,
  "storiesShared" INTEGER NOT NULL DEFAULT 0,
  "commentsWritten" INTEGER NOT NULL DEFAULT 0,
  "invitationsSent" INTEGER NOT NULL DEFAULT 0,
  "personsEdited" INTEGER NOT NULL DEFAULT 0,
  "totalPoints" INTEGER NOT NULL DEFAULT 0,
  "level" INTEGER NOT NULL DEFAULT 1,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "UserContribution" ADD CONSTRAINT "UserContribution_userId_familyId_key" UNIQUE ("userId", "familyId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "UserContribution" ADD CONSTRAINT "UserContribution_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "UserContribution_familyId_totalPoints_idx" ON "UserContribution" ("familyId", "totalPoints");

-- ── STEP 56: "Badge" table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "Badge" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "slug" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "nameHi" TEXT,
  "description" TEXT NOT NULL,
  "icon" TEXT NOT NULL,
  "category" TEXT NOT NULL,
  "tier" TEXT NOT NULL DEFAULT 'bronze',
  "threshold" INTEGER NOT NULL,
  "isSecret" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "Badge" ADD CONSTRAINT "Badge_slug_key" UNIQUE ("slug");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Badge_category_idx" ON "Badge" ("category");

-- ── STEP 57: "UserBadge" table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS "UserBadge" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "badgeId" TEXT NOT NULL,
  "familyId" TEXT,
  "earnedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "UserBadge" ADD CONSTRAINT "UserBadge_userId_badgeId_familyId_key" UNIQUE ("userId", "badgeId", "familyId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "UserBadge" ADD CONSTRAINT "UserBadge_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "UserBadge" ADD CONSTRAINT "UserBadge_badgeId_fkey" FOREIGN KEY ("badgeId") REFERENCES "Badge"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "UserBadge_userId_idx" ON "UserBadge" ("userId");

-- ── STEP 58: "FamilyMilestone" table ──────────────────────────────
CREATE TABLE IF NOT EXISTS "FamilyMilestone" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "milestone" TEXT NOT NULL,
  "reachedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "celebrated" BOOLEAN NOT NULL DEFAULT false
);

DO $$ BEGIN
  ALTER TABLE "FamilyMilestone" ADD CONSTRAINT "FamilyMilestone_familyId_milestone_key" UNIQUE ("familyId", "milestone");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

-- ── STEP 59: "PersonPrivacySetting" table ─────────────────────────
CREATE TABLE IF NOT EXISTS "PersonPrivacySetting" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "personId" TEXT NOT NULL,
  "visibility" TEXT NOT NULL DEFAULT 'family',
  "searchable" BOOLEAN NOT NULL DEFAULT true,
  "matrimonialEligible" BOOLEAN NOT NULL DEFAULT true,
  "communityFeatures" BOOLEAN NOT NULL DEFAULT true,
  "minorFlag" BOOLEAN NOT NULL DEFAULT false,
  "photoConsent" BOOLEAN NOT NULL DEFAULT true,
  "healthConsent" BOOLEAN NOT NULL DEFAULT false,
  "gotraVisibility" TEXT NOT NULL DEFAULT 'family',
  "showPhone" BOOLEAN NOT NULL DEFAULT false,
  "showEmail" BOOLEAN NOT NULL DEFAULT false,
  "showAddress" BOOLEAN NOT NULL DEFAULT false,
  "showDob" BOOLEAN NOT NULL DEFAULT true,
  "showAge" BOOLEAN NOT NULL DEFAULT true,
  "showOccupation" BOOLEAN NOT NULL DEFAULT true,
  "showEducation" BOOLEAN NOT NULL DEFAULT true,
  "showBloodGroup" BOOLEAN NOT NULL DEFAULT false,
  "showAnniversary" BOOLEAN NOT NULL DEFAULT false,
  "profileVisibleTo" TEXT NOT NULL DEFAULT 'family',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "PersonPrivacySetting" ADD CONSTRAINT "PersonPrivacySetting_personId_key" UNIQUE ("personId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "PersonPrivacySetting" ADD CONSTRAINT "PersonPrivacySetting_personId_fkey" FOREIGN KEY ("personId") REFERENCES "Person"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "PersonPrivacySetting_visibility_idx" ON "PersonPrivacySetting" ("visibility");
CREATE INDEX IF NOT EXISTS "PersonPrivacySetting_minorFlag_idx" ON "PersonPrivacySetting" ("minorFlag");

-- ── STEP 60: "DataAccessLog" table ────────────────────────────────
CREATE TABLE IF NOT EXISTS "DataAccessLog" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "personId" TEXT NOT NULL,
  "viewerId" TEXT NOT NULL,
  "viewerRole" TEXT NOT NULL,
  "fieldAccessed" TEXT NOT NULL,
  "granted" BOOLEAN NOT NULL,
  "reason" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "DataAccessLog_personId_createdAt_idx" ON "DataAccessLog" ("personId", "createdAt");
CREATE INDEX IF NOT EXISTS "DataAccessLog_viewerId_idx" ON "DataAccessLog" ("viewerId");

-- ── STEP 61: "PhotoConsent" table ─────────────────────────────────
CREATE TABLE IF NOT EXISTS "PhotoConsent" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "personId" TEXT NOT NULL,
  "photoUrl" TEXT NOT NULL,
  "consentedBy" TEXT NOT NULL,
  "consentType" TEXT NOT NULL,
  "revokedAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "PhotoConsent_personId_idx" ON "PhotoConsent" ("personId");

-- ── STEP 62: "FamilyInvite" table ─────────────────────────────────
CREATE TABLE IF NOT EXISTS "FamilyInvite" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "invitedBy" TEXT NOT NULL,
  "inviteCode" TEXT NOT NULL,
  "role" TEXT NOT NULL DEFAULT 'viewer',
  "status" TEXT NOT NULL DEFAULT 'pending',
  "inviteType" TEXT NOT NULL DEFAULT 'link',
  "maxUses" INTEGER NOT NULL DEFAULT 1,
  "currentUses" INTEGER NOT NULL DEFAULT 0,
  "useCount" INTEGER NOT NULL DEFAULT 0,
  "expiresAt" TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "FamilyInvite" ADD CONSTRAINT "FamilyInvite_inviteCode_key" UNIQUE ("inviteCode");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FamilyInvite" ADD CONSTRAINT "FamilyInvite_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FamilyInvite" ADD CONSTRAINT "FamilyInvite_invitedBy_fkey" FOREIGN KEY ("invitedBy") REFERENCES "FamilyMember"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "FamilyInvite_inviteCode_idx" ON "FamilyInvite" ("inviteCode");

-- ── STEP 63: "GraphLayoutState" table ─────────────────────────────
CREATE TABLE IF NOT EXISTS "GraphLayoutState" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "layoutMode" TEXT NOT NULL DEFAULT 'tree',
  "nodePositions" JSONB NOT NULL DEFAULT '{}',
  "collapsedNodes" JSONB NOT NULL DEFAULT '[]',
  "hiddenNodes" JSONB NOT NULL DEFAULT '[]',
  "zoomLevel" DOUBLE PRECISION NOT NULL DEFAULT 1.0,
  "panOffset" JSONB NOT NULL DEFAULT '{"x":0,"y":0}',
  "filters" JSONB NOT NULL DEFAULT '{}',
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "GraphLayoutState" ADD CONSTRAINT "GraphLayoutState_familyId_userId_key" UNIQUE ("familyId", "userId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "GraphLayoutState" ADD CONSTRAINT "GraphLayoutState_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── STEP 64: "GraphChangeLog" table ───────────────────────────────
CREATE TABLE IF NOT EXISTS "GraphChangeLog" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "entityType" TEXT NOT NULL,
  "entityId" TEXT NOT NULL,
  "details" JSONB NOT NULL DEFAULT '{}',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "GraphChangeLog" ADD CONSTRAINT "GraphChangeLog_familyId_fkey" FOREIGN KEY ("familyId") REFERENCES "Family"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "GraphChangeLog_familyId_idx" ON "GraphChangeLog" ("familyId");
CREATE INDEX IF NOT EXISTS "GraphChangeLog_userId_idx" ON "GraphChangeLog" ("userId");

-- ── STEP 65: "RelationshipTypeMetadata" table ─────────────────────
CREATE TABLE IF NOT EXISTS "RelationshipTypeMetadata" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "relationshipKey" TEXT NOT NULL,
  "englishLabel" TEXT NOT NULL,
  "gender" TEXT NOT NULL,
  "lineage" TEXT NOT NULL,
  "generation" INTEGER NOT NULL,
  "relationCategory" TEXT NOT NULL,
  "inverseKey" TEXT NOT NULL,
  "pathComponents" JSONB NOT NULL DEFAULT '[]',
  "category" TEXT NOT NULL,
  "isCompound" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "RelationshipTypeMetadata" ADD CONSTRAINT "RelationshipTypeMetadata_relationshipKey_key" UNIQUE ("relationshipKey");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "RelationshipTypeMetadata_relationshipKey_idx" ON "RelationshipTypeMetadata" ("relationshipKey");
CREATE INDEX IF NOT EXISTS "RelationshipTypeMetadata_category_idx" ON "RelationshipTypeMetadata" ("category");
CREATE INDEX IF NOT EXISTS "RelationshipTypeMetadata_lineage_idx" ON "RelationshipTypeMetadata" ("lineage");

-- ── STEP 66: "RefreshToken" table ─────────────────────────────────
CREATE TABLE IF NOT EXISTS "RefreshToken" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "token" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "familyId" TEXT NOT NULL,
  "expiresAt" TIMESTAMPTZ NOT NULL,
  "revokedAt" TIMESTAMPTZ,
  "userAgent" TEXT,
  "ipAddress" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "RefreshToken" ADD CONSTRAINT "RefreshToken_token_key" UNIQUE ("token");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "RefreshToken" ADD CONSTRAINT "RefreshToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "RefreshToken_userId_idx" ON "RefreshToken" ("userId");
CREATE INDEX IF NOT EXISTS "RefreshToken_token_idx" ON "RefreshToken" ("token");
CREATE INDEX IF NOT EXISTS "RefreshToken_familyId_idx" ON "RefreshToken" ("familyId");

-- ── STEP 67: "FcmToken" table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS "FcmToken" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "token" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "deviceType" TEXT NOT NULL DEFAULT 'unknown',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "lastUsedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "FcmToken" ADD CONSTRAINT "FcmToken_token_key" UNIQUE ("token");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "FcmToken" ADD CONSTRAINT "FcmToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "FcmToken_userId_idx" ON "FcmToken" ("userId");
CREATE INDEX IF NOT EXISTS "FcmToken_token_idx" ON "FcmToken" ("token");
CREATE INDEX IF NOT EXISTS "FcmToken_lastUsedAt_idx" ON "FcmToken" ("lastUsedAt");

-- ── STEP 68: "FeatureFlag" table ──────────────────────────────────
CREATE TABLE IF NOT EXISTS "FeatureFlag" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "name" TEXT NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT false,
  "rolloutPct" INTEGER NOT NULL DEFAULT 0,
  "description" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "FeatureFlag" ADD CONSTRAINT "FeatureFlag_name_key" UNIQUE ("name");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

-- ── STEP 69: "SyncLog" table ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS "SyncLog" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "familyId" TEXT,
  "syncType" TEXT NOT NULL,
  "lastSyncedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "entitiesSynced" INTEGER NOT NULL DEFAULT 0,
  "conflictsCount" INTEGER NOT NULL DEFAULT 0,
  "resolvedCount" INTEGER NOT NULL DEFAULT 0,
  "status" TEXT NOT NULL DEFAULT 'completed',
  "errorMessage" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "SyncLog_userId_familyId_idx" ON "SyncLog" ("userId", "familyId");
CREATE INDEX IF NOT EXISTS "SyncLog_userId_lastSyncedAt_idx" ON "SyncLog" ("userId", "lastSyncedAt");

-- ── STEP 70: "RelationshipPathCache" table ────────────────────────
CREATE TABLE IF NOT EXISTS "RelationshipPathCache" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "familyId" TEXT NOT NULL,
  "fromPersonId" TEXT NOT NULL,
  "toPersonId" TEXT NOT NULL,
  "path" TEXT NOT NULL,
  "kinshipTerm" TEXT,
  "kinshipTermHi" TEXT,
  "distance" INTEGER NOT NULL,
  "computedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "expiresAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "RelationshipPathCache" ADD CONSTRAINT "RelationshipPathCache_familyId_fromPersonId_toPersonId_key" UNIQUE ("familyId", "fromPersonId", "toPersonId");
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "RelationshipPathCache_familyId_idx" ON "RelationshipPathCache" ("familyId");
CREATE INDEX IF NOT EXISTS "RelationshipPathCache_fromPersonId_idx" ON "RelationshipPathCache" ("fromPersonId");
CREATE INDEX IF NOT EXISTS "RelationshipPathCache_toPersonId_idx" ON "RelationshipPathCache" ("toPersonId");
CREATE INDEX IF NOT EXISTS "RelationshipPathCache_expiresAt_idx" ON "RelationshipPathCache" ("expiresAt");

-- ── STEP 71: "AiInteraction" table ────────────────────────────────
CREATE TABLE IF NOT EXISTS "AiInteraction" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "familyId" TEXT,
  "personId" TEXT,
  "interactionType" TEXT NOT NULL,
  "prompt" TEXT NOT NULL,
  "response" TEXT NOT NULL,
  "modelUsed" TEXT NOT NULL DEFAULT 'gemini-flash',
  "tokenCount" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "AiInteraction_userId_createdAt_idx" ON "AiInteraction" ("userId", "createdAt");
CREATE INDEX IF NOT EXISTS "AiInteraction_interactionType_idx" ON "AiInteraction" ("interactionType");

-- ── STEP 72: "UsernameChangeLog" table ────────────────────────────
CREATE TABLE IF NOT EXISTS "UsernameChangeLog" (
  "id" TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" TEXT NOT NULL,
  "oldUsername" TEXT,
  "newUsername" TEXT NOT NULL,
  "changedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE "UsernameChangeLog" ADD CONSTRAINT "UsernameChangeLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "UsernameChangeLog_userId_changedAt_idx" ON "UsernameChangeLog" ("userId", "changedAt");
CREATE INDEX IF NOT EXISTS "UsernameChangeLog_newUsername_idx" ON "UsernameChangeLog" ("newUsername");

-- ══════════════════════════════════════════════════════════════════════════
-- DONE! All tables and columns synced from Prisma schema.
-- This script is 100% idempotent — safe to run multiple times.
-- ══════════════════════════════════════════════════════════════════════════
