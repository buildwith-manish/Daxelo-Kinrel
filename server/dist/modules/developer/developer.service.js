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
exports.DeveloperService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
const crypto_1 = require("crypto");
const VALID_SCOPES = [
    'families:read',
    'families:write',
    'persons:read',
    'persons:write',
    'developer:manage',
    'webhooks:read',
    'webhooks:manage',
    'graph:read',
];
let DeveloperService = class DeveloperService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async listApiKeys(userId) {
        const keys = await this.prisma.apiKey.findMany({
            where: { userId, revokedAt: null },
            orderBy: { createdAt: 'desc' },
        });
        return keys.map((k) => ({
            id: k.id,
            name: k.name,
            keyPrefix: k.keyPrefix,
            scopes: JSON.parse(k.scopes),
            tier: k.tier,
            rateLimitPerMinute: k.rateLimitPerMinute,
            lastUsedAt: k.lastUsedAt,
            expiresAt: k.expiresAt,
            createdAt: k.createdAt,
        }));
    }
    async createApiKey(userId, data) {
        if (!data.name || data.name.trim().length === 0) {
            throw new common_1.BadRequestException('API key name is required');
        }
        const scopes = data.scopes || ['families:read', 'persons:read'];
        const invalidScopes = scopes.filter((s) => !VALID_SCOPES.includes(s));
        if (invalidScopes.length > 0) {
            throw new common_1.BadRequestException(`Invalid scopes: ${invalidScopes.join(', ')}`);
        }
        const keyMode = data.tier === 'enterprise' ? 'live' : 'test';
        const keySecret = (0, crypto_1.randomBytes)(24).toString('hex');
        const fullKey = `kin_${keyMode}_${keySecret}`;
        const keyPrefix = fullKey.substring(0, 16);
        const keyHash = (0, crypto_1.createHash)('sha256').update(fullKey).digest('hex');
        const apiKey = await this.prisma.apiKey.create({
            data: {
                name: data.name.trim(),
                keyPrefix,
                keyHash,
                userId,
                scopes: JSON.stringify(scopes),
                tier: data.tier || 'free',
            },
        });
        await this.prisma.auditLog.create({
            data: {
                userId,
                action: 'API_KEY_CREATED',
                resource: 'ApiKey',
                resourceId: apiKey.id,
                details: JSON.stringify({ name: data.name, scopes, tier: data.tier || 'free' }),
            },
        });
        return {
            id: apiKey.id,
            name: apiKey.name,
            key: fullKey,
            keyPrefix: apiKey.keyPrefix,
            scopes,
            tier: apiKey.tier,
            createdAt: apiKey.createdAt,
        };
    }
    async revokeApiKey(keyId, userId, reason) {
        const apiKey = await this.prisma.apiKey.findUnique({
            where: { id: keyId },
        });
        if (!apiKey) {
            throw new common_1.NotFoundException('API key not found');
        }
        if (apiKey.userId !== userId) {
            throw new common_1.ForbiddenException('You can only revoke your own API keys');
        }
        if (apiKey.revokedAt) {
            throw new common_1.BadRequestException('API key is already revoked');
        }
        const updated = await this.prisma.apiKey.update({
            where: { id: keyId },
            data: {
                revokedAt: new Date(),
                revokeReason: reason || 'User requested revocation',
            },
        });
        await this.prisma.auditLog.create({
            data: {
                userId,
                action: 'API_KEY_REVOKED',
                resource: 'ApiKey',
                resourceId: keyId,
                details: JSON.stringify({ reason: reason || 'User requested revocation' }),
            },
        });
        return {
            id: updated.id,
            name: updated.name,
            revoked: true,
            revokedAt: updated.revokedAt,
        };
    }
    async listWebhooks(userId) {
        const webhooks = await this.prisma.webhookSubscription.findMany({
            where: { userId },
            orderBy: { createdAt: 'desc' },
            include: {
                _count: { select: { deliveries: true } },
            },
        });
        return webhooks.map((w) => ({
            id: w.id,
            url: w.url,
            events: JSON.parse(w.events),
            active: w.active,
            description: w.description,
            deliveryCount: w._count.deliveries,
            createdAt: w.createdAt,
            updatedAt: w.updatedAt,
        }));
    }
    async createWebhook(userId, data) {
        if (!data.url || !data.url.startsWith('https://')) {
            throw new common_1.BadRequestException('Webhook URL must be a valid HTTPS URL');
        }
        if (!data.events || data.events.length === 0) {
            throw new common_1.BadRequestException('At least one event type is required');
        }
        const secret = (0, crypto_1.randomBytes)(32).toString('hex');
        const webhook = await this.prisma.webhookSubscription.create({
            data: {
                userId,
                url: data.url,
                secret,
                events: JSON.stringify(data.events),
                description: data.description || null,
            },
        });
        return {
            id: webhook.id,
            url: webhook.url,
            secret: webhook.secret,
            events: JSON.parse(webhook.events),
            active: webhook.active,
            description: webhook.description,
            createdAt: webhook.createdAt,
        };
    }
    async getWebhookDeliveries(webhookId, userId) {
        const webhook = await this.prisma.webhookSubscription.findUnique({
            where: { id: webhookId },
        });
        if (!webhook) {
            throw new common_1.NotFoundException('Webhook not found');
        }
        if (webhook.userId !== userId) {
            throw new common_1.ForbiddenException('You can only view your own webhook deliveries');
        }
        const deliveries = await this.prisma.webhookDelivery.findMany({
            where: { webhookId },
            orderBy: { createdAt: 'desc' },
            take: 50,
        });
        return deliveries.map((d) => ({
            id: d.id,
            eventId: d.eventId,
            eventType: d.eventType,
            status: d.status,
            attemptCount: d.attemptCount,
            maxAttempts: d.maxAttempts,
            lastAttemptAt: d.lastAttemptAt,
            responseStatusCode: d.responseStatusCode,
            createdAt: d.createdAt,
        }));
    }
};
exports.DeveloperService = DeveloperService;
exports.DeveloperService = DeveloperService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], DeveloperService);
//# sourceMappingURL=developer.service.js.map