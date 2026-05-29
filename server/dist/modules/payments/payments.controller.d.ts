import { PaymentsService } from './payments.service';
export declare class PaymentsController {
    private readonly paymentsService;
    constructor(paymentsService: PaymentsService);
    createOrder(userId: string, body: {
        plan: string;
        amount: number;
        currency?: string;
    }): Promise<{
        orderId: string;
        amount: number;
        currency: string;
        plan: string;
    }>;
    verifyPayment(userId: string, body: Record<string, any>): Promise<any>;
    getSubscription(userId: string): Promise<any>;
    cancelSubscription(userId: string): Promise<any>;
}
