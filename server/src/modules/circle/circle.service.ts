import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
  ConflictException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  CreateCircleDto,
  UpdateCircleDto,
  AddMemberDto,
  SendCircleMessageDto,
  AddCircleReactionDto,
} from './dto/circle.dto';

// ── Constants (product limits) ────────────────────────────────────
const MAX_MEMBERS_PER_CIRCLE = 100;
const MAX_CIRCLES_PER_USER = 30;
const MESSAGE_PAGINATION_DEFAULT = 50;
const MESSAGE_PAGINATION_MAX = 100;

// ── Analytics event names (existing tracker, no personal data) ──
const ANALYTICS_EVENTS = {
  CIRCLE_CREATED: 'circle_created',
  CIRCLE_MEMBER_ADDED: 'circle_member_added',
  CIRCLE_LEFT: 'circle_left',
  CIRCLE_MESSAGE_SENT: 'circle_message_sent',
} as const;

/**
 * CircleService — business logic for account-level cross-family
 * group chats.
 *
 * Every mutation enforces the product rules on the SERVER (not only
 * in the UI):
 *   • Eligibility: "share at least one family OR accepted follow"
 *   • Blocked users cannot be added and cannot add you
 *   • Limits: max 100 members per circle, max 30 circles per user
 *   • Roles: admin can add/remove members and change settings;
 *     default only admins can add (anyoneCanAdd toggle);
 *     onlyAdminsPost toggle enforced on message INSERT
 *   • If the last admin leaves, the longest-standing member becomes
 *     admin (auto-promotion in a single transaction)
 *
 * RLS policies on the database tables ALSO enforce these rules as a
 * defense-in-depth layer — see the SQL migration for the policy
 * definitions. This service double-checks so that even a direct
 * Prisma call (bypassing RLS via the service role) respects the rules.
 */
