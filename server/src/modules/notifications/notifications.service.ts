import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';

// ── Social System Notification Event Types ──────────────────────────
export const SOCIAL_NOTIFICATION_TYPES = {
  FOLLOW_NEW: 'follow:new',
  FOLLOW_REQUEST: 'follow:request',
  FOLLOW_ACCEPTED: 'follow:accepted',
  FAMILY_JOINED: 'family:joined',
  FAMILY_MEMBER_JOINED: 'family:member_joined',
  SPARQ_VIEWS_BATCH: 'sparq:views_batch',
  SPARQ_REPLY: 'sparq:reply',
} as const;

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: KinrelGateway,
  ) {}

  /** Lists notifications for a user, optionally filtered to unread only, with pagination. */
  async listForUser(userId: string, limit: number = 30, unreadOnly: boolean = false, page: number = 1) {
    const where: Record<string, any> = { userId };
    if (unreadOnly) {
      where.read = false;
    }
    const skip = (page - 1) * limit;

    const [items, total] = await this.prisma.$transaction([
      this.prisma.notification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
        select: {
          id: true,
          userId: true,
          eventType: true,
          title: true,
          body: true,
          familyId: true,
          personId: true,
          priority: true,
          read: true,
          readAt: true,
          actionUrl: true,
          createdAt: true,
          updatedAt: true,
        },
      }),
      this.prisma.notification.count({ where }),
    ]);

    return { items, total, page, limit };
  }

  /** Marks a single notification as read. */
  async markRead(notificationId: string) {
    return this.prisma.notification.update({
      where: { id: notificationId },
      data: { read: true, readAt: new Date() },
    });
  }

  /** Marks all unread notifications for a user as read. */
  async markAllRead(userId: string) {
    return this.prisma.notification.updateMany({
      where: { userId, read: false },
      data: { read: true, readAt: new Date() },
    });
  }

  /** Creates a new notification record in the database. */
  async create(data: {
    userId: string;
    eventType: string;
    title: string;
    body: string;
    familyId?: string;
    personId?: string;
    priority?: string;
    actionUrl?: string;
  }) {
    return this.prisma.notification.create({ data });
  }

  /** Returns the count of unread notifications for a user. */
  async getUnreadCount(userId: string) {
    return this.prisma.notification.count({
      where: { userId, read: false },
    });
  }

  /** Creates or updates a notification preference for a user and event type. */
  async updatePreference(userId: string, eventType: string, data: Record<string, any>) {
    return this.prisma.notificationPreference.upsert({
      where: { userId_eventType: { userId, eventType } },
      update: data,
      create: { userId, eventType, ...data },
    });
  }

  // ── Social System Notification Helpers ──────────────────────────────

  /** Notify a user that someone followed their public profile. */
  async notifyFollowNew(targetUserId: string, followerName: string, followerId: string) {
    try {
      const notification = await this.create({
        userId: targetUserId,
        eventType: SOCIAL_NOTIFICATION_TYPES.FOLLOW_NEW,
        title: 'New Follower',
        body: `${followerName} started following you`,
        actionUrl: `/profile/${followerId}`,
        priority: 'normal',
      });
      this.gateway.emitToUser(targetUserId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send follow:new notification', e);
    }
  }

  /** Notify a user that someone wants to follow them (private profile). */
  async notifyFollowRequest(targetUserId: string, requesterName: string, requesterId: string) {
    try {
      const notification = await this.create({
        userId: targetUserId,
        eventType: SOCIAL_NOTIFICATION_TYPES.FOLLOW_REQUEST,
        title: 'Follow Request',
        body: `${requesterName} wants to follow you`,
        actionUrl: '/follow-requests',
        priority: 'high',
      });
      this.gateway.emitToUser(targetUserId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send follow:request notification', e);
    }
  }

  /** Notify a user that their follow request was accepted. */
  async notifyFollowAccepted(requesterId: string, acceptorName: string, acceptorId: string) {
    try {
      const notification = await this.create({
        userId: requesterId,
        eventType: SOCIAL_NOTIFICATION_TYPES.FOLLOW_ACCEPTED,
        title: 'Follow Accepted',
        body: `${acceptorName} accepted your follow request`,
        actionUrl: `/profile/${acceptorId}`,
        priority: 'normal',
      });
      this.gateway.emitToUser(requesterId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send follow:accepted notification', e);
    }
  }

  /** Notify a user that they joined a family. */
  async notifyFamilyJoined(userId: string, familyName: string, familyId: string) {
    try {
      const notification = await this.create({
        userId,
        eventType: SOCIAL_NOTIFICATION_TYPES.FAMILY_JOINED,
        title: 'Family Joined',
        body: `You joined ${familyName}`,
        actionUrl: `/family/${familyId}`,
        priority: 'normal',
      });
      this.gateway.emitToUser(userId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send family:joined notification', e);
    }
  }

  /** Notify family owners that someone joined their family. */
  async notifyFamilyMemberJoined(ownerId: string, memberName: string, familyName: string, familyId: string) {
    try {
      const notification = await this.create({
        userId: ownerId,
        eventType: SOCIAL_NOTIFICATION_TYPES.FAMILY_MEMBER_JOINED,
        title: 'New Family Member',
        body: `${memberName} joined your ${familyName} family`,
        actionUrl: `/family/${familyId}`,
        familyId,
        priority: 'normal',
      });
      this.gateway.emitToUser(ownerId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send family:member_joined notification', e);
    }
  }

  /** Batch Sparq view notifications (called hourly by scheduler). */
  async notifySparqViewsBatch(creatorId: string, viewCount: number, sparqId: string) {
    if (viewCount <= 0) return;
    try {
      const notification = await this.create({
        userId: creatorId,
        eventType: SOCIAL_NOTIFICATION_TYPES.SPARQ_VIEWS_BATCH,
        title: 'Sparq Views',
        body: `${viewCount} ${viewCount === 1 ? 'person viewed' : 'people viewed'} your Sparq`,
        actionUrl: `/sparq/${sparqId}/viewers`,
        priority: 'low',
      });
      this.gateway.emitToUser(creatorId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send sparq:views_batch notification', e);
    }
  }

  /** Notify a Sparq creator that someone replied. */
  async notifySparqReply(creatorId: string, replierName: string, sparqId: string) {
    try {
      const notification = await this.create({
        userId: creatorId,
        eventType: SOCIAL_NOTIFICATION_TYPES.SPARQ_REPLY,
        title: 'Sparq Reply',
        body: `${replierName} replied to your Sparq`,
        actionUrl: `/sparq/viewer/${creatorId}`,
        priority: 'normal',
      });
      this.gateway.emitToUser(creatorId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send sparq:reply notification', e);
    }
  }
}
