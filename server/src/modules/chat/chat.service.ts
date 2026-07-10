import { Injectable, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class ChatService {
  constructor(private readonly prisma: PrismaService) {}

  /** Returns chat messages for a family, ordered by newest first with pagination. */
  private async assertMember(familyId: string, userId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) throw new ForbiddenException('Not a member of this family');
    return membership;
  }

  async listMessages(familyId: string, userId: string, limit: number = 50, before?: string) {
    await this.assertMember(familyId, userId);
    const where: Record<string, any> = { familyId, postType: 'chat_message' };
    if (before) {
      where.createdAt = { lt: new Date(before) };
    }

    return this.prisma.familyPost.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
  }

  /** Posts a new chat message to the family feed. */
  async sendMessage(familyId: string, userId: string, content: string) {
    await this.assertMember(familyId, userId);
    return this.prisma.familyPost.create({
      data: {
        familyId,
        userId,
        postType: 'chat_message',
        content: JSON.stringify({ text: content }),
      },
    });
  }
}
