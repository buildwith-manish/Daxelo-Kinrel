import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * ChatThrottlerService — per-user, per-chat rate limiting for chat actions.
 *
 * Uses in-memory sliding-window counters (Map of Maps). Not Redis-backed
 * (single-instance is fine for the current deployment; a future multi-
 * instance deployment would move this to Redis).
 *
 * Limits (per user, per family chat):
 *   • message_send:   30 per minute  (max 30/min)
 *   • typing:          1 per 2 seconds (max 1/2s)
 *   • reaction:       20 per minute  (max 20/min)
 *
 * When a limit is hit, the gateway emits a 'chat:rateLimitExceeded'
 * event to the client with the action type + retryAfterMs so the Flutter
 * client can show appropriate feedback (not just silently drop messages).
 *
 * The existing global @nestjs/throttler tiers (short: 20/s, long: 200/min,
 * auth: 5/min) apply to ALL HTTP routes. This service is SEPARATE — it
 * applies only to chat Socket.IO events + is per-chat, not per-IP.
 *
 * ── Tier 2 Feature 2.6: Slow Mode ──────────────────────────────────
 * Each Family row carries a slowModeSeconds column. When > 0, NON-ADMIN
 * members can send at most 1 message every slowModeSeconds. Admins/
 * creators bypass slow mode. The throttler loads the family's
 * slowModeSeconds via Prisma + caches it for 60s (TTL). The check is
 * additive to the existing 30/min limit — both must pass.
 */

interface RateLimitBucket {
  timestamps: number[]; // epoch ms of each request in the window
}

interface SlowModeCacheEntry {
  slowModeSeconds: number;
  loadedAt: number; // epoch ms
}

@Injectable()
export class ChatThrottlerService {
  private readonly logger = new Logger(ChatThrottlerService.name);

  /// Limits per action type. [windowMs] is the sliding window size;
  /// [maxRequests] is the max allowed in that window.
  private readonly limits: Record<string, { windowMs: number; maxRequests: number }> = {
    message_send: { windowMs: 60_000, maxRequests: 30 }, // 30/min
    typing: { windowMs: 2_000, maxRequests: 1 }, // 1 per 2s
    reaction: { windowMs: 60_000, maxRequests: 20 }, // 20/min
    /// Tier 2 Feature 2.6: slow-mode key is dynamic per-family — we don't
    /// use this entry directly, but having it here lets the cleanup pass
    /// + the getCount debug method treat slow-mode buckets uniformly.
    slow_mode: { windowMs: 60_000, maxRequests: 1 }, // overridden per-family
  };

  /// Map<actionType, Map<key, RateLimitBucket>> where key = `${userId}:${familyId}`.
  /// For typing, the key is just userId (typing is per-user, not per-chat —
  /// a user typing in 5 chats simultaneously should still be throttled).
  private readonly buckets = new Map<string, Map<string, RateLimitBucket>>();

  /// Tier 2 Feature 2.6: cache of (familyId → slowModeSeconds) loaded from
  /// the Family table. TTL = 60s. The cache is per-process; a multi-instance
  /// deployment would move this to Redis (same as the main buckets).
  private readonly slowModeCache = new Map<string, SlowModeCacheEntry>();
  private readonly slowModeCacheTtlMs = 60_000; // 60s

  constructor(private readonly prisma: PrismaService) {
    // Periodic cleanup of stale buckets every 5 minutes to prevent memory
    // growth from abandoned user sessions.
    setInterval(() => this._cleanupStaleBuckets(), 5 * 60 * 1000);
    // Also cleanup stale slow-mode cache entries every 5 min.
    setInterval(() => this._cleanupSlowModeCache(), 5 * 60 * 1000);
  }

