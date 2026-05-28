import { Injectable, BadRequestException, NotFoundException, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FcmService } from './fcm.service';
import { GetNotificationsDto } from './dto/get-notifications.dto';
import { MarkReadDto } from './dto/mark-read.dto';
import { UpdatePreferencesDto } from './dto/update-preferences.dto';
import { CreateNotificationDto } from './dto/create-notification.dto';
import { randomUUID } from 'crypto';

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private prisma: PrismaService,
    private fcmService: FcmService,
  ) {}

  /**
   * GET /api/notifications — Get user's notifications with unread count
   */
  async getNotifications(dto: GetNotificationsDto) {
    const limit = dto.limit ?? 20;
    const offset = dto.offset ?? 0;

    const where: Record<string, unknown> = { userId: dto.userId };

    if (dto.read !== undefined && dto.read !== null && dto.read !== '') {
      where.read = dto.read === 'true';
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
        where: { userId: dto.userId, read: false },
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

  /**
   * PATCH /api/notifications — Mark as read
   */
  async markAsRead(dto: MarkReadDto) {
    const now = new Date();

    let count: number;

    if (dto.notificationIds && dto.notificationIds.length > 0) {
      // Mark specific notifications as read
      const result = await this.prisma.notification.updateMany({
        where: {
          id: { in: dto.notificationIds },
          userId: dto.userId,
          read: false,
        },
        data: {
          read: true,
          readAt: now,
        },
      });
      count = result.count;
    } else {
      // Mark all unread as read
      const result = await this.prisma.notification.updateMany({
        where: {
          userId: dto.userId,
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

  /**
   * PUT /api/notifications — Update notification preferences
   */
  async updatePreferences(dto: UpdatePreferencesDto) {
    // Verify user exists
    const user = await this.prisma.user.findUnique({ where: { id: dto.userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const updateData: Record<string, unknown> = {};
    if (dto.whatsapp !== undefined) updateData.whatsapp = dto.whatsapp;
    if (dto.push !== undefined) updateData.push = dto.push;
    if (dto.inApp !== undefined) updateData.inApp = dto.inApp;
    if (dto.email !== undefined) updateData.email = dto.email;
    if (dto.quietHoursStart !== undefined) updateData.quietHoursStart = dto.quietHoursStart;
    if (dto.quietHoursEnd !== undefined) updateData.quietHoursEnd = dto.quietHoursEnd;
    if (dto.digestMode !== undefined) updateData.digestMode = dto.digestMode;
    if (dto.maxPerDay !== undefined) updateData.maxPerDay = dto.maxPerDay;

    const preference = await this.prisma.notificationPreference.upsert({
      where: {
        userId_eventType: {
          userId: dto.userId,
          eventType: dto.eventType,
        },
      },
      update: updateData,
      create: {
        userId: dto.userId,
        eventType: dto.eventType,
        whatsapp: dto.whatsapp ?? true,
        push: dto.push ?? true,
        inApp: dto.inApp ?? true,
        email: dto.email ?? false,
        quietHoursStart: dto.quietHoursStart ?? null,
        quietHoursEnd: dto.quietHoursEnd ?? null,
        digestMode: dto.digestMode ?? 'immediate',
        maxPerDay: dto.maxPerDay ?? 10,
      },
    });

    return { preference };
  }

  /**
   * POST /api/notifications — Create and send a notification
   * Simplified: just persist to DB (no external notification engine)
   */
  async createNotification(dto: CreateNotificationDto) {
    const now = new Date();
    const dedupKey = `${dto.type}:${dto.targetUserId}:${dto.familyId ?? ''}:${dto.personId ?? ''}:${now.getTime()}`;

    // Build notification title/body from type and payload
    const title = this.buildTitle(dto.type, dto.payload);
    const body = this.buildBody(dto.type, dto.payload);

    // Determine channels from preferences (simplified — default to inApp + push)
    const channels = ['inApp', 'push'];

    // Persist the notification
    const notification = await this.prisma.notification.create({
      data: {
        userId: dto.targetUserId,
        eventType: dto.type,
        title,
        body,
        familyId: dto.familyId ?? null,
        personId: dto.personId ?? null,
        channels: JSON.stringify(channels),
        priority: dto.priority,
        actionUrl: (dto.payload.actionUrl as string) ?? null,
      },
      include: {
        updates: true,
      },
    });

    // Create notification update for tracking
    await this.prisma.notificationUpdate.create({
      data: {
        notificationId: notification.id,
        channel: 'inApp',
        status: 'delivered',
      },
    });

    // Parse JSON channels for response
    const parsedNotification = {
      ...notification,
      channels: JSON.parse(notification.channels) as string[],
      dedupKey,
    };

    return { notification: parsedNotification };
  }

  private buildTitle(type: string, payload: Record<string, unknown>): string {
    const actorName = (payload.actorName as string) ?? 'Someone';
    const titles: Record<string, string> = {
      'family.invite': `${actorName} invited you to join a family`,
      'family.member_joined': `${actorName} joined your family`,
      'person.birthday': `Birthday reminder`,
      'relationship.new_match': `New relationship discovered`,
      'share.card_viewed': `Your shared card was viewed`,
    };
    return titles[type] ?? `New notification`;
  }

  private buildBody(type: string, payload: Record<string, unknown>): string {
    const familyName = (payload.familyName as string) ?? '';
    const personName = (payload.personName as string) ?? '';
    const bodies: Record<string, string> = {
      'family.invite': familyName ? `You've been invited to ${familyName}` : 'You have a new family invitation',
      'family.member_joined': familyName ? `${personName} joined ${familyName}` : 'A new member joined your family',
      'person.birthday': personName ? `It's ${personName}'s birthday!` : 'Birthday coming up!',
      'relationship.new_match': personName ? `New kinship found with ${personName}` : 'A new kinship was discovered',
      'share.card_viewed': 'Someone viewed your shared card',
    };
    return bodies[type] ?? JSON.stringify(payload).substring(0, 200);
  }

  // ── FCM Push Notification Methods ──────────────────────────────────

  /** Send a birthday reminder to all family members */
  async sendBirthdayReminder(
    memberId: string,
    memberName: string,
    familyId: string,
    daysUntil: number,
  ): Promise<number> {
    // Find all family members
    const familyMembers = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: { userId: true },
    });

    const userIds = familyMembers.map((fm) => fm.userId).filter(Boolean);
    if (userIds.length === 0) return 0;

    // Check for duplicates — don't send same notification twice in same day
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const alreadySent = await this.prisma.notificationLog.findMany({
      where: {
        type: 'birthday_reminder',
        referenceId: memberId,
        sentAt: { gte: today },
      },
      select: { userId: true },
    });
    const sentUserIds = new Set(alreadySent.map((n) => n.userId));
    const pendingUserIds = userIds.filter((id) => !sentUserIds.has(id));

    if (pendingUserIds.length === 0) return 0;

    const title = `${memberName}'s birthday is in ${daysUntil} day(s)!`;
    const body = "Don't forget to wish them!";
    const data: Record<string, string> = {
      type: 'birthday_reminder',
      memberId,
      memberName,
      daysUntil: String(daysUntil),
    };

    const successCount = await this.fcmService.sendToMultiple(pendingUserIds, title, body, data);

    // Log each notification
    for (const userId of pendingUserIds) {
      try {
        await this.prisma.notificationLog.create({
          data: { userId, type: 'birthday_reminder', referenceId: memberId },
        });
      } catch (_) {
        // Unique constraint violation — already sent today, skip
      }
    }

    this.logger.log(
      `Birthday reminder sent: ${memberName} (${successCount}/${pendingUserIds.length} delivered)`,
    );
    return successCount;
  }

  /** Send a new family member notification */
  async sendNewMemberNotification(
    familyId: string,
    memberId: string,
    addedByName: string,
  ): Promise<number> {
    const familyMembers = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: { userId: true },
    });

    const userIds = familyMembers.map((fm) => fm.userId).filter(Boolean);
    if (userIds.length === 0) return 0;

    const title = 'New family member added!';
    const body = `${addedByName} added a new member to the family`;
    const data: Record<string, string> = {
      type: 'new_family_member',
      familyId,
      memberId,
      addedByName,
    };

    return this.fcmService.sendToMultiple(userIds, title, body, data);
  }

  /** Send a family event notification */
  async sendFamilyEventNotification(
    familyId: string,
    eventId: string,
    eventTitle: string,
  ): Promise<number> {
    const familyMembers = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: { userId: true },
    });

    const userIds = familyMembers.map((fm) => fm.userId).filter(Boolean);
    if (userIds.length === 0) return 0;

    const title = `${eventTitle}`;
    const body = 'A new family event has been scheduled!';
    const data: Record<string, string> = {
      type: 'family_event',
      familyId,
      eventId,
      eventTitle,
    };

    return this.fcmService.sendToMultiple(userIds, title, body, data);
  }
}
