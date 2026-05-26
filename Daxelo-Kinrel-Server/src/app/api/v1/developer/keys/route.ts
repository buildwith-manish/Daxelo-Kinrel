import { NextRequest, NextResponse } from 'next/server'
import { z } from 'zod'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, collection, error } from '@/lib/api/response'
import { createKey, getKeysForUser, revokeKey, rotateKey, maskKey, TIER_LIMITS, API_SCOPES, type TierName } from '@/lib/api/api-key'
import { apiVersionHeaders } from '@/lib/api/middleware'

// ── GET /v1/developer/keys ───────────────────────────────────────────

export async function GET(request: NextRequest) {
  const result = await apiMiddleware(request, {
    requiredScope: 'developer:manage',
    endpoint: 'GET /v1/developer/keys',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  const keys = await getKeysForUser(apiKey.userId)

  // Mask sensitive data
  const maskedKeys = keys.map(key => ({
    ...key,
    keyPrefix: maskKey(key.keyPrefix),
    scopes: JSON.parse(key.scopes),
  }))

  const response = collection(maskedKeys, {
    page: 1,
    limit: 100,
    total: maskedKeys.length,
    hasMore: false,
  })

  return new NextResponse(response.body, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}

// ── POST /v1/developer/keys ──────────────────────────────────────────

const createKeySchema = z.object({
  name: z.string().min(1).max(100),
  scopes: z.array(z.string()).min(1),
  tier: z.enum(['free', 'pro', 'enterprise']).default('free'),
})

export async function POST(request: NextRequest) {
  const result = await apiMiddleware(request, {
    requiredScope: 'developer:manage',
    endpoint: 'POST /v1/developer/keys',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  const body = await request.json().catch(() => null)
  if (!body) {
    return error('INVALID_PARAMETER', 'Invalid JSON body', 400)
  }

  const parsed = createKeySchema.safeParse(body)
  if (!parsed.success) {
    const details = parsed.error.issues.map(issue => ({
      path: issue.path.join('.'),
      message: issue.message,
    }))
    return error('VALIDATION_ERROR', 'Request validation failed', 400, details)
  }

  const data = parsed.data

  // Validate scopes
  const validScopes = Object.keys(API_SCOPES)
  const invalidScopes = data.scopes.filter(s => !validScopes.includes(s) && s !== '*')
  if (invalidScopes.length > 0) {
    return error('INVALID_PARAMETER', `Invalid scopes: ${invalidScopes.join(', ')}`, 400, {
      validScopes,
    })
  }

  // Check tier limits
  const tierConfig = TIER_LIMITS[data.tier]
  const existingKeys = await db.apiKey.count({
    where: { userId: apiKey.userId, revokedAt: null },
  })

  if (existingKeys >= tierConfig.maxKeys) {
    return error('CONFLICT', `Maximum ${tierConfig.maxKeys} API keys allowed for ${data.tier} tier`, 409, {
      current: existingKeys,
      max: tierConfig.maxKeys,
      tier: data.tier,
    })
  }

  const newKeyResult = await createKey(apiKey.userId, data.name, data.scopes, data.tier)

  const response = success({
    id: newKeyResult.apiKey.id,
    name: newKeyResult.apiKey.name,
    key: newKeyResult.key, // Only shown once!
    keyPrefix: maskKey(newKeyResult.apiKey.keyPrefix),
    scopes: data.scopes,
    tier: data.tier,
    rateLimitPerMinute: tierConfig.rateLimitPerMinute,
    createdAt: newKeyResult.apiKey.createdAt,
    warning: 'Store this API key securely. It will not be shown again.',
  })

  return new NextResponse(response.body, {
    status: 201,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}

// ── DELETE /v1/developer/keys ────────────────────────────────────────

const revokeKeySchema = z.object({
  keyId: z.string().min(1),
  reason: z.string().min(1).max(500).default('Revoked by user'),
})

export async function DELETE(request: NextRequest) {
  const result = await apiMiddleware(request, {
    requiredScope: 'developer:manage',
    endpoint: 'DELETE /v1/developer/keys',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  const body = await request.json().catch(() => null)
  if (!body) {
    return error('INVALID_PARAMETER', 'Invalid JSON body', 400)
  }

  const parsed = revokeKeySchema.safeParse(body)
  if (!parsed.success) {
    const details = parsed.error.issues.map(issue => ({
      path: issue.path.join('.'),
      message: issue.message,
    }))
    return error('VALIDATION_ERROR', 'Request validation failed', 400, details)
  }

  const data = parsed.data

  const revoked = await revokeKey(data.keyId, apiKey.userId, data.reason)

  if (!revoked) {
    return error('NOT_FOUND', 'API key not found or already revoked', 404)
  }

  const response = success({
    revoked: true,
    keyId: data.keyId,
    reason: data.reason,
  })

  return new NextResponse(response.body, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}
