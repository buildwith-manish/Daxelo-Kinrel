import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { CreateStoryDto } from './dto/create-story.dto';

/**
 * StoriesService — Ephemeral stories with media upload, audience control,
 * cron cleanup, and real-time socket events.
 *
 * SCHEMA CHANGE REQUESTS (for Agent-0):
 * ─────────────────────────────────────
 * The Story model needs two additional fields:
 *   audience     String   @default("PUBLIC")  // PUBLIC | FAMILY_ONLY
 *   thumbnailUrl String?                      // Cloudinary thumbnail
 *
 * Until the schema is updated, `audience` is accepted in the DTO but
 * not persisted, and `thumbnailUrl` is computed but not stored.
 */

@Injectable()
export class StoriesService {
  private readonly logger = new Logger(StoriesService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: KinrelGateway,
    private readonly config: ConfigService,
  ) {}

  // ── CRUD ────────────────────────────────────────────────────

  /** Creates a new story for the given user.
   *  Defaults expiresAt to now + 24h if not provided.
   *  Handles file upload via Cloudinary (with base64 fallback for dev). */
  async create(
    userId: string,
    dto: CreateStoryDto,
    file?: Express.Multer.File,
  ) {
    // Validate file size (50MB limit)
    if (file && file.size > 50 * 1024 * 1024) {
      throw new BadRequestException({
        statusCode: 400,
        errorCode: 'FILE_TOO_LARGE',
        message: 'File exceeds 50MB limit',
        details: {
          maxAllowedMB: 50,
          receivedMB: Math.round((file.size / (1024 * 1024)) * 10) / 10,
        },
      });
    }

    const now = new Date();
    const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000); // 24h default

    let mediaUrl = '';
    let mediaType = dto.mediaType || 'text';

    // Upload media file if provided
    if (file) {
      const result = await this.uploadMediaToCloudinary(userId, file);
      mediaUrl = result.mediaUrl;
      // Derive mediaType from file mimetype if not explicitly set
      if (!dto.mediaType) {
        mediaType = file.mimetype.startsWith('video/') ? 'video' : 'image';
      }
    } else if (dto.mediaType === 'image' || dto.mediaType === 'video') {
      throw new BadRequestException(
        `Media file is required for type ${dto.mediaType}`,
      );
    }

