import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { FcmService } from './fcm.service';

// ── Types & Interfaces ─────────────────────────────────────────────────

interface Invitation {
  id: string;
  token: string;
  familyId: string;
  inviterId: string;
  recipientEmail?: string | null;
  recipientPhone?: string | null;
  recipientName?: string | null;
  status: string;
  role: string;
  channel: string;
  family?: { id: string; name: string };
  inviter?: { id: string; name: string; email: string };
}

interface CreateNotificationParams {
  userId: string;
  eventType: string;
  title: string;
  body: string;
  familyId?: string;
  personId?: string;
  priority?: 'critical' | 'high' | 'normal' | 'low';
  actionUrl?: string;
  channels?: string[];
  data?: Record<string, string>;
}

export interface PaginatedNotifications {
  notifications: Array<{
    id: string;
    userId: string;
    eventType: string;
    title: string;
    body: string;
    familyId: string | null;
    personId: string | null;
    channels: string;
    priority: string;
    read: boolean;
    readAt: Date | null;
    actionUrl: string | null;
    createdAt: Date;
    updatedAt: Date;
  }>;
  total: number;
  page: number;
  limit: number;
  totalPages: number;
  unreadCount: number;
}

// ── Constants ──────────────────────────────────────────────────────────

/** Critical event types that bypass standard rate limits */
const CRITICAL_EVENT_TYPES = new Set([
  'invitation_received',
  'invitation_accepted',
  'security_alert',
  'account_recovery',
]);

/** Max notifications per user per day */
const MAX_DAILY_NON_CRITICAL = 10;
const MAX_DAILY_CRITICAL = 50;

/** Default IST timezone */
const DEFAULT_TIMEZONE = 'Asia/Kolkata';

/** All known notification event types with defaults */
const EVENT_TYPE_DEFAULTS: Record<string, { push: boolean; inApp: boolean; email: boolean; whatsapp: boolean }> = {
  birthday_reminder:       { push: true, inApp: true, email: false, whatsapp: true },
  anniversary_reminder:    { push: true, inApp: true, email: false, whatsapp: true },
  invitation_received:     { push: true, inApp: true, email: true,  whatsapp: false },
  invitation_accepted:     { push: true, inApp: true, email: false, whatsapp: false },
  new_relative:            { push: true, inApp: true, email: false, whatsapp: false },
  profile_update:          { push: true, inApp: true, email: false, whatsapp: false },
  security_alert:          { push: true, inApp: true, email: true,  whatsapp: false },
  account_recovery:        { push: true, inApp: true, email: true,  whatsapp: false },
};

// ── Service ────────────────────────────────────────────────────────────

@Injectable()
export class NotificationsV2Service {
  private readonly logger = new Logger(NotificationsV2Service.name);

  /** In-memory rate limit counters: userId -> { date, count, criticalCount } */
  private readonly rateLimitCache = new Map<
    string,
    { date: string; count: number; criticalCount: number }
  >();

  constructor(
    private readonly prisma: PrismaService,
    private readonly fcmService: FcmService,
  ) {}

  // ── Specific notification triggers ─────────────────────────────────

  /**
   * New family invitation received.
   * Notifies the recipient user (matched by email or phone).
   */
  async notifyNewInvitation(invitation: Invitation): Promise<void> {
    try {
      // Find the recipient user by email or phone
      let recipientUser: { id: string; name: string | null } | null = null;

      if (invitation.recipientEmail) {
        recipientUser = await this.prisma.user.findUnique({
          where: { email: invitation.recipientEmail },
          select: { id: true, name: true },
        });
      }

      if (!recipientUser && invitation.recipientPhone) {
        recipientUser = await this.prisma.user.findFirst({
          where: { phone: invitation.recipientPhone },
          select: { id: true, name: true },
        });
      }

      if (!recipientUser) {
        this.logger.debug(
          `No registered user found for invitation ${invitation.id} — skipping in-app notification`,
        );
        return;
      }

      const familyName = invitation.family?.name || 'a family';
      const inviterName = invitation.inviter?.name || 'Someone';

      await this.createAndSend({
        userId: recipientUser.id,
        eventType: 'invitation_received',
        title: '📬 New Family Invitation',
        body: `${inviterName} invited you to join "${familyName}"`,
        familyId: invitation.familyId,
        priority: 'critical',
        actionUrl: `/invitations/${invitation.id}`,
        data: {
          type: 'invitation_received',
          invitationId: invitation.id,
          familyId: invitation.familyId,
          familyName,
          inviterName,
        },
      });

      this.logger.log(
        `Notified user ${recipientUser.id} about invitation ${invitation.id}`,
      );
    } catch (error: any) {
      this.logger.error(
        `Error in notifyNewInvitation: ${error?.message}`,
        error?.stack,
      );
    }
  }

