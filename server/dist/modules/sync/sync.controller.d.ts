import { SyncService } from './sync.service';
import { SyncQueryDto } from './dto/sync-query.dto';
export declare class SyncController {
    private readonly syncService;
    private readonly logger;
    constructor(syncService: SyncService);
    sync(authenticatedUserId: string, dto: SyncQueryDto): Promise<{
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
}