  /**
   * Check if an action is allowed under the rate limit. Returns:
   *   { allowed: true } if the action is permitted
   *   { allowed: false, retryAfterMs } if the action is rate-limited
   *
   * Side effect: if allowed, records the timestamp in the bucket.
   *
   * ── Tier 2 Feature 2.6: Slow Mode ──────────────────────────────────
   * For action='message_send', the throttler ALSO checks the family's
   * slowModeSeconds. If > 0 AND the caller is NOT an admin/creator, the
   * throttler enforces "1 message per slowModeSeconds" additively. The
   * admin role is passed via the isAdmin flag (resolved by the caller —
   * the ChatGateway looks up the FamilyMember role once per session).
   */
  async check(
    action: string,
    userId: string,
    familyId: string,
    isAdmin: boolean = false,
  ): Promise<{ allowed: true } | { allowed: false; retryAfterMs: number }> {
    const limit = this.limits[action];
    if (!limit) {
      // Unknown action type — allow (no limit configured).
      return { allowed: true };
    }

    // ── Tier 2 Feature 2.6: Slow Mode ────────────────────────────────
    // For message_send, check the family's slow-mode window FIRST (only
    // applies to non-admins). If slow-mode throttles, return immediately
    // — the user can't send regardless of the per-minute bucket state.
    if (action === 'message_send' && !isAdmin) {
      const slowModeSeconds = await this._getSlowModeSeconds(familyId);
      if (slowModeSeconds > 0) {
        const slowResult = this._checkSlowMode(userId, familyId, slowModeSeconds);
        if (!slowResult.allowed) {
          this.logger.debug(
            `Slow mode hit: ${userId} in ${familyId} (retry in ${slowResult.retryAfterMs}ms)`,
          );
          return { allowed: false, retryAfterMs: slowResult.retryAfterMs };
        }
        // Slow-mode passed — record the timestamp.
        this._recordSlowModeTimestamp(userId, familyId);
      }
    }

    // For typing, the key is just userId (per-user global, not per-chat).
    // For message_send + reaction, the key is userId:familyId (per-chat).
    const key = action === 'typing' ? userId : `${userId}:${familyId}`;

    const actionBuckets = this.buckets.get(action) ?? new Map<string, RateLimitBucket>();
    const bucket = actionBuckets.get(key) ?? { timestamps: [] };

    const now = Date.now();
    const windowStart = now - limit.windowMs;

    // Remove timestamps outside the sliding window.
    bucket.timestamps = bucket.timestamps.filter((t) => t > windowStart);

    if (bucket.timestamps.length >= limit.maxRequests) {
      // Rate limited — compute how long until the oldest timestamp exits
      // the window (that's when the user can retry).
      const oldest = bucket.timestamps[0];
      const retryAfterMs = oldest + limit.windowMs - now;
      this.logger.debug(
        `Rate limit hit: ${action} by ${userId} in ${familyId} (retry in ${retryAfterMs}ms)`,
      );
      return { allowed: false, retryAfterMs: Math.max(retryAfterMs, 100) };
    }

    // Allowed — record the timestamp.
    bucket.timestamps.push(now);
    actionBuckets.set(key, bucket);
    this.buckets.set(action, actionBuckets);

    return { allowed: true };
  }

  /// Synchronous check for callers that haven't been migrated to async.
  /// Prefer check() above — this version skips the slow-mode check.
  checkSync(
    action: string,
    userId: string,
    familyId: string,
  ): { allowed: true } | { allowed: false; retryAfterMs: number } {
    const limit = this.limits[action];
    if (!limit) return { allowed: true };

    const key = action === 'typing' ? userId : `${userId}:${familyId}`;
    const actionBuckets = this.buckets.get(action) ?? new Map<string, RateLimitBucket>();
    const bucket = actionBuckets.get(key) ?? { timestamps: [] };

    const now = Date.now();
    const windowStart = now - limit.windowMs;
    bucket.timestamps = bucket.timestamps.filter((t) => t > windowStart);

    if (bucket.timestamps.length >= limit.maxRequests) {
      const oldest = bucket.timestamps[0];
      return { allowed: false, retryAfterMs: Math.max(oldest + limit.windowMs - now, 100) };
    }

    bucket.timestamps.push(now);
    actionBuckets.set(key, bucket);
    this.buckets.set(action, actionBuckets);
    return { allowed: true };
  }

  // ── Tier 2 Feature 2.6: Slow Mode helpers ──────────────────────────

  /// Load the family's slowModeSeconds from the cache, or fetch from
  /// the DB on a cache miss. The cache TTL is 60s — slow-mode changes
  /// propagate within a minute without invalidating the whole cache.
  private async _getSlowModeSeconds(familyId: string): Promise<number> {
    const cached = this.slowModeCache.get(familyId);
    if (cached && Date.now() - cached.loadedAt < this.slowModeCacheTtlMs) {
      return cached.slowModeSeconds;
    }
    try {
      const family = await this.prisma.family.findUnique({
        where: { id: familyId },
        select: { slowModeSeconds: true },
      });
      const seconds = family?.slowModeSeconds ?? 0;
      this.slowModeCache.set(familyId, {
        slowModeSeconds: seconds,
        loadedAt: Date.now(),
      });
      return seconds;
    } catch (err: any) {
      // DB error — fail OPEN (allow the message). Don't block a user
      // from sending because of a transient DB issue.
      this.logger.warn(`Slow-mode load failed for ${familyId}: ${err?.message}`);
      return 0;
    }
  }

