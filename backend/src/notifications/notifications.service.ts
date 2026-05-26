import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { GetNotificationsDto } from './dto/get-notifications.dto';
import { MarkReadDto } from './dto/mark-read.dto';
import { UpdatePreferencesDto } from './dto/update-preferences.dto';
import { CreateNotificationDto } from './dto/create-notification.dto';
import { randomUUID } from 'crypto';

@Injectable()
export class NotificationsService {
  constructor(private prisma: PrismaService) {}

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
}
