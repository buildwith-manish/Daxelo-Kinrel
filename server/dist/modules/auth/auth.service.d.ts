import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma/prisma.service';
export interface TokenPair {
    accessToken: string;
    refreshToken: string;
}
export declare class AuthService {
    private readonly prisma;
    private readonly jwt;
    private readonly config;
    constructor(prisma: PrismaService, jwt: JwtService, config: ConfigService);
    register(dto: {
        name: string;
        email: string;
        password: string;
    }): Promise<any>;
    login(dto: {
        email: string;
        password: string;
    }, userAgent?: string, ipAddress?: string): Promise<{
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
    refresh(oldRefreshToken: string): Promise<TokenPair>;
    logout(refreshToken: string): Promise<{
        success: boolean;
    }>;
    changePassword(userId: string, dto: {
        currentPassword: string;
        newPassword: string;
    }): Promise<{
        message: string;
    }>;
    me(userId: string): Promise<{
        user: any;
    }>;
    setup2FA(userId: string): Promise<{
        secret: string;
        qrCodeUrl: string | undefined;
    }>;
    verify2FA(userId: string, code: string): Promise<{
        verified: boolean;
    }>;
    disable2FA(userId: string, password: string): Promise<{
        disabled: boolean;
    }>;
    validateUser(payload: {
        sub: string;
        email: string;
    }): Promise<any>;
    generateTokenPair(userId: string, email: string, role: string, existingFamilyId?: string, userAgent?: string, ipAddress?: string): Promise<TokenPair>;
    private hashSha256;
    private computeExpiryDate;
    private revokeTokenFamily;
    getUserSessions(userId: string, currentRefreshToken?: string): Promise<any>;
    revokeSession(sessionId: string, userId: string): Promise<{
        success: boolean;
        message: string;
    }>;
    revokeAllSessionsExceptCurrent(userId: string, currentRefreshToken?: string): Promise<{
        success: boolean;
        message: string;
        revokedCount: any;
    }>;
    private parseUserAgent;
    cleanupExpiredTokens(): Promise<{
        deleted: any;
    }>;
}
