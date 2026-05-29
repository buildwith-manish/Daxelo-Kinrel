import { PrismaService } from '../../prisma/prisma.service';
export declare class SupportService {
    private prisma;
    constructor(prisma: PrismaService);
    createTicket(userId: string, data: {
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
    listTickets(page?: number, limit?: number, filters?: {
        status?: string;
        category?: string;
        queue?: string;
    }): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    listMyTickets(userId: string, page?: number, limit?: number): Promise<{
        data: any;
        pagination: {
            page: number;
            limit: number;
            total: any;
            totalPages: number;
        };
    }>;
    addMessage(ticketId: string, userId: string, data: {
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
    submitCSAT(ticketId: string, userId: string, data: {
        rating: number;
        comment?: string;
    }): Promise<{
        id: any;
        ticketId: any;
        rating: any;
        comment: any;
        createdAt: any;
    }>;
    private generateTicketNumber;
    private formatTicket;
}
