import { PrismaService } from '../prisma/prisma.service';
export declare class InvitationsService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    acceptInvitation(userId: string, invitationId: string): Promise<{
        message: string;
        invitation: any;
    }>;
    declineInvitation(userId: string, invitationId: string): Promise<{
        message: string;
        invitation: any;
    }>;
}
