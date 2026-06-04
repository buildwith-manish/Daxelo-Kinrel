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
 */
@Injectable()
export class TwoFactorVerificationService {
  private readonly redis: Redis;
  private readonly logger = new Logger(TwoFactorVerificationService.name);
  private readonly TTL = 900; // 15 minutes in seconds

  constructor(private readonly config: ConfigService) {
    this.redis = new Redis(this.config.get<string>('REDIS_URL', 'redis://localhost:6379'));

    this.redis.on('connect', () => {
      this.logger.log('Connected to Redis for 2FA verification tracking');
    });

    this.redis.on('error', (err) => {
      this.logger.error('Redis connection error', err);
    });
  }

  /**
   * Mark a user as having recently completed 2FA verification.
   * Sets a Redis key with a 15-minute TTL.
   */
  async markVerified(userId: string): Promise<void> {
    await this.redis.setex(`2fa:verified:${userId}`, this.TTL, '1');
  }

  /**
   * Check whether a user has verified 2FA within the recent window.
   * Returns `true` if the user was verified and the verification
   * has not yet expired (within last 15 minutes).
   */
  async isVerified(userId: string): Promise<boolean> {
    const val = await this.redis.get(`2fa:verified:${userId}`);
    return val === '1';
  }

  /**
   * Remove a user's 2FA verification record.
   * Called on logout so that a fresh verification is required on next login.
   */
  async clearVerification(userId: string): Promise<void> {
    await this.redis.del(`2fa:verified:${userId}`);
  }
}
