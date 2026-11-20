import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { CreateShareableLinkDto, TrackShareDto } from './dto/share.dto';
import { randomBytes } from 'crypto';

const VALID_CARD_TYPES = [
  'family_tree',
  'birthday',
  'anniversary',
  'memorial',
  'milestone',
  'relationship_discovery',
  'festival_greeting',
];

@Injectable()
export class ShareService {
  private readonly logger = new Logger(ShareService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: KinrelGateway,
  ) {}

  /**
   * Create a shareable link.
   * Stores the userId of the creator (`ShareableLink.userId`) for ownership tracking.
   */
  async createShareableLink(userId: string, dto: CreateShareableLinkDto) {
    if (!VALID_CARD_TYPES.includes(dto.cardType)) {
      throw new BadRequestException(
        `Invalid card type. Must be one of: ${VALID_CARD_TYPES.join(', ')}`,
      );
    }

    if (!dto.title || dto.title.trim().length === 0) {
      throw new BadRequestException('Title is required');
    }

    // Generate unique token
    const token = randomBytes(16).toString('hex');

    // Set expiry if specified
    let expiresAt: Date | null = null;
    if (dto.expiresInDays && dto.expiresInDays > 0) {
      expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + dto.expiresInDays);
    }

    // Build deep link URL
    const deepLinkUrl =
      dto.deepLinkUrl ||
      `kinrel://share/${dto.cardType}/${token}`;

    const link = await this.prisma.shareableLink.create({
      data: {
        token,
        cardType: dto.cardType,
        familyId: dto.familyId || null,
        personId: dto.personId || null,
        title: dto.title.trim(),
        description: dto.description?.trim() || '',
        deepLinkUrl,
        expiresAt,
        userId,
      },
    });

    // Emit socket event to creator
    this.gateway.emitToUser(userId, 'share:link_created', {
      id: link.id,
      token: link.token,
      cardType: link.cardType,
      title: link.title,
    });