  /**
   * Invitation was accepted.
   * Notifies the original inviter that their invitation was accepted.
   */
  async notifyInvitationAccepted(
    familyId: string,
    newMemberName: string,
    inviterId: string,
  ): Promise<void> {
    try {
      const family = await this.prisma.family.findUnique({
        where: { id: familyId },
        select: { name: true },
      });

      const familyName = family?.name || 'the family';

      await this.createAndSend({
        userId: inviterId,
        eventType: 'invitation_accepted',
        title: '🎉 Invitation Accepted',
        body: `${newMemberName} accepted your invitation to join "${familyName}"`,
        familyId,
        priority: 'critical',
        actionUrl: `/family/${familyId}`,
        data: {
          type: 'invitation_accepted',
          familyId,
          familyName,
          newMemberName,
        },
      });

      this.logger.log(
        `Notified inviter ${inviterId} that ${newMemberName} accepted invitation to family ${familyId}`,
      );
    } catch (error: any) {
      this.logger.error(
        `Error in notifyInvitationAccepted: ${error?.message}`,
        error?.stack,
      );
    }
  }

  /**
   * New relative added to family.
   * Notifies all family members except the one who added the relative.
   */
  async notifyNewRelative(
    familyId: string,
    personName: string,
    relationship: string,
  ): Promise<void> {
    try {
      const family = await this.prisma.family.findUnique({
        where: { id: familyId },
        select: { name: true },
      });

      const familyName = family?.name || 'your family';
      const relationshipLabel = relationship || 'a family member';

      // Get all family members who are registered users
      const familyMembers = await this.prisma.familyMember.findMany({
        where: { familyId },
        include: {
          user: { select: { id: true, name: true } },
        },
      });

      if (familyMembers.length === 0) return;

      const userIds = familyMembers.map((m) => m.user.id);

      // Send individual notifications to each family member
      for (const member of familyMembers) {
        try {
          await this.createAndSend({
            userId: member.user.id,
            eventType: 'new_relative',
            title: '👨‍👩‍👧‍👦 New Relative Added',
            body: `${personName} (${relationshipLabel}) was added to "${familyName}"`,
            familyId,
            priority: 'normal',
            actionUrl: `/family/${familyId}`,
            data: {
              type: 'new_relative',
              familyId,
              familyName,
              personName,
              relationship: relationshipLabel,
            },
          });
        } catch (error: any) {
          this.logger.error(
            `Error notifying user ${member.user.id} about new relative: ${error?.message}`,
          );
        }
      }

      this.logger.log(
        `Notified ${familyMembers.length} member(s) of family ${familyId} about new relative "${personName}"`,
      );
    } catch (error: any) {
      this.logger.error(
        `Error in notifyNewRelative: ${error?.message}`,
        error?.stack,
      );
    }
  }

  /**
   * Profile updated in a family the user belongs to.
   * Notifies all other family members about the profile update.
   */
  async notifyProfileUpdate(
    familyId: string,
    personName: string,
    updatedFields: string[],
  ): Promise<void> {
    try {
      const family = await this.prisma.family.findUnique({
        where: { id: familyId },
        select: { name: true },
      });

      const familyName = family?.name || 'your family';
      const fieldsSummary =
        updatedFields.length > 3
          ? `${updatedFields.slice(0, 3).join(', ')} and more`
          : updatedFields.join(', ');

      const familyMembers = await this.prisma.familyMember.findMany({
        where: { familyId },
        include: {
          user: { select: { id: true, name: true } },
        },
      });

      if (familyMembers.length === 0) return;

      for (const member of familyMembers) {
        try {
          await this.createAndSend({
            userId: member.user.id,
            eventType: 'profile_update',
            title: '✏️ Profile Updated',
            body: `${personName}'s profile was updated in "${familyName}" — ${fieldsSummary}`,
            familyId,
            priority: 'low',
            actionUrl: `/family/${familyId}`,
            data: {
              type: 'profile_update',
              familyId,
              familyName,
              personName,
              updatedFields: JSON.stringify(updatedFields),
            },
          });
        } catch (error: any) {
          this.logger.error(
            `Error notifying user ${member.user.id} about profile update: ${error?.message}`,
          );
        }
      }

      this.logger.log(
        `Notified ${familyMembers.length} member(s) of family ${familyId} about profile update for "${personName}"`,
      );
    } catch (error: any) {
      this.logger.error(
        `Error in notifyProfileUpdate: ${error?.message}`,
        error?.stack,
      );
    }
  }

