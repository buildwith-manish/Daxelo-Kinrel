import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class TimelineService {
  constructor(private readonly prisma: PrismaService) {}

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
