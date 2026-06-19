-- ============================================================
-- Migration: enable_rls_all_unprotected_tables
-- Version:  20260608182831
-- Source:   Pulled from live Supabase (supabase_migrations.schema_migrations)
-- Notes:    Backfilled into the repo on 2026-06-18. This migration was
--           previously applied to production via the Supabase SQL Editor
--           "Save as migration" feature and never committed to source control.
-- ============================================================


-- ── User private data ──────────────────────────────────────

ALTER TABLE "UsernameChangeLog" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own username history" ON "UsernameChangeLog" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "System can create username change logs" ON "UsernameChangeLog" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

ALTER TABLE "DataAccessLog" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can view data access logs" ON "DataAccessLog" FOR SELECT
  USING ("personId" IN (SELECT id FROM "Person" WHERE "familyId" IN (
    SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin'))));
CREATE POLICY "System can create data access logs" ON "DataAccessLog" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

ALTER TABLE "PhotoConsent" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Family members can view photo consent" ON "PhotoConsent" FOR SELECT
  USING ("personId" IN (SELECT id FROM "Person" WHERE "familyId" IN (
    SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text)));
CREATE POLICY "Admins can manage photo consent" ON "PhotoConsent" FOR INSERT
  WITH CHECK ("personId" IN (SELECT id FROM "Person" WHERE "familyId" IN (
    SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin'))));

ALTER TABLE "ParentalConsent" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Guardians can view own parental consent" ON "ParentalConsent" FOR SELECT USING ("guardianUserId" = auth.uid()::text);
CREATE POLICY "Guardians can create parental consent" ON "ParentalConsent" FOR INSERT WITH CHECK ("guardianUserId" = auth.uid()::text);
CREATE POLICY "Guardians can update parental consent" ON "ParentalConsent" FOR UPDATE USING ("guardianUserId" = auth.uid()::text);

ALTER TABLE "AiInteraction" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own AI interactions" ON "AiInteraction" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "System can create AI interactions" ON "AiInteraction" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

ALTER TABLE "SyncLog" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own sync logs" ON "SyncLog" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "System can create sync logs" ON "SyncLog" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ── Support system ─────────────────────────────────────────

ALTER TABLE "SupportTicket" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own support tickets" ON "SupportTicket" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can create support tickets" ON "SupportTicket" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can update own support tickets" ON "SupportTicket" FOR UPDATE USING ("userId" = auth.uid()::text);

ALTER TABLE "SupportMessage" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view messages for own tickets" ON "SupportMessage" FOR SELECT
  USING ("ticketId" IN (SELECT id FROM "SupportTicket" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Users can create messages for own tickets" ON "SupportMessage" FOR INSERT
  WITH CHECK ("ticketId" IN (SELECT id FROM "SupportTicket" WHERE "userId" = auth.uid()::text));

ALTER TABLE "SupportAgent" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Agents can view own agent profile" ON "SupportAgent" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "System can manage support agents" ON "SupportAgent" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Agents can update own profile" ON "SupportAgent" FOR UPDATE USING ("userId" = auth.uid()::text);

ALTER TABLE "SupportEscalation" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Agents can view escalations for own tickets" ON "SupportEscalation" FOR SELECT
  USING ("ticketId" IN (SELECT id FROM "SupportTicket" WHERE "userId" = auth.uid()::text));
CREATE POLICY "System can create escalations" ON "SupportEscalation" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

ALTER TABLE "SupportCSAT" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own CSAT" ON "SupportCSAT" FOR SELECT
  USING ("ticketId" IN (SELECT id FROM "SupportTicket" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Users can submit CSAT" ON "SupportCSAT" FOR INSERT
  WITH CHECK ("ticketId" IN (SELECT id FROM "SupportTicket" WHERE "userId" = auth.uid()::text));

-- ── Audit / admin-only ─────────────────────────────────────

ALTER TABLE "AuditLog" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System can create audit logs" ON "AuditLog" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "No direct audit log reads" ON "AuditLog" FOR SELECT USING (false);

ALTER TABLE "SLATracking" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages SLA tracking insert" ON "SLATracking" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages SLA tracking select" ON "SLATracking" FOR SELECT USING (false);

ALTER TABLE "OnCallSchedule" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages on-call schedule insert" ON "OnCallSchedule" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages on-call schedule select" ON "OnCallSchedule" FOR SELECT USING (false);

ALTER TABLE "Incident" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can view incidents" ON "Incident" FOR SELECT USING (true);
CREATE POLICY "System manages incidents" ON "Incident" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System updates incidents" ON "Incident" FOR UPDATE USING (auth.uid() IS NOT NULL);

ALTER TABLE "IncidentUpdate" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can view incident updates" ON "IncidentUpdate" FOR SELECT USING (true);
CREATE POLICY "System creates incident updates" ON "IncidentUpdate" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

ALTER TABLE "IncidentSubscriber" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can subscribe to incidents" ON "IncidentSubscriber" FOR INSERT WITH CHECK (true);
CREATE POLICY "Subscribers can view own subscriptions" ON "IncidentSubscriber" FOR SELECT USING (true);

ALTER TABLE "PostMortem" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can view post mortems" ON "PostMortem" FOR SELECT USING (true);
CREATE POLICY "System manages post mortems" ON "PostMortem" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ── Knowledge base ─────────────────────────────────────────

ALTER TABLE "KBArticle" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Published articles are public" ON "KBArticle" FOR SELECT USING (status = 'published');
CREATE POLICY "System manages KB articles" ON "KBArticle" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System updates KB articles" ON "KBArticle" FOR UPDATE USING (auth.uid() IS NOT NULL);

ALTER TABLE "KBSearchLog" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System can create KB search logs" ON "KBSearchLog" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "No direct KB search log reads" ON "KBSearchLog" FOR SELECT USING (false);

-- ── Moderation ─────────────────────────────────────────────

ALTER TABLE "ModerationCase" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages moderation cases insert" ON "ModerationCase" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages moderation cases select" ON "ModerationCase" FOR SELECT USING (false);

ALTER TABLE "ModerationActionItem" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages moderation action items insert" ON "ModerationActionItem" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages moderation action items select" ON "ModerationActionItem" FOR SELECT USING (false);

ALTER TABLE "ModerationRule" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages moderation rules insert" ON "ModerationRule" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages moderation rules select" ON "ModerationRule" FOR SELECT USING (false);

ALTER TABLE "ModerationAppeal" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own appeals" ON "ModerationAppeal" FOR SELECT USING ("appellantId" = auth.uid()::text);
CREATE POLICY "Users can submit appeals" ON "ModerationAppeal" FOR INSERT WITH CHECK ("appellantId" = auth.uid()::text);

ALTER TABLE "ModerationAuditLog" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System creates moderation audit logs" ON "ModerationAuditLog" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "No direct moderation audit log reads" ON "ModerationAuditLog" FOR SELECT USING (false);

ALTER TABLE "ModerationAction" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages moderation actions insert" ON "ModerationAction" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages moderation actions select" ON "ModerationAction" FOR SELECT USING (false);

ALTER TABLE "UserModerationStatus" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own moderation status" ON "UserModerationStatus" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "System manages user moderation status" ON "UserModerationStatus" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System updates user moderation status" ON "UserModerationStatus" FOR UPDATE USING (auth.uid() IS NOT NULL);

ALTER TABLE "ContentReport" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own content reports" ON "ContentReport" FOR SELECT USING ("reporterId" = auth.uid()::text);
CREATE POLICY "Users can create content reports" ON "ContentReport" FOR INSERT WITH CHECK ("reporterId" = auth.uid()::text);

-- ── Community ──────────────────────────────────────────────

ALTER TABLE "Community" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view communities" ON "Community" FOR SELECT USING (true);
CREATE POLICY "Authenticated users can create communities" ON "Community" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Community owners can update" ON "Community" FOR UPDATE
  USING (id IN (SELECT "communityId" FROM "CommunityMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin')));

ALTER TABLE "CommunityMember" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view community members" ON "CommunityMember" FOR SELECT USING (true);
CREATE POLICY "Authenticated users can join communities" ON "CommunityMember" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can leave communities" ON "CommunityMember" FOR DELETE USING ("userId" = auth.uid()::text);

ALTER TABLE "CommunityPost" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Members can view community posts" ON "CommunityPost" FOR SELECT
  USING (visibility = 'public' OR "communityId" IN (SELECT "communityId" FROM "CommunityMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Members can create community posts" ON "CommunityPost" FOR INSERT
  WITH CHECK ("authorId" = auth.uid()::text AND "communityId" IN (SELECT "communityId" FROM "CommunityMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Authors can update own community posts" ON "CommunityPost" FOR UPDATE USING ("authorId" = auth.uid()::text);
CREATE POLICY "Authors can delete own community posts" ON "CommunityPost" FOR DELETE USING ("authorId" = auth.uid()::text);

ALTER TABLE "CommunityRule" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view community rules" ON "CommunityRule" FOR SELECT USING (true);
CREATE POLICY "Admins can manage community rules" ON "CommunityRule" FOR INSERT
  WITH CHECK ("communityId" IN (SELECT "communityId" FROM "CommunityMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin')));

ALTER TABLE "CommunityEvent" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Members can view community events" ON "CommunityEvent" FOR SELECT USING (true);
CREATE POLICY "Members can create events" ON "CommunityEvent" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Creators can update events" ON "CommunityEvent" FOR UPDATE USING ("creatorId" = auth.uid()::text);

ALTER TABLE "EventRSVP" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view RSVPs" ON "EventRSVP" FOR SELECT USING (true);
CREATE POLICY "Users can RSVP to events" ON "EventRSVP" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can update own RSVP" ON "EventRSVP" FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can cancel own RSVP" ON "EventRSVP" FOR DELETE USING ("userId" = auth.uid()::text);

ALTER TABLE "EventReminder" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own event reminders" ON "EventReminder" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can create event reminders" ON "EventReminder" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can delete own event reminders" ON "EventReminder" FOR DELETE USING ("userId" = auth.uid()::text);

-- ── Social / Engagement ────────────────────────────────────

ALTER TABLE "Post" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can view posts" ON "Post" FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Authenticated users can create posts" ON "Post" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

ALTER TABLE "Comment" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can view comments" ON "Comment" FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Authenticated users can create comments" ON "Comment" FOR INSERT WITH CHECK ("authorId" = auth.uid()::text);
CREATE POLICY "Authors can update own comments" ON "Comment" FOR UPDATE USING ("authorId" = auth.uid()::text);
CREATE POLICY "Authors can delete own comments" ON "Comment" FOR DELETE USING ("authorId" = auth.uid()::text);

ALTER TABLE "Reaction" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can view reactions" ON "Reaction" FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Authenticated users can react" ON "Reaction" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can remove own reactions" ON "Reaction" FOR DELETE USING ("userId" = auth.uid()::text);

ALTER TABLE "FamilyConnection" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Family members can view connections" ON "FamilyConnection" FOR SELECT
  USING ("fromFamilyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text)
    OR "toFamilyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Family owners can create connections" ON "FamilyConnection" FOR INSERT
  WITH CHECK ("fromFamilyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text AND role IN ('owner','admin')));

ALTER TABLE "FamilyMilestone" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Family members can view milestones" ON "FamilyMilestone" FOR SELECT
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "Members can create milestones" ON "FamilyMilestone" FOR INSERT
  WITH CHECK ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text));

ALTER TABLE "UserContribution" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Family members can view contributions" ON "UserContribution" FOR SELECT
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "System manages contributions" ON "UserContribution" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System updates contributions" ON "UserContribution" FOR UPDATE USING (auth.uid() IS NOT NULL);

ALTER TABLE "Badge" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view badges" ON "Badge" FOR SELECT USING (true);
CREATE POLICY "System manages badges" ON "Badge" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

ALTER TABLE "UserBadge" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Family members can view user badges" ON "UserBadge" FOR SELECT
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text)
    OR "userId" = auth.uid()::text);
CREATE POLICY "System awards badges" ON "UserBadge" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ── Infrastructure / System ────────────────────────────────

ALTER TABLE "ApiKey" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own API keys" ON "ApiKey" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can create own API keys" ON "ApiKey" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can update own API keys" ON "ApiKey" FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can delete own API keys" ON "ApiKey" FOR DELETE USING ("userId" = auth.uid()::text);

ALTER TABLE "WebhookSubscription" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own webhooks" ON "WebhookSubscription" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can create own webhooks" ON "WebhookSubscription" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can update own webhooks" ON "WebhookSubscription" FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can delete own webhooks" ON "WebhookSubscription" FOR DELETE USING ("userId" = auth.uid()::text);

ALTER TABLE "WebhookDelivery" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own webhook deliveries" ON "WebhookDelivery" FOR SELECT
  USING ("webhookId" IN (SELECT id FROM "WebhookSubscription" WHERE "userId" = auth.uid()::text));

ALTER TABLE "OAuthClient" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages OAuth clients insert" ON "OAuthClient" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages OAuth clients select" ON "OAuthClient" FOR SELECT USING (false);

ALTER TABLE "OAuthAuthorizationCode" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages OAuth codes insert" ON "OAuthAuthorizationCode" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages OAuth codes select" ON "OAuthAuthorizationCode" FOR SELECT USING (false);

ALTER TABLE "IdempotencyKey" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages idempotency keys insert" ON "IdempotencyKey" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages idempotency keys select" ON "IdempotencyKey" FOR SELECT USING (false);

ALTER TABLE "ShareableLink" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view shareable links" ON "ShareableLink" FOR SELECT USING (true);
CREATE POLICY "Authenticated users can create shareable links" ON "ShareableLink" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

ALTER TABLE "FeatureFlag" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages feature flags insert" ON "FeatureFlag" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages feature flags select" ON "FeatureFlag" FOR SELECT USING (false);

ALTER TABLE "RelationshipTypeMetadata" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view relationship type metadata" ON "RelationshipTypeMetadata" FOR SELECT USING (true);
CREATE POLICY "System manages relationship type metadata" ON "RelationshipTypeMetadata" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

ALTER TABLE "RelationshipPathCache" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Family members can view relationship path cache" ON "RelationshipPathCache" FOR SELECT
  USING ("familyId" IN (SELECT "familyId" FROM "FamilyMember" WHERE "userId" = auth.uid()::text));
CREATE POLICY "System manages relationship path cache insert" ON "RelationshipPathCache" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System updates relationship path cache" ON "RelationshipPathCache" FOR UPDATE USING (auth.uid() IS NOT NULL);
CREATE POLICY "System deletes relationship path cache" ON "RelationshipPathCache" FOR DELETE USING (auth.uid() IS NOT NULL);

-- ── WhatsApp ────────────────────────────────────────────────

ALTER TABLE "WhatsAppTemplate" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages WhatsApp templates insert" ON "WhatsAppTemplate" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages WhatsApp templates select" ON "WhatsAppTemplate" FOR SELECT USING (false);

ALTER TABLE "WhatsAppConsent" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own WhatsApp consent" ON "WhatsAppConsent" FOR SELECT USING ("userId" = auth.uid()::text);
CREATE POLICY "Users can create WhatsApp consent" ON "WhatsAppConsent" FOR INSERT WITH CHECK ("userId" = auth.uid()::text);
CREATE POLICY "Users can update own WhatsApp consent" ON "WhatsAppConsent" FOR UPDATE USING ("userId" = auth.uid()::text);

ALTER TABLE "WhatsAppOptIn" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System manages WhatsApp opt-ins insert" ON "WhatsAppOptIn" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "System manages WhatsApp opt-ins select" ON "WhatsAppOptIn" FOR SELECT USING (false);

ALTER TABLE "WhatsAppAnalytics" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "System creates WhatsApp analytics" ON "WhatsAppAnalytics" FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "No direct WhatsApp analytics reads" ON "WhatsAppAnalytics" FOR SELECT USING (false);
