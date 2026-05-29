import { UsersService } from './users.service';
import { UpdateProfileDto } from '../dto/update-profile.dto';
import { UpdateQuietHoursDto } from '../dto/update-quiet-hours.dto';
export declare class UsersController {
    private readonly usersService;
    constructor(usersService: UsersService);
    getProfile(user: any): Promise<{
        user: any;
    }>;
    updateProfile(user: any, body: UpdateProfileDto): Promise<{
        user: any;
    }>;
    uploadAvatar(user: any, body: {
        avatarUrl: string;
    }): Promise<{
        user: any;
    }>;
    getStats(user: any): Promise<{
        familyTrees: any;
        membersAdded: any;
        relations: any;
    }>;
    checkUsername(username: string): Promise<{
        available: boolean;
    }>;
    setUsername(user: any, body: {
        username: string;
    }): Promise<{
        error: any;
        user?: undefined;
    } | {
        user: any;
        error?: undefined;
    }>;
    getFamilies(user: any): Promise<{
        families: any;
    }>;
    getInvitations(user: any): Promise<{
        invitations: any;
    }>;
    getBlocked(user: any): Promise<{
        blocked: never[];
    }>;
    unblockUser(user: any, blockedUserId: string): Promise<{
        message: string;
    }>;
    requestDataExport(user: any): Promise<{
        message: string;
        exportId: string;
    }>;
    deleteAccount(user: any): Promise<{
        message: string;
    }>;
    updateQuietHours(user: any, body: UpdateQuietHoursDto): Promise<{
        message: string;
        quietHours: any;
    }>;
}
