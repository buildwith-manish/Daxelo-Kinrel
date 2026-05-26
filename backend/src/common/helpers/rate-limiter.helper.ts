/**
 * In-memory sliding window rate limiter
 * Matches the Next.js version's behavior with tier-based configuration
 */

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetAt: number;
  retryAfter?: number;
  limit: number;
}

export interface TierConfig {
  maxRequests: number;
  windowMs: number;
}

/**
 * Rate limit tier configurations
 * free: 30 requests per minute
 * pro: 120 requests per minute
 * enterprise: 500 requests per minute
 */
export const TIER_CONFIGS: Record<string, TierConfig> = {
  free: { maxRequests: 30, windowMs: 60_000 },
  pro: { maxRequests: 120, windowMs: 60_000 },
  enterprise: { maxRequests: 500, windowMs: 60_000 },
};

/**
 * In-memory store: Map<key, timestamps[]>
 * Each key maps to an array of request timestamps within the sliding window
 */
const store = new Map<string, number[]>();

/**
 * Clean up expired entries periodically
 */
function cleanupExpired(key: string, windowMs: number): void {
  const timestamps = store.get(key);
  if (!timestamps) return;

  const cutoff = Date.now() - windowMs;
  const filtered = timestamps.filter((ts) => ts > cutoff);

  if (filtered.length === 0) {
    store.delete(key);
  } else {
    store.set(key, filtered);
  }
}

/**
 * Check rate limit for a given key
 * @param keyId - Unique identifier (e.g., API key ID or user ID)
 * @param tier - Subscription tier (free, pro, enterprise)
 * @param endpoint - Optional endpoint for per-endpoint rate limiting
 * @returns RateLimitResult with allowed status and metadata
 */
export function checkRateLimit(
  keyId: string,
  tier: string = 'free',
  endpoint?: string,
): RateLimitResult {
  const config = TIER_CONFIGS[tier] || TIER_CONFIGS.free;
  const compositeKey = endpoint ? `${keyId}:${endpoint}` : keyId;

  const now = Date.now();
  const windowStart = now - config.windowMs;

  // Get existing timestamps and filter out expired ones
  let timestamps = store.get(compositeKey) || [];
  timestamps = timestamps.filter((ts) => ts > windowStart);

  const currentCount = timestamps.length;
  const allowed = currentCount < config.maxRequests;

  if (allowed) {
    timestamps.push(now);
    store.set(compositeKey, timestamps);
  }

  const remaining = Math.max(0, config.maxRequests - timestamps.length);
  const resetAt = timestamps.length > 0 ? timestamps[0] + config.windowMs : now + config.windowMs;

  const result: RateLimitResult = {
    allowed,
    remaining,
    resetAt,
    limit: config.maxRequests,
  };

  if (!allowed) {
    result.retryAfter = Math.ceil((resetAt - now) / 1000);
  }

  return result;
}

/**
 * Generate rate limit headers for HTTP response
 * @param result - RateLimitResult from checkRateLimit
 * @returns Object with rate limit headers
 */
export function rateLimitHeaders(result: RateLimitResult): Record<string, string> {
  const headers: Record<string, string> = {
    'X-RateLimit-Limit': String(result.limit),
    'X-RateLimit-Remaining': String(result.remaining),
    'X-RateLimit-Reset': String(Math.ceil(result.resetAt / 1000)),
  };

  if (!result.allowed && result.retryAfter) {
    headers['Retry-After'] = String(result.retryAfter);
  }

  return headers;
}

/**
 * Clear all rate limit data (useful for testing)
 */
export function clearRateLimitStore(): void {
  store.clear();
}
