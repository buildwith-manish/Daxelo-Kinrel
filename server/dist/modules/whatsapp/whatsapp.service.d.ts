import { PrismaService } from '../../prisma/prisma.service';
export declare class WhatsAppService {
    private prisma;
    constructor(prisma: PrismaService);
    getConsent(userId: string): Promise<{
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
    optIn(userId: string, data: {
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
    optOut(userId: string, data: {
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
    updateMarketingConsent(userId: string, data: {
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
    getAnalytics(filters?: {
        event?: string;
        startDate?: string;
        endDate?: string;
        userId?: string;
    }): Promise<{
        events: any;
        summary: {
            total: any;
            eventCounts: Record<string, number>;
        };
    }>;
    trackEvent(data: {
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
    private logConsentEvent;
    private formatConsent;
}
