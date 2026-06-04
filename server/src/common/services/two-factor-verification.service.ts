import { Injectable, OnModuleDestroy } from '@nestjs/common';

/**
 * TwoFactorVerificationService — In-memory tracking of 2FA verification status.
 *
 * When a user successfully verifies their TOTP code during the login
 * flow, this service records that fact with a timestamp. Subsequent
 * requests are then allowed through the TwoFactorGuard without
 * requiring re-verification for a configurable window (default 30 min).
 *
 * A periodic cleanup runs every 30 minutes to evict expired entries
 * so the Map doesn't grow unbounded.
 */
@Injectable()
export class TwoFactorVerificationService implements OnModuleDestroy {
  /** userId → timestamp of last successful 2FA verification */
  private readonly verifiedUsers = new Map<string, Date>();

  /** Verification window in milliseconds (default: 30 minutes) */
  private readonly verificationWindowMs = 30 * 60 * 1000;

  /** Handle for the periodic cleanup interval */
  private cleanupInterval: ReturnType<typeof setInterval> | null = null;

  constructor() {
    // Run cleanup every 30 minutes
    this.cleanupInterval = setInterval(
      () => this.cleanup(),
      30 * 60 * 1000,
    );
  }

  onModuleDestroy() {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }
  }

  /**
   * Mark a user as having recently completed 2FA verification.
   */
  markVerified(userId: string): void {
    this.verifiedUsers.set(userId, new Date());
  }

  /**
   * Check whether a user has verified 2FA within the recent window.
   * Returns `true` if the user was verified and the verification
   * has not yet expired (within last 30 minutes).
   */
  isVerified(userId: string): boolean {
    const verifiedAt = this.verifiedUsers.get(userId);
    if (!verifiedAt) {
      return false;
    }

    const now = Date.now();
    const elapsed = now - verifiedAt.getTime();

    if (elapsed > this.verificationWindowMs) {
      // Expired — remove and report as not verified
      this.verifiedUsers.delete(userId);
      return false;
    }

    return true;
  }

  /**
   * Remove a user's 2FA verification record.
   * Called on logout so that a fresh verification is required on next login.
   */
  clearVerification(userId: string): void {
    this.verifiedUsers.delete(userId);
  }

  /**
   * Remove all expired entries from the map.
   */
  private cleanup(): void {
    const now = Date.now();
    for (const [userId, verifiedAt] of this.verifiedUsers) {
      if (now - verifiedAt.getTime() > this.verificationWindowMs) {
        this.verifiedUsers.delete(userId);
      }
    }
  }
}
