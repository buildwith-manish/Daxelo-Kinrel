import { SupportService } from './support.service';
export declare class SupportController {
    private readonly supportService;
    constructor(supportService: SupportService);
    listMyTickets(userId: string, page?: string, limit?: string): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    listTickets(userId: string, page?: string, limit?: string, status?: string, category?: string, queue?: string): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    createTicket(userId: string, body: {
        subject: string;
        description: string;
        category?: string;
        subcategory?: string;
        severity?: string;
        attachments?: string[];
        appVersion?: string;
        platform?: string;
        deviceInfo?: string;
        language?: string;
    }): Promise<{
        id: any;
        ticketNumber: any;
        userId: any;
        user: any;
        category: any;
        subcategory: any;
        severity: any;
        priority: any;
        subject: any;
        description: any;
        status: any;
        queue: any;
        slaTier: any;
        slaBreached: any;
        firstResponseAt: any;
        firstResponseDeadline: any;
        resolutionDeadline: any;
        assignedAgent: {
            id: any;
            name: any;
        } | null;
        language: any;
        createdAt: any;
        updatedAt: any;
        resolvedAt: any;
        closedAt: any;
    }>;
    addMessage(userId: string, ticketId: string, body: {
        content: string;
        attachments?: string[];
        senderType?: string;
        channel?: string;
    }): Promise<{
        id: any;
        ticketId: any;
        senderType: any;
        senderId: any;
        senderName: any;
        content: any;
        attachments: any;
        channel: any;
        createdAt: any;
    }>;
    submitCSAT(userId: string, ticketId: string, body: {
        rating: number;
        comment?: string;
    }): Promise<{
        id: any;
        ticketId: any;
        rating: any;
        comment: any;
        createdAt: any;
    }>;
}
