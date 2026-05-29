import { PrismaService } from '../../prisma/prisma.service';
export declare class AdminService {
    private prisma;
    constructor(prisma: PrismaService);
    private requireAdmin;
    getDashboardStats(userRole: string): Promise<{
        users: {
            total: any;
            newLast30Days: any;
        };
        families: {
            total: any;
        };
        persons: {
            total: any;
        };
        support: {
            openTickets: any;
            totalTickets: any;
            resolvedLast30Days: any;
            slaBreachCount: any;
        };
        invitations: {
            pending: any;
        };
        communities: {
            total: any;
        };
        developer: {
            activeApiKeys: any;
        };
        whatsapp: {
            optedIn: any;
        };
    }>;
    listUsers(userRole: string, page?: number, limit?: number, search?: string): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    getSlaReport(userRole: string): Promise<{
        overall: {
            totalTickets: any;
            breachedTickets: any;
            breachRate: number;
            avgFirstResponseTimeMinutes: any;
            avgResolutionTimeMinutes: any;
            avgCsatScore: number;
            totalCsatResponses: any;
        };
        byTier: Record<string, {
            total: number;
            breached: number;
            breachRate: number;
        }>;
    }>;
    getKbAnalytics(userRole: string): Promise<{
        totalArticles: any;
        publishedArticles: any;
        totalViews: any;
        totalSearches: any;
        searchesLeadingToTickets: any;
        searchToTicketRate: number;
        topArticles: any;
    }>;
    getWhatsappTemplates(userRole: string): Promise<any>;
    getModerationStats(userRole: string): Promise<{
        cases: {
            pending: any;
            underReview: any;
            actioned: any;
        };
        reports: {
            total: any;
            pending: any;
        };
        appeals: {
            total: any;
            pending: any;
        };
        casesByCategory: any;
        reportsByReason: any;
    }>;
    getModerationRules(userRole: string): Promise<any>;
}
