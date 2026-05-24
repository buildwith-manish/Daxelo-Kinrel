import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { CreateInvitationDto } from './dto/create-invitation.dto';
import { randomUUID } from 'crypto';

@Injectable()
export class InvitationService {
  private readonly logger = new Logger(InvitationService.name);
  private readonly appBaseUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {
    this.appBaseUrl = this.configService.get<string>('NEXT_PUBLIC_APP_URL', 'https://daxelo.app');
  }

  // ── List Invitations ──────────────────────────────────────────────

  async listInvitations(options: { familyId: string; status?: string }) {
    if (!options.familyId) {
      throw new BadRequestException('familyId query parameter is required');
    }

    const where: Record<string, unknown> = { familyId: options.familyId };
    if (options.status) where.status = options.status;

    const invitations = await this.prisma.invitation.findMany({
      where,
      include: {
        inviter: { select: { id: true, name: true, email: true, phone: true } },
        family: { select: { id: true, name: true, primaryLanguage: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    const parsedInvitations = invitations.map((inv) => ({
      ...inv,
      preFilledData: JSON.parse(inv.preFilledData) as Record<string, unknown>,
    }));

    return { invitations: parsedInvitations };
  }

  // ── Create Invitation ─────────────────────────────────────────────

  async createInvitation(dto: CreateInvitationDto) {
    if (!dto.familyId || !dto.inviterId) {
      throw new BadRequestException('familyId and inviterId are required');
    }

    const family = await this.prisma.family.findUnique({ where: { id: dto.familyId } });
    if (!family) throw new NotFoundException('Family not found');

    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId: dto.familyId, userId: dto.inviterId } },
    });
    if (!membership) throw new ForbiddenException('Inviter is not a member of this family');

    const token = randomUUID();
    const now = new Date();
    const isWhatsapp = dto.channel === 'whatsapp';

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
        inviter: { select: { id: true, name: true, email: true } },
        family: { select: { id: true, name: true } },
      },
    });

    const deepLink = `${this.appBaseUrl}/invite/${token}`;

    const parsedInvitation = {
      ...invitation,
      preFilledData: JSON.parse(invitation.preFilledData) as Record<string, unknown>,
      deepLink,
    };

    return { invitation: parsedInvitation };
  }

  // ── Accept Invitation ─────────────────────────────────────────────

  async acceptInvitation(token: string) {
    if (!token) throw new BadRequestException('token is required');

    const invitation = await this.prisma.invitation.findUnique({ where: { token } });
    if (!invitation) throw new NotFoundException('Invitation not found');

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

    const updated = await this.prisma.invitation.update({
      where: { id: invitation.id },
      data: { status: 'accepted', acceptedAt: now },
    });

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
