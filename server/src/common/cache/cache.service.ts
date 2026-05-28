import { Injectable, Logger } from '@nestjs/common';

/**
 * CacheEntry — Internal structure for each cached item.
 */
interface CacheEntry<T = any> {
  value: T;
  expiresAt: number; // Unix timestamp in ms
  createdAt: number;
}

/**
 * CacheRouteConfig — TTL configuration per route pattern.
 */
export interface CacheRouteConfig {
  pattern: RegExp;
  ttl: number; // seconds
}

/**
 * CacheService — In-memory LRU cache with TTL support.
 *
 * Features:
 *  - Max 500 entries with LRU eviction
 *  - Per-entry TTL (time-to-live)
 *  - Cache key = route + userId + params
 *  - Invalidation by resource prefix
 *  - Hit/miss tracking via X-Cache header
 *
 * Configured route-specific TTLs:
 *  - GET /api/family/:id → 60s
 *  - GET /api/families/:familyId/persons → 30s
 *  - GET /api/v1/kinship → 3600s (static data)
 *  - GET /api/users/me → 30s
 *  - GET /api/families/:familyId/timeline → 60s
 */
@Injectable()
export class CacheService {
  private readonly logger = new Logger(CacheService.name);
  private readonly cache = new Map<string, CacheEntry>();
  private readonly maxSize = 500;

  /** Route-specific TTL configurations (matched in order, first match wins) */
  private readonly routeConfigs: CacheRouteConfig[] = [
    { pattern: /^GET\/api\/family\/[^/]+$/, ttl: 60 },
    { pattern: /^GET\/api\/families\/[^/]+\/persons/, ttl: 30 },
    { pattern: /^GET\/api\/v1\/kinship/, ttl: 3600 },
    { pattern: /^GET\/api\/users\/me/, ttl: 30 },
    { pattern: /^GET\/api\/families\/[^/]+\/timeline/, ttl: 60 },
  ];

  /** Routes that should NEVER be cached */
  private readonly noCachePatterns: RegExp[] = [
    /\/api\/auth\//,       // auth routes
    /\/api\/payments\//,   // payment routes
    /\/api\/.*\/upload/,   // file upload routes
    /\/api\/.*\/avatar/,   // avatar upload routes
  ];

  /**
   * Get the configured TTL for a given route key.
   * Returns 0 if the route should not be cached.
   */
  getTtlForKey(routeKey: string): number {
    // Check no-cache patterns first
    for (const pattern of this.noCachePatterns) {
      if (pattern.test(routeKey)) {
        return 0;
      }
    }

    // Only cache GET requests
    if (!routeKey.startsWith('GET')) {
      return 0;
    }

    // Find matching route config
    for (const config of this.routeConfigs) {
      if (config.pattern.test(routeKey)) {
        return config.ttl;
      }
    }

    // No matching config — not cacheable
    return 0;
  }

  /**
   * Build a cache key from route, userId, and params.
   * Format: METHOD:path:userId:params
   */
  buildKey(method: string, path: string, userId?: string, params?: Record<string, string>): string {
    const paramSuffix = params && Object.keys(params).length > 0
      ? ':' + Object.entries(params).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}=${v}`).join('&')
      : '';
    const userSuffix = userId ? `:${userId}` : ':anonymous';
    return `${method.toUpperCase()}${path}${userSuffix}${paramSuffix}`;
  }

  /**
   * Retrieve a cached value.
   * Returns { value, hit: true } on cache hit, { value: undefined, hit: false } on miss.
   */
  get<T = any>(key: string): { value: T | undefined; hit: boolean } {
    const entry = this.cache.get(key);
    if (!entry) {
      return { value: undefined, hit: false };
    }

    const now = Date.now();
    if (now >= entry.expiresAt) {
      // Entry has expired — remove and report miss
      this.cache.delete(key);
      return { value: undefined, hit: false };
    }

    // LRU: re-insert at the end (most recently used)
    this.cache.delete(key);
    this.cache.set(key, entry);

    return { value: entry.value as T, hit: true };
  }

  /**
   * Store a value in the cache with a given TTL.
   */
  set<T = any>(key: string, value: T, ttlSeconds: number): void {
    // Enforce max size with LRU eviction
    while (this.cache.size >= this.maxSize) {
      // Evict the oldest entry (first in Map = least recently used)
      const oldestKey = this.cache.keys().next().value;
      if (oldestKey !== undefined) {
        this.cache.delete(oldestKey);
      }
    }

    this.cache.set(key, {
      value,
      expiresAt: Date.now() + ttlSeconds * 1000,
      createdAt: Date.now(),
    });
  }

  /**
   * Invalidate cache entries matching a resource prefix.
   * Called on POST/PUT/DELETE/PATCH to the same resource.
   *
   * For example, if a PUT to /api/families/abc is made,
   * this will invalidate all GET cache entries for that resource.
   */
  invalidateByResource(method: string, path: string, userId?: string): number {
    let invalidated = 0;

    // Determine the resource prefix to invalidate
    // For a mutation on a resource, we invalidate all GET caches for that resource
    const resourcePath = path;

    for (const key of this.cache.keys()) {
      // Match by resource path prefix (any userId on this resource)
      if (this.isRelatedCacheKey(key, resourcePath)) {
        this.cache.delete(key);
        invalidated++;
      }
    }

    if (invalidated > 0) {
      this.logger.debug(`Invalidated ${invalidated} cache entries for ${method} ${path}`);
    }

    return invalidated;
  }

  /**
   * Check if a cache key is related to a mutated path.
   * E.g., mutating /api/families/abc should also invalidate:
   *  - /api/families/abc/persons
   *  - /api/families/abc/timeline
   */
  private isRelatedCacheKey(cacheKey: string, mutatedPath: string): boolean {
    // Extract the path portion from the cache key (after GET prefix, before userId)
    // Cache key format: GET/path:userId:params
    const methodEndIdx = cacheKey.indexOf('/');
    if (methodEndIdx === -1) return false;

    const keyWithoutMethod = cacheKey.substring(methodEndIdx);
    // Extract just the path (before the first colon that marks userId)
    const colonIdx = keyWithoutMethod.indexOf(':');
    const keyPath = colonIdx === -1 ? keyWithoutMethod : keyWithoutMethod.substring(0, colonIdx);

    // If the mutated path is a prefix of the cached path, they're related
    if (keyPath.startsWith(mutatedPath)) return true;

    // Also check reverse: /api/families/abc mutation should invalidate
    // /api/families/abc/persons and /api/families/abc/timeline
    const basePath = mutatedPath.split('/persons')[0].split('/timeline')[0];
    if (keyPath.startsWith(basePath)) return true;

    return false;
  }

  /**
   * Clear all cache entries.
   */
  flush(): void {
    this.cache.clear();
    this.logger.log('Cache flushed');
  }

  /**
   * Get cache statistics.
   */
  getStats(): { size: number; maxSize: number } {
    return {
      size: this.cache.size,
      maxSize: this.maxSize,
    };
  }

  /**
   * Remove all expired entries. Can be called periodically.
   */
  cleanup(): number {
    const now = Date.now();
    let cleaned = 0;

    for (const [key, entry] of this.cache.entries()) {
      if (now >= entry.expiresAt) {
        this.cache.delete(key);
        cleaned++;
      }
    }

    if (cleaned > 0) {
      this.logger.debug(`Cleaned up ${cleaned} expired cache entries`);
    }

    return cleaned;
  }
}
