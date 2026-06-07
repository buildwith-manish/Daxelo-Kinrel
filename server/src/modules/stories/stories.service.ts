import {
  Injectable,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateStoryDto } from './dto/create-story.dto';

@Injectable()
export class StoriesService {
  constructor(private prisma: PrismaService) {}

  /** Verifies that the user is a member of the specified family. */
  private async verifyFamilyMembership(userId: string, familyId: string): Promise<void> {
    const member = await this.prisma.familyMember.findFirst({
      where: { userId, familyId },
    });
    if (!member) {
      throw new ForbiddenException('You are not a member of this family');
    }
  }

  /** Creates a new story for the given user. */
  async create(userId: string, dto: CreateStoryDto) {
    // Verify family membership if a familyId is provided
    if (dto.familyId) {
      await this.verifyFamilyMembership(userId, dto.familyId);
    }

    const story = await this.prisma.story.create({
      data: {
        userId,
        familyId: dto.familyId || null,
        caption: dto.caption || null,
        mediaUrl: dto.mediaUrl || '',
        mediaType: dto.mediaType || 'text',
        bgGradient: dto.bgGradient || null,
        expiresAt: new Date(dto.expiresAt),
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

    return this.formatStory(story);
  }

  /** Gets active (non-expired) stories for a family, grouped by user.
   *  Each group includes user info, their stories array, and a hasUnviewed flag. */
  async findByFamily(familyId: string, userId?: string, limit: number = 50, cursor?: string) {
    // Verify family membership before listing stories
    if (userId) {
      await this.verifyFamilyMembership(userId, familyId);
    }

    const now = new Date();

    const cursorFilter = cursor ? { id: { lt: cursor } } : {};

    const stories = await this.prisma.story.findMany({
      where: {
        familyId,
        expiresAt: { gt: now },
        ...cursorFilter,
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
      take: limit + 1,
    });

    const hasNext = stories.length > limit;
    const sliced = hasNext ? stories.slice(0, limit) : stories;

    // Group stories by user
    const groupedMap = new Map<
      string,
      {
        user: { id: string; name: string | null; username: string | null; avatarUrl: string | null };
        stories: Record<string, unknown>[];
        hasUnviewed: boolean;
      }
    >();

    for (const story of sliced) {
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

    return {
      data: Array.from(groupedMap.values()),
      nextCursor: hasNext && sliced.length > 0 ? sliced[sliced.length - 1].id : null,
    };
  }

  /** Gets active stories by a specific user. */
  async findByUser(userId: string, limit: number = 50, cursor?: string) {
    const now = new Date();

    const cursorFilter = cursor ? { id: { lt: cursor } } : {};

    const stories = await this.prisma.story.findMany({
      where: {
        userId,
        expiresAt: { gt: now },
        ...cursorFilter,
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
      take: limit + 1,
    });

    const hasNext = stories.length > limit;
    const sliced = hasNext ? stories.slice(0, limit) : stories;

    return {
      data: sliced.map((s) => this.formatStory(s)),
      nextCursor: hasNext && sliced.length > 0 ? sliced[sliced.length - 1].id : null,
    };
  }

  /** Marks a story as viewed by creating a StoryView record (upsert since storyId+viewerId is unique). */
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
    user?: { id: string; name: string | null; username: string | null; avatarUrl: string | null };
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
        ? { viewCount: story.views.length, viewerIds: story.views.map((v) => v.viewerId) }
        : {}),
    };
  }
}
