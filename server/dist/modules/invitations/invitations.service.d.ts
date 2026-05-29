import { PrismaService } from '../../prisma/prisma.service';
export declare class InvitationsService {
    private prisma;
    constructor(prisma: PrismaService);
    create(userId: string, data: {
        familyId: string;
        inviterId: string;
        recipientEmail?: string;
        recipientPhone?: string;
        recipientName?: string;
        role?: string;
        channel?: string;
    }): Promise<{
        id: any;
        token: any;
        familyId: any;
        inviterId: any;
        family: any;
        inviter: any;
        recipientEmail: any;
        recipientPhone: any;
        recipientName: any;
        status: any;
        role: any;
        channel: any;
        expiresAt: any;
        acceptedAt: any;
        createdAt: any;
    }>;
    findByFamily(familyId: string, userId: string): Promise<any>;
    acceptById(invitationId: string, userId: string): Promise<{
        accepted: boolean;
        invitationId: any;
        familyId: string;
        role: string;
    }>;
    declineById(invitationId: string, userId: string): Promise<{
        accepted: boolean;
        invitationId: any;
        status: any;
    }>;
    acceptByToken(token: string, userId: string): Promise<{
        accepted: boolean;
        invitationId: any;
        familyId: string;
        role: string;
    }>;
    cancel(invitationId: string, userId: string): Promise<{
        cancelled: boolean;
        invitationId: any;
    }>;
    private acceptInvitation;
    private formatInvitation;
}
