import { ModerationService } from './moderation.service';
export declare class ModerationController {
    private readonly moderationService;
    constructor(moderationService: ModerationService);
    submitReport(userId: string, body: {
        targetType: string;
        targetId: string;
        reason: string;
        description?: string;
    }): Promise<{
        id: any;
        targetType: any;
        targetId: any;
        reason: any;
        status: any;
        createdAt: any;
    }>;
    getQueue(userId: string, page?: string, limit?: string, status?: string, priority?: string, category?: string): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    classifyContent(userId: string, body: {
        contentType: string;
        contentId: string;
        contentPreview: string;
    }): Promise<{
        contentType: string;
        contentId: string;
        category: string;
        autoAction: string;
        confidence: number;
        flaggedCategories: string[];
        priority: string;
    }>;
    listAppeals(page?: string, limit?: string, status?: string): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    reviewAppeal(userId: string, appealId: string, body: {
        decision: string;
        notes?: string;
    }): Promise<{
        id: any;
        caseId: any;
        appealTier: any;
        decision: any;
        notes: any;
        reviewedAt: any;
    }>;
}