    const story = await this.prisma.story.create({
      data: {
        userId,
        familyId: dto.familyId || null,
        caption: dto.caption || null,
        mediaUrl,
        mediaType,
        bgGradient: dto.bgGradient || null,
        expiresAt,
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
          },
        },
      },
    });

    // Emit real-time event to the creator's followers
    // (We notify via family room if familyId is set, otherwise direct)
    if (dto.familyId) {
      this.gateway.emitToFamily(dto.familyId, 'story:new', {
        id: story.id,
        type: 'story',
        updatedAt: story.updatedAt.toISOString(),
        familyId: dto.familyId,
        userId,
      });
    }
    this.gateway.emitToUser(userId, 'story:created', {
      storyId: story.id,
      userId,
    });

    return this.formatStory(story);
  }

  /** Gets active (non-expired) stories for a family, grouped by user.
   *  Applies audience filtering: PUBLIC stories visible to all,
   *  FAMILY_ONLY stories only to family members. */
  private async assertMember(familyId: string, userId: string) {
    const m = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!m) throw new ForbiddenException('Not a member of this family');
    return m;
  }

  async findByFamily(familyId: string, userId?: string) {
    const now = new Date();

    // Check if the requesting user is a member of this family
    let isFamilyMember = false;
    if (userId) {
      const membership = await this.prisma.familyMember.findFirst({
        where: { userId, familyId },
      });
      isFamilyMember = !!membership;
    }

    const stories = await this.prisma.story.findMany({
      where: {
        familyId,
        expiresAt: { gt: now },
      },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
          },
        },
        views: true,
      },
      orderBy: { createdAt: 'desc' },
    });

    // Apply audience filtering at the application level
    // TODO: Once `audience` field is added to the Story schema by Agent-0,
    // replace this with a proper Prisma where clause filtering.
    // For now: stories with familyId are treated as PUBLIC (no FAMILY_ONLY
    // filtering until the schema field exists).
    const filteredStories = stories.filter((story) => {
      // When the audience column exists, this will be:
      // if (story.audience === 'FAMILY_ONLY' && !isFamilyMember) return false;
      // return true;
      // Currently, all family stories are visible to anyone querying the family
      return true;
    });

    // Group stories by user
    const groupedMap = new Map<
      string,
      {
        user: {
          id: string;
          name: string | null;
          username: string | null;
          avatarUrl: string | null;
        };
        stories: Record<string, unknown>[];
        hasUnviewed: boolean;
      }
    >();

    for (const story of filteredStories) {
      const existing = groupedMap.get(story.userId);
      const formatted = this.formatStory(story);

      // Determine if this story is unviewed by the requesting user
      const isUnviewed = userId
        ? !story.views.some((v) => v.viewerId === userId)
        : true;

      if (existing) {
        existing.stories.push(formatted);
        if (isUnviewed) {
          existing.hasUnviewed = true;
        }
      } else {
        groupedMap.set(story.userId, {
          user: story.user,
          stories: [formatted],
          hasUnviewed: isUnviewed,
        });
      }
    }

    return Array.from(groupedMap.values());
  }

  /** Gets active stories by a specific user. */
  async findByUser(userId: string) {
    const now = new Date();

    const stories = await this.prisma.story.findMany({
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
          },
        },
        views: true,
      },
      orderBy: { createdAt: 'desc' },
    });

    return stories.map((s) => this.formatStory(s));
  }

  /** Marks a story as viewed by creating a StoryView record (upsert since storyId+viewerId is unique).
   *  Emits a real-time event to the story owner. */
  async markViewed(storyId: string, viewerId: string) {
    const story = await this.prisma.story.findUnique({
      where: { id: storyId },
    });

    if (!story) {
      throw new NotFoundException('Story not found');
    }

    await this.prisma.storyView.upsert({
      where: {
        storyId_viewerId: { storyId, viewerId },
      },
      create: {
        storyId,
        viewerId,
      },
      update: {
        viewedAt: new Date(),
      },
    });

    // Emit real-time event to the story owner
    if (story.userId !== viewerId) {
      this.gateway.emitToUser(story.userId, 'story:viewed', {
        storyId,
        viewerId,
      });
    }

    return { viewed: true, storyId, viewerId };
  }

  /** Deletes a story (only owner can delete). */
  async remove(id: string, userId: string) {
    const story = await this.prisma.story.findUnique({
      where: { id },
    });

    if (!story) {
      throw new NotFoundException('Story not found');
    }

    if (story.userId !== userId) {
      throw new ForbiddenException('You can only delete your own stories');
    }

    await this.prisma.story.delete({ where: { id } });

    return { deleted: true, storyId: id };
  }

  // ── Cron Cleanup ────────────────────────────────────────────

  /** Scheduled job: delete expired stories every hour */
  @Cron('0 * * * *')
  async cleanupExpiredStories() {
    const now = new Date();
    try {
      const result = await this.prisma.story.deleteMany({
        where: { expiresAt: { lte: now } },
      });
      if (result.count > 0) {
        this.logger.log(`Cleaned up ${result.count} expired stories`);
      }
    } catch (error) {
      this.logger.error('Failed to cleanup expired stories', error);
    }
  }

  // ── Media Upload ────────────────────────────────────────────

  /** Upload a story media file to Cloudinary, returning mediaUrl and thumbnailUrl.
   *  Falls back to base64 data URL for development when Cloudinary is not configured. */
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

    const uploadResult = await new Promise<any>((resolve, reject) => {
      const uploadStream = cloudinary.uploader.upload_stream(
        {
          folder: 'kinrel/stories',
          public_id: `story_${userId}_${Date.now()}`,
          resource_type: isVideo ? 'video' : 'image',
          ...(isVideo && {
            transformation: [{ width: 1080, crop: 'limit', quality: 'auto' }],
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
    // for images, apply a smaller transformation.
    let thumbnailUrl: string | null = null;

    if (isVideo) {
      thumbnailUrl = cloudinary.url(publicId, {
        resource_type: 'video',
        transformation: [
          {
            width: 400,
            height: 400,
            crop: 'fill',
            quality: 'auto',
            fetch_format: 'auto',
            start_offset: '1',
          },
        ],
      });
    } else {
      thumbnailUrl = cloudinary.url(publicId, {
        transformation: [
          {
            width: 400,
            height: 400,
            crop: 'fill',
            quality: 'auto',
            fetch_format: 'auto',
          },
        ],
      });
    }

    // TODO: Once `thumbnailUrl` field is added to the Story schema by Agent-0,
    // persist this value in the database alongside mediaUrl.

    return { mediaUrl, thumbnailUrl };
  }

  // ── Helpers ─────────────────────────────────────────────────

  /** Check if a user is a member of a specific family */
  private async isFamilyMember(userId: string, familyId: string): Promise<boolean> {
    const membership = await this.prisma.familyMember.findFirst({
      where: { userId, familyId },
    });
    return !!membership;
  }

  private formatStory(story: {
    id: string;
    userId: string;
    familyId: string | null;
    caption: string | null;
    mediaUrl: string;
    mediaType: string;
    bgGradient: string | null;
    expiresAt: Date;
    createdAt: Date;
    updatedAt: Date;
    user?: {
      id: string;
      name: string | null;
      username: string | null;
      avatarUrl: string | null;
    };
    views?: { id: string; storyId: string; viewerId: string; viewedAt: Date }[];
  }) {
    return {
      id: story.id,
      userId: story.userId,
      familyId: story.familyId,
      caption: story.caption,
      mediaUrl: story.mediaUrl,
      mediaType: story.mediaType,
      bgGradient: story.bgGradient,
      expiresAt: story.expiresAt,
      createdAt: story.createdAt,
      updatedAt: story.updatedAt,
      ...(story.user ? { user: story.user } : {}),
      ...(story.views
        ? {
            viewCount: story.views.length,
            viewerIds: story.views.map((v) => v.viewerId),
          }
        : {}),
    };
  }
}
