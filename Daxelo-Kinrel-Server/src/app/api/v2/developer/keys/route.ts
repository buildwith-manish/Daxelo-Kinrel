import { NextRequest } from 'next/server';
import { z } from 'zod';
import { apiMiddleware } from '@/packages/api/middleware';
import { success, created, error, collection } from '@/packages/api';
import { createKey, getKeysForUser, revokeKey, maskKey, TIER_LIMITS, API_SCOPES, type TierName } from '@/packages/api/api-key';
import { db } from '@/lib/db';
import { apiVersionHeaders } from '@/packages/api/response';

export async function GET(request: NextRequest) {
  const result = await apiMiddleware(request, { requiredScope: 'developer:manage', endpoint: 'GET /v2/developer/keys' });
  if (result instanceof Response) return result;
  const { apiKey, rateLimitHeaders } = result;

  const keys = await getKeysForUser(apiKey.userId);
  const masked = keys.map(k => ({ ...k, keyPrefix: maskKey(k.keyPrefix), scopes: JSON.parse(k.scopes) }));
  return collection(masked, { page: 1, limit: 100, total: masked.length, hasMore: false });
}

const createKeySchema = z.object({ name: z.string().min(1).max(100), scopes: z.array(z.string()).min(1), tier: z.enum(['free', 'pro', 'enterprise']).default('free') });

export async function POST(request: NextRequest) {
  const result = await apiMiddleware(request, { requiredScope: 'developer:manage', endpoint: 'POST /v2/developer/keys' });
  if (result instanceof Response) return result;
  const { apiKey, rateLimitHeaders } = result;

  const body = await request.json().catch(() => null);
  if (!body) return error('INVALID_PARAMETER', 'Invalid JSON body', 400);
  const parsed = createKeySchema.safeParse(body);
  if (!parsed.success) return error('VALIDATION_ERROR', 'Validation failed', 400, parsed.error.issues.map(i => ({ path: i.path.join('.'), message: i.message })));

  const tierConfig = TIER_LIMITS[parsed.data.tier];
  const existingCount = await db.apiKey.count({ where: { userId: apiKey.userId, revokedAt: null } });
  if (existingCount >= tierConfig.maxKeys) return error('CONFLICT', `Max ${tierConfig.maxKeys} keys for ${parsed.data.tier} tier`, 409);

  const newKey = await createKey(apiKey.userId, parsed.data.name, parsed.data.scopes, parsed.data.tier);
  return created({
    id: newKey.apiKey.id, name: newKey.apiKey.name, key: newKey.key,
    keyPrefix: maskKey(newKey.apiKey.keyPrefix), scopes: parsed.data.scopes,
    tier: parsed.data.tier, rateLimitPerMinute: tierConfig.rateLimitPerMinute,
    warning: 'Store this key securely. It will not be shown again.',
  });
}
