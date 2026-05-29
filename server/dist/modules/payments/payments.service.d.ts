import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
export declare class PaymentsService {
    private readonly prisma;
    private readonly config;
    private readonly logger;
    constructor(prisma: PrismaService, config: ConfigService);
    createOrder(userId: string, plan: string, amount: number, currency?: string): Promise<{
        orderId: string;
        amount: number;
        currency: string;
        plan: string;
    }>;
    verifyAndActivate(userId: string, paymentData: Record<string, any>): Promise<any>;
    getSubscription(userId: string): Promise<any>;
    cancelSubscription(userId: string): Promise<any>;
}
