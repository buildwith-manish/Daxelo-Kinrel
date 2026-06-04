import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { createHash, randomBytes } from 'crypto';

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

@Injectable()
export class DeveloperService {
  constructor(private prisma: PrismaService) {}

  // ── API Keys ──────────────────────────────────────────────────────────

  /**
   * List all API keys for a user.
   * Only returns metadata — never the full key.
   */
  async listApiKeys(userId: string) {
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

  /**
   * Create a new API key.
   * Returns the full key only once — subsequent calls only show the prefix.
   */
  async createApiKey(
    userId: string,
    data: {
      name: string;
      scopes?: string[];
      tier?: string;
    },
  ) {
    if (!data.name || data.name.trim().length === 0) {
      throw new BadRequestException('API key name is required');
    }

    // Validate scopes
    const scopes = data.scopes || ['families:read', 'persons:read'];
    const invalidScopes = scopes.filter((s) => !VALID_SCOPES.includes(s));
    if (invalidScopes.length > 0) {
      throw new BadRequestException(
        `Invalid scopes: ${invalidScopes.join(', ')}`,
      );
    }

    // Generate API key
    const keyMode = data.tier === 'enterprise' ? 'live' : 'test';
    const keySecret = randomBytes(24).toString('hex');
    const fullKey = `kin_${keyMode}_${keySecret}`;
    const keyPrefix = fullKey.substring(0, 16);
    const keyHash = createHash('sha256').update(fullKey).digest('hex');

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

    // Create audit log
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
      key: fullKey, // Only returned once!
      keyPrefix: apiKey.keyPrefix,
      scopes,
      tier: apiKey.tier,
      createdAt: apiKey.createdAt,
    };
  }

  /**
   * Revoke an API key.
   */
  async revokeApiKey(keyId: string, userId: string, reason?: string) {
    const apiKey = await this.prisma.apiKey.findUnique({
      where: { id: keyId },
    });

    if (!apiKey) {
      throw new NotFoundException('API key not found');
    }

    if (apiKey.userId !== userId) {
      throw new ForbiddenException('You can only revoke your own API keys');
    }

    if (apiKey.revokedAt) {
      throw new BadRequestException('API key is already revoked');
    }

    const updated = await this.prisma.apiKey.update({
      where: { id: keyId },
      data: {
        revokedAt: new Date(),
        revokeReason: reason || 'User requested revocation',
      },
    });

    // Create audit log
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

  // ── Webhooks ──────────────────────────────────────────────────────────

  /**
   * List webhooks for a user.
   */
  async listWebhooks(userId: string) {
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

  /**
   * Create a new webhook subscription.
   */
  async createWebhook(
    userId: string,
    data: {
      url: string;
      events: string[];
      description?: string;
    },
  ) {
    if (!data.url || !data.url.startsWith('https://')) {
      throw new BadRequestException(
        'Webhook URL must be a valid HTTPS URL',
      );
    }

    if (!data.events || data.events.length === 0) {
      throw new BadRequestException('At least one event type is required');
    }

    // Generate a secret for HMAC signature verification
    const secret = randomBytes(32).toString('hex');

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
      secret: webhook.secret, // Only returned once!
      events: JSON.parse(webhook.events),
      active: webhook.active,
      description: webhook.description,
      createdAt: webhook.createdAt,
    };
  }

  /**
   * Get delivery log for a webhook.
   */
  async getWebhookDeliveries(webhookId: string, userId: string) {
    const webhook = await this.prisma.webhookSubscription.findUnique({
      where: { id: webhookId },
    });

    if (!webhook) {
      throw new NotFoundException('Webhook not found');
    }

    if (webhook.userId !== userId) {
      throw new ForbiddenException('You can only view your own webhook deliveries');
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
}
