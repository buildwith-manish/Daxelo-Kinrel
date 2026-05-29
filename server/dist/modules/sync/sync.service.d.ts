import { PrismaService } from '../../prisma/prisma.service';
export declare class SyncService {
    private prisma;
    private readonly logger;
    private readonly MAX_RECORDS;
    private readonly MAX_RESPONSE_SIZE_BYTES;
    constructor(prisma: PrismaService);
    sync(since: string | undefined, userId: string): Promise<{
        members: never[];
        events: never[];
        familyMeta: {};
        serverTime: string;
        hasMore: boolean;
    } | {
        members: any;
        events: any;
        familyMeta: Record<string, any>;
        serverTime: string;
        hasMore: boolean;
    }>;
    private truncateToFit;
    private emptySyncResponse;
}
