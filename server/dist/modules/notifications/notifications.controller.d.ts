import { NotificationsService } from './notifications.service';
import { FcmService } from './fcm.service';
declare class RegisterFcmTokenDto {
    token: string;
    deviceType?: string;
}
declare class RemoveFcmTokenDto {
    token: string;
}
export declare class NotificationsController {
    private readonly notificationsService;
    private readonly fcmService;
    constructor(notificationsService: NotificationsService, fcmService: FcmService);
    list(userId: string, limit?: string, unread?: string): Promise<any>;
    unreadCount(userId: string): Promise<{
        count: any;
    }>;
    markRead(id: string): Promise<any>;
    markAllRead(userId: string): Promise<any>;
    registerFcmToken(userId: string, dto: RegisterFcmTokenDto): Promise<{
        success: boolean;
        message: string;
        id: any;
    }>;
    removeFcmToken(dto: RemoveFcmTokenDto): Promise<{
        success: boolean;
        removed: boolean;
        message: string;
    }>;
}
export {};
