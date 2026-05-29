"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.WhatsAppService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
let WhatsAppService = class WhatsAppService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async getConsent(userId) {
        const consent = await this.prisma.whatsAppConsent.findUnique({
            where: { userId },
        });
        if (!consent) {
            return {
                userId,
                optedIn: false,
                phone: null,
                marketingConsent: false,
                messageCategories: [],
            };
        }
        return {
            userId: consent.userId,
            optedIn: consent.optedIn,
            phone: consent.phone,
            optInMethod: consent.optInMethod,
            optInAt: consent.optInAt,
            optOutAt: consent.optOutAt,
            optOutMethod: consent.optOutMethod,
            optOutReason: consent.optOutReason,
            consentVersion: consent.consentVersion,
            messageCategories: JSON.parse(consent.messageCategories || '[]'),
            marketingConsent: consent.marketingConsent,
            marketingOptInAt: consent.marketingOptInAt,
            createdAt: consent.createdAt,
            updatedAt: consent.updatedAt,
        };
    }
    async optIn(userId, data) {
        if (!data.phone || data.phone.trim().length === 0) {
            throw new common_1.BadRequestException('Phone number is required');
        }
        const existing = await this.prisma.whatsAppConsent.findUnique({
            where: { userId },
        });
        if (existing) {
            const updated = await this.prisma.whatsAppConsent.update({
                where: { userId },
                data: {
                    phone: data.phone.trim(),
                    optedIn: true,
                    optInMethod: data.optInMethod || 'app_settings',
                    optInAt: new Date(),
                    optOutAt: null,
                    optOutMethod: null,
                    optOutReason: null,
                    messageCategories: JSON.stringify(data.messageCategories || [
                        'birthday_reminder',
                        'family_invite',
                        'new_match',
                    ]),
                    consentVersion: 'v1',
                },
            });
            await this.logConsentEvent(userId, 'opt_in.completed', data.phone);
            return this.formatConsent(updated);
        }
        const consent = await this.prisma.whatsAppConsent.create({
            data: {
                userId,
                phone: data.phone.trim(),
                optedIn: true,
                optInMethod: data.optInMethod || 'app_settings',
                optInAt: new Date(),
                messageCategories: JSON.stringify(data.messageCategories || [
                    'birthday_reminder',
                    'family_invite',
                    'new_match',
                ]),
                consentVersion: 'v1',
            },
        });
        await this.logConsentEvent(userId, 'opt_in.completed', data.phone);
        return this.formatConsent(consent);
    }
    async optOut(userId, data) {
        const existing = await this.prisma.whatsAppConsent.findUnique({
            where: { userId },
        });
        if (!existing) {
            throw new common_1.NotFoundException('No WhatsApp consent record found for this user');
        }
        if (!existing.optedIn) {
            throw new common_1.BadRequestException('User is already opted out');
        }
        const updated = await this.prisma.whatsAppConsent.update({
            where: { userId },
            data: {
                optedIn: false,
                optOutAt: new Date(),
                optOutMethod: data.optOutMethod || 'app_settings',
                optOutReason: data.optOutReason || null,
                marketingConsent: false,
            },
        });
        await this.logConsentEvent(userId, 'opt_out.requested', existing.phone, {
            method: data.optOutMethod || 'app_settings',
            reason: data.optOutReason,
        });
        return this.formatConsent(updated);
    }
    async updateMarketingConsent(userId, data) {
        const existing = await this.prisma.whatsAppConsent.findUnique({
            where: { userId },
        });
        if (!existing) {
            throw new common_1.NotFoundException('No WhatsApp consent record found for this user');
        }
        if (!existing.optedIn) {
            throw new common_1.BadRequestException('Cannot update marketing consent when user is opted out');
        }
        const updated = await this.prisma.whatsAppConsent.update({
            where: { userId },
            data: {
                marketingConsent: data.marketingConsent,
                marketingOptInAt: data.marketingConsent ? new Date() : null,
            },
        });
        await this.logConsentEvent(userId, data.marketingConsent
            ? 'opt_in.completed'
            : 'opt_out.requested', existing.phone, { type: 'marketing_consent', value: data.marketingConsent });
        return this.formatConsent(updated);
    }
    async getAnalytics(filters) {
        const where = {};
        if (filters?.event) {
            where.event = filters.event;
        }
        if (filters?.userId) {
            where.userId = filters.userId;
        }
        if (filters?.startDate || filters?.endDate) {
            where.createdAt = {};
            if (filters.startDate) {
                where.createdAt.gte = new Date(filters.startDate);
            }
            if (filters.endDate) {
                where.createdAt.lte = new Date(filters.endDate);
            }
        }
        const [events, total] = await Promise.all([
            this.prisma.whatsAppAnalytics.findMany({
                where,
                orderBy: { createdAt: 'desc' },
                take: 100,
            }),
            this.prisma.whatsAppAnalytics.count({ where }),
        ]);
        const eventCounts = {};
        for (const event of events) {
            eventCounts[event.event] = (eventCounts[event.event] || 0) + 1;
        }
        return {
            events: events.map((e) => ({
                id: e.id,
                event: e.event,
                userId: e.userId,
                familyId: e.familyId,
                messageId: e.messageId,
                templateId: e.templateId,
                metadata: JSON.parse(e.metadata || '{}'),
                createdAt: e.createdAt,
            })),
            summary: {
                total,
                eventCounts,
            },
        };
    }
    async trackEvent(data) {
        const analytics = await this.prisma.whatsAppAnalytics.create({
            data: {
                event: data.event,
                userId: data.userId || null,
                familyId: data.familyId || null,
                messageId: data.messageId || null,
                templateId: data.templateId || null,
                metadata: JSON.stringify(data.metadata || {}),
            },
        });
        return {
            id: analytics.id,
            event: analytics.event,
            createdAt: analytics.createdAt,
        };
    }
    async logConsentEvent(userId, event, phone, metadata) {
        await this.prisma.whatsAppAnalytics.create({
            data: {
                event: `whatsapp.${event}`,
                userId,
                metadata: JSON.stringify({
                    phone,
                    timestamp: new Date().toISOString(),
                    ...metadata,
                }),
            },
        });
    }
    formatConsent(consent) {
        return {
            userId: consent.userId,
            phone: consent.phone,
            optedIn: consent.optedIn,
            optInMethod: consent.optInMethod,
            optInAt: consent.optInAt,
            optOutAt: consent.optOutAt,
            optOutMethod: consent.optOutMethod,
            optOutReason: consent.optOutReason,
            consentVersion: consent.consentVersion,
            messageCategories: JSON.parse(consent.messageCategories || '[]'),
            marketingConsent: consent.marketingConsent,
            marketingOptInAt: consent.marketingOptInAt,
            updatedAt: consent.updatedAt,
        };
    }
};
exports.WhatsAppService = WhatsAppService;
exports.WhatsAppService = WhatsAppService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], WhatsAppService);
//# sourceMappingURL=whatsapp.service.js.map