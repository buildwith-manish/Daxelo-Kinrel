import { Injectable, ForbiddenException, BadRequestException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class ChatService {
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

  /** Returns chat messages for a family, ordered by newest first with pagination. */
  async listMessages(familyId: string, userId: string, limit: number = 50, before?: string) {
    await this.verifyMembership(userId, familyId);

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
  async sendMessage(familyId: string, authorId: string, content: string) {
    await this.verifyMembership(authorId, familyId);

    if (content.length > 2000) {
      throw new BadRequestException('Message content exceeds 2000 character limit');
    }

    return this.prisma.familyPost.create({
      data: {
        familyId,
        authorId,
        postType: 'chat_message',
        content: JSON.stringify({ text: content }),
      },
    });
  }
}
