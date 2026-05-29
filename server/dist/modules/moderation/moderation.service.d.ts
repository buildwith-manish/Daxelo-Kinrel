import { PrismaService } from '../../prisma/prisma.service';
export declare class ModerationService {
    private prisma;
    constructor(prisma: PrismaService);
    submitReport(userId: string, data: {
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
    getQueue(page?: number, limit?: number, filters?: {
        status?: string;
        priority?: string;
        category?: string;
    }): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    classifyContent(adminId: string, data: {
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
    listAppeals(page?: number, limit?: number, status?: string): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    reviewAppeal(appealId: string, adminId: string, data: {
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
    private mapReportReasonToPriority;
    private formatCase;
}
