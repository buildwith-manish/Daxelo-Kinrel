import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { CreateSparqDto, SparqFeedDto } from './dto/sparq.dto';

@Injectable()
export class SparqService {
  private readonly logger = new Logger(SparqService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: KinrelGateway,
  ) {}

  /** Get the Sparq feed — grouped by user, unseen users first */
  async getFeed(userId: string, dto: SparqFeedDto) {
    const limit = dto.limit ?? 20;

    // Get IDs of users the current user follows (ACCEPTED)
    const following = await this.prisma.follow.findMany({
      where: { followerId: userId, status: 'ACCEPTED' },
      select: { followingId: true },
    });
    const followedIds = following.map((f) => f.followingId);

    // Get IDs of families the current user is a member of
    const familyMemberships = await this.prisma.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });
    const familyIds = familyMemberships.map((m) => m.familyId);

    // Get member IDs from those families
    const familyMemberRecords = familyIds.length
      ? await this.prisma.familyMember.findMany({
          where: { familyId: { in: familyIds } },
          select: { userId: true },
          distinct: ['userId'],
        })
      : [];
    const familyMemberIds = familyMemberRecords.map((m) => m.userId);

    // Combine: followed users + family members, deduplicated
    const relevantUserIds = [...new Set([...followedIds, ...familyMemberIds])];

    if (relevantUserIds.length === 0) {
      return { items: [], total: 0 };
    }

    // Fetch active Sparqs from relevant users
    const now = new Date();
    const sparqs = await this.prisma.sparq.findMany({
      where: {
        userId: { in: relevantUserIds },
        expiresAt: { gt: now },
        OR: [
          { audience: 'PUBLIC' },
          { audience: 'FAMILY_ONLY', userId: { in: familyMemberIds } },
        ],
      },
      include: {
        user: {
          select: { id: true, name: true, username: true, avatarUrl: true, photoThumb: true },
        },
        views: {
          where: { viewerId: userId },
          select: { id: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    // Group by user
    const grouped = new Map<string, {
      user: typeof sparqs[0]['user'];
      sparqs: typeof sparqs;
      allSeen: boolean;
    }>();

    for (const sparq of sparqs) {
      const existing = grouped.get(sparq.userId);
      if (existing) {
        existing.sparqs.push(sparq);
      } else {
        grouped.set(sparq.userId, {
          user: sparq.user,
          sparqs: [sparq],
          allSeen: sparq.views.length > 0,
        });
      }
      // Update allSeen: false if any sparq has not been seen
      if (sparq.views.length === 0) {
        grouped.get(sparq.userId)!.allSeen = false;
      }
    }

    // Sort: unseen users first, then by most recent sparq
    const items = [...grouped.values()].sort((a, b) => {
      if (a.allSeen !== b.allSeen) return a.allSeen ? 1 : -1;
      return new Date(b.sparqs[0].createdAt).getTime() - new Date(a.sparqs[0].createdAt).getTime();
    });

    return { items: items.slice(0, limit), total: items.length };
  }

  /** Create a new Sparq */
  async createSparq(userId: string, dto: CreateSparqDto, mediaUrl?: string, thumbnailUrl?: string) {
    const now = new Date();
    const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000); // 24 hours

    const sparq = await this.prisma.sparq.create({
      data: {
        userId,
        type: dto.type as any,
        mediaUrl: mediaUrl ?? null,
        thumbnailUrl: thumbnailUrl ?? null,
        text: dto.text ?? null,
        backgroundColor: dto.backgroundColor ?? null,
        duration: dto.duration ?? null,
        audience: (dto.audience ?? 'PUBLIC') as any,
        expiresAt,
      },
    });

    // Emit to relevant users
    this.gateway.emitToUser(userId, 'sparq:new', { sparqId: sparq.id, userId });

    return sparq;
  }

  /** Get all active Sparqs for a specific user */
  async getUserSparqs(userId: string, viewerId: string) {
    const now = new Date();

    // Check if viewer should see FAMILY_ONLY sparqs
    const isFamilyMember = await this.isFamilyMember(viewerId, userId);

    const whereClause: any = {
      userId,
      expiresAt: { gt: now },
      OR: [{ audience: 'PUBLIC' }],
    };

    if (isFamilyMember) {
      whereClause.OR.push({ audience: 'FAMILY_ONLY' });
    }

    const sparqs = await this.prisma.sparq.findMany({
      where: whereClause,
      orderBy: { createdAt: 'desc' },
      include: {
        views: {
          where: { viewerId },
          select: { id: true, viewedAt: true },
        },
      },
    });

    return sparqs;
  }

  /** Mark a Sparq as viewed */
  async markViewed(sparqId: string, viewerId: string) {
    const sparq = await this.prisma.sparq.findUnique({ where: { id: sparqId } });
    if (!sparq) {
      throw new NotFoundException('Sparq not found');
    }

    // Upsert view record
    await this.prisma.sparqView.upsert({
      where: { sparqId_viewerId: { sparqId, viewerId } },
      create: { sparqId, viewerId },
      update: { viewedAt: new Date() },
    });

    // Increment view count
    await this.prisma.sparq.update({
      where: { id: sparqId },
      data: { viewCount: { increment: 1 } },
    });

    return { success: true };
  }

  /** Get viewers for a specific Sparq — creator only */
  async getViewers(sparqId: string, userId: string) {
    const sparq = await this.prisma.sparq.findUnique({ where: { id: sparqId } });
    if (!sparq) {
      throw new NotFoundException('Sparq not found');
    }
    if (sparq.userId !== userId) {
      throw new ForbiddenException('Only the creator can view viewers');
    }

    const views = await this.prisma.sparqView.findMany({
      where: { sparqId },
      include: {
        viewer: {
          select: { id: true, name: true, username: true, avatarUrl: true, photoThumb: true },
        },
      },
      orderBy: { viewedAt: 'desc' },
    });

    return views.map((v) => ({
      ...v.viewer,
      viewedAt: v.viewedAt,
    }));
  }

  /** Delete your own Sparq */
  async deleteSparq(sparqId: string, userId: string) {
    const sparq = await this.prisma.sparq.findUnique({ where: { id: sparqId } });
    if (!sparq) {
      throw new NotFoundException('Sparq not found');
    }
    if (sparq.userId !== userId) {
      throw new ForbiddenException('You can only delete your own Sparqs');
    }

    await this.prisma.sparq.delete({ where: { id: sparqId } });
    return { success: true };
  }

  /** Scheduled job: delete expired Sparqs every hour */
  @Cron('0 * * * *')
  async cleanupExpiredSparqs() {
    const now = new Date();
    try {
      const result = await this.prisma.sparq.deleteMany({
        where: { expiresAt: { lte: now } },
      });
      if (result.count > 0) {
        this.logger.log(`Cleaned up ${result.count} expired Sparqs`);
      }
    } catch (error) {
      this.logger.error('Failed to cleanup expired Sparqs', error);
    }
  }

  /** Check if two users are in the same family */
  private async isFamilyMember(userId1: string, userId2: string): Promise<boolean> {
    const user1Families = await this.prisma.familyMember.findMany({
      where: { userId: userId1 },
      select: { familyId: true },
    });
    if (user1Families.length === 0) return false;

    const user2InSameFamily = await this.prisma.familyMember.findFirst({
      where: {
        userId: userId2,
        familyId: { in: user1Families.map((f) => f.familyId) },
      },
    });
    return !!user2InSameFamily;
  }
}
