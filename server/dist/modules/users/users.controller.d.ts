import { UsersService } from './users.service';
export declare class UsersController {
    private readonly usersService;
    constructor(usersService: UsersService);
    getProfile(userId: string): Promise<{
        user: any;
    }>;
    getStats(userId: string): Promise<{
        familyTrees: any;
        membersAdded: any;
        relations: any;
    }>;
    updateProfile(userId: string, body: {
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
    uploadAvatarPost(userId: string, file: Express.Multer.File): Promise<{
        user: any;
    }>;
    uploadAvatarPut(userId: string, file: Express.Multer.File): Promise<{
        user: any;
    }>;
    checkUsername(username: string): Promise<{
        available: boolean;
        reason: string;
    } | {
        available: boolean;
        reason?: undefined;
    }>;
    updateUsername(userId: string, body: {
        username: string;
    }): Promise<{
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
    unblockUser(currentUserId: string, blockedUserId: string): Promise<{
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
    deleteAccount(userId: string, body?: {
        password?: string;
    }): Promise<{
        success: boolean;
        message: string;
    }>;
    setQuietHours(userId: string, body: {
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
