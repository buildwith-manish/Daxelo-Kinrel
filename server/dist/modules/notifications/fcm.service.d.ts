import { OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
interface FcmNotification {
    title: string;
    body: string;
    data?: Record<string, string>;
}
export declare class FcmService implements OnModuleInit {
    private readonly prisma;
    private readonly configService;
    private readonly logger;
    private firebaseApp;
    private isFirebaseInitialized;
    private retryQueue;
    private retryTimer;
    constructor(prisma: PrismaService, configService: ConfigService);
    onModuleInit(): Promise<void>;
    private initializeFirebase;
    sendToUser(userId: string, notification: FcmNotification): Promise<boolean>;
    sendToUsers(userIds: string[], notification: FcmNotification): Promise<boolean>;
    sendMulticast(tokens: string[], notification: FcmNotification): Promise<boolean>;
    registerToken(userId: string, token: string, deviceType?: string): Promise<any>;
    removeToken(token: string): Promise<boolean>;
    private removeTokens;
    private queueForRetry;
    private processRetryQueue;
    isAvailable(): boolean;
}
export {};
