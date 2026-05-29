import { DeveloperService } from './developer.service';
export declare class WebhooksController {
    private readonly developerService;
    constructor(developerService: DeveloperService);
    listWebhooks(userId: string): Promise<any>;
    createWebhook(userId: string, body: {
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
    getWebhookDeliveries(userId: string, webhookId: string): Promise<any>;
}
