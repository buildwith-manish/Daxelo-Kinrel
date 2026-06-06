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
