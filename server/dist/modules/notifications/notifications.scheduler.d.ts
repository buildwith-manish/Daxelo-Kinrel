import { PrismaService } from '../../prisma/prisma.service';
import { FcmService } from './fcm.service';
import { NotificationsService } from './notifications.service';
export declare class NotificationsScheduler {
    private readonly prisma;
    private readonly fcmService;
    private readonly notificationsService;
    private readonly logger;
    constructor(prisma: PrismaService, fcmService: FcmService, notificationsService: NotificationsService);
    handleBirthdayReminders(): Promise<void>;
    private findUpcomingBirthdays;
    private getDaysUntilNextBirthday;
    private isInQuietHours;
    private createInAppNotification;
}
