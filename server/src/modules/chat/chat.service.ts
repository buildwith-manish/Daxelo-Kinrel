import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class ChatService {
  constructor(private readonly prisma: PrismaService) {}

  async listMessages(familyId: string, limit: number = 50, before?: string) {
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

  async sendMessage(familyId: string, authorId: string, content: string) {
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