    return {
      id: link.id,
      token: link.token,
      cardType: link.cardType,
      familyId: link.familyId,
      personId: link.personId,
      title: link.title,
      description: link.description,
      deepLinkUrl: link.deepLinkUrl,
      viewCount: link.viewCount,
      shareCount: link.shareCount,
      expiresAt: link.expiresAt,
      createdAt: link.createdAt,
    };
  }

  /**
   * Get share stats by token.
   */
  async getShareStats(token: string) {
    const link = await this.prisma.shareableLink.findUnique({
      where: { token },
    });

    if (!link) {
      throw new NotFoundException('Shareable link not found');
    }

    return {
      id: link.id,
      token: link.token,
      cardType: link.cardType,
      title: link.title,
      viewCount: link.viewCount,
      shareCount: link.shareCount,
      expiresAt: link.expiresAt,
      createdAt: link.createdAt,
    };
  }

  /**
   * Get shared card data by token (public access — no auth required).
   * Also increments the view count.
   */
  async getSharedCard(token: string) {
    const link = await this.prisma.shareableLink.findUnique({
      where: { token },
    });

    if (!link) {
      throw new NotFoundException('Shared card not found or has expired');
    }

    // Check if expired
    if (link.expiresAt && link.expiresAt < new Date()) {
      throw new NotFoundException('Shared card has expired');
    }

    // Increment view count
    await this.prisma.shareableLink.update({
      where: { token },
      data: { viewCount: { increment: 1 } },
    });

    // Fetch associated data if available
    let familyData: Record<string, any> | null = null;
    let personData: Record<string, any> | null = null;

    if (link.familyId) {
      const family = await this.prisma.family.findUnique({
        where: { id: link.familyId },
        select: {
          id: true,
          name: true,
          description: true,
          avatarUrl: true,
          memberCount: true,
          gotra: true,
          originVillage: true,
          region: true,
        },
      });
      familyData = family;
    }

    if (link.personId) {
      const person = await this.prisma.person.findUnique({
        where: { id: link.personId },
        select: {
          id: true,
          name: true,
          dateOfBirth: true,
          birthYear: true,
          photoUrl: true,
          gender: true,
          gotra: true,
          occupation: true,
          city: true,
        },
      });
      personData = person;
    }

    return {
      id: link.id,
      token: link.token,
      cardType: link.cardType,
      title: link.title,
      description: link.description,
      deepLinkUrl: link.deepLinkUrl,
      viewCount: link.viewCount + 1, // Include the increment we just made
      shareCount: link.shareCount,
      family: familyData,
      person: personData,
      expiresAt: link.expiresAt,
      createdAt: link.createdAt,
    };
  }

  /**
   * Track a share event — increments the shareCount when a user shares
   * a link via any channel (WhatsApp, copy link, etc.).
   */
  async trackShare(dto: TrackShareDto) {
    const link = await this.prisma.shareableLink.findUnique({
      where: { token: dto.token },
    });

    if (!link) {
      throw new NotFoundException('Shareable link not found');
    }

    // Check if expired
    if (link.expiresAt && link.expiresAt < new Date()) {
      throw new NotFoundException('Shareable link has expired');
    }

    const updated = await this.prisma.shareableLink.update({
      where: { token: dto.token },
      data: { shareCount: { increment: 1 } },
    });

    return {
      id: updated.id,
      token: updated.token,
      shareCount: updated.shareCount,
    };
  }

  /**
   * Revoke (delete) a shareable link.
   * Only the creator (`link.userId`) can revoke their own links.
   *
   * Legacy rows (`link.userId IS NULL`, created before the userId column was
   * populated; no creator can be recovered) are NOT locked out: they stay
   * publicly resolvable by token, and an owner/admin of the link's family
   * (`link.familyId`) may revoke them. A legacy row with no familyId cannot
   * be revoked through this API.
   */
  async revokeShareableLink(userId: string, linkId: string) {
    const link = await this.prisma.shareableLink.findUnique({
      where: { id: linkId },
    });

    if (!link) {
      throw new NotFoundException('Shareable link not found');
    }

    if (link.userId) {
      if (link.userId !== userId) {
        throw new ForbiddenException('Not your link');
      }
    } else if (!(await this.isFamilyAdmin(link.familyId, userId))) {
      // Legacy row with no recorded creator.
      throw new ForbiddenException('Not your link');
    }

    await this.prisma.shareableLink.delete({
      where: { id: linkId },
    });

    // Emit socket event
    this.gateway.emitToUser(userId, 'share:link_revoked', {
      id: linkId,
      token: link.token,
    });

    return { deleted: true, id: linkId };
  }

  /**
   * List the shareable links the current user manages: links they created,
   * plus legacy links (`userId IS NULL`) belonging to a family they own/admin
   * (the same set `revokeShareableLink` lets them revoke).
   */
  async getMyShareableLinks(userId: string, limit: number = 20, page: number = 1) {
    const adminFamilyIds = await this.getAdminFamilyIds(userId);
    const where =
      adminFamilyIds.length > 0
        ? {
            OR: [
              { userId },
              { userId: null, familyId: { in: adminFamilyIds } },
            ],
          }
        : { userId };

    const [items, total] = await Promise.all([
      this.prisma.shareableLink.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        select: {
          id: true,
          token: true,
          cardType: true,
          familyId: true,
          personId: true,
          title: true,
          description: true,
          deepLinkUrl: true,
          viewCount: true,
          shareCount: true,
          expiresAt: true,
          createdAt: true,
        },
      }),
      this.prisma.shareableLink.count({ where }),
    ]);

    return { items, total, page, limit };
  }

  /** True if the user is an owner/admin of the family. False when familyId is empty. */
  private async isFamilyAdmin(
    familyId: string | null | undefined,
    userId: string,
  ): Promise<boolean> {
    if (!familyId) return false;
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    return membership?.role === 'owner' || membership?.role === 'admin';
  }

  /** Ids of the families where the user is an owner/admin. */
  private async getAdminFamilyIds(userId: string): Promise<string[]> {
    const rows = await this.prisma.familyMember.findMany({
      where: { userId, role: { in: ['owner', 'admin'] } },
      select: { familyId: true },
    });
    return rows.map((r) => r.familyId);
  }
}
