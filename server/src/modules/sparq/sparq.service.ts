import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { Cron } from '@nestjs/schedule';
import { CreateSparqDto } from './dto/create-sparq.dto';

@Injectable()
export class SparqService {
  private readonly logger = new Logger(SparqService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  // ── Create Sparq ────────────────────────────────────────────────

  /** Creates a new Sparq with 24-hour expiry. Handles media upload for IMAGE/VIDEO/VOICE types. */
  async create(
    userId: string,
    dto: CreateSparqDto,
    mediaFile?: Express.Multer.File,
  ) {
    let mediaUrl: string | null = null;

    // Handle media upload for IMAGE, VIDEO, VOICE types
    if (['IMAGE', 'VIDEO', 'VOICE'].includes(dto.type) && mediaFile) {
      mediaUrl = await this.uploadMedia(mediaFile, userId);
    }

    // Set expiry to 24 hours from now
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);

    const sparq = await this.prisma.sparq.create({
      data: {
        userId,
        type: dto.type as any,
        mediaUrl,
        text: dto.text || null,
        bgColor: dto.bgColor || null,
        audience: (dto.audience || 'PUBLIC') as any,
        expiresAt,
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
            photoThumb: true,
          },
        },
      },
    });

    return this.formatSparq(sparq);
  }

  // ── Delete Sparq ────────────────────────────────────────────────

  /** Deletes a Sparq — only the owner can delete. */
  async delete(sparqId: string, userId: string) {
    const sparq = await this.prisma.sparq.findUnique({
      where: { id: sparqId },
    });

    if (!sparq) {
      throw new NotFoundException('Sparq not found');
    }

    if (sparq.userId !== userId) {
      throw new ForbiddenException('You can only delete your own Sparqs');
    }

    await this.prisma.sparq.delete({ where: { id: sparqId } });

    return { deleted: true, sparqId };
  }

  // ── Get Feed ────────────────────────────────────────────────────

  /**
   * Returns the Sparq feed for the current user, grouped by user.
   * Includes Sparqs from:
   *   - Users the current user follows (status = ACCEPTED)
   *   - The current user's own Sparqs
   */
  async getFeed(userId: string) {
    const now = new Date();

    // Get IDs of users the current user follows (ACCEPTED)
    const following = await this.prisma.follow.findMany({
      where: { followerId: userId, status: 'ACCEPTED' },
      select: { followingId: true },
    });

    const followingIds = following.map((f) => f.followingId);
    // Include own Sparqs in the feed too
    const userIds = [...followingIds, userId];

    // Fetch all active Sparqs from followed users + self
    const sparqs = await this.prisma.sparq.findMany({
      where: {
        userId: { in: userIds },
        expiresAt: { gt: now },
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
            photoThumb: true,
          },
        },
        views: {
          where: { viewerId: userId },
          select: { id: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    // Group by user
    const groupedMap = new Map<
      string,
      {
        userId: string;
        user: { id: string; name: string | null; avatarUrl: string | null };
        sparqs: Record<string, unknown>[];
        hasUnseen: boolean;
        totalCount: number;
      }
    >();

    for (const sparq of sparqs) {
      const existing = groupedMap.get(sparq.userId);
      const formatted = this.formatSparq(sparq);
      const viewed = sparq.views.length > 0;

      const feedItem = {
        ...formatted,
        viewed,
      };

      if (existing) {
        existing.sparqs.push(feedItem);
        existing.totalCount++;
        if (!viewed) {
          existing.hasUnseen = true;
        }
      } else {
        groupedMap.set(sparq.userId, {
          userId: sparq.userId,
          user: {
            id: sparq.user.id,
            name: sparq.user.name,
            avatarUrl: sparq.user.photoThumb || sparq.user.avatarUrl,
          },
          sparqs: [feedItem],
          hasUnseen: !viewed,
          totalCount: 1,
        });
      }
    }

    // Sort: users with unseen Sparqs first, then by most recent Sparq
    const result = Array.from(groupedMap.values()).sort((a, b) => {
      if (a.hasUnseen && !b.hasUnseen) return -1;
      if (!a.hasUnseen && b.hasUnseen) return 1;
      return 0;
    });

    return result;
  }

  // ── Get My Sparqs ───────────────────────────────────────────────

  /** Returns the current user's own active Sparqs. */
  async getMySparqs(userId: string) {
    const now = new Date();

    const sparqs = await this.prisma.sparq.findMany({
      where: {
        userId,
        expiresAt: { gt: now },
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
            photoThumb: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return sparqs.map((s) => this.formatSparq(s));
  }

  // ── Mark as Viewed ──────────────────────────────────────────────

  /** Marks a Sparq as viewed by creating a SparqView record. */
  async markViewed(sparqId: string, viewerId: string) {
    const sparq = await this.prisma.sparq.findUnique({
      where: { id: sparqId },
    });

    if (!sparq) {
      throw new NotFoundException('Sparq not found');
    }

    // Upsert to handle duplicate view attempts gracefully
    await this.prisma.sparqView.upsert({
      where: {
        sparqId_viewerId: { sparqId, viewerId },
      },
      create: {
        sparqId,
        viewerId,
      },
      update: {
        viewedAt: new Date(),
      },
    });

    // Increment view count
    await this.prisma.sparq.update({
      where: { id: sparqId },
      data: { viewCount: { increment: 1 } },
    });

    return { viewed: true, sparqId };
  }

  // ── Get Viewers ─────────────────────────────────────────────────

  /** Returns the list of users who viewed a Sparq (own Sparqs only). */
  async getViewers(sparqId: string, userId: string) {
    const sparq = await this.prisma.sparq.findUnique({
      where: { id: sparqId },
    });

    if (!sparq) {
      throw new NotFoundException('Sparq not found');
    }

    if (sparq.userId !== userId) {
      throw new ForbiddenException('You can only view viewers of your own Sparqs');
    }

    const views = await this.prisma.sparqView.findMany({
      where: { sparqId },
      include: {
        viewer: {
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
            photoThumb: true,
          },
        },
      },
      orderBy: { viewedAt: 'desc' },
    });

    return {
      viewers: views.map((v) => ({
        id: v.viewer.id,
        name: v.viewer.name,
        username: v.viewer.username,
        avatarUrl: v.viewer.photoThumb || v.viewer.avatarUrl,
        viewedAt: v.viewedAt,
      })),
    };
  }

  // ── Cron: Clean up expired Sparqs ───────────────────────────────

  /** Runs every hour to delete all Sparqs where expiresAt < NOW(). */
  @Cron('0 * * * *')
  async cleanupExpiredSparqs() {
    const now = new Date();

    const result = await this.prisma.sparq.deleteMany({
      where: { expiresAt: { lt: now } },
    });

    if (result.count > 0) {
      this.logger.log(`Cleaned up ${result.count} expired Sparqs`);
    }
  }

  // ── Media Upload ────────────────────────────────────────────────

  /** Uploads a media file to Cloudinary (or returns base64 fallback). */
  private async uploadMedia(file: Express.Multer.File, userId: string): Promise<string> {
    const cloudName = this.config.get<string>('CLOUDINARY_CLOUD_NAME');
    const apiKey = this.config.get<string>('CLOUDINARY_API_KEY');
    const apiSecret = this.config.get<string>('CLOUDINARY_API_SECRET');

    if (cloudName && apiKey && apiSecret) {
      const cloudinary = require('cloudinary').v2;
      cloudinary.config({ cloud_name: cloudName, api_key: apiKey, api_secret: apiSecret });

      const folder = 'kinrel/sparqs';
      const publicId = `sparq_${userId}_${Date.now()}`;

      const uploadResult = await new Promise((resolve, reject) => {
        const uploadStream = cloudinary.uploader.upload_stream(
          {
            folder,
            public_id: publicId,
            resource_type: 'auto',
            overwrite: true,
          },
          (error: any, result: any) => {
            if (error) reject(error);
            else resolve(result);
          },
        );
        uploadStream.end(file.buffer);
      });

      return (uploadResult as any).secure_url;
    }

    // Fallback: store as base64 data URL
    const base64 = file.buffer.toString('base64');
    return `data:${file.mimetype};base64,${base64}`;
  }

  // ── Format Sparq ────────────────────────────────────────────────

  private formatSparq(sparq: any) {
    return {
      id: sparq.id,
      type: sparq.type,
      mediaUrl: sparq.mediaUrl,
      text: sparq.text,
      bgColor: sparq.bgColor,
      audience: sparq.audience,
      expiresAt: sparq.expiresAt,
      viewCount: sparq.viewCount ?? 0,
      createdAt: sparq.createdAt,
      ...(sparq.user
        ? {
            user: {
              id: sparq.user.id,
              name: sparq.user.name,
              username: sparq.user.username,
              avatarUrl: sparq.user.photoThumb || sparq.user.avatarUrl,
            },
          }
        : {}),
    };
  }
}
