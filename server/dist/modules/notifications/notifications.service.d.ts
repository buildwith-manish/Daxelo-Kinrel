import { PrismaService } from '../../prisma/prisma.service';
export declare class NotificationsService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    listForUser(userId: string, limit?: number, unreadOnly?: boolean): Promise<any>;
    markRead(notificationId: string): Promise<any>;
    markAllRead(userId: string): Promise<any>;
    create(data: {
        userId: string;
        eventType: string;
        title: string;
        body: string;
        familyId?: string;
        personId?: string;
        priority?: string;
        actionUrl?: string;
    }): Promise<any>;
    getUnreadCount(userId: string): Promise<any>;
    updatePreference(userId: string, eventType: string, data: Record<string, any>): Promise<any>;
}
