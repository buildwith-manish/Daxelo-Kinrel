// DAXELO KINREL — Notification Engine
// Pack 04: WhatsApp Platform — Notification Pipeline
//
// Central notification processing engine that handles:
// - Deduplication (24h in-memory cache)
// - Rate limiting (max 20 per user per hour, in-memory counter)
// - User preference resolution
// - Template resolution with Indian context
// - Channel routing based on priority and preferences
// - Persisting notification records
// - Dispatching to channel adapters

import { db } from '@/lib/db';
import {
  type NotificationEvent,
  type NotificationChannel,
  type NotificationTemplate,
  type NotificationProcessResult,
  type NotificationEventType,
} from './event-schema';
import { sendWhatsAppNotification } from './channels/whatsapp';
import { sendPushNotification } from './channels/push';
import { sendInAppNotification } from './channels/in-app';
import { sendEmailNotification } from './channels/email';

// ── In-Memory Dedup Cache ──────────────────────────────────────────────
// Maps dedupKey → timestamp of when the marker was set.
// Entries are cleaned up after 24 hours via a periodic sweep.

const DEDUP_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const dedupCache = new Map<string, number>();

// ── In-Memory Rate Limit Counter ───────────────────────────────────────
// Maps userId → { count, windowStart }.
// Each user can send at most MAX_PER_USER_PER_HOUR notifications per hour.

const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const MAX_PER_USER_PER_HOUR = 20;

interface RateLimitEntry {
  count: number;
  windowStart: number;
}

const rateLimitCounter = new Map<string, RateLimitEntry>();

// ── Periodic Cleanup ───────────────────────────────────────────────────
// Clean up expired dedup markers and rate limit windows every 30 minutes.

const CLEANUP_INTERVAL_MS = 30 * 60 * 1000;

let cleanupTimer: ReturnType<typeof setInterval> | null = null;

function startCleanupTimer(): void {
  if (cleanupTimer) return;
  cleanupTimer = setInterval(() => {
    const now = Date.now();

    // Clean expired dedup markers
    for (const [key, timestamp] of dedupCache.entries()) {
      if (now - timestamp > DEDUP_TTL_MS) {
        dedupCache.delete(key);
      }
    }

    // Clean expired rate limit windows
    for (const [userId, entry] of rateLimitCounter.entries()) {
      if (now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
        rateLimitCounter.delete(userId);
      }
    }
  }, CLEANUP_INTERVAL_MS);

  // Prevent the timer from keeping the process alive
  if (cleanupTimer && typeof cleanupTimer === 'object' && 'unref' in cleanupTimer) {
    cleanupTimer.unref();
  }
}

startCleanupTimer();

// ── Template Resolvers ─────────────────────────────────────────────────
// Map each event type to a function that resolves the notification title
// and body. Uses Indian context: emoji, cultural references, and IST timezone.

type TemplateResolver = (event: NotificationEvent) => NotificationTemplate;

