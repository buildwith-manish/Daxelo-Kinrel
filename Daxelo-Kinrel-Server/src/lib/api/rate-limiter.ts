// ── Rate Limiter (In-Memory, SQLite-Compatible) ──────────────────────
// Uses sliding window algorithm with a Map of timestamps

// ── Types ────────────────────────────────────────────────────────────

export interface RateLimitConfig {
  windowMs: number
  maxRequests: number
}

export interface RateLimitResult {
  allowed: boolean
  remaining: number
  resetAt: number
  retryAfter?: number
  limit: number
}

// ── Tier Configs ─────────────────────────────────────────────────────

export const TIER_CONFIGS: Record<string, RateLimitConfig> = {
  free: { windowMs: 60_000, maxRequests: 30 },
  pro: { windowMs: 60_000, maxRequests: 120 },
  enterprise: { windowMs: 60_000, maxRequests: 500 },
}

// ── Endpoint-Specific Overrides ──────────────────────────────────────

export const ENDPOINT_OVERRIDES: Record<string, Partial<Record<string, RateLimitConfig>>> = {
  // tier -> endpoint -> config
  free: {
    'POST /v1/families': { windowMs: 60_000, maxRequests: 5 },
    'POST /v1/families/*/persons': { windowMs: 60_000, maxRequests: 10 },
    'GET /v1/graph/*/tree': { windowMs: 60_000, maxRequests: 10 },
    'GET /v1/graph/*/path': { windowMs: 60_000, maxRequests: 10 },
  },
  pro: {
    'POST /v1/families': { windowMs: 60_000, maxRequests: 20 },
    'POST /v1/families/*/persons': { windowMs: 60_000, maxRequests: 30 },
  },
  enterprise: {
    'POST /v1/families': { windowMs: 60_000, maxRequests: 100 },
    'POST /v1/families/*/persons': { windowMs: 60_000, maxRequests: 100 },
  },
}

// ── Sliding Window Store ─────────────────────────────────────────────

const requestStore = new Map<string, number[]>()

// Periodic cleanup of old entries (every 5 minutes)
const CLEANUP_INTERVAL = 5 * 60_000
let lastCleanup = Date.now()

function cleanupStore(): void {
  const now = Date.now()
  if (now - lastCleanup < CLEANUP_INTERVAL) return
  lastCleanup = now

  for (const [key, timestamps] of requestStore.entries()) {
    const windowMs = TIER_CONFIGS.free.windowMs // Use max window
    const cutoff = now - windowMs
    const filtered = timestamps.filter(ts => ts > cutoff)
    if (filtered.length === 0) {
      requestStore.delete(key)
    } else {
      requestStore.set(key, filtered)
    }
  }
}

// ── Check Rate Limit ─────────────────────────────────────────────────

export function checkRateLimit(
  keyId: string,
  tier: string,
  endpoint?: string
): RateLimitResult {
  cleanupStore()

  // Determine the config to use
  let config = TIER_CONFIGS[tier] || TIER_CONFIGS.free

  // Check endpoint overrides
  if (endpoint) {
    const tierOverrides = ENDPOINT_OVERRIDES[tier]
    if (tierOverrides) {
      // Try exact match first, then wildcard patterns
      const exactMatch = tierOverrides[endpoint]
      if (exactMatch) {
        config = exactMatch
      } else {
        // Check wildcard patterns
        for (const [pattern, override] of Object.entries(tierOverrides)) {
          if (!override) continue
          const regex = new RegExp('^' + pattern.replace(/\*/g, '[^/]+') + '$')
          if (regex.test(endpoint)) {
            config = override
            break
          }
        }
      }
    }
  }

  const now = Date.now()
  const windowStart = now - config.windowMs
  const storeKey = endpoint ? `${keyId}:${endpoint}` : keyId

  // Get existing timestamps and filter to current window
  const existing = requestStore.get(storeKey) || []
  const inWindow = existing.filter(ts => ts > windowStart)

  const remaining = Math.max(0, config.maxRequests - inWindow.length)
  const resetAt = inWindow.length > 0 ? inWindow[0] + config.windowMs : now + config.windowMs

  if (inWindow.length >= config.maxRequests) {
    const oldestInWindow = inWindow[0]
    const retryAfter = Math.ceil((oldestInWindow + config.windowMs - now) / 1000)

    return {
      allowed: false,
      remaining: 0,
      resetAt,
      retryAfter,
      limit: config.maxRequests,
    }
  }

  // Record this request
  inWindow.push(now)
  requestStore.set(storeKey, inWindow)

  return {
    allowed: true,
    remaining: remaining - 1,
    resetAt,
    limit: config.maxRequests,
  }
}

// ── Rate Limit Headers ───────────────────────────────────────────────

export function rateLimitHeaders(result: RateLimitResult): Record<string, string> {
  const headers: Record<string, string> = {
    'X-RateLimit-Limit': String(result.limit),
    'X-RateLimit-Remaining': String(result.remaining),
    'X-RateLimit-Reset': String(Math.ceil(result.resetAt / 1000)),
  }

  if (!result.allowed && result.retryAfter !== undefined) {
    headers['Retry-After'] = String(result.retryAfter)
  }

  return headers
}

// ── Reset (for testing) ──────────────────────────────────────────────

export function resetRateLimiter(): void {
  requestStore.clear()
}
