import { PrismaService } from '../prisma/prisma.service';
export declare class AuthController {
    private readonly prisma;
    constructor(prisma: PrismaService);
    logout(req: any): Promise<{
        message: string;
    }>;
    changePassword(req: any, body: any): Promise<{
        message: string;
    }>;
    setup2fa(req: any): Promise<{
        secret: string;
        qrCodeUrl: string;
    }>;
    verify2fa(req: any, body: {
        code: string;
    }): Promise<{
        verified: boolean;
        message: string;
    }>;
    disable2fa(req: any): Promise<{
        message: string;
    }>;
    getSessions(req: any): Promise<{
        sessions: any;
    }>;
    revokeSession(id: string, req: any): Promise<{
        message: string;
    }>;
    revokeAllOtherSessions(req: any): Promise<{
        message: string;
    }>;
}