const templateResolvers: Record<NotificationEventType, TemplateResolver> = {
  'family.member_added': (e) => ({
    title: 'New Family Member! 🎉',
    body: `${String(e.payload.addedByName ?? 'Someone')} added ${String(e.payload.personName ?? 'a new member')} to your family tree.`,
  }),

  'family.member_removed': (e) => ({
    title: 'Family Member Removed',
    body: `${String(e.payload.removedByName ?? 'Someone')} was removed from the ${String(e.payload.familyName ?? 'family')} tree.`,
  }),

  'family.invitation_sent': (e) => ({
    title: 'Family Invitation 💌',
    body: `${String(e.payload.inviterName ?? 'Someone')} invited you to join the ${String(e.payload.familyName ?? 'family')} family on Daxelo Kinrel.`,
  }),

  'family.invitation_accepted': (e) => ({
    title: 'Invitation Accepted! 🎉',
    body: `${String(e.payload.acceptedByName ?? 'Someone')} accepted your invitation to join the family.`,
  }),

  'family.role_changed': (e) => ({
    title: 'Role Updated',
    body: `Your role in the ${String(e.payload.familyName ?? 'family')} family was changed to ${String(e.payload.newRole ?? 'member')}.`,
  }),

  'person.birthday_upcoming': (e) => ({
    title: 'Upcoming Birthday 🎂',
    body: `${String(e.payload.personName ?? 'Someone')}'s birthday is in ${String(e.payload.daysUntil ?? 'a few')} days! Don't forget to wish them.`,
  }),

  'person.anniversary_upcoming': (e) => ({
    title: 'Upcoming Anniversary 💐',
    body: `${String(e.payload.personName ?? 'Someone')}'s anniversary is in ${String(e.payload.daysUntil ?? 'a few')} days. Plan something special!`,
  }),

  'person.deceased_memorial': (e) => ({
    title: 'Memorial Notice 🙏',
    body: `A memorial has been created for ${String(e.payload.personName ?? 'a family member')}. You can share your memories and condolences.`,
  }),

  'person.health_alert': (e) => ({
    title: 'Health Alert ⚕️',
    body: `Health update for ${String(e.payload.personName ?? 'a family member')}: ${String(e.payload.alertMessage ?? 'Please check the app for details.')}`,
  }),

  'relationship.added': (e) => ({
    title: 'New Relationship 🔗',
    body: `${String(e.payload.personName ?? 'Someone')} is now marked as ${String(e.payload.relationshipType ?? 'related')} in your family tree.`,
  }),

  'relationship.suggested': (e) => ({
    title: 'Relationship Suggestion 💡',
    body: `Daxelo Kinrel suggests that ${String(e.payload.personName ?? 'someone')} might be ${String(e.payload.suggestedRelationship ?? 'related')}. Review and confirm?`,
  }),

  'subscription.payment_failed': (e) => ({
    title: 'Payment Failed 💳',
    body: `Your ${String(e.payload.planName ?? 'subscription')} payment could not be processed. Please update your payment method to continue enjoying premium features.`,
  }),

  'subscription.trial_ending': (e) => ({
    title: 'Trial Ending Soon ⏰',
    body: `Your ${String(e.payload.planName ?? 'pro')} trial ends in ${String(e.payload.daysRemaining ?? 'a few')} days. Upgrade now to keep all features!`,
  }),

  'subscription.renewed': (e) => ({
    title: 'Subscription Renewed ✅',
    body: `Your ${String(e.payload.planName ?? 'subscription')} has been renewed successfully. Enjoy another period of premium features!`,
  }),

  'ai.suggestion_ready': (e) => ({
    title: 'AI Suggestion Ready 🤖',
    body: `Daxelo Kinrel AI has new suggestions for your family tree. ${String(e.payload.suggestionSummary ?? 'Check the app for details.')}`,
  }),

  'system.maintenance': (e) => ({
    title: 'Scheduled Maintenance 🔧',
    body: `Daxelo Kinrel will undergo maintenance on ${String(e.payload.scheduledTime ?? 'the scheduled time')}. ${String(e.payload.estimatedDuration ?? '')}`,
  }),

  'community.mention': (e) => ({
    title: 'You Were Mentioned 📣',
    body: `${String(e.payload.mentionedByName ?? 'Someone')} mentioned you in a community post: "${String(e.payload.preview ?? '')}"`,
  }),

  'community.comment': (e) => ({
    title: 'New Comment 💬',
    body: `${String(e.payload.commentedByName ?? 'Someone')} commented on your post: "${String(e.payload.preview ?? '')}"`,
  }),
};

// ── Notification Engine ────────────────────────────────────────────────

