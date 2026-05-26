/**
 * KINREL Mirror — API Key Management
 * Create, validate, rotate, and revoke API keys with scoped access.
 */

import crypto from 'crypto';
import { db } from '@/lib/db';

export const API_KEY_PREFIX = 'kin_live_';

export const TIER_LIMITS = {
  free: { rateLimitPerMinute: 30, maxKeys: 2, maxWebhooks: 2 },
  pro: { rateLimitPerMinute: 120, maxKeys: 10, maxWebhooks: 10 },
  enterprise: { rateLimitPerMinute: 500, maxKeys: 50, maxWebhooks: 50 },
} as const;

export type TierName = keyof typeof TIER_LIMITS;

export const API_SCOPES = {
  'families:read': { description: 'Read family data and members' },
  'families:write': { description: 'Create and update families' },
  'persons:read': { description: 'Read person data within families' },
  'persons:write': { description: 'Create and update persons' },
  'relationships:read': { description: 'Read relationship data' },
  'relationships:write': { description: 'Create and update relationships' },
  'graph:read': { description: 'Access family graph and tree data' },
  'webhooks:manage': { description: 'Manage webhook subscriptions' },
  'webhooks:read': { description: 'Read webhook data' },
  'stats:read': { description: 'Access family statistics' },
  'developer:manage': { description: 'Manage API keys' },
  'audit:read': { description: 'Read audit log entries' },
} as const;

export type ApiScope = keyof typeof API_SCOPES;

function generateRawKey(): string {
  const randomBytes = crypto.randomBytes(24).toString('hex');
  return `${API_KEY_PREFIX}${randomBytes}`;
}

function hashKey(fullKey: string): string {
  return crypto.createHash('sha256').update(fullKey).digest('hex');
}

export async function createKey(
  userId: string, name: string, scopes: string[], tier: TierName = 'free',
): Promise<{ key: string; apiKey: Awaited<ReturnType<typeof db.apiKey.create>> }> {
  const rawKey = generateRawKey();
  const keyHash = hashKey(rawKey);
  const keyPrefix = rawKey.slice(0, 12);
  const tierConfig = TIER_LIMITS[tier];

  const apiKey = await db.apiKey.create({
    data: { name, keyPrefix, keyHash, userId, scopes: JSON.stringify(scopes), tier, rateLimitPerMinute: tierConfig.rateLimitPerMinute },
  });

  await db.auditLog.create({
    data: { userId, action: 'API_KEY_CREATED', resource: 'ApiKey', resourceId: apiKey.id, details: JSON.stringify({ name, scopes, tier, keyPrefix }) },
  });

  return { key: rawKey, apiKey };
}

export async function validateKey(fullKey: string): Promise<Awaited<ReturnType<typeof db.apiKey.findUnique>> | null> {
  if (!fullKey.startsWith(API_KEY_PREFIX)) return null;
  const keyHash = hashKey(fullKey);
  const keyPrefix = fullKey.slice(0, 12);
  const apiKey = await db.apiKey.findUnique({ where: { keyPrefix_keyHash: { keyPrefix, keyHash } } });
  if (!apiKey || apiKey.revokedAt) return null;
  if (apiKey.expiresAt && new Date() > apiKey.expiresAt) return null;

  // Fire-and-forget lastUsedAt update
  db.apiKey.update({ where: { id: apiKey.id }, data: { lastUsedAt: new Date() } }).catch(() => {});
  return apiKey;
}

export async function revokeKey(keyId: string, userId: string, reason: string): Promise<boolean> {
  const apiKey = await db.apiKey.findFirst({ where: { id: keyId, userId } });
  if (!apiKey || apiKey.revokedAt) return false;
  await db.apiKey.update({ where: { id: keyId }, data: { revokedAt: new Date(), revokeReason: reason } });
  await db.auditLog.create({ data: { userId, action: 'API_KEY_REVOKED', resource: 'ApiKey', resourceId: keyId, details: JSON.stringify({ reason, keyPrefix: apiKey.keyPrefix }) } });
  return true;
}

export async function rotateKey(keyId: string, userId: string): Promise<{ newKey: string }> {
  const existing = await db.apiKey.findFirst({ where: { id: keyId, userId, revokedAt: null } });
  if (!existing) throw new Error('API key not found or already revoked');
  await db.apiKey.update({ where: { id: keyId }, data: { revokedAt: new Date(), revokeReason: 'Rotated' } });
  const scopes: string[] = JSON.parse(existing.scopes);
  const tier = existing.tier as TierName;
  const result = await createKey(userId, `${existing.name} (rotated)`, scopes, tier);
  await db.auditLog.create({ data: { userId, action: 'API_KEY_ROTATED', resource: 'ApiKey', resourceId: keyId, details: JSON.stringify({ oldKeyPrefix: existing.keyPrefix, newKeyPrefix: result.apiKey.keyPrefix }) } });
  return { newKey: result.key };
}

export function maskKey(keyPrefix: string): string {
  return `${keyPrefix}${'•'.repeat(32)}`;
}

export async function getKeysForUser(userId: string) {
  return db.apiKey.findMany({
    where: { userId },
    select: { id: true, name: true, keyPrefix: true, scopes: true, tier: true, rateLimitPerMinute: true, lastUsedAt: true, expiresAt: true, revokedAt: true, revokeReason: true, createdAt: true, updatedAt: true },
    orderBy: { createdAt: 'desc' },
  });
}
