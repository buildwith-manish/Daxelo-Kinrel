import { Injectable, Logger } from '@nestjs/common';

/**
 * CacheEntry — Internal structure for each cached item.
 */
interface CacheEntry<T = any> {
  value: T;
  expiresAt: number; // Unix timestamp in ms
  createdAt: number;
  tags: string[]; // Tags for group invalidation
}

/**
 * CacheRouteConfig — TTL configuration per route pattern.
 */
export interface CacheRouteConfig {
  pattern: RegExp;
  ttl: number; // seconds
}

/**
 * SingleflightEntry — Tracks in-flight cache fill operations.
 * Prevents cache stampede: if multiple requests ask for the same key
 * simultaneously, only one fill operation runs and the rest wait for it.
 */
interface SingleflightEntry<T = any> {
  promise: Promise<T>;
  timestamp: number;
}

/**
 * CacheService — In-memory LRU cache with TTL, tags, and singleflight support.
 *
 * Features:
 *  - Max 500 entries with LRU eviction
 *  - Per-entry TTL (time-to-live)
 *  - Cache key = route + userId + params
 *  - Invalidation by resource prefix
 *  - Tag-based caching and invalidation
 *  - Singleflight (cache stampede protection)
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

  /** Tag → Set of cache keys (for tag-based invalidation) */
  private readonly tagIndex = new Map<string, Set<string>>();

  /** Singleflight map: key → in-flight promise */
  private readonly singleflightMap = new Map<string, SingleflightEntry>();
  private static readonly SINGLEFLIGHT_TTL_MS = 30_000; // 30s max wait

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
      this.removeEntry(key);
      return { value: undefined, hit: false };
    }

    // LRU: re-insert at the end (most recently used)
    this.cache.delete(key);
    this.cache.set(key, entry);

    return { value: entry.value as T, hit: true };
  }

  /**
   * Store a value in the cache with a given TTL and optional tags.
   */
  set<T = any>(key: string, value: T, ttlSeconds: number, tags: string[] = []): void {
    // Enforce max size with LRU eviction
    while (this.cache.size >= this.maxSize) {
      // Evict the oldest entry (first in Map = least recently used)
      const oldestKey = this.cache.keys().next().value;
      if (oldestKey !== undefined) {
        this.removeEntry(oldestKey);
      }
    }

    // If key already exists, remove old tag associations
    const existing = this.cache.get(key);
    if (existing) {
      this.removeTagsFromKey(key, existing.tags);
    }

    const entry: CacheEntry<T> = {
      value,
      expiresAt: Date.now() + ttlSeconds * 1000,
      createdAt: Date.now(),
      tags,
    };

    this.cache.set(key, entry);

    // Register tags
    for (const tag of tags) {
      if (!this.tagIndex.has(tag)) {
        this.tagIndex.set(tag, new Set());
      }
      this.tagIndex.get(tag)!.add(key);
    }
  }

  /**
   * Invalidate all cache entries matching a given tag.
   * Returns the number of entries invalidated.
   */
  invalidateByTag(tag: string): number {
    const keys = this.tagIndex.get(tag);
    if (!keys || keys.size === 0) {
      return 0;
    }

    let invalidated = 0;
    const keysToRemove = [...keys]; // Copy to avoid mutation during iteration
    for (const key of keysToRemove) {
      this.removeEntry(key);
      invalidated++;
    }

    this.tagIndex.delete(tag);

    if (invalidated > 0) {
      this.logger.debug(`Invalidated ${invalidated} cache entries for tag "${tag}"`);
    }

    return invalidated;
  }

  /**
   * Invalidate cache entries matching multiple tags.
   * Returns the total number of entries invalidated.
   */
  invalidateByTags(tags: string[]): number {
    let total = 0;
    for (const tag of tags) {
      total += this.invalidateByTag(tag);
    }
    return total;
  }

  /**
   * Invalidate cache entries matching a resource prefix.
   * Called on POST/PUT/DELETE/PATCH to the same resource.
   */
  invalidateByResource(method: string, path: string, userId?: string): number {
    let invalidated = 0;

    const resourcePath = path;

    for (const key of this.cache.keys()) {
      if (this.isRelatedCacheKey(key, resourcePath)) {
        this.removeEntry(key);
        invalidated++;
      }
    }

    if (invalidated > 0) {
      this.logger.debug(`Invalidated ${invalidated} cache entries for ${method} ${path}`);
    }

    return invalidated;
  }

  /**
   * Singleflight: Execute a function only once for a given key.
   * If another call is in-flight for the same key, return the same promise.
   * This prevents cache stampede when multiple requests miss the cache
   * simultaneously and all try to fetch the same data.
   */
  async singleflight<T = any>(
    key: string,
    fn: () => Promise<T>,
    ttlSeconds: number = 30,
    tags: string[] = [],
  ): Promise<T> {
    // Check cache first
    const cached = this.get<T>(key);
    if (cached.hit && cached.value !== undefined) {
      return cached.value;
    }

    // Check if there's an in-flight request for this key
    const inflight = this.singleflightMap.get(key);
    if (inflight && Date.now() - inflight.timestamp < CacheService.SINGLEFLIGHT_TTL_MS) {
      return inflight.promise as Promise<T>;
    }

    // Create the in-flight promise
    const promise = fn()
      .then((result) => {
        // Cache the result
        this.set(key, result, ttlSeconds, tags);
        return result;
      })
      .finally(() => {
        // Remove from singleflight map once resolved/rejected
        this.singleflightMap.delete(key);
      });

    this.singleflightMap.set(key, { promise, timestamp: Date.now() });

    return promise;
  }

  /**
   * Check if a cache key is related to a mutated path.
   */
  private isRelatedCacheKey(cacheKey: string, mutatedPath: string): boolean {
    const methodEndIdx = cacheKey.indexOf('/');
    if (methodEndIdx === -1) return false;

    const keyWithoutMethod = cacheKey.substring(methodEndIdx);
    const colonIdx = keyWithoutMethod.indexOf(':');
    const keyPath = colonIdx === -1 ? keyWithoutMethod : keyWithoutMethod.substring(0, colonIdx);

    if (keyPath.startsWith(mutatedPath)) return true;

    const basePath = mutatedPath.split('/persons')[0].split('/timeline')[0];
    if (keyPath.startsWith(basePath)) return true;

    return false;
  }

  /**
   * Remove a cache entry and clean up tag associations.
   */
  private removeEntry(key: string): void {
    const entry = this.cache.get(key);
    if (entry) {
      this.removeTagsFromKey(key, entry.tags);
    }
    this.cache.delete(key);
  }

  /**
   * Remove tag → key associations for a given key.
   */
  private removeTagsFromKey(key: string, tags: string[]): void {
    for (const tag of tags) {
      const keys = this.tagIndex.get(tag);
      if (keys) {
        keys.delete(key);
        if (keys.size === 0) {
          this.tagIndex.delete(tag);
        }
      }
    }
  }

  /**
   * Clear all cache entries.
   */
  flush(): void {
    this.cache.clear();
    this.tagIndex.clear();
    this.singleflightMap.clear();
    this.logger.log('Cache flushed');
  }

  /**
   * Get cache statistics.
   */
  getStats(): { size: number; maxSize: number; tagCount: number; singleflightCount: number } {
    return {
      size: this.cache.size,
      maxSize: this.maxSize,
      tagCount: this.tagIndex.size,
      singleflightCount: this.singleflightMap.size,
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
        this.removeEntry(key);
        cleaned++;
      }
    }

    // Also clean up stale singleflight entries
    for (const [key, entry] of this.singleflightMap.entries()) {
      if (now - entry.timestamp > CacheService.SINGLEFLIGHT_TTL_MS) {
        this.singleflightMap.delete(key);
      }
    }

    if (cleaned > 0) {
      this.logger.debug(`Cleaned up ${cleaned} expired cache entries`);
    }

    return cleaned;
  }
}
