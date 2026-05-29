import { PrismaService } from '../../prisma/prisma.service';
export declare class ShareService {
    private prisma;
    constructor(prisma: PrismaService);
    createShareableLink(userId: string, data: {
        cardType: string;
        familyId?: string;
        personId?: string;
        title: string;
        description?: string;
        deepLinkUrl?: string;
        expiresInDays?: number;
    }): Promise<{
        id: any;
        token: any;
        cardType: any;
        familyId: any;
        personId: any;
        title: any;
        description: any;
        deepLinkUrl: any;
        viewCount: any;
        shareCount: any;
        expiresAt: any;
        createdAt: any;
    }>;
    getShareStats(token: string): Promise<{
        id: any;
        token: any;
        cardType: any;
        title: any;
        viewCount: any;
        shareCount: any;
        expiresAt: any;
        createdAt: any;
    }>;
    getSharedCard(token: string): Promise<{
        id: any;
        token: any;
        cardType: any;
        title: any;
        description: any;
        deepLinkUrl: any;
        viewCount: any;
        shareCount: any;
        family: Record<string, any> | null;
        person: Record<string, any> | null;
        expiresAt: any;
        createdAt: any;
    }>;
}