@Injectable()
export class CircleService {
  private readonly logger = new Logger(CircleService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ═══════════════════════════════════════════════════════════════
  // Circle CRUD
  // ═══════════════════════════════════════════════════════════════

  /**
   * Creates a new circle. The caller becomes the owner + admin.
   * Auto-adds the creator as the first CircleMember with role='admin'.
   * Optionally adds initial members (subject to eligibility checks).
   */
  async createCircle(userId: string, dto: CreateCircleDto) {
    // ── Limit: max 30 circles per user ──────────────────────────
    const existingCount = await this.prisma.circle.count({
      where: { ownerId: userId },
    });
    if (existingCount >= MAX_CIRCLES_PER_USER) {
      throw new BadRequestException(
        `You've reached the limit of ${MAX_CIRCLES_PER_USER} circles.`,
      );
    }

    // ── Create the circle + auto-add the creator as admin ────────
    const circle = await this.prisma.circle.create({
      data: {
        ownerId: userId,
        name: dto.name,
        description: dto.description,
        iconKey: dto.iconKey ?? 'default',
        onlyAdminsPost: dto.onlyAdminsPost ?? false,
        anyoneCanAdd: dto.anyoneCanAdd ?? false,
        members: {
          create: {
            userId,
            role: 'admin',
            displayName: '', // populated by the Flutter client from user metadata
          },
        },
      },
      include: { members: true },
    });

    this.logger.log(
      `Circle created: id=${circle.id}, owner=${userId}, name="${dto.name}"`,
    );

    // ── Optionally add initial members ──────────────────────────
    // Each member is checked for eligibility via the SQL function
    // fn_user_can_be_added_to_circle (which also checks blocked users).
    if (dto.memberUserIds && dto.memberUserIds.length > 0) {
      for (const candidateId of dto.memberUserIds) {
        if (candidateId === userId) continue; // skip self (already admin)
        try {
          await this.addMember(circle.id, userId, {
            userId: candidateId,
          });
        } catch (e) {
          // Silently skip ineligible candidates during circle
          // creation — the caller can retry individually if needed.
          this.logger.warn(
            `Skipped adding ${candidateId} to circle ${circle.id}: ${e.message}`,
          );
        }
      }
    }

    return circle;
  }

  /**
   * Returns a single circle's metadata + member roster.
   * RLS ensures only members can read this.
   */
  async getCircle(circleId: string, userId: string) {
    const circle = await this.prisma.circle.findUnique({
      where: { id: circleId },
      include: {
        members: {
          orderBy: { joinedAt: 'asc' },
        },
      },
    });

    if (!circle) {
      throw new NotFoundException('Circle not found.');
    }

    // Server-side membership check (defense in depth — RLS already
    // blocks non-members, but this gives a clear 403 instead of 404).
    const isMember = circle.members.some((m) => m.userId === userId);
    if (!isMember) {
      throw new ForbiddenException('You are not a member of this circle.');
    }

    return circle;
  }

  /**
   * Lists all circles the user is a member of (across all families —
   * circles are account-scoped, not family-scoped).
   */
  async listMyCircles(userId: string) {
    const memberships = await this.prisma.circleMember.findMany({
      where: { userId },
      include: {
        circle: {
          include: {
            members: { orderBy: { joinedAt: 'asc' } },
          },
        },
      },
      orderBy: { circle: { lastActivityAt: 'desc' } },
    });

    // Compute last-message preview + unread count per circle
    // (a single query per circle would be expensive on 30 circles;
    // use a batch query instead).
    const circleIds = memberships.map((m) => m.circle.id);
    if (circleIds.length === 0) return [];

    const lastMessages = await this.prisma.circleMessage.findMany({
      where: { circleId: { in: circleIds }, isDeletedForEveryone: false },
      orderBy: { createdAt: 'desc' },
      distinct: 'circleId',
    });

    const unreadCounts = await this.prisma.circleMessage.groupBy({
      by: ['circleId'],
      where: {
        circleId: { in: circleIds },
        senderId: { not: userId },
        isDeletedForEveryone: false,
        NOT: {
          readBy: { has: userId },
        },
      },
      _count: true,
    });

    const lastMsgMap = new Map(lastMessages.map((m) => [m.circleId, m]));
    const unreadMap = new Map(unreadCounts.map((u) => [u.circleId, u._count]));

    return memberships.map((m) => ({
      ...m.circle,
      isArchived: m.isArchived,
      mutedUntil: m.mutedUntil,
      myRole: m.role,
      lastMessage: lastMsgMap.get(m.circle.id) ?? null,
      unreadCount: unreadMap.get(m.circle.id) ?? 0,
    }));
  }

  /**
   * Updates circle settings. Admin only.
   */
  async updateSettings(
    circleId: string,
    userId: string,
    dto: UpdateCircleDto,
  ) {
    await this._assertAdmin(circleId, userId);

    const updated = await this.prisma.circle.update({
      where: { id: circleId },
      data: {
        ...(dto.name !== undefined && { name: dto.name }),
        ...(dto.description !== undefined && { description: dto.description }),
        ...(dto.iconKey !== undefined && { iconKey: dto.iconKey }),
        ...(dto.avatarUrl !== undefined && { avatarUrl: dto.avatarUrl }),
        ...(dto.onlyAdminsPost !== undefined && {
          onlyAdminsPost: dto.onlyAdminsPost,
        }),
        ...(dto.anyoneCanAdd !== undefined && {
          anyoneCanAdd: dto.anyoneCanAdd,
        }),
      },
    });

    this.logger.log(
      `Circle updated: id=${circleId}, by=${userId}, fields=${Object.keys(dto).join(',')}`,
    );

    return updated;
  }

  /**
   * Deletes a circle. Owner only (not just admin — the original creator).
   * Cascade-deletes all messages, reactions, receipts, members.
   */
  async deleteCircle(circleId: string, userId: string) {
    const circle = await this.prisma.circle.findUnique({
      where: { id: circleId },
      select: { ownerId: true },
    });

    if (!circle) {
      throw new NotFoundException('Circle not found.');
    }
    if (circle.ownerId !== userId) {
      throw new ForbiddenException('Only the circle owner can delete it.');
    }

    await this.prisma.circle.delete({ where: { id: circleId } });

    this.logger.log(`Circle deleted: id=${circleId}, by=${userId}`);
  }

  // ═══════════════════════════════════════════════════════════════
  // Member management
  // ═══════════════════════════════════════════════════════════════

  /**
   * Adds a member to a circle.
   *
   * Server-side enforcement:
   *   1. Caller is admin OR circle.anyoneCanAdd = true
   *   2. fn_user_can_be_added_to_circle(circleId, candidateId) = true
   *      (which checks: not already a member, < 100 members, shares
   *      a family OR accepted follow, NOT blocked either direction)
   *   3. The candidate is a Kinrel user (has an auth.users row)
   */
  async addMember(
    circleId: string,
    callerId: string,
    dto: AddMemberDto,
  ) {
    // ── Step 1: authorization ──────────────────────────────────
    const circle = await this.prisma.circle.findUnique({
      where: { id: circleId },
      select: { ownerId: true, anyoneCanAdd: true },
    });

    if (!circle) {
      throw new NotFoundException('Circle not found.');
    }

    const callerMember = await this.prisma.circleMember.findUnique({
      where: { circleId_userId: { circleId, userId: callerId } },
      select: { role: true },
    });

    const isAdmin = callerMember?.role === 'admin';
    if (!isAdmin && !circle.anyoneCanAdd) {
      throw new ForbiddenException(
        'Only admins can add members to this circle. The owner can enable "Anyone can add" in settings.',
      );
    }

    // ── Step 2: eligibility (the SQL function does the heavy lift) ─
    const eligible = await this.prisma.$queryRaw<boolean>`
      SELECT fn_user_can_be_added_to_circle(${circleId}::text, ${dto.userId}::text)
    `;

    if (!eligible[0]?.fn_user_can_be_added_to_circle) {
      // Distinguish the reason for a friendlier error message
      const isAlreadyMember = await this.prisma.circleMember.findUnique({
        where: { circleId_userId: { circleId, userId: dto.userId } },
      });
      if (isAlreadyMember) {
        throw new ConflictException('This person is already a member.');
      }

      const memberCount = await this.prisma.circleMember.count({
        where: { circleId },
      });
      if (memberCount >= MAX_MEMBERS_PER_CIRCLE) {
        throw new BadRequestException(
          `This circle has reached the ${MAX_MEMBERS_PER_CIRCLE}-member limit.`,
        );
      }

      const isBlocked = await this.prisma.$queryRaw<boolean>`
        SELECT EXISTS(
          SELECT 1 FROM "BlockedUser"
          WHERE ("blockerId" = ${circle.ownerId}::text AND "blockedId" = ${dto.userId}::text)
             OR ("blockerId" = ${dto.userId}::text AND "blockedId" = ${circle.ownerId}::text)
        )
      `;
      if (isBlocked[0]?.exists) {
        throw new ForbiddenException('This person cannot be added to your circle.');
      }

      throw new ForbiddenException(
        'This person must share a family with you or be an accepted follow to be added.',
      );
    }

    // ── Step 3: add the member ─────────────────────────────────
    const member = await this.prisma.circleMember.create({
      data: {
        circleId,
        userId: dto.userId,
        role: 'member',
        displayName: dto.displayName ?? '',
        avatarUrl: dto.avatarUrl,
      },
    });

    // ── Step 4: notification ("{added by} added you to {circle}") ─
    // Fire-and-forget — failures don't block the add.
    this._notifyMemberAdded(circleId, callerId, dto.userId).catch((e) => {
      this.logger.warn(`Failed to notify member added: ${e.message}`);
    });

    this.logger.log(
      `Member added: circle=${circleId}, by=${callerId}, member=${dto.userId}`,
    );

    return member;
  }

  /**
   * Removes a member. Admin only (or self-leave — use leaveCircle
   * for that path).
   */
  async removeMember(circleId: string, callerId: string, targetUserId: string) {
    await this._assertAdmin(circleId, callerId);

    // ── Last-admin auto-promote: if the target is the last admin ──
    const adminCount = await this.prisma.circleMember.count({
      where: { circleId, role: 'admin' },
    });
    if (adminCount <= 1) {
      const target = await this.prisma.circleMember.findUnique({
        where: { circleId_userId: { circleId, userId: targetUserId } },
        select: { role: true },
      });
      if (target?.role === 'admin') {
        throw new BadRequestException(
          'You cannot remove the last admin. Transfer admin first or delete the circle.',
        );
      }
    }

    const removed = await this.prisma.circleMember.delete({
      where: { circleId_userId: { circleId, userId: targetUserId } },
    });

    this.logger.log(
      `Member removed: circle=${circleId}, by=${callerId}, target=${targetUserId}`,
    );

    return removed;
  }

  /**
   * Self-leave. If the caller is the last admin, auto-promote the
   * longest-standing member before leaving (single transaction).
   */
  async leaveCircle(circleId: string, userId: string) {
    const member = await this.prisma.circleMember.findUnique({
      where: { circleId_userId: { circleId, userId } },
      select: { role: true },
    });

    if (!member) {
      throw new NotFoundException('You are not a member of this circle.');
    }

    // ── Last-admin auto-promote ────────────────────────────────
    if (member.role === 'admin') {
      const adminCount = await this.prisma.circleMember.count({
        where: { circleId, role: 'admin' },
      });
      if (adminCount <= 1) {
        // Find the longest-standing non-admin member + promote them
        const longestStanding = await this.prisma.circleMember.findFirst({
          where: { circleId, userId: { not: userId } },
          orderBy: { joinedAt: 'asc' },
        });
        if (longestStanding) {
          await this.prisma.$transaction([
            this.prisma.circleMember.update({
              where: { id: longestStanding.id },
              data: { role: 'admin' },
            }),
            this.prisma.circleMember.delete({
              where: { circleId_userId: { circleId, userId } },
            }),
          ]);
          this.logger.log(
            `Admin left + auto-promoted: circle=${circleId}, ` +
              `left=${userId}, promoted=${longestStanding.userId}`,
          );
          return { promoted: longestStanding.userId };
        }
        // No other members — the circle is now empty. The owner
        // should delete it. If they leave, the circle becomes orphaned
        // (no members, no admin). We'll leave it for the owner to clean up.
      }
    }

    await this.prisma.circleMember.delete({
      where: { circleId_userId: { circleId, userId } },
    });

    this.logger.log(`Member left: circle=${circleId}, user=${userId}`);
    return { left: true };
  }

  /**
   * Transfers admin role to another member. Caller must be admin.
   * The caller stays admin (multiple admins are allowed). If the
   * caller wants to step down, they use leaveCircle instead.
   */
  async transferAdmin(circleId: string, callerId: string, targetUserId: string) {
    await this._assertAdmin(circleId, callerId);

    const target = await this.prisma.circleMember.findUnique({
      where: { circleId_userId: { circleId, userId: targetUserId } },
    });
    if (!target) {
      throw new NotFoundException('Target user is not a member of this circle.');
    }

    const updated = await this.prisma.circleMember.update({
      where: { circleId_userId: { circleId, userId: targetUserId } },
      data: { role: 'admin' },
    });

    this.logger.log(
      `Admin transferred: circle=${circleId}, by=${callerId}, to=${targetUserId}`,
    );

    return updated;
  }

  /**
   * Mutes a circle (per-member). Self only.
   * mutedUntil = null means unmute.
   */
  async mute(circleId: string, userId: string, mutedUntil: Date | null) {
    const member = await this.prisma.circleMember.findUnique({
      where: { circleId_userId: { circleId, userId } },
    });
    if (!member) {
      throw new NotFoundException('You are not a member of this circle.');
    }

    return this.prisma.circleMember.update({
      where: { circleId_userId: { circleId, userId } },
      data: { mutedUntil },
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Messages
  // ═══════════════════════════════════════════════════════════════

  /**
   * Sends a message to a circle.
   *
   * Server-side enforcement:
   *   1. Caller is a member (RLS already blocks, but we double-check)
   *   2. If circle.onlyAdminsPost = true, caller must be admin
   */
  async sendMessage(circleId: string, userId: string, dto: SendCircleMessageDto) {
    const member = await this.prisma.circleMember.findUnique({
      where: { circleId_userId: { circleId, userId } },
      select: { role: true, displayName: true },
    });
    if (!member) {
      throw new ForbiddenException('You are not a member of this circle.');
    }

    // ── onlyAdminsPost enforcement ─────────────────────────────
    const circle = await this.prisma.circle.findUnique({
      where: { id: circleId },
      select: { onlyAdminsPost: true, name: true },
    });
    if (circle?.onlyAdminsPost && member.role !== 'admin') {
      throw new ForbiddenException(
        'Only admins can post in this circle.',
      );
    }

    // ── Reply-to resolution ────────────────────────────────────
    let replyToContent: string | null = null;
    let replyToSenderName: string | null = null;
    if (dto.replyToId) {
      const replyTarget = await this.prisma.circleMessage.findUnique({
        where: { id: dto.replyToId },
        select: { content: true, senderName: true, circleId: true },
      });
      if (!replyTarget) {
        throw new BadRequestException('Reply-to message not found.');
      }
      if (replyTarget.circleId !== circleId) {
        throw new BadRequestException(
          'Reply-to message belongs to a different circle.',
        );
      }
      replyToContent = replyTarget.content;
      replyToSenderName = replyTarget.senderName;
    }

    // ── Create the message ─────────────────────────────────────
    const message = await this.prisma.circleMessage.create({
      data: {
        circleId,
        senderId: userId,
        senderName: member.displayName || 'Member',
        senderInitials: dto.senderInitials,
        senderPersonId: dto.senderPersonId,
        senderFamilyId: dto.senderFamilyId,
        content: dto.content,
        messageType: dto.messageType ?? 'text',
        messageSubType: 'text',
        replyToId: dto.replyToId,
        replyToContent,
        replyToSenderName,
        mediaUrl: dto.mediaUrl,
        mediaType: dto.mediaType,
        mediaFileName: dto.mediaFileName,
      },
    });

    // ── Bump the circle's lastActivityAt ───────────────────────
    await this.prisma.circle.update({
      where: { id: circleId },
      data: { lastActivityAt: new Date() },
    });

    this.logger.log(
      `Message sent: circle=${circleId}, sender=${userId}, type=${dto.messageType ?? 'text'}`,
    );

    return message;
  }

  /**
   * Lists messages (paginated, cursor-based using createdAt).
   */
  async listMessages(
    circleId: string,
    userId: string,
    limit?: number,
    before?: string,
  ) {
    // ── Membership check (defense in depth) ────────────────────
    const isMember = await this.prisma.circleMember.findUnique({
      where: { circleId_userId: { circleId, userId } },
    });
    if (!isMember) {
      throw new ForbiddenException('You are not a member of this circle.');
    }

    const take = Math.min(
      limit ? parseInt(limit, 10) : MESSAGE_PAGINATION_DEFAULT,
      MESSAGE_PAGINATION_MAX,
    );

    return this.prisma.circleMessage.findMany({
      where: {
        circleId,
        isDeletedForEveryone: false,
        ...(before && { createdAt: { lt: new Date(before) } }),
      },
      orderBy: { createdAt: 'desc' },
      take,
      include: {
        reactions: true,
      },
    });
  }

  /**
   * Marks a message (or all unread messages in the circle) as read.
   */
  async markAsRead(circleId: string, userId: string, messageId?: string) {
    const isMember = await this.prisma.circleMember.findUnique({
      where: { circleId_userId: { circleId, userId } },
    });
    if (!isMember) {
      throw new ForbiddenException('You are not a member of this circle.');
    }

    if (messageId) {
      // ── Mark a single message as read ──────────────────────────
      const message = await this.prisma.circleMessage.findUnique({
        where: { id: messageId },
        select: { circleId: true, readBy: true },
      });
      if (!message) {
        throw new NotFoundException('Message not found.');
      }
      if (message.circleId !== circleId) {
        throw new BadRequestException('Message belongs to a different circle.');
      }
      if (!message.readBy.includes(userId)) {
        await this.prisma.$transaction([
          this.prisma.circleMessage.update({
            where: { id: messageId },
            data: { readBy: { push: userId } },
          }),
          this.prisma.circleReadReceipt.upsert({
            where: { messageId_userId: { messageId, userId } },
            create: { messageId, userId },
            update: { readAt: new Date() },
          }),
        ]);
      }
    } else {
      // ── Mark ALL unread messages in the circle as read ────────
      const unreadMessages = await this.prisma.circleMessage.findMany({
        where: {
          circleId,
          senderId: { not: userId },
          isDeletedForEveryone: false,
          NOT: {
            readBy: { has: userId },
          },
        },
        select: { id: true },
      });

      if (unreadMessages.length > 0) {
        // Loop over each message and push userId into readBy.
        // Prisma doesn't support array_append in updateMany, so
        // we use individual updates. For a typical batch of 5-20
        // unread messages this is fast enough; for larger batches
        // (50+), consider a raw SQL UPDATE.
        await this.prisma.$transaction(
          unreadMessages.map((msg) =>
            this.prisma.circleMessage.update({
              where: { id: msg.id },
              data: { readBy: { push: userId } },
            }),
          ),
        );

        // Create read receipts (skipDuplicates so re-reading doesn't fail)
        await this.prisma.circleReadReceipt.createMany({
          data: unreadMessages.map((msg) => ({
            messageId: msg.id,
            userId,
          })),
          skipDuplicates: true,
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Reactions + Pins
  // ═══════════════════════════════════════════════════════════════

  async addReaction(
    circleId: string,
    userId: string,
    messageId: string,
    dto: AddCircleReactionDto,
  ) {
    await this._assertMember(circleId, userId);

    const message = await this.prisma.circleMessage.findUnique({
      where: { id: messageId },
      select: { circleId: true },
    });
    if (!message) throw new NotFoundException('Message not found.');
    if (message.circleId !== circleId) {
      throw new BadRequestException('Message belongs to a different circle.');
    }

    return this.prisma.circleReaction.upsert({
      where: {
        messageId_userId_emoji: { messageId, userId, emoji: dto.emoji },
      },
      create: { messageId, userId, emoji: dto.emoji },
      update: {},
    });
  }

  async removeReaction(
    circleId: string,
    userId: string,
    messageId: string,
    emoji: string,
  ) {
    await this._assertMember(circleId, userId);

    return this.prisma.circleReaction.delete({
      where: {
        messageId_userId_emoji: { messageId, userId, emoji },
      },
    });
  }

  async pinMessage(circleId: string, userId: string, messageId: string) {
    await this._assertAdmin(circleId, userId);

    return this.prisma.circleMessage.update({
      where: { id: messageId },
      data: {
        isPinned: true,
        pinnedBy: userId,
        pinnedAt: new Date(),
      },
    });
  }

  async unpinMessage(circleId: string, userId: string, messageId: string) {
    await this._assertAdmin(circleId, userId);

    return this.prisma.circleMessage.update({
      where: { id: messageId },
      data: {
        isPinned: false,
        pinnedBy: null,
        pinnedAt: null,
      },
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Private helpers
  // ═══════════════════════════════════════════════════════════════

  private async _assertAdmin(circleId: string, userId: string) {
    const member = await this.prisma.circleMember.findUnique({
      where: { circleId_userId: { circleId, userId } },
      select: { role: true },
    });
    if (!member) {
      throw new ForbiddenException('You are not a member of this circle.');
    }
    if (member.role !== 'admin') {
      throw new ForbiddenException('Only admins can perform this action.');
    }
  }

  private async _assertMember(circleId: string, userId: string) {
    const member = await this.prisma.circleMember.findUnique({
      where: { circleId_userId: { circleId, userId } },
    });
    if (!member) {
      throw new ForbiddenException('You are not a member of this circle.');
    }
  }

  /**
   * Fires the "{added by} added you to {circle}" notification.
   * Fire-and-forget — the caller doesn't wait for this.
   *
   * Implementation note: the actual notification dispatch (FCM push +
   * in-app notification row) is deferred to the existing
   * NotificationsModule. For Phase 1, we log the event; the full
   * notification integration is wired in Phase 2 when the Flutter
   * client renders the notification.
   */
  private async _notifyMemberAdded(
    circleId: string,
    addedByUserId: string,
    newMemberUserId: string,
  ) {
    // TODO (Phase 2): integrate with NotificationsModule to:
    //   1. Create a row in the Notification table (type:
    //      'circle:member_added', actionUrl: '/circle/<id>')
    //   2. Send an FCM push to newMemberUserId (respecting their
    //      push preferences)
    //   3. Track analytics event: circle_member_added
    this.logger.log(
      `Notification (pending): "${addedByUserId} added you to circle ${circleId}" → ${newMemberUserId}`,
    );
  }
}
