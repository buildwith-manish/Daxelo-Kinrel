import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

/**
 * TwoFactorVerificationService — Redis-backed tracking of 2FA verification status.
 *
 * When a user successfully verifies their TOTP code during the login
 * flow, this service records that fact in Redis with a TTL. Subsequent
 * requests are then allowed through the TwoFactorGuard without
 * requiring re-verification for the TTL window (default 15 minutes).
 *
 * Replaces the previous in-memory Map implementation to ensure:
 * - State survives server restarts (if Redis persists)
 * - Consistent state across multiple server instances
 * - No memory leak from unbounded Map growth
 *
 * Falls back to in-memory Map if Redis is unavailable, ensuring the
 * app can start even without a Redis instance configured.
 */
@Injectable()
export class TwoFactorVerificationService {
  private redis: Redis | null = null;
  private readonly memoryStore = new Map<string, { value: string; expiresAt: number }>();
  private readonly logger = new Logger(TwoFactorVerificationService.name);
  private readonly TTL = 900; // 15 minutes in seconds

  constructor(private readonly config: ConfigService) {
    const redisUrl = this.config.get<string>('REDIS_URL', '');

    if (redisUrl && redisUrl !== 'redis://localhost:6379') {
      this.redis = new Redis(redisUrl, {
        lazyConnect: true,
        maxRetriesPerRequest: 1,
        connectTimeout: 5000,
      });

      this.redis.on('connect', () => {
        this.logger.log('Connected to Redis for 2FA verification tracking');
      });

      this.redis.on('error', (err) => {
        this.logger.warn(`Redis connection error: ${err.message}. Falling back to in-memory store.`);
        this.redis = null;
      });

      // Attempt connection lazily
      this.redis.connect().catch(() => {
        this.logger.warn('Redis connection failed — using in-memory 2FA store (not production-safe)');
        this.redis = null;
      });
    } else {
      this.logger.warn('REDIS_URL not configured — using in-memory 2FA store (not production-safe)');
    }
  }

  /**
   * Mark a user as having recently completed 2FA verification.
   */
  async markVerified(userId: string): Promise<void> {
    if (this.redis) {
      await this.redis.setex(`2fa:verified:${userId}`, this.TTL, '1');
    } else {
      this.memoryStore.set(`2fa:verified:${userId}`, {
        value: '1',
        expiresAt: Date.now() + this.TTL * 1000,
      });
    }
  }

  /**
   * Check whether a user has verified 2FA within the recent window.
   */
  async isVerified(userId: string): Promise<boolean> {
    if (this.redis) {
      const val = await this.redis.get(`2fa:verified:${userId}`);
      return val === '1';
    } else {
      const entry = this.memoryStore.get(`2fa:verified:${userId}`);
      if (!entry) return false;
      if (Date.now() > entry.expiresAt) {
        this.memoryStore.delete(`2fa:verified:${userId}`);
        return false;
      }
      return entry.value === '1';
    }
  }

  /**
   * Remove a user's 2FA verification record.
   */
  async clearVerification(userId: string): Promise<void> {
    if (this.redis) {
      await this.redis.del(`2fa:verified:${userId}`);
    } else {
      this.memoryStore.delete(`2fa:verified:${userId}`);
    }
  }
}
