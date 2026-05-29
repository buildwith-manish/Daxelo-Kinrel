import { WhatsAppService } from './whatsapp.service';
export declare class WhatsAppController {
    private readonly whatsappService;
    constructor(whatsappService: WhatsAppService);
    getConsent(currentUserId: string, userId?: string): Promise<{
        userId: string;
        optedIn: boolean;
        phone: null;
        marketingConsent: boolean;
        messageCategories: never[];
        optInMethod?: undefined;
        optInAt?: undefined;
        optOutAt?: undefined;
        optOutMethod?: undefined;
        optOutReason?: undefined;
        consentVersion?: undefined;
        marketingOptInAt?: undefined;
        createdAt?: undefined;
        updatedAt?: undefined;
    } | {
        userId: any;
        optedIn: any;
        phone: any;
        optInMethod: any;
        optInAt: any;
        optOutAt: any;
        optOutMethod: any;
        optOutReason: any;
        consentVersion: any;
        messageCategories: any;
        marketingConsent: any;
        marketingOptInAt: any;
        createdAt: any;
        updatedAt: any;
    }>;
    optIn(userId: string, body: {
        userId?: string;
        phone: string;
        optInMethod?: string;
        messageCategories?: string[];
    }): Promise<{
        userId: any;
        phone: any;
        optedIn: any;
        optInMethod: any;
        optInAt: any;
        optOutAt: any;
        optOutMethod: any;
        optOutReason: any;
        consentVersion: any;
        messageCategories: any;
        marketingConsent: any;
        marketingOptInAt: any;
        updatedAt: any;
    }>;
    optOut(userId: string, body: {
        userId?: string;
        optOutMethod?: string;
        optOutReason?: string;
    }): Promise<{
        userId: any;
        phone: any;
        optedIn: any;
        optInMethod: any;
        optInAt: any;
        optOutAt: any;
        optOutMethod: any;
        optOutReason: any;
        consentVersion: any;
        messageCategories: any;
        marketingConsent: any;
        marketingOptInAt: any;
        updatedAt: any;
    }>;
    updateMarketingConsent(userId: string, body: {
        marketingConsent: boolean;
    }): Promise<{
        userId: any;
        phone: any;
        optedIn: any;
        optInMethod: any;
        optInAt: any;
        optOutAt: any;
        optOutMethod: any;
        optOutReason: any;
        consentVersion: any;
        messageCategories: any;
        marketingConsent: any;
        marketingOptInAt: any;
        updatedAt: any;
    }>;
    getAnalytics(event?: string, startDate?: string, endDate?: string, userId?: string): Promise<{
        events: any;
        summary: {
            total: any;
            eventCounts: Record<string, number>;
        };
    }>;
    trackEvent(body: {
        event: string;
        userId?: string;
        familyId?: string;
        messageId?: string;
        templateId?: string;
        metadata?: Record<string, any>;
    }): Promise<{
        id: any;
        event: any;
        createdAt: any;
    }>;
}
