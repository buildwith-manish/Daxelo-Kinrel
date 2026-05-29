import { AdminService } from './admin.service';
export declare class AdminController {
    private readonly adminService;
    constructor(adminService: AdminService);
    getDashboardStats(role: string): Promise<{
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
    listUsers(role: string, page?: string, limit?: string, search?: string): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    getSlaReport(role: string): Promise<{
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
    getKbAnalytics(role: string): Promise<{
        totalArticles: any;
        publishedArticles: any;
        totalViews: any;
        totalSearches: any;
        searchesLeadingToTickets: any;
        searchToTicketRate: number;
        topArticles: any;
    }>;
    getWhatsappTemplates(role: string): Promise<any>;
    getModerationStats(role: string): Promise<{
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
    getModerationRules(role: string): Promise<any>;
}
