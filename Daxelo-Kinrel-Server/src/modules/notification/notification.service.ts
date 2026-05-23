import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import {
  type NotificationEventType,
  type NotificationPriority,
  NOTIFICATION_EVENT_TYPES,
  NOTIFICATION_PRIORITIES,
} from './dto/create-notification.dto';

import { MarkReadDto } from './dto/mark-read.dto';
import { UpdatePreferenceDto } from './dto/update-preference.dto';

// Channel types for notification delivery
type NotificationChannel = 'whatsapp' | 'push' | 'inApp' | 'email';

// ── In-Memory Dedup Cache ──────────────────────────────────────────

const DEDUP_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const dedupCache = new Map<string, number>();

// ── In-Memory Rate Limit Counter ───────────────────────────────────

const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const MAX_PER_USER_PER_HOUR = 20;

interface RateLimitEntry {
  count: number;
  windowStart: number;
}

const rateLimitCounter = new Map<string, RateLimitEntry>();

// ── Periodic Cleanup ───────────────────────────────────────────────

const CLEANUP_INTERVAL_MS = 30 * 60 * 1000;
let cleanupTimer: ReturnType<typeof setInterval> | null = null;

function startCleanupTimer(): void {
  if (cleanupTimer) return;
  cleanupTimer = setInterval(() => {
    const now = Date.now();
    for (const [key, timestamp] of dedupCache.entries()) {
      if (now - timestamp > DEDUP_TTL_MS) {
        dedupCache.delete(key);
      }
    }
    for (const [userId, entry] of rateLimitCounter.entries()) {
      if (now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
        rateLimitCounter.delete(userId);
      }
    }
  }, CLEANUP_INTERVAL_MS);

  if (cleanupTimer && typeof cleanupTimer === 'object' && 'unref' in cleanupTimer) {
    cleanupTimer.unref();
  }
}

startCleanupTimer();

// ── Template Resolvers ─────────────────────────────────────────────

interface NotificationTemplate {
  title: string;
  body: string;
}

type TemplateResolver = (event: {
  type: NotificationEventType;
  payload: Record<string, unknown>;
}) => NotificationTemplate;

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
    body: `Your ${String(e.payload.planName ?? 'subscription')} payment could not be processed. Please update your payment method.`,
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
  'community.festival_greeting': (e) => ({
    title: `${String(e.payload.festivalName ?? 'Festival')} ${String(e.payload.emoji ?? '🎉')}`,
    body: String(e.payload.greeting ?? `Happy ${String(e.payload.festivalName ?? 'Festival')}!`),
  }),
};

// ═════════════════════════════════════════════════════════════════════
// NotificationService
// ═════════════════════════════════════════════════════════════════════

@Injectable()
export class NotificationService {
  private readonly logger = new Logger(NotificationService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ═══════════════════════════════════════════════════════════════════
  // GET /api/notifications — List notifications
  // ═══════════════════════════════════════════════════════════════════

  async listNotifications(options: {
    userId: string;
    read?: string;
    limit?: number;
    offset?: number;
  }) {
    const { userId, read, limit = 20, offset = 0 } = options;

    if (!userId) {
      throw new BadRequestException('userId query parameter is required');
    }

    const where: Record<string, unknown> = { userId };

    if (read !== undefined && read !== null && read !== '') {
      where.read = read === 'true';
    }

    const [notifications, unreadCount] = await Promise.all([
      this.prisma.notification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: Math.min(limit, 100),
        skip: offset,
        include: {
          updates: {
            orderBy: { createdAt: 'desc' },
          },
        },
      }),
      this.prisma.notification.count({
        where: { userId, read: false },
      }),
    ]);

    // Parse JSON channels for client convenience
    const parsedNotifications = notifications.map((n) => ({
      ...n,
      channels: JSON.parse(n.channels) as string[],
    }));

