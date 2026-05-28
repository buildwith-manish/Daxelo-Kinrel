import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class InvitationsService {
  constructor(private readonly prisma: PrismaService) {}

  async acceptInvitation(userId: string, invitationId: string) {
    const invitation = await this.prisma.invitation.findUnique({
      where: { id: invitationId },
    });
    if (!invitation) {
      throw new NotFoundException('Invitation not found');
    }
    if (invitation.inviteeId !== userId) {
      throw new ForbiddenException('This invitation is not for you');
    }
    if (invitation.status !== 'pending') {
      return { message: 'Invitation already processed', invitation };
    }

    // Update invitation status
    const updated = await this.prisma.invitation.update({
      where: { id: invitationId },
      data: { status: 'accepted' },
    });

    // Add user as family member
    await this.prisma.familyMember.create({
      data: {
        familyId: invitation.familyId,
        userId,
        role: invitation.role,
      },
    });

    // Update family member count
    const count = await this.prisma.familyMember.count({
      where: { familyId: invitation.familyId },
    });
    await this.prisma.family.update({
      where: { id: invitation.familyId },
      data: { memberCount: count },
    });

    return { message: 'Invitation accepted', invitation: updated };
  }

  async declineInvitation(userId: string, invitationId: string) {
    const invitation = await this.prisma.invitation.findUnique({
      where: { id: invitationId },
    });
    if (!invitation) {
      throw new NotFoundException('Invitation not found');
    }
    if (invitation.inviteeId !== userId) {
      throw new ForbiddenException('This invitation is not for you');
    }

    const updated = await this.prisma.invitation.update({
      where: { id: invitationId },
      data: { status: 'declined' },
    });

    return { message: 'Invitation declined', invitation: updated };
  }
}