export class NotificationEngine {
  /**
   * Process a notification event through the full pipeline:
   * 1. Dedup check using event.dedupKey
   * 2. Rate limit check
   * 3. Get user notification preferences from db
   * 4. Set dedup marker
   * 5. Resolve template (map event type to title/body)
   * 6. Resolve channels based on prefs and priority
   * 7. Persist notification record in db
   * 8. Dispatch to each channel adapter
   */
  async process(event: NotificationEvent): Promise<NotificationProcessResult> {
    const result: NotificationProcessResult = {
      notificationId: '',
      channels: [],
      delivered: [],
      failed: [],
      deduplicated: false,
      rateLimited: false,
    };

    try {
      // ── Step 1: Dedup check ─────────────────────────────────────────
      const dedupKey = `notif:dedup:${event.dedupKey}`;
      const existingDedup = dedupCache.get(dedupKey);
      if (existingDedup && Date.now() - existingDedup < DEDUP_TTL_MS) {
        console.log(`[NotificationEngine] Dedup: skipping ${event.type} for ${event.targetUserId} (key=${event.dedupKey})`);
        result.deduplicated = true;
        return result;
      }

      // ── Step 2: Rate limit check ────────────────────────────────────
      const now = Date.now();
      const rateEntry = rateLimitCounter.get(event.targetUserId);

      if (rateEntry && now - rateEntry.windowStart < RATE_LIMIT_WINDOW_MS) {
        if (rateEntry.count >= MAX_PER_USER_PER_HOUR) {
          console.log(`[NotificationEngine] Rate limited: ${event.targetUserId} (${rateEntry.count}/${MAX_PER_USER_PER_HOUR})`);
          result.rateLimited = true;
          return result;
        }
        rateEntry.count += 1;
      } else {
        rateLimitCounter.set(event.targetUserId, { count: 1, windowStart: now });
      }

      // ── Step 3: Get user notification preferences ───────────────────
      const prefs = await db.notificationPreference.findUnique({
        where: {
          userId_eventType: {
            userId: event.targetUserId,
            eventType: event.type,
          },
        },
      });

      // ── Step 4: Set dedup marker ────────────────────────────────────
      dedupCache.set(dedupKey, now);

      // ── Step 5: Resolve template ────────────────────────────────────
      const template = this.resolveTemplate(event);

      // ── Step 6: Resolve channels ────────────────────────────────────
      const channels = this.resolveChannels(prefs, event.priority);
      result.channels = channels;

      // ── Step 7: Persist notification record ─────────────────────────
      const record = await db.notification.create({
        data: {
          userId: event.targetUserId,
          eventType: event.type,
          title: template.title,
          body: template.body,
          familyId: event.familyId ?? null,
          personId: event.personId ?? null,
          channels: JSON.stringify(channels),
          priority: event.priority,
          read: false,
        },
      });

      result.notificationId = record.id;

      // ── Step 8: Dispatch to each channel adapter ────────────────────
      for (const channel of channels) {
        try {
          await this.dispatchToChannel(channel, record.id, template, event);

          if (channel === 'inApp') {
            // inApp is always considered delivered since it's persisted
            result.delivered.push(channel as NotificationChannel);
          } else {
            result.delivered.push(channel as NotificationChannel);
          }
        } catch (err) {
          const errorMessage = err instanceof Error ? err.message : String(err);
          console.error(`[NotificationEngine] Channel ${channel} failed for notification ${record.id}:`, errorMessage);
          result.failed.push({
            channel: channel as NotificationChannel,
            error: errorMessage,
          });

          // Record failure in NotificationUpdate
          try {
            await db.notificationUpdate.create({
              data: {
                notificationId: record.id,
                channel,
                status: 'failed',
                error: errorMessage,
              },
            });
          } catch (dbErr) {
            console.error('[NotificationEngine] Failed to record channel failure:', dbErr);
          }
        }
      }

      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error('[NotificationEngine] Fatal error processing event:', {
        eventId: event.id,
        eventType: event.type,
        targetUserId: event.targetUserId,
        error: errorMessage,
      });

      // If we have a notification ID, record the failure
      if (result.notificationId) {
        try {
          await db.notificationUpdate.create({
            data: {
              notificationId: result.notificationId,
              channel: 'engine',
              status: 'failed',
              error: errorMessage,
            },
          });
        } catch {
          // Best effort
        }
      }

      return result;
    }
  }

