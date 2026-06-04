import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class NotificationsService {
  constructor(private readonly prisma: PrismaService) {}

  async listForUser(userId: string, limit: number = 30, unreadOnly: boolean = false) {
    const where: Record<string, any> = { userId };
    if (unreadOnly) {
      where.read = false;
    }
    return this.prisma.notification.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
      select: {
        id: true,
        userId: true,
        eventType: true,
        title: true,
        body: true,
        familyId: true,
        personId: true,
        priority: true,
        read: true,
        readAt: true,
        actionUrl: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  }

  async markRead(notificationId: string) {
    return this.prisma.notification.update({
      where: { id: notificationId },
      data: { read: true, readAt: new Date() },
    });
  }

  async markAllRead(userId: string) {
    return this.prisma.notification.updateMany({
      where: { userId, read: false },
      data: { read: true, readAt: new Date() },
    });
  }

  async create(data: {
    userId: string;
    eventType: string;
    title: string;
    body: string;
    familyId?: string;
    personId?: string;
    priority?: string;
    actionUrl?: string;
  }) {
    return this.prisma.notification.create({ data });
  }

  async getUnreadCount(userId: string) {
    return this.prisma.notification.count({
      where: { userId, read: false },
    });
  }

  async updatePreference(userId: string, eventType: string, data: Record<string, any>) {
    return this.prisma.notificationPreference.upsert({
      where: { userId_eventType: { userId, eventType } },
      update: data,
      create: { userId, eventType, ...data },
    });
  }
}
