import { CommunityService } from './community.service';
export declare class CommunityController {
    private readonly communityService;
    constructor(communityService: CommunityService);
    search(search?: string, type?: string, page?: string, limit?: string): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    create(userId: string, body: {
        type: string;
        name: string;
        description?: string;
        isPrivate?: boolean;
        gotraName?: string;
        villageName?: string;
        surname?: string;
        region?: string;
    }): Promise<{
        id: any;
        type: any;
        name: any;
        slug: any;
        description: any;
        coverImageUrl: any;
        iconUrl: any;
        isVerified: any;
        isPrivate: any;
        memberCount: any;
        postCount: any;
        gotraName: any;
        villageName: any;
        surname: any;
        region: any;
        rules: any;
        createdAt: any;
        updatedAt: any;
    }>;
    findOne(communityId: string): Promise<{
        id: any;
        type: any;
        name: any;
        slug: any;
        description: any;
        coverImageUrl: any;
        iconUrl: any;
        isVerified: any;
        isPrivate: any;
        memberCount: any;
        postCount: any;
        gotraName: any;
        villageName: any;
        surname: any;
        region: any;
        rules: any;
        createdAt: any;
        updatedAt: any;
    }>;
    join(userId: string, communityId: string): Promise<{
        joined: boolean;
        communityId: string;
        role: string;
    }>;
}
