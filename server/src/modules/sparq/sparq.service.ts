import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
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
    private readonly config: ConfigService,
  ) {}

  /** Get the Sparq feed — grouped by user, unseen users first */
  async getFeed(userId: string, dto: SparqFeedDto) {
    const page = dto.page ?? 1;
    const limit = dto.limit ?? 20;
    const skip = (page - 1) * limit;

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

    // Get IDs of mutual followers (users who follow each other) for VIP_CIRCLE
    const mutualFollowerIds = await this.getMutualFollowerIds(userId);

    // Combine: followed users + family members, deduplicated
    const relevantUserIds = [...new Set([...followedIds, ...familyMemberIds])];

    if (relevantUserIds.length === 0) {
      return { items: [], total: 0, page, limit };
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
          { audience: 'VIP_CIRCLE', userId: { in: mutualFollowerIds } },
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

    // Strip unrevealed time capsule content
    const sanitizedSparqs = sparqs.map((s) => this.stripUnrevealedContent(s));

    // Group by user
    const grouped = new Map<string, {
      user: typeof sanitizedSparqs[0]['user'];
      sparqs: typeof sanitizedSparqs;
      allSeen: boolean;
    }>();

    for (const sparq of sanitizedSparqs) {
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

    // Apply pagination using both page and limit
    const total = items.length;
    const paginatedItems = items.slice(skip, skip + limit);

    return { items: paginatedItems, total, page, limit };
  }

  /** Create a new Sparq */
  async createSparq(userId: string, dto: CreateSparqDto, file?: Express.Multer.File) {
    // Validate time capsule fields
    if (dto.isTimeCapsule && !dto.revealAt) {
      throw new BadRequestException('revealAt is required for Time Capsule Sparqs');
    }
    if (dto.revealAt && new Date(dto.revealAt) <= new Date()) {
      throw new BadRequestException('revealAt must be a future timestamp');
    }

    // Validate file size (10MB limit)
    if (file && file.size > 10 * 1024 * 1024) {
      throw new BadRequestException({
        statusCode: 400,
        errorCode: 'FILE_TOO_LARGE',
        message: 'File exceeds 10MB limit',
        details: { maxAllowedMB: 10, receivedMB: Math.round(file.size / (1024 * 1024) * 10) / 10 },
      });
    }

    const now = new Date();
    const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000); // 24 hours

    let mediaUrl: string | null = null;
    let thumbnailUrl: string | null = null;

    // Upload media file to Cloudinary if provided
    if (file) {
      const result = await this.uploadMediaToCloudinary(userId, file);
      mediaUrl = result.mediaUrl;
      thumbnailUrl = result.thumbnailUrl;
    } else if (dto.type === 'IMAGE' || dto.type === 'VIDEO' || dto.type === 'VOICE') {
      throw new BadRequestException(`Media file is required for type ${dto.type}`);
    }

    const sparq = await this.prisma.sparq.create({
      data: {
        userId,
        type: dto.type as any,
        mediaUrl,
        thumbnailUrl,
        text: dto.text ?? null,
        backgroundColor: dto.backgroundColor ?? null,
        duration: dto.duration ?? null,
        audience: (dto.audience ?? 'PUBLIC') as any,
        mood: (dto.mood ?? 'happy') as any,
        intensity: (dto.intensity ?? 'warm') as any,
        allowChain: dto.allowChain ?? false,
        allowReplies: dto.allowReplies ?? true,
        isTimeCapsule: dto.isTimeCapsule ?? false,
        revealAt: dto.revealAt ? new Date(dto.revealAt) : null,
        isRevealed: dto.isTimeCapsule ? false : true,
        parentSparqId: dto.parentSparqId ?? null,
        expiresAt,
      },
    });

    // Emit to relevant users
    this.gateway.emitToUser(userId, 'sparq:new', { sparqId: sparq.id, userId });

    return sparq;
  }

  /** Toggle echo on a Sparq — adds or removes the echo */
  async toggleEcho(sparqId: string, userId: string) {
    const sparq = await this.prisma.sparq.findUnique({ where: { id: sparqId } });
    if (!sparq) throw new NotFoundException('Sparq not found');

    const existing = await this.prisma.sparqEcho.findUnique({
      where: { sparqId_userId: { sparqId, userId } },
    });

    if (existing) {
      // Remove echo
      await this.prisma.sparqEcho.delete({ where: { id: existing.id } });
      await this.prisma.sparq.update({
        where: { id: sparqId },
        data: { echoCount: { decrement: 1 } },
      });
      return { echoCount: sparq.echoCount - 1, isEchoed: false };
    } else {
      // Add echo
      await this.prisma.sparqEcho.create({ data: { sparqId, userId } });
      await this.prisma.sparq.update({
        where: { id: sparqId },
        data: { echoCount: { increment: 1 } },
      });
      return { echoCount: sparq.echoCount + 1, isEchoed: true };
    }
  }

  /** Get all Sparqs in a chain */
  async getChain(sparqId: string) {
    // Find the root of the chain (the original sparq)
    const sparq = await this.prisma.sparq.findUnique({ where: { id: sparqId } });
    if (!sparq) throw new NotFoundException('Sparq not found');

    const rootId = sparq.parentSparqId ?? sparqId;

    const chain = await this.prisma.sparq.findMany({
      where: {
        OR: [
          { id: rootId },
          { parentSparqId: rootId },
        ],
      },
      include: {
        user: { select: { id: true, name: true, username: true, avatarUrl: true, photoThumb: true } },
      },
      orderBy: { chainOrder: 'asc' },
    });

    return chain;
  }

  /** Add a Sparq to an existing chain */
  async addToChain(parentSparqId: string, userId: string, dto: CreateSparqDto, file?: Express.Multer.File) {
    const parent = await this.prisma.sparq.findUnique({ where: { id: parentSparqId } });
    if (!parent) throw new NotFoundException('Parent Sparq not found');
    if (!parent.allowChain) throw new BadRequestException('This Sparq does not allow chaining');

    // Find root
    const rootId = parent.parentSparqId ?? parentSparqId;

    // Count existing chain items
    const chainCount = await this.prisma.sparq.count({
      where: {
        OR: [
          { id: rootId },
          { parentSparqId: rootId },
        ],
      },
    });

    if (chainCount >= 10) throw new BadRequestException('Chain limit of 10 reached');

    // Verify requester follows the original poster
    const follow = await this.prisma.follow.findFirst({
      where: { followerId: userId, followingId: parent.userId, status: 'ACCEPTED' },
    });

    // Allow if same user or following
    if (parent.userId !== userId && !follow) {
      throw new ForbiddenException('You must follow the creator to chain their Sparq');
    }

    const now = new Date();
    const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000);

    let mediaUrl: string | null = null;
    let thumbnailUrl: string | null = null;

    if (file) {
      const result = await this.uploadMediaToCloudinary(userId, file);
      mediaUrl = result.mediaUrl;
      thumbnailUrl = result.thumbnailUrl;
    }

    const sparq = await this.prisma.sparq.create({
      data: {
        userId,
        type: dto.type as any,
        mediaUrl,
        thumbnailUrl,
        text: dto.text ?? null,
        backgroundColor: dto.backgroundColor ?? null,
        duration: dto.duration ?? null,
        audience: (dto.audience ?? 'PUBLIC') as any,
        mood: (dto.mood ?? 'happy') as any,
        intensity: (dto.intensity ?? 'warm') as any,
        allowChain: dto.allowChain ?? false,
        allowReplies: dto.allowReplies ?? true,
        isTimeCapsule: dto.isTimeCapsule ?? false,
        revealAt: dto.revealAt ? new Date(dto.revealAt) : null,
        isRevealed: false,
        parentSparqId: rootId,
        chainOrder: chainCount + 1,
        expiresAt,
      },
    });

    // Notify original poster
    if (parent.userId !== userId) {
      this.gateway.emitToUser(parent.userId, 'sparq:chained', {
        sparqId: sparq.id,
        parentSparqId,
        userId,
      });
    }

    return sparq;
  }

  /** Upload a Sparq media file to Cloudinary, returning mediaUrl and thumbnailUrl */
  private async uploadMediaToCloudinary(
    userId: string,
    file: Express.Multer.File,
  ): Promise<{ mediaUrl: string; thumbnailUrl: string | null }> {
    const cloudName = this.config.get<string>('CLOUDINARY_CLOUD_NAME');
    const apiKey = this.config.get<string>('CLOUDINARY_API_KEY');
    const apiSecret = this.config.get<string>('CLOUDINARY_API_SECRET');

    // Fallback for dev: store as base64 data URL
    if (!cloudName || !apiKey || !apiSecret) {
      const base64 = file.buffer.toString('base64');
      const dataUrl = `data:${file.mimetype};base64,${base64}`;
      return { mediaUrl: dataUrl, thumbnailUrl: null };
    }

    const cloudinary = require('cloudinary').v2;
    cloudinary.config({ cloud_name: cloudName, api_key: apiKey, api_secret: apiSecret });

    const isVideo = file.mimetype.startsWith('video/');
    const isAudio = file.mimetype.startsWith('audio/');

    const uploadResult = await new Promise<any>((resolve, reject) => {
      const uploadStream = cloudinary.uploader.upload_stream(
        {
          folder: 'kinrel/sparqs',
          public_id: `sparq_${userId}_${Date.now()}`,
          resource_type: isVideo ? 'video' : isAudio ? 'video' : 'image',
          ...(isVideo && {
            transformation: [{ width: 1080, crop: 'limit', quality: 'auto' }],
          }),
          ...(isAudio && {
            transformation: [{ quality: 'auto' }],
          }),
          overwrite: true,
        },
        (error: any, result: any) => {
          if (error) reject(error);
          else resolve(result);
        },
      );
      uploadStream.end(file.buffer);
    });

    const mediaUrl: string = uploadResult.secure_url;
    const publicId = uploadResult.public_id;

    // Generate thumbnail: for videos Cloudinary can auto-generate one;
    // for images, apply a smaller transformation; for audio, no thumbnail.
    let thumbnailUrl: string | null = null;

    if (isVideo) {
      thumbnailUrl = cloudinary.url(publicId, {
        resource_type: 'video',
        transformation: [
          { width: 400, height: 400, crop: 'fill', quality: 'auto', fetch_format: 'auto', start_offset: '1' },
        ],
      });
    } else if (!isAudio) {
      thumbnailUrl = cloudinary.url(publicId, {
        transformation: [
          { width: 400, height: 400, crop: 'fill', quality: 'auto', fetch_format: 'auto' },
        ],
      });
    }

    return { mediaUrl, thumbnailUrl };
  }

  /** Get all active Sparqs for a specific user */
  async getUserSparqs(userId: string, viewerId: string) {
    const now = new Date();

    // Check if viewer should see FAMILY_ONLY sparqs
    const isFamilyMember = await this.isFamilyMember(viewerId, userId);

    // Check if viewer is a mutual follower for VIP_CIRCLE
    const isMutualFollower = await this.isMutualFollower(viewerId, userId);

    const whereClause: any = {
      userId,
      expiresAt: { gt: now },
      OR: [{ audience: 'PUBLIC' }],
    };

    if (isFamilyMember) {
      whereClause.OR.push({ audience: 'FAMILY_ONLY' });
    }

    if (isMutualFollower) {
      whereClause.OR.push({ audience: 'VIP_CIRCLE' });
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

    // Strip unrevealed time capsule content
    return sparqs.map((s) => this.stripUnrevealedContent(s));
  }

  /** Mark a Sparq as viewed — increments viewCount only on first view */
  async markViewed(sparqId: string, viewerId: string) {
    const sparq = await this.prisma.sparq.findUnique({ where: { id: sparqId } });
    if (!sparq) {
      throw new NotFoundException('Sparq not found');
    }

    // Check if this viewer has already viewed this Sparq
    const existingView = await this.prisma.sparqView.findUnique({
      where: { sparqId_viewerId: { sparqId, viewerId } },
    });

    if (existingView) {
      // Already viewed — just update the timestamp, do NOT increment viewCount
      await this.prisma.sparqView.update({
        where: { id: existingView.id },
        data: { viewedAt: new Date() },
      });
    } else {
      // First view — create the record AND increment viewCount
      await this.prisma.sparqView.create({
        data: { sparqId, viewerId },
      });
      await this.prisma.sparq.update({
        where: { id: sparqId },
        data: { viewCount: { increment: 1 } },
      });
    }

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

  /** Scheduled job: reveal time capsule Sparqs every minute */
  @Cron('* * * * *')
  async revealTimeCapsuleSparqs() {
    const now = new Date();
    try {
      const toReveal = await this.prisma.sparq.findMany({
        where: {
          isTimeCapsule: true,
          isRevealed: false,
          revealAt: { lte: now },
        },
      });

      for (const sparq of toReveal) {
        await this.prisma.sparq.update({
          where: { id: sparq.id },
          data: { isRevealed: true },
        });

        // Emit real-time event
        this.gateway.emitToUser(sparq.userId, 'sparq:timecapsule-revealed', {
          sparqId: sparq.id,
        });
      }

      if (toReveal.length > 0) {
        this.logger.log(`Revealed ${toReveal.length} Time Capsule Sparqs`);
      }
    } catch (error) {
      this.logger.error('Failed to reveal Time Capsule Sparqs', error);
    }
  }

  /** Strip content from unrevealed time capsule Sparqs */
  private stripUnrevealedContent(sparq: any) {
    if (sparq.isTimeCapsule && !sparq.isRevealed) {
      return { ...sparq, mediaUrl: null, thumbnailUrl: null, text: null };
    }
    return sparq;
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

  /** Check if two users are mutual followers (both follow each other) */
  private async isMutualFollower(userId1: string, userId2: string): Promise<boolean> {
    const forward = await this.prisma.follow.findFirst({
      where: { followerId: userId1, followingId: userId2, status: 'ACCEPTED' },
    });
    if (!forward) return false;

    const reverse = await this.prisma.follow.findFirst({
      where: { followerId: userId2, followingId: userId1, status: 'ACCEPTED' },
    });
    return !!reverse;
  }

  /** Get IDs of mutual followers for a user (users who follow each other) */
  private async getMutualFollowerIds(userId: string): Promise<string[]> {
    // Users that the current user follows
    const following = await this.prisma.follow.findMany({
      where: { followerId: userId, status: 'ACCEPTED' },
      select: { followingId: true },
    });
    const followingIds = following.map((f) => f.followingId);

    if (followingIds.length === 0) return [];

    // Of those, find users who also follow the current user back (mutual)
    const mutualFollows = await this.prisma.follow.findMany({
      where: {
        followerId: { in: followingIds },
        followingId: userId,
        status: 'ACCEPTED',
      },
      select: { followerId: true },
    });

    return mutualFollows.map((f) => f.followerId);
  }
}
