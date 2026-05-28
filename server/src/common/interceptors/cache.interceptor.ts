import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  Logger,
} from '@nestjs/common';
import { Observable, of, tap } from 'rxjs';
import { CacheService } from '../cache/cache.service';
import { Reflector } from '@nestjs/core';

/**
 * CacheInterceptor — NestJS interceptor for API response caching.
 *
 * Usage:
 *   @UseInterceptors(CacheInterceptor)          // auto TTL from route config
 *   @UseInterceptors(new CacheInterceptor({ ttl: 60 }))  // custom TTL
 *
 * Behaviour:
 *  - GET requests: checks cache, returns HIT or caches MISS
 *  - POST/PUT/DELETE/PATCH: invalidates cache for the same resource
 *  - Always sets X-Cache header: HIT or MISS
 *  - Skips caching for auth, payment, and file upload routes
 */
@Injectable()
export class CacheInterceptor implements NestInterceptor {
  private readonly logger = new Logger(CacheInterceptor.name);
  private readonly customTtl?: number;
  private readonly cacheService: CacheService;

  constructor(options?: { ttl?: number; cacheService?: CacheService }) {
    this.customTtl = options?.ttl;
    // If a CacheService instance is provided, use it; otherwise create one
    // In NestJS DI context, the service will be injected via the module
    this.cacheService = options?.cacheService ?? new CacheService();
  }

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest();
    const response = context.switchToHttp().getResponse();
    const method = request.method.toUpperCase();
    const url: string = request.url;

    // Extract userId from the authenticated user (if available)
    const userId: string | undefined = request.user?.id;

    // Extract route params
    const params: Record<string, string> = request.params ?? {};

    // Build the cache key
    const cacheKey = this.cacheService.buildKey(method, url, userId, params);

    // ── Mutation requests: invalidate cache ──────────────────────
    if (['POST', 'PUT', 'DELETE', 'PATCH'].includes(method)) {
      return next.handle().pipe(
        tap(() => {
          // Invalidate all cached GET entries for this resource
          this.cacheService.invalidateByResource(method, url, userId);
        }),
      );
    }

    // ── Non-GET requests: pass through without caching ───────────
    if (method !== 'GET') {
      response.setHeader('X-Cache', 'MISS');
      return next.handle();
    }

    // ── Determine TTL ────────────────────────────────────────────
    const ttl = this.customTtl ?? this.cacheService.getTtlForKey(cacheKey);

    if (ttl <= 0) {
      // Route not cacheable
      response.setHeader('X-Cache', 'MISS');
      return next.handle();
    }

    // ── Check cache ──────────────────────────────────────────────
    const { value, hit } = this.cacheService.get(cacheKey);

    if (hit && value !== undefined) {
      // Cache HIT
      response.setHeader('X-Cache', 'HIT');
      this.logger.debug(`Cache HIT: ${cacheKey}`);
      return of(value);
    }

    // Cache MISS — call handler and cache the response
    response.setHeader('X-Cache', 'MISS');
    this.logger.debug(`Cache MISS: ${cacheKey}`);

    return next.handle().pipe(
      tap((data) => {
        // Only cache successful responses
        if (response.statusCode >= 200 && response.statusCode < 300) {
          this.cacheService.set(cacheKey, data, ttl);
        }
      }),
    );
  }
}
