import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  Inject,
  forwardRef,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { createHash, randomBytes } from 'crypto';

@Injectable()
export class InvitationsService {
  constructor(
    private prisma: PrismaService,
    @Inject(forwardRef(() => NotificationsService))
    private notificationsService: NotificationsService,
  ) {}

  // ── Allowed values for invite permission ────────────────────────────
  private static readonly INVITE_PERMISSION_ANYONE = 'anyone';
  private static readonly INVITE_PERMISSION_CONNECTIONS = 'connections';
  private static readonly INVITE_PERMISSION_NOBODY = 'nobody';

  /**
   * Create a new family invitation with a unique token.
   * Enforces the target user's invitePermission setting:
   *   - anyone: any authenticated user can invite
   *   - connections: only users who share a family can invite
   *   - nobody: no one can invite this user
   */
  async create(
    userId: string,
    data: {
      familyId: string;
      inviterId: string;
      recipientEmail?: string;
      recipientPhone?: string;
      recipientName?: string;
      role?: string;
      channel?: string;
    },
  ) {
    // Verify inviter is a member of the family with admin/editor role
    const membership = await this.prisma.familyMember.findUnique({
      where: {
        familyId_userId: { familyId: data.familyId, userId },
      },
    });

    if (!membership) {
      throw new ForbiddenException(
        'You are not a member of this family',
      );
    }

    if (membership.role !== 'admin' && membership.role !== 'editor') {
      throw new ForbiddenException(
        'Only admins and editors can send invitations',
      );
    }

    // Verify family exists
    const family = await this.prisma.family.findUnique({
      where: { id: data.familyId },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    // ── Check target user's invitePermission ─────────────────────────
    // If the invitation targets an existing user (by email or phone),
    // we must respect their invite permission settings.
    // Look up the invitee by email or phone
    let inviteeUser: { id: string; invitePermission: string } | null = null;

    if (data.recipientEmail) {
      inviteeUser = await this.prisma.user.findUnique({
        where: { email: data.recipientEmail },
        select: { id: true, invitePermission: true },
      });
    }

    if (!inviteeUser && data.recipientPhone) {
      inviteeUser = await this.prisma.user.findFirst({
        where: { phone: data.recipientPhone },
        select: { id: true, invitePermission: true },
      });
    }

    if (inviteeUser) {
      await this._enforceInvitePermission(userId, inviteeUser.id, inviteeUser.invitePermission);
    }

    // Generate unique token
    const token = randomBytes(24).toString('hex');

    // Set expiry to 7 days from now
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7);

    const invitation = await this.prisma.invitation.create({
      data: {
        token,
        familyId: data.familyId,
        inviterId: userId,
        recipientEmail: data.recipientEmail || null,
        recipientPhone: data.recipientPhone || null,
        recipientName: data.recipientName || null,
        role: data.role || 'member',
        channel: data.channel || (data.recipientPhone ? 'whatsapp' : 'email'),
        expiresAt,
      },
      include: {
        family: { select: { id: true, name: true, familyCode: true } },
        inviter: { select: { id: true, name: true, email: true } },
      },
    });

    return this.formatInvitation(invitation);
  }

  // ── Enforce target user's invite permission ──────────────────────

  /**
   * Checks whether the inviter is allowed to invite the target user
   * based on the target's invitePermission setting.
   */
  private async _enforceInvitePermission(
    inviterId: string,
    targetUserId: string,
    invitePermission: string | null,
  ): Promise<void> {
    const permission = invitePermission || InvitationsService.INVITE_PERMISSION_ANYONE;

    // Self-invite doesn't make sense but shouldn't be blocked by permission
    if (inviterId === targetUserId) return;

    switch (permission) {
      case InvitationsService.INVITE_PERMISSION_ANYONE:
        // Anyone can invite — no restriction
        return;

      case InvitationsService.INVITE_PERMISSION_CONNECTIONS:
        // Only connections (users sharing a family) can invite
        const areConnections = await this._areConnections(inviterId, targetUserId);
        if (!areConnections) {
          throw new ForbiddenException(
            'This user only accepts invitations from their connections',
          );
        }
        return;

      case InvitationsService.INVITE_PERMISSION_NOBODY:
        throw new ForbiddenException(
          'This user does not accept invitations',
        );

      default:
        // Unknown permission — default to allowing (backward compatibility)
        return;
    }
  }

  // ── Check if two users share a family (are "connections") ────────

  /** Returns true if two users are members of at least one common family. */
  private async _areConnections(userIdA: string, userIdB: string): Promise<boolean> {
    const familiesA = await this.prisma.familyMember.findMany({
      where: { userId: userIdA },
      select: { familyId: true },
    });
    const familyIdsA = new Set(familiesA.map((m) => m.familyId));

    if (familyIdsA.size === 0) return false;

    const overlap = await this.prisma.familyMember.findFirst({
      where: {
        userId: userIdB,
        familyId: { in: [...familyIdsA] },
      },
    });

    return !!overlap;
  }

  /**
   * List invitations for a family, with pagination.
   */
  async findByFamily(familyId: string, userId: string, pagination?: { page?: number; limit?: number }) {
    // Verify user is a member
    const membership = await this.prisma.familyMember.findUnique({
      where: {
        familyId_userId: { familyId, userId },
      },
    });

    if (!membership) {
      throw new ForbiddenException(
        'You are not a member of this family',
      );
    }

    const page = pagination?.page ?? 1;
    const limit = pagination?.limit ?? 20;
    const skip = (page - 1) * limit;

    const [items, total] = await this.prisma.$transaction([
      this.prisma.invitation.findMany({
        where: { familyId, status: { in: ['pending', 'accepted'] } },
        skip,
        take: limit,
        include: {
          inviter: { select: { id: true, name: true, email: true } },
        },
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.invitation.count({
        where: { familyId, status: { in: ['pending', 'accepted'] } },
      }),
    ]);

    return {
      items: items.map((inv) => this.formatInvitation(inv)),
      total,
      page,
      limit,
    };
  }

  /**
   * Accept an invitation by ID (Flutter app endpoint).
   * The user must be authenticated and the invitation must be pending and not expired.
   */
  async acceptById(invitationId: string, userId: string) {
    const invitation = await this.prisma.invitation.findUnique({
      where: { id: invitationId },
    });

    if (!invitation) {
      throw new NotFoundException('Invitation not found');
    }

    if (invitation.status !== 'pending') {
      throw new BadRequestException(
        `Invitation is already ${invitation.status}`,
      );
    }

    if (invitation.expiresAt && invitation.expiresAt < new Date()) {
      await this.prisma.invitation.update({
        where: { id: invitationId },
        data: { status: 'expired' },
      });
      throw new BadRequestException('Invitation has expired');
    }

    return this.acceptInvitation(invitation, userId);
  }

  /**
   * Decline an invitation by ID (Flutter app endpoint).
   */
  async declineById(invitationId: string, userId: string) {
    const invitation = await this.prisma.invitation.findUnique({
      where: { id: invitationId },
    });

    if (!invitation) {
      throw new NotFoundException('Invitation not found');
    }

    if (invitation.status !== 'pending') {
      throw new BadRequestException(
        `Invitation is already ${invitation.status}`,
      );
    }

    const updated = await this.prisma.invitation.update({
      where: { id: invitationId },
      data: { status: 'cancelled' },
    });

    return { accepted: false, invitationId: updated.id, status: updated.status };
  }

  /**
   * Accept an invitation by token (Next.js route).
   */
  async acceptByToken(token: string, userId: string) {
    const invitation = await this.prisma.invitation.findUnique({
      where: { token },
    });

    if (!invitation) {
      throw new NotFoundException('Invitation not found');
    }

    if (invitation.status !== 'pending') {
      throw new BadRequestException(
        `Invitation is already ${invitation.status}`,
      );
    }

    if (invitation.expiresAt && invitation.expiresAt < new Date()) {
      await this.prisma.invitation.update({
        where: { token },
        data: { status: 'expired' },
      });
      throw new BadRequestException('Invitation has expired');
    }

    return this.acceptInvitation(invitation, userId);
  }

  /**
   * Cancel (revoke) an invitation.
   */
  async cancel(invitationId: string, userId: string) {
    const invitation = await this.prisma.invitation.findUnique({
      where: { id: invitationId },
    });

    if (!invitation) {
      throw new NotFoundException('Invitation not found');
    }

    // Only the inviter or a family admin can cancel
    if (invitation.inviterId !== userId) {
      const membership = await this.prisma.familyMember.findUnique({
        where: {
          familyId_userId: { familyId: invitation.familyId, userId },
        },
      });

      if (!membership || membership.role !== 'admin') {
        throw new ForbiddenException(
          'Only the inviter or a family admin can cancel this invitation',
        );
      }
    }

    if (invitation.status !== 'pending') {
      throw new BadRequestException(
        `Cannot cancel an invitation that is ${invitation.status}`,
      );
    }

    const updated = await this.prisma.invitation.update({
      where: { id: invitationId },
      data: { status: 'cancelled' },
    });

    return { cancelled: true, invitationId: updated.id };
  }

  /**
   * Internal: Accept an invitation — add user as FamilyMember and update status.
   * Also sends notifications to the accepting user, the inviter, and other admins.
   */
  private async acceptInvitation(
    invitation: { id: string; familyId: string; role: string; token: string; inviterId?: string },
    userId: string,
  ) {
    // Check if user is already a member
    const existing = await this.prisma.familyMember.findUnique({
      where: {
        familyId_userId: { familyId: invitation.familyId, userId },
      },
    });

    if (existing) {
      throw new BadRequestException(
        'You are already a member of this family',
      );
    }

    const result = await this.prisma.$transaction(async (tx) => {
      // Create FamilyMember
      await tx.familyMember.create({
        data: {
          familyId: invitation.familyId,
          userId,
          role: invitation.role,
        },
      });

      // Increment family member count
      await tx.family.update({
        where: { id: invitation.familyId },
        data: {
          memberCount: { increment: 1 },
          lastActivityAt: new Date(),
        },
      });

      // Update invitation status
      const updated = await tx.invitation.update({
        where: { id: invitation.id },
        data: {
          status: 'accepted',
          acceptedAt: new Date(),
        },
      });

      return updated;
    });

    // ── Send notifications (fire-and-forget) ─────────────────────────
    try {
      // Fetch family name, accepting user name, and inviter ID
      const [family, acceptingUser, fullInvitation] = await Promise.all([
        this.prisma.family.findUnique({
          where: { id: invitation.familyId },
          select: { name: true },
        }),
        this.prisma.user.findUnique({
          where: { id: userId },
          select: { name: true },
        }),
        this.prisma.invitation.findUnique({
          where: { id: invitation.id },
          select: { inviterId: true },
        }),
      ]);

      const familyName = family?.name ?? 'the family';
      const acceptingUserName = acceptingUser?.name ?? 'A family member';
      const inviterId = fullInvitation?.inviterId;

      // Notification A — to the user who accepted
      this.notificationsService.notifyFamilyJoined(userId, familyName, invitation.familyId);

      if (inviterId) {
        // Notification B — to the inviter (personalised "accepted your invite")
        this.notificationsService.notifyFamilyMemberJoined(
          inviterId,
          acceptingUserName,
          familyName,
          invitation.familyId,
          true, // isDirectInviteAccept
        );
      }

      // Notification C — to all other admins (excluding inviter)
      const admins = await this.prisma.familyMember.findMany({
        where: { familyId: invitation.familyId, role: 'admin' },
        select: { userId: true },
      });

      for (const admin of admins.filter((a) => a.userId !== userId && a.userId !== inviterId)) {
        this.notificationsService.notifyFamilyMemberJoined(
          admin.userId,
          acceptingUserName,
          familyName,
          invitation.familyId,
        );
      }
    } catch (e) {
      // Swallow errors — never fail the accept flow after successful transaction
      console.error('Failed to send invitation-accept notifications', e);
    }

    return {
      accepted: true,
      invitationId: result.id,
      familyId: invitation.familyId,
      role: invitation.role,
    };
  }

  private formatInvitation(inv: any) {
    return {
      id: inv.id,
      token: inv.token,
      familyId: inv.familyId,
      inviterId: inv.inviterId,
      family: inv.family || undefined,
      inviter: inv.inviter || undefined,
      recipientEmail: inv.recipientEmail,
      recipientPhone: inv.recipientPhone,
      recipientName: inv.recipientName,
      status: inv.status,
      role: inv.role,
      channel: inv.channel,
      expiresAt: inv.expiresAt,
      acceptedAt: inv.acceptedAt,
      createdAt: inv.createdAt,
    };
  }

  /**
   * Checks whether two users share at least one family.
   * Used by invitePermission='connections' enforcement.
   */
  private async usersShareFamily(userId1: string, userId2: string): Promise<boolean> {
    const [user1Families, user2Families] = await Promise.all([
      this.prisma.familyMember.findMany({
        where: { userId: userId1 },
        select: { familyId: true },
      }),
      this.prisma.familyMember.findMany({
        where: { userId: userId2 },
        select: { familyId: true },
      }),
    ]);

    const familyIds1 = new Set(user1Families.map((m) => m.familyId));
    return user2Families.some((m) => familyIds1.has(m.familyId));
  }
}