  /**
   * Birthday reminder — called by cron job.
   * Queries all persons with dateOfBirth matching today (month + day).
   * For each birthday person, finds all family members and sends notifications.
   * Respects notification preferences and quiet hours.
   * Returns the number of push notifications sent.
   */
  async sendBirthdayReminders(): Promise<number> {
    this.logger.log('🎂 Running birthday reminder job...');

    try {
      const now = new Date();
      // Use IST for date comparison
      const istNow = this.toIST(now);
      const todayMonth = istNow.getMonth(); // 0-11
      const todayDay = istNow.getDate(); // 1-31

      // Query all persons with a dateOfBirth that matches today's month+day
      const birthdayPersons = await this.prisma.person.findMany({
        where: {
          dateOfBirth: { not: null },
          isDeceased: false,
          deletedAt: null,
        },
        select: {
          id: true,
          name: true,
          familyId: true,
          dateOfBirth: true,
        },
      });

      // Filter to only those whose birthday is today
      const todayBirthdays = birthdayPersons.filter((person) => {
        if (!person.dateOfBirth) return false;
        const dob = new Date(person.dateOfBirth);
        return dob.getMonth() === todayMonth && dob.getDate() === todayDay;
      });

      if (todayBirthdays.length === 0) {
        this.logger.log('🎂 No birthdays found for today');
        return 0;
      }

      this.logger.log(
        `🎂 Found ${todayBirthdays.length} birthday(s) today`,
      );

      let pushSent = 0;

      for (const birthdayPerson of todayBirthdays) {
        try {
          const memberName = birthdayPerson.name;
          const title = '🎂 Birthday Reminder';
          const body = `It's ${memberName}'s birthday today! 🎉`;

          // Find all family members who are registered users
          const familyMembers = await this.prisma.familyMember.findMany({
            where: { familyId: birthdayPerson.familyId },
            include: {
              user: { select: { id: true, name: true } },
            },
          });

          if (familyMembers.length === 0) {
            this.logger.debug(
              `No family members to notify for ${memberName}'s birthday in family ${birthdayPerson.familyId}`,
            );
            continue;
          }

          // Get family name for context
          const family = await this.prisma.family.findUnique({
            where: { id: birthdayPerson.familyId },
            select: { name: true },
          });

          const familyName = family?.name;

          for (const member of familyMembers) {
            try {
              // Check notification preferences
              const pref = await this.getOrCreatePreference(
                member.user.id,
                'birthday_reminder',
              );

              // Check quiet hours — if in quiet hours, only create in-app notification
              const inQuietHours = this.isInQuietHours(
                pref.quietHoursStart,
                pref.quietHoursEnd,
                pref.quietHoursTimezone || DEFAULT_TIMEZONE,
              );

              // Always create in-app notification if enabled
              if (pref.inApp) {
                await this.sendInAppNotification(
                  member.user.id,
                  title,
                  body,
                  'birthday_reminder',
                  `/family/${birthdayPerson.familyId}`,
                  birthdayPerson.familyId,
                  birthdayPerson.id,
                  'normal',
                );
              }

              // Send push if enabled and not in quiet hours
              if (pref.push && !inQuietHours) {
                const notificationData: Record<string, string> = {
                  type: 'birthday_reminder',
                  personId: birthdayPerson.id,
                  personName: memberName,
                  familyId: birthdayPerson.familyId,
                };

                if (familyName) {
                  notificationData.familyName = familyName;
                }

                await this.sendPushNotification(
                  member.user.id,
                  title,
                  body,
                  notificationData,
                );
                pushSent++;
              } else if (inQuietHours) {
                this.logger.debug(
                  `User ${member.user.id} in quiet hours — skipping push for birthday reminder`,
                );
              }
            } catch (error: any) {
              this.logger.error(
                `Error sending birthday reminder to user ${member.user.id}: ${error?.message}`,
              );
            }
          }
        } catch (error: any) {
          this.logger.error(
            `Error processing birthday for ${birthdayPerson.name}: ${error?.message}`,
          );
        }
      }

      this.logger.log(
        `🎂 Birthday reminder job complete — sent ${pushSent} push notification(s)`,
      );

      return pushSent;
    } catch (error: any) {
      this.logger.error(
        `Birthday reminder job failed: ${error?.message}`,
        error?.stack,
      );
      return 0;
    }
  }

