import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { createHash, randomBytes } from 'crypto';

@Injectable()
export class InvitationsService {
  constructor(private prisma: PrismaService) {}

  /**
   * Create a new family invitation with a unique token.
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

  /**
   * List invitations for a family.
   */
  async findByFamily(familyId: string, userId: string) {
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

    const invitations = await this.prisma.invitation.findMany({
      where: { familyId, status: { in: ['pending', 'accepted'] } },
      include: {
        inviter: { select: { id: true, name: true, email: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    return invitations.map((inv) => this.formatInvitation(inv));
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
   */
  private async acceptInvitation(
    invitation: { id: string; familyId: string; role: string; token: string },
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
}
