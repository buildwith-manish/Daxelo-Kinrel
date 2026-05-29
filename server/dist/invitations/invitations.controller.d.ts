import { InvitationsService } from './invitations.service';
export declare class InvitationsController {
    private readonly invitationsService;
    constructor(invitationsService: InvitationsService);
    acceptInvitation(user: any, id: string): Promise<{
        message: string;
        invitation: any;
    }>;
    declineInvitation(user: any, id: string): Promise<{
        message: string;
        invitation: any;
    }>;
}
