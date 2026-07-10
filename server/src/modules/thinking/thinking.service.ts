import {
  Injectable,
  Logger,
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { SendTapDto } from './dto/send-tap.dto';

@Injectable()
export class ThinkingService {
  private readonly logger = new Logger(ThinkingService.name);
  private readonly RATE_LIMIT_MINUTES = 60;

  constructor(private readonly prisma: PrismaService) {}

  async sendTap(senderId: string, dto: SendTapDto): Promise<{ success: boolean; tappedAt: Date }> {
    const { receiverId, familyId } = dto;

    if (senderId === receiverId) {
      throw new BadRequestException('You cannot send a thinking tap to yourself.');
    }

    const [senderMembership, receiverMembership] = await Promise.all([
      this.prisma.familyMember.findFirst({
        where: { userId: senderId, familyId },
      }),
      this.prisma.familyMember.findFirst({
        where: { userId: receiverId, familyId },
        include: {
          user: {
            select: { id: true, name: true, username: true, photoThumb: true },
          },
        },
      }),
    ]);

    if (!senderMembership) {
      throw new ForbiddenException('You are not a member of this family.');
    }

    if (!receiverMembership) {
      throw new NotFoundException('Receiver is not a member of this family.');
    }

    // Rate limit check
    const rateLimitCutoff = new Date(Date.now() - this.RATE_LIMIT_MINUTES * 60 * 1000);
    const recentTap = await this.prisma.thinkingOfYouTap.findFirst({
      where: {
        senderId,
        receiverId,
        tappedAt: { gte: rateLimitCutoff },
      },
    });

    if (recentTap) {
      throw new BadRequestException('You already sent a tap to this person recently. Try again later.');
    }

    const tap = await this.prisma.thinkingOfYouTap.create({
      data: { senderId, receiverId, familyId },
      include: {
        sender: {
          select: { id: true, name: true, username: true, photoThumb: true },
        },
      },
    });

    // Persist a notification for the receiver
    try {
      await this.prisma.notification.create({
        data: {
          id: 'toy_' + Date.now() + '_' + receiverId,
          userId: receiverId,
          eventType: 'thinking_of_you',
          title: 'Thinking of You',
          body: `${tap.sender.name ?? 'Someone'} was thinking of you`,
          familyId,
          actionUrl: null,
          priority: 'normal',
          read: false,
          channels: [],
          createdAt: new Date(),
          updatedAt: new Date(),
        },
      });
    } catch (e) {
      this.logger.warn(`Failed to create notification for tap: ${e}`);
    }

    this.logger.log(`Tap sent: ${senderId} -> ${receiverId} in family ${familyId}`);
    return { success: true, tappedAt: tap.tappedAt };
  }

  async getReceivedTaps(receiverId: string, limit = 20, page = 1) {
    const skip = (page - 1) * limit;
    const [taps, total] = await this.prisma.$transaction([
      this.prisma.thinkingOfYouTap.findMany({
        where: { receiverId },
        orderBy: { tappedAt: 'desc' },
        take: limit,
        skip,
        include: {
          sender: {
            select: { id: true, name: true, username: true, photoThumb: true },
          },
        },
      }),
      this.prisma.thinkingOfYouTap.count({ where: { receiverId } }),
    ]);
    return { taps, total };
  }
}
