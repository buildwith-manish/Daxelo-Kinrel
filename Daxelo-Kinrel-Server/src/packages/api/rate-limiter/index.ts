/**
 * KINREL Mirror — Rate Limiter
 * Sliding window rate limiter with tier-based configuration.
 */

export interface RateLimitConfig {
  windowMs: number;
  maxRequests: number;
}

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetAt: number;
  retryAfter?: number;
  limit: number;
}

export const TIER_CONFIGS: Record<string, RateLimitConfig> = {
  free: { windowMs: 60_000, maxRequests: 30 },
  pro: { windowMs: 60_000, maxRequests: 120 },
  enterprise: { windowMs: 60_000, maxRequests: 500 },
};

export const ENDPOINT_OVERRIDES: Record<string, Partial<Record<string, RateLimitConfig>>> = {
  free: {
    'POST /v1/families': { windowMs: 60_000, maxRequests: 5 },
    'POST /v1/families/*/persons': { windowMs: 60_000, maxRequests: 10 },
  },
  pro: {
    'POST /v1/families': { windowMs: 60_000, maxRequests: 20 },
  },
  enterprise: {
    'POST /v1/families': { windowMs: 60_000, maxRequests: 100 },
  },
};

const requestStore = new Map<string, number[]>();
const CLEANUP_INTERVAL = 5 * 60_000;
let lastCleanup = Date.now();

function cleanupStore(): void {
  const now = Date.now();
  if (now - lastCleanup < CLEANUP_INTERVAL) return;
  lastCleanup = now;
  for (const [key, timestamps] of requestStore.entries()) {
    const cutoff = now - 60_000;
    const filtered = timestamps.filter(ts => ts > cutoff);
    if (filtered.length === 0) requestStore.delete(key);
    else requestStore.set(key, filtered);
  }
}

export function checkRateLimit(
  keyId: string,
  tier: string,
  endpoint?: string,
): RateLimitResult {
  cleanupStore();

  let config = TIER_CONFIGS[tier] || TIER_CONFIGS.free;

  if (endpoint) {
    const tierOverrides = ENDPOINT_OVERRIDES[tier];
    if (tierOverrides) {
      const exactMatch = tierOverrides[endpoint];
      if (exactMatch) {
        config = exactMatch;
      } else {
        for (const [pattern, override] of Object.entries(tierOverrides)) {
          if (!override) continue;
          const regex = new RegExp('^' + pattern.replace(/\*/g, '[^/]+') + '$');
          if (regex.test(endpoint)) { config = override; break; }
        }
      }
    }
  }

  const now = Date.now();
  const windowStart = now - config.windowMs;
  const storeKey = endpoint ? `${keyId}:${endpoint}` : keyId;
  const existing = requestStore.get(storeKey) || [];
  const inWindow = existing.filter(ts => ts > windowStart);
  const remaining = Math.max(0, config.maxRequests - inWindow.length);
  const resetAt = inWindow.length > 0 ? inWindow[0] + config.windowMs : now + config.windowMs;

  if (inWindow.length >= config.maxRequests) {
    const oldestInWindow = inWindow[0];
    const retryAfter = Math.ceil((oldestInWindow + config.windowMs - now) / 1000);
    return { allowed: false, remaining: 0, resetAt, retryAfter, limit: config.maxRequests };
  }

  inWindow.push(now);
  requestStore.set(storeKey, inWindow);
  return { allowed: true, remaining: remaining - 1, resetAt, limit: config.maxRequests };
}

export function resetRateLimiter(): void {
  requestStore.clear();
}
