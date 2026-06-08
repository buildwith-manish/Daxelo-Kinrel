import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class TimelineService {
  constructor(private readonly prisma: PrismaService) {}

  /** Returns paginated family posts ordered by newest first with cursor-based pagination. */
  async getTimeline(familyId: string, limit: number = 20, cursor?: string) {
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
   * Returns the home feed — a merged, paginated list of posts from:
   *   1. Families the current user has joined (all their family posts)
   *   2. Families where followed users are members (public families only)
   *
   * Posts are sorted by createdAt descending. Cursor-based pagination.
   */
  async getHomeFeed(userId: string, limit: number = 20, cursor?: string) {
    // ── Step 1: Gather family IDs from memberships ─────────────────────
    const myFamilyMemberships = await this.prisma.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });
    const myFamilyIds = myFamilyMemberships.map((m) => m.familyId);

    // ── Step 2: Gather family IDs from followed users' memberships ──────
    // Get users the current user follows (ACCEPTED)
    const following = await this.prisma.follow.findMany({
      where: { followerId: userId, status: 'ACCEPTED' },
      select: { followingId: true },
    });
    const followedUserIds = following.map((f) => f.followingId);

    let followedFamilyIds: string[] = [];
    if (followedUserIds.length > 0) {
      // Get families where followed users are members
      const followedFamilyMemberships = await this.prisma.familyMember.findMany({
        where: {
          userId: { in: followedUserIds },
          family: { isPublic: true, deletedAt: null },
        },
        select: { familyId: true },
        distinct: ['familyId'],
      });
      followedFamilyIds = followedFamilyMemberships.map((m) => m.familyId);
    }

    // ── Step 3: Combine family IDs (deduplicated) ──────────────────────
    const allFamilyIds = [...new Set([...myFamilyIds, ...followedFamilyIds])];

    if (allFamilyIds.length === 0) {
      return { data: [], nextCursor: null };
    }

    // ── Step 4: Fetch posts from all relevant families ─────────────────
    const whereClause: any = {
      familyId: { in: allFamilyIds },
    };

    if (cursor) {
      whereClause.id = { lt: cursor };
    }

    const posts = await this.prisma.familyPost.findMany({
      where: whereClause,
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
        author: { select: { id: true, name: true, photoUrl: true, photoThumb: true } },
        family: { select: { id: true, name: true, avatarUrl: true, isPublic: true } },
      },
    });

    const hasNextPage = posts.length > limit;
    const data = hasNextPage ? posts.slice(0, -1) : posts;
    const nextCursor = hasNextPage ? data[data.length - 1].id : null;

    // ── Step 5: Tag posts with source context ──────────────────────────
    const myFamilyIdSet = new Set(myFamilyIds);
    const enrichedData = data.map((post) => ({
      ...post,
      source: myFamilyIdSet.has(post.familyId) ? 'family' : 'following',
    }));

    return {
      data: enrichedData,
      nextCursor,
    };
  }

  /** Creates a new post in the family timeline feed. */
  async createPost(familyId: string, authorId: string, postType: string, content: Record<string, any>) {
    return this.prisma.familyPost.create({
      data: {
        familyId,
        authorId,
        postType,
        content: JSON.stringify(content),
      },
    });
  }
}
