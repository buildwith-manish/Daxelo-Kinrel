import { PrismaService } from '../prisma/prisma.service';
export declare class UsersService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    getOrCreateUser(id: string, email: string): Promise<any>;
    getProfile(id: string): Promise<any>;
    updateProfile(id: string, data: any): Promise<any>;
    updateAvatar(id: string, avatarUrl: string): Promise<any>;
    getStats(id: string): Promise<{
        familyTrees: any;
        membersAdded: any;
        relations: any;
    }>;
    checkUsername(username: string): Promise<{
        available: boolean;
    }>;
    setUsername(id: string, username: string): Promise<any>;
    getFamilies(id: string): Promise<any>;
    getInvitations(id: string): Promise<any>;
    getBlocked(id: string): Promise<{
        blocked: never[];
    }>;
    unblockUser(id: string, blockedUserId: string): Promise<{
        message: string;
    }>;
    requestDataExport(id: string): Promise<{
        message: string;
        exportId: string;
    }>;
    deleteAccount(id: string): Promise<{
        message: string;
    }>;
    updateQuietHours(id: string, data: any): Promise<{
        message: string;
        quietHours: any;
    }>;
}