  /// Check the slow-mode bucket (1 message per slowModeSeconds).
  private _checkSlowMode(
    userId: string,
    familyId: string,
    slowModeSeconds: number,
  ): { allowed: true } | { allowed: false; retryAfterMs: number } {
    const key = `${userId}:${familyId}`;
    const actionBuckets = this.buckets.get('slow_mode') ?? new Map<string, RateLimitBucket>();
    const bucket = actionBuckets.get(key) ?? { timestamps: [] };

    const now = Date.now();
    const windowMs = slowModeSeconds * 1000;
    const windowStart = now - windowMs;
    bucket.timestamps = bucket.timestamps.filter((t) => t > windowStart);

    // Slow-mode allows exactly 1 message per window.
    if (bucket.timestamps.length >= 1) {
      const oldest = bucket.timestamps[0];
      const retryAfterMs = oldest + windowMs - now;
      return { allowed: false, retryAfterMs: Math.max(retryAfterMs, 100) };
    }
    return { allowed: true };
  }

  /// Record a slow-mode timestamp (called AFTER a slow-mode check passes).
  private _recordSlowModeTimestamp(userId: string, familyId: string) {
    const key = `${userId}:${familyId}`;
    const actionBuckets = this.buckets.get('slow_mode') ?? new Map<string, RateLimitBucket>();
    const bucket = actionBuckets.get(key) ?? { timestamps: [] };
    bucket.timestamps.push(Date.now());
    actionBuckets.set(key, bucket);
    this.buckets.set('slow_mode', actionBuckets);
  }

  /// Invalidate the slow-mode cache for a family. Called by the admin
  /// "set slow mode" endpoint so the new value applies immediately
  /// (instead of waiting up to 60s for the TTL to expire).
  invalidateSlowModeCache(familyId: string) {
    this.slowModeCache.delete(familyId);
  }

  /// Remove buckets that haven't been touched in the last 5 minutes.
  /// Prevents memory growth from abandoned user sessions.
  private _cleanupStaleBuckets() {
    const fiveMinAgo = Date.now() - 5 * 60 * 1000;
    for (const [action, actionBuckets] of this.buckets.entries()) {
      const limit = this.limits[action];
      if (!limit) continue;
      const windowMs = limit.windowMs;
      for (const [key, bucket] of actionBuckets.entries()) {
        // Remove timestamps outside the window.
        bucket.timestamps = bucket.timestamps.filter((t) => t > Date.now() - windowMs);
        // If the bucket is empty AND the last access was > 5 min ago,
        // delete it. We approximate "last access" as the newest timestamp
        // (or fiveMinAgo if empty).
        const lastAccess = bucket.timestamps.length > 0
          ? Math.max(...bucket.timestamps)
          : 0;
        if (bucket.timestamps.length === 0 && lastAccess < fiveMinAgo) {
          actionBuckets.delete(key);
        }
      }
      if (actionBuckets.size === 0) {
        this.buckets.delete(action);
      }
    }
  }

  /// Cleanup stale slow-mode cache entries (older than 5 min unused).
  private _cleanupSlowModeCache() {
    const fiveMinAgo = Date.now() - 5 * 60 * 1000;
    for (const [familyId, entry] of this.slowModeCache.entries()) {
      if (entry.loadedAt < fiveMinAgo) {
        this.slowModeCache.delete(familyId);
      }
    }
  }

  /// Get the current count for an action (for debugging / admin dashboards).
  getCount(action: string, userId: string, familyId: string): number {
    const limit = this.limits[action];
    if (!limit) return 0;
    const key = action === 'typing' ? userId : `${userId}:${familyId}`;
    const actionBuckets = this.buckets.get(action);
    if (!actionBuckets) return 0;
    const bucket = actionBuckets.get(key);
    if (!bucket) return 0;
    const windowStart = Date.now() - limit.windowMs;
    return bucket.timestamps.filter((t) => t > windowStart).length;
  }
}