  /**
   * Anniversary reminder — called by cron job.
   * Queries all persons with anniversaryDate matching today (month + day).
   * Same flow as birthdays.
   * Returns the number of push notifications sent.
   */
  async sendAnniversaryReminders(): Promise<number> {
    this.logger.log('💍 Running anniversary reminder job...');

    try {
      const now = new Date();
      const istNow = this.toIST(now);
      const todayMonth = istNow.getMonth();
      const todayDay = istNow.getDate();

      // Query all persons with anniversaryDate that matches today's month+day
      const anniversaryPersons = await this.prisma.person.findMany({
        where: {
          anniversaryDate: { not: null },
          isDeceased: false,
          deletedAt: null,
        },
        select: {
          id: true,
          name: true,
          familyId: true,
          anniversaryDate: true,
        },
      });

      const todayAnniversaries = anniversaryPersons.filter((person) => {
        if (!person.anniversaryDate) return false;
        const anniv = new Date(person.anniversaryDate);
        return anniv.getMonth() === todayMonth && anniv.getDate() === todayDay;
      });

      if (todayAnniversaries.length === 0) {
        this.logger.log('💍 No anniversaries found for today');
        return 0;
      }

      this.logger.log(
        `💍 Found ${todayAnniversaries.length} anniversary(ies) today`,
      );

      let pushSent = 0;

      for (const annivPerson of todayAnniversaries) {
        try {
          const memberName = annivPerson.name;
          const title = '💍 Anniversary Reminder';
          const body = `It's ${memberName}'s anniversary today! 🎊`;

          const familyMembers = await this.prisma.familyMember.findMany({
            where: { familyId: annivPerson.familyId },
            include: {
              user: { select: { id: true, name: true } },
            },
          });

          if (familyMembers.length === 0) continue;

          const family = await this.prisma.family.findUnique({
            where: { id: annivPerson.familyId },
            select: { name: true },
          });

          const familyName = family?.name;

          for (const member of familyMembers) {
            try {
              const pref = await this.getOrCreatePreference(
                member.user.id,
                'anniversary_reminder',
              );

              const inQuietHours = this.isInQuietHours(
                pref.quietHoursStart,
                pref.quietHoursEnd,
                pref.quietHoursTimezone || DEFAULT_TIMEZONE,
              );

              if (pref.inApp) {
                await this.sendInAppNotification(
                  member.user.id,
                  title,
                  body,
                  'anniversary_reminder',
                  `/family/${annivPerson.familyId}`,
                  annivPerson.familyId,
                  annivPerson.id,
                  'normal',
                );
              }

              if (pref.push && !inQuietHours) {
                const notificationData: Record<string, string> = {
                  type: 'anniversary_reminder',
                  personId: annivPerson.id,
                  personName: memberName,
                  familyId: annivPerson.familyId,
                };

                if (familyName) {
                  notificationData.familyName = familyName;
                }

                await this.sendPushNotification(
                  member.user.id,
                  title,
                  body,
                  notificationData,
                );
                pushSent++;
              } else if (inQuietHours) {
                this.logger.debug(
                  `User ${member.user.id} in quiet hours — skipping push for anniversary reminder`,
                );
              }
            } catch (error: any) {
              this.logger.error(
                `Error sending anniversary reminder to user ${member.user.id}: ${error?.message}`,
              );
            }
          }
        } catch (error: any) {
          this.logger.error(
            `Error processing anniversary for ${annivPerson.name}: ${error?.message}`,
          );
        }
      }

      this.logger.log(
        `💍 Anniversary reminder job complete — sent ${pushSent} push notification(s)`,
      );

      return pushSent;
    } catch (error: any) {
      this.logger.error(
        `Anniversary reminder job failed: ${error?.message}`,
        error?.stack,
      );
      return 0;
    }
  }

