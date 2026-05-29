import { PrismaService } from '../../prisma/prisma.service';
export declare class TimelineService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    getTimeline(familyId: string, limit?: number, cursor?: string): Promise<{
        data: any;
        nextCursor: any;
    }>;
    createPost(familyId: string, authorId: string, postType: string, content: Record<string, any>): Promise<any>;
}
