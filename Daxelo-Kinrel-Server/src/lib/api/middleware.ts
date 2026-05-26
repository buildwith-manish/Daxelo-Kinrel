import { NextRequest, NextResponse } from 'next/server'
import { z, ZodSchema } from 'zod'
import { validateKey, API_KEY_PREFIX, TIER_LIMITS, type TierName } from './api-key'
import { checkRateLimit, rateLimitHeaders, type RateLimitResult } from './rate-limiter'
import { error, errorFromCode } from './response'

// ── Authenticate API Key ─────────────────────────────────────────────

export async function authenticateApiKey(
  request: Request
): Promise<{
  apiKey: Awaited<ReturnType<typeof validateKey>> | null
  error?: NextResponse
}> {
  const authHeader = request.headers.get('Authorization')

  if (!authHeader) {
    return {
      apiKey: null,
      error: errorFromCode('AUTH_REQUIRED'),
    }
  }

  // Support "Bearer kin_live_..." and just "kin_live_..."
  let fullKey = authHeader
  if (authHeader.startsWith('Bearer ')) {
    fullKey = authHeader.slice(7).trim()
  }

  if (!fullKey.startsWith(API_KEY_PREFIX)) {
    return {
      apiKey: null,
      error: errorFromCode('INVALID_API_KEY'),
    }
  }

  const apiKey = await validateKey(fullKey)

  if (!apiKey) {
    return {
      apiKey: null,
      error: errorFromCode('INVALID_API_KEY'),
    }
  }

  if (apiKey.revokedAt) {
    return {
      apiKey: null,
      error: errorFromCode('API_KEY_REVOKED'),
    }
  }

  if (apiKey.expiresAt && new Date() > apiKey.expiresAt) {
    return {
      apiKey: null,
      error: errorFromCode('API_KEY_EXPIRED'),
    }
  }

  return { apiKey }
}

// ── Require Scope ────────────────────────────────────────────────────

export function requireScope(
  apiKey: { scopes: string },
  scope: string
): NextResponse | null {
  const scopes: string[] = JSON.parse(apiKey.scopes)
  if (!scopes.includes(scope) && !scopes.includes('*')) {
    return errorFromCode('INSUFFICIENT_SCOPE', { required: scope, have: scopes })
  }
  return null
}

// ── API Version Headers ──────────────────────────────────────────────

export function apiVersionHeaders(version: string): Record<string, string> {
  return {
    'X-API-Version': version,
    'Deprecation-Notice': '', // Set if deprecated
  }
}

// ── Apply Rate Limit ─────────────────────────────────────────────────

export function applyRateLimit(
  apiKey: { id: string; tier: string },
  endpoint?: string
): { result: RateLimitResult; headers: Record<string, string>; response?: NextResponse } {
  const result = checkRateLimit(apiKey.id, apiKey.tier, endpoint)
  const headers = rateLimitHeaders(result)

  if (!result.allowed) {
    return {
      result,
      headers,
      response: NextResponse.json(
        {
          error: {
            code: 'RATE_LIMITED',
            message: 'Rate limit exceeded. Please retry later.',
            docsUrl: 'https://docs.kinrel.in/api/errors/rate_limited',
          },
          meta: {
            requestId: `req_${Date.now().toString(36)}`,
            timestamp: new Date().toISOString(),
            version: '1.0.0',
          },
        },
        {
          status: 429,
          headers: { ...headers },
        }
      ),
    }
  }

  return { result, headers }
}

// ── Validate JSON Body with Zod ──────────────────────────────────────

export async function validateJsonBody<T>(
  request: NextRequest,
  schema: ZodSchema<T>
): Promise<{ data: T } | { error: NextResponse }> {
  try {
    const body = await request.json()
    const parsed = schema.safeParse(body)

    if (!parsed.success) {
      const details = parsed.error.issues.map(issue => ({
        path: issue.path.join('.'),
        message: issue.message,
      }))

      return {
        error: error('VALIDATION_ERROR', 'Request validation failed', 400, details),
      }
    }

    return { data: parsed.data }
  } catch {
    return {
      error: error('INVALID_PARAMETER', 'Invalid JSON body', 400),
    }
  }
}

// ── Full Middleware Pipeline ─────────────────────────────────────────

export async function apiMiddleware(
  request: NextRequest,
  options: {
    requiredScope?: string
    endpoint?: string
  }
): Promise<{
  apiKey: NonNullable<Awaited<ReturnType<typeof validateKey>>>
  rateLimitHeaders: Record<string, string>
} | NextResponse> {
  // 1. Authenticate
  const authResult = await authenticateApiKey(request)
  if (authResult.error || !authResult.apiKey) {
    return authResult.error!
  }

  const apiKey = authResult.apiKey

  // 2. Check scope
  if (options.requiredScope) {
    const scopeError = requireScope(apiKey, options.requiredScope)
    if (scopeError) return scopeError
  }

  // 3. Rate limit
  const rateLimitResult = applyRateLimit(apiKey, options.endpoint)
  if (rateLimitResult.response) {
    return rateLimitResult.response
  }

  return {
    apiKey,
    rateLimitHeaders: rateLimitResult.headers,
  }
}
