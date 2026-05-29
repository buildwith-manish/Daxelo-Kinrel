import { InvitationsService } from './invitations.service';
export declare class InvitationsController {
    private readonly invitationsService;
    constructor(invitationsService: InvitationsService);
    findByFamily(userId: string, familyId: string): Promise<any>;
    create(userId: string, body: {
        familyId: string;
        inviterId?: string;
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
    accept(userId: string, id: string): Promise<{
        accepted: boolean;
        invitationId: any;
        familyId: string;
        role: string;
    }>;
    decline(userId: string, id: string): Promise<{
        accepted: boolean;
        invitationId: any;
        status: any;
    }>;
    acceptByToken(userId: string, body: {
        token: string;
    }): Promise<{
        accepted: boolean;
        invitationId: any;
        familyId: string;
        role: string;
    }>;
    cancel(userId: string, id: string): Promise<{
        cancelled: boolean;
        invitationId: any;
    }>;
}
