import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { CreateKeyDto, RevokeKeyDto } from './dto/create-key.dto';
import { CreateWebhookDto } from './dto/create-webhook.dto';
import { createHash, randomBytes } from 'crypto';

// ── Tier Limits ─────────────────────────────────────────────────────

const TIER_LIMITS: Record<string, { maxKeys: number; maxWebhooks: number; rateLimitPerMinute: number }> = {
  free: { maxKeys: 2, maxWebhooks: 2, rateLimitPerMinute: 30 },
  pro: { maxKeys: 10, maxWebhooks: 10, rateLimitPerMinute: 120 },
  enterprise: { maxKeys: 50, maxWebhooks: 50, rateLimitPerMinute: 600 },
};

const API_SCOPES: Record<string, string> = {
  'families:read': 'Read family data',
  'families:write': 'Write family data',
  'persons:read': 'Read person data',
  'persons:write': 'Write person data',
  'relationships:read': 'Read relationships',
  'relationships:write': 'Write relationships',
  'developer:manage': 'Manage API keys',
  'webhooks:read': 'Read webhook subscriptions',
  'webhooks:manage': 'Manage webhook subscriptions',
};

// ── Key Generation ──────────────────────────────────────────────────

function generateApiKey(): { key: string; prefix: string; hash: string } {
  const key = `kin_live_${randomBytes(32).toString('hex')}`;
  const prefix = key.substring(0, 12);
  const hash = createHash('sha256').update(key).digest('hex');
  return { key, prefix, hash };
}

function maskKey(prefix: string): string {
  if (prefix.length <= 8) return `${prefix}****`;
  return `${prefix.substring(0, 8)}****`;
}

@Injectable()
export class DeveloperService {
  private readonly logger = new Logger(DeveloperService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ── List API Keys ─────────────────────────────────────────────────

  async listKeys(userId: string) {
    const keys = await this.prisma.apiKey.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });

    const maskedKeys = keys.map((key) => ({
      ...key,
      keyPrefix: maskKey(key.keyPrefix),
      scopes: JSON.parse(key.scopes),
    }));

