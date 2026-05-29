import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
export declare class UsersService {
    private readonly prisma;
    private readonly config;
    constructor(prisma: PrismaService, config: ConfigService);
    getProfile(userId: string): Promise<{
        user: any;
    }>;
    getStats(userId: string): Promise<{
        familyTrees: any;
        membersAdded: any;
        relations: any;
    }>;
    updateProfile(userId: string, data: {
        name?: string;
        phone?: string;
        preferredLanguage?: string;
        username?: string;
        bio?: string;
        dateOfBirth?: string;
        gender?: string;
        avatarUrl?: string;
        profileVisibility?: string;
        invitePermission?: string;
    }): Promise<{
        user: any;
    }>;
    uploadAvatar(userId: string, file: Express.Multer.File): Promise<{
        user: any;
    }>;
    deleteAccount(userId: string, password?: string): Promise<{
        success: boolean;
        message: string;
    }>;
    checkUsername(username: string): Promise<{
        available: boolean;
        reason: string;
    } | {
        available: boolean;
        reason?: undefined;
    }>;
    updateUsername(userId: string, username: string): Promise<{
        user: any;
    }>;
    getFamilies(userId: string): Promise<{
        families: any;
    }>;
    getInvitations(userId: string): Promise<{
        invitations: any;
    }>;
    getBlockedUsers(userId: string): Promise<{
        blocked: any;
    }>;
    unblockUser(userId: string, blockedUserId: string): Promise<{
        success: boolean;
        message: string;
    }>;
    blockUser(userId: string, targetUserId: string): Promise<{
        success: boolean;
        message: string;
    }>;
    requestDataExport(userId: string): Promise<{
        exportId: string;
        status: string;
        message: string;
        data: {
            profile: any;
            families: any;
            recentNotifications: any;
            supportTickets: any;
        };
        exportedAt: string;
    }>;
    setQuietHours(userId: string, data: {
        start?: string;
        end?: string;
        enabled?: boolean;
    }): Promise<{
        start: any;
        end: any;
        enabled: boolean;
    }>;
    getQuietHours(userId: string): Promise<{
        start: any;
        end: any;
        enabled: boolean;
    }>;
}