  /**
   * Resolve which channels to use for this notification.
   *
   * - If priority is 'critical', all channels are used regardless of prefs
   * - Otherwise, user preferences are respected
   * - If no preferences exist, defaults to push + inApp
   */
  resolveChannels(
    prefs: {
      whatsapp: boolean;
      push: boolean;
      inApp: boolean;
      email: boolean;
    } | null,
    priority: string,
  ): NotificationChannel[] {
    // Critical notifications go to all channels
    if (priority === 'critical') {
      return ['whatsapp', 'push', 'inApp', 'email'] as NotificationChannel[];
    }

    const channels: NotificationChannel[] = [];

    if (prefs) {
      if (prefs.whatsapp) channels.push('whatsapp');
      if (prefs.push) channels.push('push');
      if (prefs.inApp) channels.push('inApp');
      if (prefs.email) channels.push('email');
    } else {
      // Default channels when no preferences are set
      channels.push('push', 'inApp');
    }

    // Ensure at least inApp is always present (it's the minimum viable channel)
    if (!channels.includes('inApp')) {
      channels.push('inApp');
    }

    return channels;
  }

  /**
   * Resolve the notification template for an event type.
   * Uses the template resolvers map with Indian context.
   * Falls back to a generic template if the event type has no resolver.
   */
  resolveTemplate(event: NotificationEvent): NotificationTemplate {
    const resolver = templateResolvers[event.type];

    if (resolver) {
      return resolver(event);
    }

    // Fallback: use event type as title and stringify payload as body
    return {
      title: event.type.replace(/[._]/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
      body: JSON.stringify(event.payload),
    };
  }

  /**
   * Dispatch a notification to a specific channel adapter.
   * Each adapter is responsible for its own error handling and
   * delivery status recording.
   */
  private async dispatchToChannel(
    channel: string,
    notificationId: string,
    template: NotificationTemplate,
    event: NotificationEvent,
  ): Promise<void> {
    switch (channel) {
      case 'whatsapp': {
        const result = await sendWhatsAppNotification(
          event.targetUserId,
          notificationId,
          template,
          event,
        );
        if (!result.success && !result.skipped) {
          throw new Error(result.error ?? 'WhatsApp send failed');
        }
        break;
      }

      case 'push': {
        const result = await sendPushNotification(
          event.targetUserId,
          notificationId,
          template,
          event,
        );
        if (!result.success) {
          throw new Error(result.error ?? 'Push send failed');
        }
        break;
      }

      case 'inApp': {
        const result = await sendInAppNotification(
          event.targetUserId,
          notificationId,
          template,
          event,
        );
        if (!result.success) {
          throw new Error(result.error ?? 'In-app delivery failed');
        }
        break;
      }

      case 'email': {
        const result = await sendEmailNotification(
          event.targetUserId,
          notificationId,
          template,
          event,
        );
        if (!result.success && !result.skipped) {
          throw new Error(result.error ?? 'Email send failed');
        }
        break;
      }

      default:
        console.warn(`[NotificationEngine] Unknown channel: ${channel}`);
    }
  }

  /**
   * Clear all in-memory caches. Useful for testing.
   */
  clearCaches(): void {
    dedupCache.clear();
    rateLimitCounter.clear();
  }

  /**
   * Get current dedup cache size. Useful for monitoring.
   */
  getDedupCacheSize(): number {
    return dedupCache.size;
  }

  /**
   * Get current rate limit counter size. Useful for monitoring.
   */
  getRateLimitCounterSize(): number {
    return rateLimitCounter.size;
  }
}

// ── Singleton Export ───────────────────────────────────────────────────

export const notificationEngine = new NotificationEngine();
