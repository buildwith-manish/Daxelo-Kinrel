import { Injectable, Logger, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';

// ── Social System Notification Event Types ──────────────────────────
export const SOCIAL_NOTIFICATION_TYPES = {
  FOLLOW_NEW: 'follow:new',
  FOLLOW_REQUEST: 'follow:request',
  FOLLOW_ACCEPTED: 'follow:accepted',
  FAMILY_CREATED: 'family:created',
  FAMILY_INVITE_LINK_READY: 'family:invite_link_ready',
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

  /** Marks a single notification as read. Verifies ownership so a user
   *  cannot mark another user's notification as read. */
  async markRead(notificationId: string, userId: string) {
    // Verify the notification belongs to the requesting user before
    // updating. This prevents IDOR — without this check, any authenticated
    // user could mark any other user's notification as read by guessing IDs.
    const notification = await this.prisma.notification.findUnique({
      where: { id: notificationId },
      select: { userId: true },
    });
    if (!notification) {
      throw new NotFoundException('Notification not found');
    }
    if (notification.userId !== userId) {
      throw new ForbiddenException('Cannot mark another user\'s notification');
    }
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
        title: 'You joined a family!',
        body: `Welcome to "${familyName}". You're now part of the family graph.`,
        familyId,
        actionUrl: `/family/${familyId}`,
        priority: 'normal',
      });
      this.gateway.emitToUser(userId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send family:joined notification', e);
    }
  }

  /** Notify family owners that someone joined their family. */
  async notifyFamilyMemberJoined(
    ownerId: string,
    memberName: string,
    familyName: string,
    familyId: string,
    isDirectInviteAccept: boolean = false,
  ) {
    try {
      const title = isDirectInviteAccept
        ? `${memberName} accepted your invite`
        : 'New family member joined';
      const body = isDirectInviteAccept
        ? `${memberName} accepted your invitation and joined "${familyName}".`
        : `${memberName} has joined "${familyName}". Your family graph just got bigger!`;

      const notification = await this.create({
        userId: ownerId,
        eventType: SOCIAL_NOTIFICATION_TYPES.FAMILY_MEMBER_JOINED,
        title,
        body,
        actionUrl: `/family/${familyId}/members`,
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

  // ── Family Creation Notification Helpers ──────────────────────────

  /** Notify the creator that their family was created successfully. */
  async notifyFamilyCreated(userId: string, familyName: string, familyId: string) {
    try {
      const notification = await this.create({
        userId,
        eventType: SOCIAL_NOTIFICATION_TYPES.FAMILY_CREATED,
        title: 'Family created successfully 🎉',
        body: `Your family "${familyName}" is live. Invite members to start building your family graph.`,
        familyId,
        actionUrl: `/family/${familyId}`,
        priority: 'normal',
      });
      this.gateway.emitToUser(userId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send family:created notification', e);
    }
  }

  /** Notify the creator that the invite link is ready. */
  async notifyFamilyInviteLinkReady(userId: string, familyName: string, familyId: string) {
    try {
      const notification = await this.create({
        userId,
        eventType: SOCIAL_NOTIFICATION_TYPES.FAMILY_INVITE_LINK_READY,
        title: 'Invite link ready',
        body: `Share your invite link to add members to "${familyName}". Link expires in 7 days.`,
        familyId,
        actionUrl: `/family/${familyId}/invite`,
        priority: 'low',
      });
      this.gateway.emitToUser(userId, 'notification:new', notification);
    } catch (e) {
      this.logger.error('Failed to send family:invite_link_ready notification', e);
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
