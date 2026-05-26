import { Injectable, BadRequestException, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { GetInvitationsDto } from './dto/get-invitations.dto';
import { CreateInvitationDto } from './dto/create-invitation.dto';
import { AcceptInvitationDto } from './dto/accept-invitation.dto';
import { randomUUID } from 'crypto';

@Injectable()
export class InvitationsService {
  constructor(private prisma: PrismaService) {}

  /**
   * GET /api/invitations?familyId=xxx&status=xxx
   * List invitations for a family
   */
  async getInvitations(dto: GetInvitationsDto) {
    const where: Record<string, unknown> = { familyId: dto.familyId };
    if (dto.status) {
      where.status = dto.status;
    }

    const invitations = await this.prisma.invitation.findMany({
      where,
      include: {
        inviter: {
          select: { id: true, name: true, email: true, phone: true },
        },
        family: {
          select: { id: true, name: true, primaryLanguage: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    // Parse JSON preFilledData for client convenience
    const parsedInvitations = invitations.map((inv) => ({
      ...inv,
      preFilledData: JSON.parse(inv.preFilledData) as Record<string, unknown>,
    }));

    return { invitations: parsedInvitations };
  }

  /**
   * POST /api/invitations
   * Create invitation: generate token, 7-day expiry, deep link
   */
  async createInvitation(dto: CreateInvitationDto) {
    // Verify family exists
    const family = await this.prisma.family.findUnique({ where: { id: dto.familyId } });
    if (!family) {
      throw new NotFoundException('Family not found');
    }

    // Verify inviter is a member of the family
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId: dto.familyId, userId: dto.inviterId } },
    });
    if (!membership) {
      throw new ForbiddenException('Inviter is not a member of this family');
    }

    // Generate unique token
    const token = randomUUID();
    const now = new Date();

    // Determine if WhatsApp sent timestamp should be set
    const isWhatsapp = dto.channel === 'whatsapp';

    // Create invitation record
    const invitation = await this.prisma.invitation.create({
      data: {
        token,
        familyId: dto.familyId,
        inviterId: dto.inviterId,
        recipientEmail: dto.recipientEmail ?? null,
        recipientPhone: dto.recipientPhone ?? null,
        recipientName: dto.recipientName ?? null,
        status: 'pending',
        role: dto.role ?? 'member',
        channel: dto.channel ?? 'email',
        preFilledData: JSON.stringify(dto.preFilledData ?? {}),
        whatsappSentAt: isWhatsapp ? now : null,
        expiresAt: new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000), // 7 days
      },
      include: {
        inviter: {
          select: { id: true, name: true, email: true },
        },
        family: {
          select: { id: true, name: true },
        },
      },
    });

    // Build deep link
    const appBaseUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'https://daxelo.app';
    const deepLink = `${appBaseUrl}/invite/${token}`;

    // Parse JSON for response
    const parsedInvitation = {
      ...invitation,
      preFilledData: JSON.parse(invitation.preFilledData) as Record<string, unknown>,
      deepLink,
    };

    return { invitation: parsedInvitation };
  }

  /**
   * PATCH /api/invitations
   * Accept invitation: { token }
   */
  async acceptInvitation(dto: AcceptInvitationDto) {
    const invitation = await this.prisma.invitation.findUnique({
      where: { token: dto.token },
    });

    if (!invitation) {
      throw new NotFoundException('Invitation not found');
    }

    if (invitation.status !== 'pending') {
      throw new BadRequestException(`Invitation is already ${invitation.status}`);
    }

    // Check if invitation has expired
    if (invitation.expiresAt && new Date() > invitation.expiresAt) {
      await this.prisma.invitation.update({
        where: { id: invitation.id },
        data: { status: 'expired' },
      });
      throw new BadRequestException('Invitation has expired');
    }

    const now = new Date();

    // Update invitation status
    const updated = await this.prisma.invitation.update({
      where: { id: invitation.id },
      data: {
        status: 'accepted',
        acceptedAt: now,
      },
    });

    // Parse preFilledData for the client
    const preFilledData = JSON.parse(updated.preFilledData) as Record<string, unknown>;

    return {
      invitation: {
        id: updated.id,
        familyId: updated.familyId,
        inviterId: updated.inviterId,
        recipientEmail: updated.recipientEmail,
        recipientPhone: updated.recipientPhone,
        recipientName: updated.recipientName,
        status: updated.status,
        role: updated.role,
        channel: updated.channel,
        preFilledData,
        acceptedAt: updated.acceptedAt,
        createdAt: updated.createdAt,
      },
    };
  }
}
