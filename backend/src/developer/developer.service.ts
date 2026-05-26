import { Injectable, NotFoundException, ConflictException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import * as crypto from 'crypto';
import { CreateKeyDto } from './dto/create-key.dto';
import { RevokeKeyDto } from './dto/revoke-key.dto';
import { CreateWebhookDto } from './dto/create-webhook.dto';
import { ListDeliveriesDto } from './dto/list-deliveries.dto';

// ── API Scopes ────────────────────────────────────────────────────────

export const API_SCOPES = [
  'families:read', 'families:write',
  'persons:read', 'persons:write',
  'relationships:read', 'relationships:write',
  'graph:read',
  'webhooks:manage', 'webhooks:read',
  'stats:read',
  'developer:manage',
  'audit:read',
] as const;

// ── Tier Limits ───────────────────────────────────────────────────────

export const TIER_LIMITS: Record<string, { maxKeys: number; maxWebhooks: number; rateLimitPerMinute: number }> = {
  free: { maxKeys: 2, maxWebhooks: 2, rateLimitPerMinute: 30 },
  pro: { maxKeys: 10, maxWebhooks: 10, rateLimitPerMinute: 120 },
  enterprise: { maxKeys: 50, maxWebhooks: 50, rateLimitPerMinute: 500 },
};

// ── Webhook Event Types ───────────────────────────────────────────────

export const EVENT_TYPES = [
  'person.created', 'person.updated', 'person.deleted',
  'relationship.created', 'relationship.deleted',
  'family.created', 'family.updated',
  'community.joined', 'community.left',
  'event.created', 'event.rsvp',
  'user.registered',
] as const;

// ── Helpers ───────────────────────────────────────────────────────────

function maskKey(prefix: string): string {
  return prefix.substring(0, 8) + '****';
}

// ── Service ───────────────────────────────────────────────────────────

@Injectable()
export class DeveloperService {
  constructor(private prisma: PrismaService) {}

  // ── API Key Management ──────────────────────────────────────────────

  async listKeys(userId: string) {
    const keys = await this.prisma.apiKey.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });

    return keys.map((key) => ({
      id: key.id,
      name: key.name,
      keyPrefix: maskKey(key.keyPrefix),
      scopes: JSON.parse(key.scopes),
      tier: key.tier,
      rateLimitPerMinute: key.rateLimitPerMinute,
      lastUsedAt: key.lastUsedAt,
      revokedAt: key.revokedAt,
      revokeReason: key.revokeReason,
      expiresAt: key.expiresAt,
      createdAt: key.createdAt,
    }));
  }

  async createKey(userId: string, dto: CreateKeyDto) {
    const tier = dto.tier || 'free';
    const tierConfig = TIER_LIMITS[tier] || TIER_LIMITS.free;

    // Validate scopes
    const validScopes = Object.values(API_SCOPES).map(String);
    const invalidScopes = dto.scopes.filter((s) => !validScopes.includes(s) && s !== '*');
    if (invalidScopes.length > 0) {
      throw new ConflictException(`Invalid scopes: ${invalidScopes.join(', ')}`);
    }

    // Check tier limits
    const existingKeys = await this.prisma.apiKey.count({
      where: { userId, revokedAt: null },
    });
    if (existingKeys >= tierConfig.maxKeys) {
      throw new ConflictException(`Maximum ${tierConfig.maxKeys} API keys allowed for ${tier} tier`);
    }

    // Generate raw key
    const rawKey = `kin_live_${crypto.randomBytes(24).toString('hex')}`;
    const keyPrefix = rawKey.substring(0, 12);
    const keyHash = crypto.createHash('sha256').update(rawKey).digest('hex');

    const apiKey = await this.prisma.apiKey.create({
      data: {
        name: dto.name,
        keyPrefix,
        keyHash,
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
      id: apiKey.id,
      name: apiKey.name,
      key: rawKey, // Only shown once!
      keyPrefix: maskKey(keyPrefix),
      scopes: dto.scopes,
      tier,
      rateLimitPerMinute: tierConfig.rateLimitPerMinute,
      createdAt: apiKey.createdAt,
      warning: 'Store this API key securely. It will not be shown again.',
    };
  }

  async revokeKey(keyId: string, userId: string, dto: RevokeKeyDto) {
    const apiKey = await this.prisma.apiKey.findFirst({
      where: { id: keyId, userId },
    });

    if (!apiKey) {
      throw new NotFoundException('API key not found or already revoked');
    }

    if (apiKey.revokedAt) {
      throw new ConflictException('API key already revoked');
    }

    await this.prisma.apiKey.update({
      where: { id: keyId },
      data: {
        revokedAt: new Date(),
        revokeReason: dto.reason,
      },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'API_KEY_REVOKED',
        resource: 'ApiKey',
        resourceId: keyId,
        details: JSON.stringify({ reason: dto.reason }),
      },
    });

    return { revoked: true, keyId, reason: dto.reason };
  }

  async rotateKey(keyId: string, userId: string) {
    const oldKey = await this.prisma.apiKey.findFirst({
      where: { id: keyId, userId, revokedAt: null },
    });

    if (!oldKey) {
      throw new NotFoundException('API key not found or already revoked');
    }

    // Revoke old key
    await this.prisma.apiKey.update({
      where: { id: keyId },
      data: { revokedAt: new Date(), revokeReason: 'Rotated' },
    });

    // Create new key with same scopes
    const scopes = JSON.parse(oldKey.scopes) as string[];
    return this.createKey(userId, {
      name: oldKey.name + ' (rotated)',
      scopes,
      tier: oldKey.tier as 'free' | 'pro' | 'enterprise',
    });
  }

  // ── API Key Validation (for ApiKeyGuard) ────────────────────────────

  async validateKey(fullKey: string) {
    const keyHash = crypto.createHash('sha256').update(fullKey).digest('hex');
    const apiKey = await this.prisma.apiKey.findFirst({ where: { keyHash } });

    if (!apiKey) return null;
    if (apiKey.revokedAt) return null;
    if (apiKey.expiresAt && apiKey.expiresAt < new Date()) return null;

    return apiKey;
  }

  // ── Webhook Management ──────────────────────────────────────────────

  async listWebhooks(userId: string, page = 1, limit = 20) {
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

    const sanitized = webhooks.map((wh) => ({
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
      webhooks: sanitized,
      pagination: { page, limit, total, hasMore: page * limit < total },
    };
  }

  async createWebhook(userId: string, dto: CreateWebhookDto) {
    // Validate event types
    const validEvents = EVENT_TYPES.map(String);
    const invalidEvents = dto.events.filter((e) => !validEvents.includes(e) && e !== '*');
    if (invalidEvents.length > 0) {
      throw new ConflictException(`Invalid event types: ${invalidEvents.join(', ')}`);
    }

    // Check webhook limit
    const tier = await this.getUserTier(userId);
    const tierConfig = TIER_LIMITS[tier] || TIER_LIMITS.free;
    const existingWebhooks = await this.prisma.webhookSubscription.count({
      where: { userId, active: true },
    });
    if (existingWebhooks >= tierConfig.maxWebhooks) {
      throw new ConflictException(`Maximum ${tierConfig.maxWebhooks} webhooks allowed for ${tier} tier`);
    }

    // Generate secret
    const secret = crypto.randomBytes(32).toString('hex');

    const subscription = await this.prisma.webhookSubscription.create({
      data: {
        userId,
        url: dto.url,
        secret,
        events: JSON.stringify(dto.events),
        description: dto.description || null,
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
      id: subscription.id,
      url: subscription.url,
      events: JSON.parse(subscription.events),
      active: subscription.active,
      description: subscription.description,
      createdAt: subscription.createdAt,
      secret, // Only shown on creation
      warning: 'Store this webhook secret securely. It will not be shown again.',
    };
  }

  async listDeliveries(webhookId: string, userId: string, dto: ListDeliveriesDto) {
    // Verify ownership
    const webhook = await this.prisma.webhookSubscription.findFirst({
      where: { id: webhookId, userId },
    });
    if (!webhook) throw new NotFoundException('Webhook subscription not found');

    const { page = 1, limit = 20, status } = dto;
    const where: Record<string, unknown> = { webhookId };
    if (status) where.status = status;

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
      deliveries,
      pagination: { page, limit, total, hasMore: page * limit < total, totalPages: Math.ceil(total / limit) },
    };
  }

  // ── Webhook Emit & Process ──────────────────────────────────────────

  async emit(eventType: string, data: Record<string, unknown>, familyId?: string) {
    // Find matching subscriptions
    const subscriptions = await this.prisma.webhookSubscription.findMany({
      where: { active: true },
    });

    const matching = subscriptions.filter((sub) => {
      const events = JSON.parse(sub.events) as string[];
      return events.includes(eventType) || events.includes('*');
    });

    const deliveries: string[] = [];

    for (const sub of matching) {
      const payload = JSON.stringify({
        event: eventType,
        data,
        timestamp: new Date().toISOString(),
        familyId: familyId || null,
      });

      const signature = this.signWebhook(payload, sub.secret);

      const delivery = await this.prisma.webhookDelivery.create({
        data: {
          webhookId: sub.id,
          eventId: crypto.randomUUID(),
          eventType,
          payload,
          signature,
          status: 'pending',
          nextAttemptAt: new Date(),
        },
      });

      deliveries.push(delivery.id);
    }

    return { emitted: true, deliveryCount: deliveries.length, deliveryIds: deliveries };
  }

  async processPending() {
    const pending = await this.prisma.webhookDelivery.findMany({
      where: {
        status: 'pending',
        nextAttemptAt: { lte: new Date() },
        attemptCount: { lt: 5 },
      },
      take: 50,
      include: { webhook: true },
    });

    const results: { id: string; status: string }[] = [];

    for (const delivery of pending) {
      try {
        const response = await fetch(delivery.webhook.url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Webhook-Signature': delivery.signature,
            'X-Webhook-Event': delivery.eventType,
            'X-Webhook-ID': delivery.eventId,
          },
          body: delivery.payload,
          signal: AbortSignal.timeout(10000),
        });

        const retrySchedule = [0, 60, 300, 900, 3600]; // seconds: 0, 1m, 5m, 15m, 1h
        const nextAttemptIndex = delivery.attemptCount + 1;

        if (response.ok) {
          await this.prisma.webhookDelivery.update({
            where: { id: delivery.id },
            data: {
              status: 'delivered',
              attemptCount: delivery.attemptCount + 1,
              lastAttemptAt: new Date(),
              responseStatusCode: response.status,
            },
          });
          results.push({ id: delivery.id, status: 'delivered' });
        } else if (nextAttemptIndex >= 5) {
          await this.prisma.webhookDelivery.update({
            where: { id: delivery.id },
            data: {
              status: 'failed',
              attemptCount: delivery.attemptCount + 1,
              lastAttemptAt: new Date(),
              responseStatusCode: response.status,
            },
          });
          results.push({ id: delivery.id, status: 'failed' });
        } else {
          const nextDelay = retrySchedule[nextAttemptIndex] || 3600;
          await this.prisma.webhookDelivery.update({
            where: { id: delivery.id },
            data: {
              attemptCount: delivery.attemptCount + 1,
              lastAttemptAt: new Date(),
              nextAttemptAt: new Date(Date.now() + nextDelay * 1000),
              responseStatusCode: response.status,
            },
          });
          results.push({ id: delivery.id, status: 'retrying' });
        }
      } catch {
        const nextAttemptIndex = delivery.attemptCount + 1;
        if (nextAttemptIndex >= 5) {
          await this.prisma.webhookDelivery.update({
            where: { id: delivery.id },
            data: {
              status: 'failed',
              attemptCount: delivery.attemptCount + 1,
              lastAttemptAt: new Date(),
            },
          });
          results.push({ id: delivery.id, status: 'failed' });
        } else {
          const retrySchedule = [0, 60, 300, 900, 3600];
          const nextDelay = retrySchedule[nextAttemptIndex] || 3600;
          await this.prisma.webhookDelivery.update({
            where: { id: delivery.id },
            data: {
              attemptCount: delivery.attemptCount + 1,
              lastAttemptAt: new Date(),
              nextAttemptAt: new Date(Date.now() + nextDelay * 1000),
            },
          });
          results.push({ id: delivery.id, status: 'retrying' });
        }
      }
    }

    return { processed: results.length, results };
  }

  signWebhook(payload: string, secret: string): string {
    return crypto.createHmac('sha256', secret).update(payload).digest('hex');
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  private async getUserTier(userId: string): Promise<string> {
    const subscription = await this.prisma.subscription.findUnique({
      where: { userId },
    });
    return subscription?.plan || 'free';
  }
}