  // ── Core notification methods ──────────────────────────────────────

  /**
   * Create and send a notification to a user.
   * Handles preference checking, rate limiting, quiet hours, and multi-channel delivery.
   */
  async createAndSend(params: CreateNotificationParams): Promise<any> {
    const {
      userId,
      eventType,
      title,
      body,
      familyId,
      personId,
      priority = 'normal',
      actionUrl,
      channels: requestedChannels,
      data,
    } = params;

    // ── 1. Check rate limit ─────────────────────────────────────────
    const isCritical = CRITICAL_EVENT_TYPES.has(eventType) || priority === 'critical';
    const rateLimitOk = this.checkRateLimit(userId, isCritical);
    if (!rateLimitOk) {
      this.logger.warn(
        `Rate limit exceeded for user ${userId}, eventType=${eventType} — dropping notification`,
      );
      return null;
    }

    // ── 2. Get or create notification preference ────────────────────
    const pref = await this.getOrCreatePreference(userId, eventType);

    // ── 3. Check quiet hours ───────────────────────────────────────
    const inQuietHours = this.isInQuietHours(
      pref.quietHoursStart,
      pref.quietHoursEnd,
      pref.quietHoursTimezone || DEFAULT_TIMEZONE,
    );

    // ── 4. Determine channels ──────────────────────────────────────
    const effectiveChannels: string[] = [];
    if (pref.inApp) effectiveChannels.push('inApp');
    if (pref.push && !inQuietHours) effectiveChannels.push('push');
    if (pref.email) effectiveChannels.push('email');
    if (pref.whatsapp) effectiveChannels.push('whatsapp');

    // Override with requested channels if provided
    const finalChannels = requestedChannels
      ? requestedChannels.filter((ch) => effectiveChannels.includes(ch))
      : effectiveChannels;

    if (finalChannels.length === 0 && !pref.inApp) {
      this.logger.debug(
        `All channels disabled for user ${userId}, eventType=${eventType} — skipping`,
      );
      return null;
    }

    // Always ensure in-app is included (minimum delivery)
    if (!finalChannels.includes('inApp') && pref.inApp) {
      finalChannels.push('inApp');
    }

    // ── 5. Create notification record ──────────────────────────────
    const notification = await this.prisma.notification.create({
      data: {
        userId,
        eventType,
        title,
        body,
        familyId: familyId || null,
        personId: personId || null,
        channels: JSON.stringify(finalChannels),
        priority,
        actionUrl: actionUrl || null,
      },
    });

    // ── 6. Create delivery tracking records ────────────────────────
    const deliveryRecords = finalChannels.map((channel) => ({
      notificationId: notification.id,
      channel,
      status: 'pending' as string,
    }));

    if (deliveryRecords.length > 0) {
      await this.prisma.notificationUpdate.createMany({
        data: deliveryRecords,
      });
    }

    // ── 7. Send push notification if applicable ────────────────────
    if (finalChannels.includes('push') && !inQuietHours) {
      try {
        const pushData: Record<string, string> = {
          type: eventType,
          notificationId: notification.id,
          ...(familyId && { familyId }),
          ...(personId && { personId }),
          ...(actionUrl && { actionUrl }),
          ...(data || {}),
        };

        await this.sendPushNotification(userId, title, body, pushData);

        // Update delivery record
        await this.prisma.notificationUpdate.updateMany({
          where: { notificationId: notification.id, channel: 'push' },
          data: { status: 'delivered' },
        });
      } catch (error: any) {
        this.logger.error(
          `Failed to send push notification to user ${userId}: ${error?.message}`,
        );
        await this.prisma.notificationUpdate.updateMany({
          where: { notificationId: notification.id, channel: 'push' },
          data: { status: 'failed', error: error?.message },
        });
      }
    }

    // ── 8. Queue email if applicable (placeholder for future) ──────
    if (finalChannels.includes('email')) {
      // Email delivery would be handled by an EmailService
      // For now, mark as pending
      this.logger.debug(
        `Email notification queued for user ${userId}, notificationId=${notification.id}`,
      );
    }

    // ── 9. Queue WhatsApp if applicable (placeholder for future) ───
    if (finalChannels.includes('whatsapp')) {
      // WhatsApp delivery would be handled by WhatsAppService
      this.logger.debug(
        `WhatsApp notification queued for user ${userId}, notificationId=${notification.id}`,
      );
    }

    return notification;
  }