    return {
      notifications: parsedNotifications,
      unreadCount,
      limit,
      offset,
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // PATCH /api/notifications — Mark as read
  // ═══════════════════════════════════════════════════════════════════

  async markAsRead(dto: MarkReadDto) {
    const { userId, notificationIds } = dto;

    if (!userId) {
      throw new BadRequestException('userId is required');
    }

    const now = new Date();
    let count: number;

    if (notificationIds && notificationIds.length > 0) {
      // Mark specific notifications as read
      const result = await this.prisma.notification.updateMany({
        where: {
          id: { in: notificationIds },
          userId,
          read: false,
        },
        data: {
          read: true,
          readAt: now,
        },
      });
      count = result.count;
    } else {
      // Mark all as read for this user
      const result = await this.prisma.notification.updateMany({
        where: {
          userId,
          read: false,
        },
        data: {
          read: true,
          readAt: now,
        },
      });
      count = result.count;
    }

    return { updated: count };
  }

  // ═══════════════════════════════════════════════════════════════════
  // PUT /api/notifications — Update notification preferences
  // ═══════════════════════════════════════════════════════════════════

  async updatePreference(dto: UpdatePreferenceDto) {
    const {
      userId,
      eventType,
      whatsapp,
      push,
      inApp,
      email,
      quietHoursStart,
      quietHoursEnd,
      digestMode,
      maxPerDay,
    } = dto;

    if (!userId || !eventType) {
      throw new BadRequestException('userId and eventType are required');
    }

    // Verify user exists
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Upsert notification preference
    const preference = await this.prisma.notificationPreference.upsert({
      where: {
        userId_eventType: {
          userId,
          eventType,
        },
      },
      update: {
        ...(whatsapp !== undefined ? { whatsapp: Boolean(whatsapp) } : {}),
        ...(push !== undefined ? { push: Boolean(push) } : {}),
        ...(inApp !== undefined ? { inApp: Boolean(inApp) } : {}),
        ...(email !== undefined ? { email: Boolean(email) } : {}),
        ...(quietHoursStart !== undefined ? { quietHoursStart } : {}),
        ...(quietHoursEnd !== undefined ? { quietHoursEnd } : {}),
        ...(digestMode !== undefined ? { digestMode } : {}),
        ...(maxPerDay !== undefined ? { maxPerDay } : {}),
      },
      create: {
        userId,
        eventType,
        whatsapp: whatsapp ?? true,
        push: push ?? true,
        inApp: inApp ?? true,
        email: email ?? false,
        quietHoursStart: quietHoursStart ?? null,
        quietHoursEnd: quietHoursEnd ?? null,
        digestMode: digestMode ?? 'immediate',
        maxPerDay: maxPerDay ?? 10,
      },
    });

    return { preference };
  }

  // ═══════════════════════════════════════════════════════════════════
  // POST /api/notifications — Create notification
  // ═══════════════════════════════════════════════════════════════════

  async createNotification(dto: {
    type: NotificationEventType;
    actorUserId: string;
    targetUserId: string;
    familyId?: string;
    personId?: string;
    payload: Record<string, unknown>;
    priority: NotificationPriority;
  }) {
    const {
      type,
      actorUserId,
      targetUserId,
      familyId,
      personId,
      payload,
      priority,
    } = dto;

    if (!type || !actorUserId || !targetUserId || !payload || !priority) {
      throw new BadRequestException(
        'type, actorUserId, targetUserId, payload, and priority are required',
      );
    }

    if (!NOTIFICATION_PRIORITIES.includes(priority as any)) {
      throw new BadRequestException(
        `priority must be one of: ${NOTIFICATION_PRIORITIES.join(', ')}`,
      );
    }

    // ── Dedup check ────────────────────────────────────────────────
    const now = Date.now();
    const dedupKey = `notif:dedup:${type}:${targetUserId}:${familyId ?? ''}:${personId ?? ''}`;
    const existingDedup = dedupCache.get(dedupKey);
    if (existingDedup && now - existingDedup < DEDUP_TTL_MS) {
      this.logger.log(
        `Dedup: skipping ${type} for ${targetUserId} (key=${dedupKey})`,
      );
      return { deduplicated: true, notificationId: '' };
    }

    // ── Rate limit check ───────────────────────────────────────────
    const rateEntry = rateLimitCounter.get(targetUserId);
    if (rateEntry && now - rateEntry.windowStart < RATE_LIMIT_WINDOW_MS) {
      if (rateEntry.count >= MAX_PER_USER_PER_HOUR) {
        this.logger.log(
          `Rate limited: ${targetUserId} (${rateEntry.count}/${MAX_PER_USER_PER_HOUR})`,
        );
        return { rateLimited: true, notificationId: '' };
      }
      rateEntry.count += 1;
    } else {
      rateLimitCounter.set(targetUserId, { count: 1, windowStart: now });
    }

    // ── Set dedup marker ───────────────────────────────────────────
    dedupCache.set(dedupKey, now);

    // ── Get user notification preferences ──────────────────────────
    const prefs = await this.prisma.notificationPreference.findUnique({
      where: {
        userId_eventType: {
          userId: targetUserId,
          eventType: type,
        },
      },
    });

    // ── Resolve template ───────────────────────────────────────────
    const template = this.resolveTemplate(type, payload);

    // ── Resolve channels ───────────────────────────────────────────
    const channels = this.resolveChannels(prefs, priority);

    // ── Persist notification record ────────────────────────────────
    const record = await this.prisma.notification.create({
      data: {
        userId: targetUserId,
        eventType: type,
        title: template.title,
        body: template.body,
        familyId: familyId ?? null,
        personId: personId ?? null,
        channels: JSON.stringify(channels),
        priority,
        read: false,
      },
    });

    // ── Dispatch to each channel adapter ───────────────────────────
    const delivered: string[] = [];
    const failed: Array<{ channel: string; error: string }> = [];

    for (const channel of channels) {
      try {
        await this.dispatchToChannel(channel, record.id, template, dto);
        delivered.push(channel);
      } catch (err) {
        const errorMessage =
          err instanceof Error ? err.message : String(err);
        this.logger.error(
          `Channel ${channel} failed for notification ${record.id}: ${errorMessage}`,
        );
        failed.push({ channel, error: errorMessage });

        // Record failure in NotificationUpdate
        try {
          await this.prisma.notificationUpdate.create({
            data: {
              notificationId: record.id,
              channel,
              status: 'failed',
              error: errorMessage,
            },
          });
        } catch (dbErr) {
          this.logger.error(
            'Failed to record channel failure:',
            dbErr instanceof Error ? dbErr.message : String(dbErr),
          );
        }
      }
    }

    this.logger.log(`Notification created: ${record.id} for user: ${targetUserId}`);

    return {
      notification: {
        id: record.id,
        userId: record.userId,
        eventType: record.eventType,
        title: record.title,
        body: record.body,
        familyId: record.familyId,
        personId: record.personId,
        channels,
        priority: record.priority,
        read: record.read,
        readAt: record.readAt,
        actionUrl: record.actionUrl,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt,
      },
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Smart Reminders
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Check for upcoming birthdays and create reminder notifications.
   * Called by the scheduler (cron).
   */
  async checkBirthdays(): Promise<number> {
    this.logger.log('Checking for upcoming birthdays...');

    const today = new Date();
    const upcomingDays = [1, 3, 7]; // 1 day, 3 days, 7 days before

    let notificationCount = 0;

    // Find all persons with a dateOfBirth who are not deceased
    const persons = await this.prisma.person.findMany({
      where: {
        dateOfBirth: { not: null },
        isDeceased: false,
        deletedAt: null,
      },
      include: {
        family: {
          include: {
            members: {
              select: { userId: true },
            },
          },
        },
      },
    });

    for (const person of persons) {
      if (!person.dateOfBirth) continue;

      const dob = person.dateOfBirth;
      // Calculate this year's birthday
      const thisYearBirthday = new Date(
        today.getFullYear(),
        dob.getMonth(),
        dob.getDate(),
      );

      for (const daysAhead of upcomingDays) {
        const targetDate = new Date(today);
        targetDate.setDate(targetDate.getDate() + daysAhead);

        if (
          thisYearBirthday.getMonth() === targetDate.getMonth() &&
          thisYearBirthday.getDate() === targetDate.getDate()
        ) {
          // Birthday is daysAhead days away — notify family members
          for (const member of person.family.members) {
            try {
              await this.createNotification({
                type: 'person.birthday_upcoming',
                actorUserId: 'system',
                targetUserId: member.userId,
                familyId: person.familyId,
                personId: person.id,
                payload: {
                  personName: person.name,
                  personId: person.id,
                  daysUntil: daysAhead,
                },
                priority: daysAhead === 1 ? 'high' : 'normal',
              });
              notificationCount++;
            } catch {
              // Skip if already sent (dedup) or rate limited
            }
          }
          break; // Only notify once per person (closest upcoming day)
        }
      }
    }

    this.logger.log(`Birthday check complete: ${notificationCount} notifications sent`);
    return notificationCount;
  }

  /**
   * Check for upcoming anniversaries and create reminder notifications.
   * Called by the scheduler (cron).
   */
  async checkAnniversaries(): Promise<number> {
    this.logger.log('Checking for upcoming anniversaries...');

    const today = new Date();
    const upcomingDays = [1, 7]; // 1 day, 7 days before

    let notificationCount = 0;

    // Find all spouse relationships where we can derive anniversary info
    const spouseRelationships = await this.prisma.relationship.findMany({
      where: {
        type: 'spouse',
      },
      include: {
        fromPerson: {
          include: {
            family: {
              include: {
                members: { select: { userId: true } },
              },
            },
          },
        },
        toPerson: true,
      },
    });

    for (const rel of spouseRelationships) {
      // Use createdAt as proxy for anniversary date if no specific date available
      const anniversaryDate = new Date(rel.createdAt);
      const thisYearAnniversary = new Date(
        today.getFullYear(),
        anniversaryDate.getMonth(),
        anniversaryDate.getDate(),
      );

      for (const daysAhead of upcomingDays) {
        const targetDate = new Date(today);
        targetDate.setDate(targetDate.getDate() + daysAhead);

        if (
          thisYearAnniversary.getMonth() === targetDate.getMonth() &&
          thisYearAnniversary.getDate() === targetDate.getDate()
        ) {
          const family = rel.fromPerson.family;
          for (const member of family.members) {
            try {
              await this.createNotification({
                type: 'person.anniversary_upcoming',
                actorUserId: 'system',
                targetUserId: member.userId,
                familyId: family.id,
                personId: rel.fromPerson.id,
                payload: {
                  personName: `${rel.fromPerson.name} & ${rel.toPerson.name}`,
                  daysUntil: daysAhead,
                },
                priority: 'normal',
              });
              notificationCount++;
            } catch {
              // Skip if already sent (dedup) or rate limited
            }
          }
          break;
        }
      }
    }

    this.logger.log(`Anniversary check complete: ${notificationCount} notifications sent`);
    return notificationCount;
  }

  /**
   * Check for upcoming festivals and create greeting notifications.
   * Uses a static festival calendar for Indian festivals.
   */
  async checkFestivals(): Promise<number> {
    this.logger.log('Checking for upcoming festivals...');

    const today = new Date();
    const year = today.getFullYear();

    // Static festival dates (approximate for each year)
    const festivals: Array<{ name: string; date: Date; emoji: string }> = [
      { name: 'Diwali', date: new Date(year, 9, 20), emoji: '🪔' }, // Approx Oct/Nov
      { name: 'Holi', date: new Date(year, 2, 14), emoji: '🎨' }, // Approx March
      { name: 'Navratri', date: new Date(year, 9, 3), emoji: '🪘' }, // Approx Oct
      { name: 'Raksha Bandhan', date: new Date(year, 7, 19), emoji: '🧵' }, // Approx Aug
      { name: 'Ganesh Chaturthi', date: new Date(year, 8, 7), emoji: '🙏' }, // Approx Sep
      { name: 'Dussehra', date: new Date(year, 9, 12), emoji: '🏹' }, // Approx Oct
      { name: 'Makar Sankranti', date: new Date(year, 0, 14), emoji: '🪁' }, // Jan 14
      { name: 'Pongal', date: new Date(year, 0, 14), emoji: '🌾' }, // Jan 14
      { name: 'Onam', date: new Date(year, 7, 20), emoji: '🌺' }, // Approx Aug/Sep
      { name: 'Baisakhi', date: new Date(year, 3, 13), emoji: '🎉' }, // Apr 13
    ];

    let notificationCount = 0;

    for (const festival of festivals) {
      const daysUntil = Math.ceil(
        (festival.date.getTime() - today.getTime()) / (1000 * 60 * 60 * 24),
      );

      // Only notify 1 day before and on the day
      if (daysUntil === 1 || daysUntil === 0) {
        // Get all users who have families
        const users = await this.prisma.user.findMany({
          where: {
            families: { some: {} },
          },
          select: { id: true },
        });

        for (const user of users) {
          try {
            await this.createNotification({
              type: 'community.festival_greeting' as NotificationEventType,
              actorUserId: 'system',
              targetUserId: user.id,
              payload: {
                festivalName: festival.name,
                emoji: festival.emoji,
                daysUntil,
                greeting: daysUntil === 0
                  ? `Happy ${festival.name}! ${festival.emoji}`
                  : `${festival.name} is tomorrow! ${festival.emoji}`,
              },
              priority: 'low',
            });
            notificationCount++;
          } catch {
            // Skip if already sent (dedup) or rate limited
          }
        }
      }
    }

    this.logger.log(`Festival check complete: ${notificationCount} notifications sent`);
    return notificationCount;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Private Helpers
  // ═══════════════════════════════════════════════════════════════════

  private resolveTemplate(
    type: NotificationEventType,
    payload: Record<string, unknown>,
  ): NotificationTemplate {
    const resolver = templateResolvers[type];

    if (resolver) {
      return resolver({ type, payload });
    }

    // Fallback: use event type as title and stringify payload as body
    return {
      title: type
        .replace(/[._]/g, ' ')
        .replace(/\b\w/g, (c) => c.toUpperCase()),
      body: JSON.stringify(payload),
    };
  }

  private resolveChannels(
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

    // Ensure at least inApp is always present
    if (!channels.includes('inApp')) {
      channels.push('inApp');
    }

    return channels;
  }

  private async dispatchToChannel(
    channel: string,
    notificationId: string,
    template: NotificationTemplate,
    event: {
      type: NotificationEventType;
      actorUserId: string;
      targetUserId: string;
      familyId?: string;
      personId?: string;
      payload: Record<string, unknown>;
      priority: NotificationPriority;
    },
  ): Promise<void> {
    switch (channel) {
      case 'inApp': {
        // In-app notifications are always delivered since they're persisted in the db
        await this.prisma.notificationUpdate.create({
          data: {
            notificationId,
            channel: 'inApp',
            status: 'delivered',
          },
        });
        break;
      }

      case 'push': {
        // Push notification — record as delivered for now
        // In production, integrate with FCM/APNs
        await this.prisma.notificationUpdate.create({
          data: {
            notificationId,
            channel: 'push',
            status: 'delivered',
          },
        });
        break;
      }

      case 'whatsapp': {
        // WhatsApp notification — check consent first
        const consent = await this.prisma.whatsAppConsent.findUnique({
          where: { userId: event.targetUserId },
        });

        if (!consent?.optedIn) {
          await this.prisma.notificationUpdate.create({
            data: {
              notificationId,
              channel: 'whatsapp',
              status: 'failed',
              error: 'User has not opted in to WhatsApp notifications',
            },
          });
          return;
        }

        // In production, call WhatsApp Business API
        await this.prisma.notificationUpdate.create({
          data: {
            notificationId,
            channel: 'whatsapp',
            status: 'delivered',
          },
        });
        break;
      }

      case 'email': {
        // Email notification — record as delivered for now
        // In production, integrate with email service
        await this.prisma.notificationUpdate.create({
          data: {
            notificationId,
            channel: 'email',
            status: 'delivered',
          },
        });
        break;
      }

      default:
        this.logger.warn(`Unknown channel: ${channel}`);
    }
  }
}
