import { PrismaService } from '../../prisma/prisma.service';
export declare class DeveloperService {
    private prisma;
    constructor(prisma: PrismaService);
    listApiKeys(userId: string): Promise<any>;
    createApiKey(userId: string, data: {
        name: string;
        scopes?: string[];
        tier?: string;
    }): Promise<{
        id: any;
        name: any;
        key: string;
        keyPrefix: any;
        scopes: string[];
        tier: any;
        createdAt: any;
    }>;
    revokeApiKey(keyId: string, userId: string, reason?: string): Promise<{
        id: any;
        name: any;
        revoked: boolean;
        revokedAt: any;
    }>;
    listWebhooks(userId: string): Promise<any>;
    createWebhook(userId: string, data: {
        url: string;
        events: string[];
        description?: string;
    }): Promise<{
        id: any;
        url: any;
        secret: any;
        events: any;
        active: any;
        description: any;
        createdAt: any;
    }>;
    getWebhookDeliveries(webhookId: string, userId: string): Promise<any>;
}
