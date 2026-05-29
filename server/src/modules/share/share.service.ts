import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
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
  constructor(private prisma: PrismaService) {}

  /**
   * Create a shareable link.
   */
  async createShareableLink(
    userId: string,
    data: {
      cardType: string;
      familyId?: string;
      personId?: string;
      title: string;
      description?: string;
      deepLinkUrl?: string;
      expiresInDays?: number;
    },
  ) {
    if (!VALID_CARD_TYPES.includes(data.cardType)) {
      throw new BadRequestException(
        `Invalid card type. Must be one of: ${VALID_CARD_TYPES.join(', ')}`,
      );
    }

    if (!data.title || data.title.trim().length === 0) {
      throw new BadRequestException('Title is required');
    }

    // Generate unique token
    const token = randomBytes(16).toString('hex');

    // Set expiry if specified
    let expiresAt: Date | null = null;
    if (data.expiresInDays && data.expiresInDays > 0) {
      expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + data.expiresInDays);
    }

    // Build deep link URL
    const deepLinkUrl =
      data.deepLinkUrl ||
      `kinrel://share/${data.cardType}/${token}`;

    const link = await this.prisma.shareableLink.create({
      data: {
        token,
        cardType: data.cardType,
        familyId: data.familyId || null,
        personId: data.personId || null,
        title: data.title.trim(),
        description: data.description?.trim() || '',
        deepLinkUrl,
        expiresAt,
      },
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
}
