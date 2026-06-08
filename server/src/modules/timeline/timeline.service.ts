import { Injectable, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class TimelineService {
  constructor(private readonly prisma: PrismaService) {}

  /** Verifies that the user is a member of the specified family. */
  private async verifyMembership(userId: string, familyId: string): Promise<void> {
    const member = await this.prisma.familyMember.findFirst({
      where: { userId, familyId },
    });
    if (!member) {
      throw new ForbiddenException('You are not a member of this family');
    }
  }

  /** Returns paginated family posts ordered by newest first with cursor-based pagination. */
  async getTimeline(familyId: string, userId: string, limit: number = 20, cursor?: string) {
    await this.verifyMembership(userId, familyId);
    limit = Math.max(1, Math.min(limit, 100));

    const posts = await this.prisma.familyPost.findMany({
      where: { familyId },
      orderBy: { createdAt: 'desc' },
      take: limit + 1,
      skip: cursor ? 1 : 0,
      cursor: cursor ? { id: cursor } : undefined,
      select: {
        id: true,
        familyId: true,
        authorId: true,
        postType: true,
        content: true,
        reactions: true,
        createdAt: true,
        updatedAt: true,
        author: { select: { id: true, name: true, photoUrl: true } },
      },
    });

    const hasNextPage = posts.length > limit;
    const data = hasNextPage ? posts.slice(0, -1) : posts;
    const nextCursor = hasNextPage ? data[data.length - 1].id : null;

    return {
      data,
      nextCursor,
    };
  }

  /**
   * Returns the unified feed for the current user, combining:
   * 1. Posts from families the user has joined
   * 2. Posts from users the user follows (Follow.status = ACCEPTED)
   *
   * Results are paginated and ordered by newest first.
   */
  async getUnifiedFeed(userId: string, limit: number = 20, cursor?: string) {
    limit = Math.max(1, Math.min(limit, 100));

    // Get IDs of families the user is a member of
    const userFamilies = await this.prisma.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });
    const familyIds = userFamilies.map((m) => m.familyId);

    // Get IDs of users the current user follows (ACCEPTED status)
    const following = await this.prisma.follow.findMany({
      where: { followerId: userId, status: 'ACCEPTED' },
      select: { followingId: true },
    });
    const followingIds = following.map((f) => f.followingId);

    // Build the where clause: posts from user's families OR from followed users
    const whereConditions: any[] = [];

    if (familyIds.length > 0) {
      whereConditions.push({ familyId: { in: familyIds } });
    }

    // For followed users, we need to find their posts in families.
    // FamilyPost.authorId is a Person ID, not a User ID.
    // So we need to find Person records linked to followed users.
    if (followingIds.length > 0) {
      // Find person records that are linked to followed users
      // Person doesn't have a direct userId field, but we can find persons
      // in the same families as the followed users
      const followedUserFamilies = await this.prisma.familyMember.findMany({
        where: { userId: { in: followingIds } },
        select: { familyId: true },
      });
      const followedFamilyIds = followedUserFamilies.map((m) => m.familyId);

      // Add family IDs from followed users that aren't already in the list
      const newFamilyIds = followedFamilyIds.filter(
        (id) => !familyIds.includes(id),
      );

      if (newFamilyIds.length > 0) {
        whereConditions.push({ familyId: { in: newFamilyIds } });
      }
    }

    if (whereConditions.length === 0) {
      return { data: [], nextCursor: null };
    }

    const posts = await this.prisma.familyPost.findMany({
      where: {
        OR: whereConditions,
        ...(cursor ? { id: { lt: cursor } } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: limit + 1,
      select: {
        id: true,
        familyId: true,
        authorId: true,
        postType: true,
        content: true,
        reactions: true,
        createdAt: true,
        updatedAt: true,
        author: { select: { id: true, name: true, photoUrl: true } },
        family: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
          },
        },
      },
    });

    const hasNextPage = posts.length > limit;
    const data = hasNextPage ? posts.slice(0, -1) : posts;
    const nextCursor = hasNextPage ? data[data.length - 1].id : null;

    return {
      data,
      nextCursor,
    };
  }

  /** Creates a new post in the family timeline feed. */
  async createPost(familyId: string, userId: string, postType: string, content: Record<string, any>) {
    await this.verifyMembership(userId, familyId);

    return this.prisma.familyPost.create({
      data: {
        familyId,
        authorId: userId,
        postType,
        content: JSON.stringify(content),
      },
    });
  }
}