  /**
   * Send push notification via FCM.
   * Includes data payload for deep linking (notification type + entity ID).
   * Handles token refresh and invalid tokens via FcmService.
   */
  async sendPushNotification(
    userId: string,
    title: string,
    body: string,
    data?: Record<string, string>,
  ): Promise<void> {
    try {
      await this.fcmService.sendToUser(userId, {
        title,
        body,
        data: data || {},
      });
    } catch (error: any) {
      this.logger.error(
        `FCM send failed for user ${userId}: ${error?.message}`,
      );
      throw error;
    }
  }

  /**
   * Send in-app notification (stored in DB).
   * Creates a notification record + delivery tracking entry.
   */
  async sendInAppNotification(
    userId: string,
    title: string,
    body: string,
    eventType: string,
    actionUrl?: string,
    familyId?: string,
    personId?: string,
    priority: string = 'normal',
  ): Promise<any> {
    const notification = await this.prisma.notification.create({
      data: {
        userId,
        eventType,
        title,
        body,
        familyId: familyId || null,
        personId: personId || null,
        channels: JSON.stringify(['inApp']),
        priority,
        actionUrl: actionUrl || null,
      },
    });

    // Create delivery tracking record
    await this.prisma.notificationUpdate.create({
      data: {
        notificationId: notification.id,
        channel: 'inApp',
        status: 'delivered',
      },
    });

    return notification;
  }