    return { data: maskedKeys, pagination: { page: 1, limit: 100, total: maskedKeys.length, hasMore: false } };
  }

  // ── Create API Key ────────────────────────────────────────────────

  async createKey(userId: string, dto: CreateKeyDto) {
    // Validate scopes
    const validScopes = Object.keys(API_SCOPES);
    const invalidScopes = dto.scopes.filter((s) => !validScopes.includes(s) && s !== '*');
    if (invalidScopes.length > 0) {
      throw new BadRequestException({ message: `Invalid scopes: ${invalidScopes.join(', ')}`, validScopes });
    }

    const tier = dto.tier ?? 'free';
    const tierConfig = TIER_LIMITS[tier];
    if (!tierConfig) throw new BadRequestException(`Invalid tier: ${tier}`);

    const existingKeys = await this.prisma.apiKey.count({
      where: { userId, revokedAt: null },
    });

    if (existingKeys >= tierConfig.maxKeys) {
      throw new ConflictException({
        message: `Maximum ${tierConfig.maxKeys} API keys allowed for ${tier} tier`,
        current: existingKeys,
        max: tierConfig.maxKeys,
        tier,
      });
    }

    const { key, prefix, hash } = generateApiKey();

    const apiKey = await this.prisma.apiKey.create({
      data: {
        name: dto.name,
        keyPrefix: prefix,
        keyHash: hash,
        userId,
        scopes: JSON.stringify(dto.scopes),
        tier,
        rateLimitPerMinute: tierConfig.rateLimitPerMinute,
      },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'API_KEY_CREATED',
        resource: 'ApiKey',
        resourceId: apiKey.id,
        details: JSON.stringify({ name: dto.name, tier, scopes: dto.scopes }),
      },
    });

    return {
      data: {
        id: apiKey.id,
        name: apiKey.name,
        key, // Only shown once!
        keyPrefix: maskKey(prefix),
        scopes: dto.scopes,
        tier,
        rateLimitPerMinute: tierConfig.rateLimitPerMinute,
        createdAt: apiKey.createdAt,
        warning: 'Store this API key securely. It will not be shown again.',
      },
    };
  }

  // ── Revoke API Key ────────────────────────────────────────────────

  async revokeKey(userId: string, dto: RevokeKeyDto) {
    const apiKey = await this.prisma.apiKey.findFirst({
      where: { id: dto.keyId, userId },
    });

    if (!apiKey || apiKey.revokedAt) {
      throw new NotFoundException('API key not found or already revoked');
    }

    await this.prisma.apiKey.update({
      where: { id: dto.keyId },
      data: {
        revokedAt: new Date(),
        revokeReason: dto.reason ?? 'Revoked by user',
      },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'API_KEY_REVOKED',
        resource: 'ApiKey',
        resourceId: dto.keyId,
        details: JSON.stringify({ reason: dto.reason }),
      },
    });

    return { data: { revoked: true, keyId: dto.keyId, reason: dto.reason } };
  }

  // ── List Webhooks ─────────────────────────────────────────────────

  async listWebhooks(userId: string, options: { page?: number; limit?: number }) {
    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(50, Math.max(1, options.limit ?? 20));

    const [webhooks, total] = await Promise.all([
      this.prisma.webhookSubscription.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        include: { _count: { select: { deliveries: true } } },
      }),
      this.prisma.webhookSubscription.count({ where: { userId } }),
    ]);

    const sanitizedWebhooks = webhooks.map((wh) => ({
      id: wh.id,
      url: wh.url,
      events: JSON.parse(wh.events),
      active: wh.active,
      description: wh.description,
      deliveryCount: wh._count.deliveries,
      createdAt: wh.createdAt,
      updatedAt: wh.updatedAt,
    }));

    return {
      data: sanitizedWebhooks,
      pagination: { page, limit, total, hasMore: page * limit < total },
    };
  }

  // ── Create Webhook ────────────────────────────────────────────────

  async createWebhook(userId: string, dto: CreateWebhookDto) {
    const tierConfig = TIER_LIMITS['free']; // Default tier
    const existingWebhooks = await this.prisma.webhookSubscription.count({
      where: { userId, active: true },
    });

    if (existingWebhooks >= tierConfig.maxWebhooks) {
      throw new ConflictException({
        message: `Maximum ${tierConfig.maxWebhooks} webhooks allowed`,
        current: existingWebhooks,
        max: tierConfig.maxWebhooks,
      });
    }

    const secret = dto.secret ?? randomBytes(32).toString('hex');

    const subscription = await this.prisma.webhookSubscription.create({
      data: {
        userId,
        url: dto.url,
        secret,
        events: JSON.stringify(dto.events),
        active: true,
        description: dto.description ?? null,
      },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'WEBHOOK_CREATED',
        resource: 'WebhookSubscription',
        resourceId: subscription.id,
        details: JSON.stringify({ url: dto.url, events: dto.events }),
      },
    });

    return {
      data: {
        id: subscription.id,
        url: subscription.url,
        events: JSON.parse(subscription.events),
        active: subscription.active,
        description: subscription.description,
        createdAt: subscription.createdAt,
        secret: subscription.secret,
        warning: 'Store this webhook secret securely. It will not be shown again.',
      },
    };
  }

  // ── List Webhook Deliveries ───────────────────────────────────────

  async listDeliveries(
    userId: string,
    webhookId: string,
    options: { page?: number; limit?: number; status?: string },
  ) {
    // Verify ownership
    const webhook = await this.prisma.webhookSubscription.findFirst({
      where: { id: webhookId, userId },
    });
    if (!webhook) throw new NotFoundException('Webhook subscription not found');

    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(50, Math.max(1, options.limit ?? 20));

    const where: Record<string, unknown> = { webhookId };
    if (options.status) where.status = options.status;

    const [deliveries, total] = await Promise.all([
      this.prisma.webhookDelivery.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        select: {
          id: true,
          eventId: true,
          eventType: true,
          attemptCount: true,
          maxAttempts: true,
          status: true,
          lastAttemptAt: true,
          nextAttemptAt: true,
          responseStatusCode: true,
          createdAt: true,
        },
      }),
      this.prisma.webhookDelivery.count({ where }),
    ]);

    return {
      data: {
        deliveries,
        pagination: { page, limit, total, hasMore: page * limit < total, totalPages: Math.ceil(total / limit) },
      },
    };
  }
}
