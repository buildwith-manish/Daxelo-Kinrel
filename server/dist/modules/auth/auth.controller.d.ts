import { AuthService } from './auth.service';
import type { Request } from 'express';
export declare class AuthController {
    private readonly authService;
    constructor(authService: AuthService);
    register(body: {
        name: string;
        email: string;
        password: string;
    }): Promise<any>;
    login(body: {
        email: string;
        password: string;
    }, req: Request): Promise<{
        accessToken: string;
        refreshToken: string;
        user: {
            id: any;
            email: any;
            name: any;
            role: any;
            preferredLanguage: any;
        };
    }>;
    refresh(body: {
        refreshToken: string;
    }): Promise<import("./auth.service").TokenPair>;
    logout(body: {
        refreshToken: string;
    }): Promise<{
        success: boolean;
    }>;
    changePassword(userId: string, body: {
        currentPassword: string;
        newPassword: string;
    }): Promise<{
        message: string;
    }>;
    setup2FA(userId: string): Promise<{
        secret: string;
        qrCodeUrl: string | undefined;
    }>;
    verify2FA(userId: string, body: {
        code: string;
    }): Promise<{
        verified: boolean;
    }>;
    disable2FA(userId: string, body: {
        password: string;
    }): Promise<{
        disabled: boolean;
    }>;
    me(userId: string): Promise<{
        user: any;
    }>;
    getSessions(userId: string, refreshToken?: string): Promise<any>;
    revokeSession(userId: string, sessionId: string): Promise<{
        success: boolean;
        message: string;
    }>;
    revokeAllSessionsExceptCurrent(userId: string, refreshToken?: string): Promise<{
        success: boolean;
        message: string;
        revokedCount: any;
    }>;
}
