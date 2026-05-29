import { PrismaService } from '../../prisma/prisma.service';
export declare class CommunityService {
    private prisma;
    constructor(prisma: PrismaService);
    search(params: {
        search?: string;
        type?: string;
        page?: number;
        limit?: number;
    }): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    create(userId: string, data: {
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
    join(communityId: string, userId: string): Promise<{
        joined: boolean;
        communityId: string;
        role: string;
    }>;
    private generateSlug;
    private formatCommunity;
}