  /**
   * Get notifications for a user with pagination.
   * Returns both the notification list and metadata.
   */
  async getUserNotifications(
    userId: string,
    page: number = 1,
    limit: number = 20,
  ): Promise<PaginatedNotifications> {
    // Clamp values
    const safePage = Math.max(1, page);
    const safeLimit = Math.min(Math.max(1, limit), 100);
    const skip = (safePage - 1) * safeLimit;

    const [notifications, total, unreadCount] = await Promise.all([
      this.prisma.notification.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        skip,
        take: safeLimit,
        select: {
          id: true,
          userId: true,
          eventType: true,
          title: true,
          body: true,
          familyId: true,
          personId: true,
          channels: true,
          priority: true,
          read: true,
          readAt: true,
          actionUrl: true,
          createdAt: true,
          updatedAt: true,
        },
      }),
      this.prisma.notification.count({
        where: { userId },
      }),
      this.prisma.notification.count({
        where: { userId, read: false },
      }),
    ]);

    return {
      notifications,
      total,
      page: safePage,
      limit: safeLimit,
      totalPages: Math.ceil(total / safeLimit),
      unreadCount,
    };
  }

  /**
   * Mark specific notifications as read.
   */
  async markAsRead(userId: string, notificationIds: string[]): Promise<void> {
    if (!notificationIds || notificationIds.length === 0) return;

    const now = new Date();

    await this.prisma.notification.updateMany({
      where: {
        id: { in: notificationIds },
        userId, // Ensure user can only mark their own notifications
        read: false,
      },
      data: {
        read: true,
        readAt: now,
      },
    });

    // Also update delivery tracking records
    await this.prisma.notificationUpdate.updateMany({
      where: {
        notificationId: { in: notificationIds },
        channel: 'inApp',
        status: 'delivered',
      },
      data: { status: 'read' },
    });
  }

  /**
   * Mark all notifications as read for a user.
   */
  async markAllAsRead(userId: string): Promise<void> {
    const now = new Date();

    // Get all unread notification IDs for delivery tracking update
    const unreadNotifications = await this.prisma.notification.findMany({
      where: { userId, read: false },
      select: { id: true },
    });

    const unreadIds = unreadNotifications.map((n) => n.id);

    await this.prisma.notification.updateMany({
      where: { userId, read: false },
      data: {
        read: true,
        readAt: now,
      },
    });

    // Update delivery tracking
    if (unreadIds.length > 0) {
      await this.prisma.notificationUpdate.updateMany({
        where: {
          notificationId: { in: unreadIds },
          channel: 'inApp',
          status: 'delivered',
        },
        data: { status: 'read' },
      });
    }
  }

  /**
   * Get unread count for a user.
   */
  async getUnreadCount(userId: string): Promise<number> {
    return this.prisma.notification.count({
      where: { userId, read: false },
    });
  }

  // ── Preference management ──────────────────────────────────────────

  /**
   * Get notification preferences for a user.
   * Returns all preferences for the user, or creates defaults if none exist.
   */
  async getUserPreferences(userId: string): Promise<any[]> {
    const prefs = await this.prisma.notificationPreference.findMany({
      where: { userId },
      orderBy: { eventType: 'asc' },
    });

    // If no preferences exist, seed defaults for all known event types
    if (prefs.length === 0) {
      const seeded: any[] = [];
      for (const [eventType, defaults] of Object.entries(EVENT_TYPE_DEFAULTS)) {
        const pref = await this.getOrCreatePreference(userId, eventType);
        seeded.push(pref);
      }
      return seeded;
    }

    return prefs;
  }

  /**
   * Update notification preferences for a user and event type.
   */
  async updatePreference(
    userId: string,
    eventType: string,
    data: {
      push?: boolean;
      inApp?: boolean;
      email?: boolean;
      whatsapp?: boolean;
      quietHoursStart?: string;
      quietHoursEnd?: string;
      quietHoursTimezone?: string;
      maxPerDay?: number;
      digestMode?: string;
    },
  ): Promise<any> {
    // Validate quiet hours format if provided
    if (data.quietHoursStart && !this.isValidTimeFormat(data.quietHoursStart)) {
      throw new Error(
        `Invalid quietHoursStart format: "${data.quietHoursStart}". Expected "HH:MM" (24h format)`,
      );
    }
    if (data.quietHoursEnd && !this.isValidTimeFormat(data.quietHoursEnd)) {
      throw new Error(
        `Invalid quietHoursEnd format: "${data.quietHoursEnd}". Expected "HH:MM" (24h format)`,
      );
    }
    if (data.digestMode && !['immediate', 'hourly', 'daily'].includes(data.digestMode)) {
      throw new Error(
        `Invalid digestMode: "${data.digestMode}". Must be "immediate", "hourly", or "daily"`,
      );
    }
    if (data.maxPerDay !== undefined && (data.maxPerDay < 0 || data.maxPerDay > 100)) {
      throw new Error('maxPerDay must be between 0 and 100');
    }

    return this.prisma.notificationPreference.upsert({
      where: { userId_eventType: { userId, eventType } },
      update: {
        ...(data.push !== undefined && { push: data.push }),
        ...(data.inApp !== undefined && { inApp: data.inApp }),
        ...(data.email !== undefined && { email: data.email }),
        ...(data.whatsapp !== undefined && { whatsapp: data.whatsapp }),
        ...(data.quietHoursStart !== undefined && { quietHoursStart: data.quietHoursStart }),
        ...(data.quietHoursEnd !== undefined && { quietHoursEnd: data.quietHoursEnd }),
        ...(data.quietHoursTimezone !== undefined && { quietHoursTimezone: data.quietHoursTimezone }),
        ...(data.maxPerDay !== undefined && { maxPerDay: data.maxPerDay }),
        ...(data.digestMode !== undefined && { digestMode: data.digestMode }),
      },
      create: {
        userId,
        eventType,
        push: data.push ?? EVENT_TYPE_DEFAULTS[eventType]?.push ?? true,
        inApp: data.inApp ?? EVENT_TYPE_DEFAULTS[eventType]?.inApp ?? true,
        email: data.email ?? EVENT_TYPE_DEFAULTS[eventType]?.email ?? false,
        whatsapp: data.whatsapp ?? EVENT_TYPE_DEFAULTS[eventType]?.whatsapp ?? false,
        quietHoursStart: data.quietHoursStart ?? null,
        quietHoursEnd: data.quietHoursEnd ?? null,
        quietHoursTimezone: data.quietHoursTimezone ?? DEFAULT_TIMEZONE,
        maxPerDay: data.maxPerDay ?? 10,
        digestMode: data.digestMode ?? 'immediate',
      },
    });
  }

  // ── Private helpers ────────────────────────────────────────────────

  /**
   * Get or create a notification preference for a user and event type.
   * If no preference exists, creates one with sensible defaults.
   */
  private async getOrCreatePreference(
    userId: string,
    eventType: string,
  ): Promise<any> {
    const existing = await this.prisma.notificationPreference.findUnique({
      where: { userId_eventType: { userId, eventType } },
    });

    if (existing) return existing;

    // Create with defaults
    const defaults = EVENT_TYPE_DEFAULTS[eventType] || {
      push: true,
      inApp: true,
      email: false,
      whatsapp: false,
    };

    return this.prisma.notificationPreference.create({
      data: {
        userId,
        eventType,
        push: defaults.push,
        inApp: defaults.inApp,
        email: defaults.email,
        whatsapp: defaults.whatsapp,
        quietHoursStart: null,
        quietHoursEnd: null,
        quietHoursTimezone: DEFAULT_TIMEZONE,
        maxPerDay: 10,
        digestMode: 'immediate',
      },
    });
  }

  /**
   * Check if the current time is within the user's quiet hours.
   * Uses the user's configured timezone (defaults to IST/Asia/Kolkata).
   */
  private isInQuietHours(
    quietStart: string | null | undefined,
    quietEnd: string | null | undefined,
    timezone: string = DEFAULT_TIMEZONE,
  ): boolean {
    if (!quietStart || !quietEnd) return false;

    try {
      // Get current time in the configured timezone
      const nowInTz = this.getTimeInTimezone(timezone);
      const currentMinutes = nowInTz.getHours() * 60 + nowInTz.getMinutes();

      const [startH, startM] = quietStart.split(':').map(Number);
      const [endH, endM] = quietEnd.split(':').map(Number);

      if (isNaN(startH) || isNaN(startM) || isNaN(endH) || isNaN(endM)) {
        return false;
      }

      const startMinutes = startH * 60 + startM;
      const endMinutes = endH * 60 + endM;

      if (startMinutes === endMinutes) return false;

      if (startMinutes < endMinutes) {
        // e.g. 08:00 - 22:00
        return currentMinutes >= startMinutes && currentMinutes < endMinutes;
      } else {
        // e.g. 22:00 - 08:00 (overnight)
        return currentMinutes >= startMinutes || currentMinutes < endMinutes;
      }
    } catch {
      return false;
    }
  }

  /**
   * Get current time in a specific timezone.
   * Falls back to IST if the timezone is invalid.
   */
  private getTimeInTimezone(timezone: string): Date {
    try {
      // Create a date string in the target timezone
      const now = new Date();
      const formatter = new Intl.DateTimeFormat('en-US', {
        timeZone: timezone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false,
      });

      const parts = formatter.formatToParts(now);
      const getPart = (type: string) =>
        parts.find((p) => p.type === type)?.value || '0';

      const year = parseInt(getPart('year'), 10);
      const month = parseInt(getPart('month'), 10) - 1; // JS months are 0-indexed
      const day = parseInt(getPart('day'), 10);
      const hour = parseInt(getPart('hour'), 10);
      const minute = parseInt(getPart('minute'), 10);
      const second = parseInt(getPart('second'), 10);

      return new Date(year, month, day, hour, minute, second);
    } catch {
      // Fallback to IST
      return this.toIST(new Date());
    }
  }

  /**
   * Convert a date to IST (Asia/Kolkata) by applying the +5:30 offset.
   */
  private toIST(date: Date): Date {
    const istOffset = 5.5 * 60 * 60 * 1000; // +5:30 in ms
    const utcTime = date.getTime() + date.getTimezoneOffset() * 60 * 1000;
    return new Date(utcTime + istOffset);
  }

  /**
   * Check rate limit for a user.
   * Returns true if the notification is allowed, false if rate-limited.
   * Uses in-memory cache with daily reset.
   */
  private checkRateLimit(userId: string, isCritical: boolean): boolean {
    const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD

    let entry = this.rateLimitCache.get(userId);

    // Reset counter if it's a new day
    if (!entry || entry.date !== today) {
      entry = { date: today, count: 0, criticalCount: 0 };
      this.rateLimitCache.set(userId, entry);
    }

    if (isCritical) {
      if (entry.criticalCount >= MAX_DAILY_CRITICAL) {
        return false;
      }
      entry.criticalCount++;
    } else {
      if (entry.count >= MAX_DAILY_NON_CRITICAL) {
        return false;
      }
      entry.count++;
    }

    return true;
  }

  /**
   * Validate time format (HH:MM, 24-hour).
   */
  private isValidTimeFormat(time: string): boolean {
    const regex = /^([01]\d|2[0-3]):([0-5]\d)$/;
    return regex.test(time);
  }
}
