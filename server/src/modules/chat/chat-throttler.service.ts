import { Injectable, Logger } from '@nestjs/common';

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
 */

interface RateLimitBucket {
  timestamps: number[]; // epoch ms of each request in the window
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
  };

  /// Map<actionType, Map<key, RateLimitBucket>> where key = `${userId}:${familyId}`.
  /// For typing, the key is just userId (typing is per-user, not per-chat —
  /// a user typing in 5 chats simultaneously should still be throttled).
  private readonly buckets = new Map<string, Map<string, RateLimitBucket>>();

  constructor() {
    // Periodic cleanup of stale buckets every 5 minutes to prevent memory
    // growth from abandoned user sessions.
    setInterval(() => this._cleanupStaleBuckets(), 5 * 60 * 1000);
  }

  /**
   * Check if an action is allowed under the rate limit. Returns:
   *   { allowed: true } if the action is permitted
   *   { allowed: false, retryAfterMs } if the action is rate-limited
   *
   * Side effect: if allowed, records the timestamp in the bucket.
   */
  check(
    action: string,
    userId: string,
    familyId: string,
  ): { allowed: true } | { allowed: false; retryAfterMs: number } {
    const limit = this.limits[action];
    if (!limit) {
      // Unknown action type — allow (no limit configured).
      return { allowed: true };
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
