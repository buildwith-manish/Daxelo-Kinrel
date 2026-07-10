// =============================================================================
// ML spec item #7 — User Engagement Profile Service
// =============================================================================
// Generalizes Track C's `reminderActionRate` concept out of aura-learning
// into a shared per-user engagement-time signal.
//
// Responsibilities:
//   1. recordEngagement(userId, when?) — called whenever a user opens/acts
//      on a notification. Increments the hour + weekday histograms.
//   2. getBestSendHour(userId, fallbackHour) — returns the hour-of-day
//      (0-23, in the user's local timezone) when this user is most likely
//      to engage with notifications. Falls back to `fallbackHour` if the
//      profile is missing, stale (no engagement in 30+ days), or has too
//      few samples (<10) to trust.
//
// The scheduler reads this to send non-Track-C reminders (e.g. birthdays)
// at the user's typical engagement hour instead of a fixed 8 AM IST for
// everyone. Two users with different patterns will receive the same
// birthday reminder at different times, each near their own engagement peak.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

// Minimum number of engagement samples before we trust the histogram to
// shift a user's send time. With <10 samples the "best hour" could just be
// noise. The user's pattern is also likely stable enough after 10 samples
// for the shift to be meaningful.
const MIN_SAMPLES_FOR_TRUST = 10;

// Profiles older than this are considered stale — the user's pattern may
// have changed (new job, baby, etc.) and we should fall back to the default
// send time rather than blindly trusting old data.
const STALE_AFTER_DAYS = 30;

// How many hours of "spread" we allow when picking the best send hour.
// If the user's engagement is concentrated in a single hour (e.g. 9 AM),
// we use that hour. If it's spread across multiple hours (e.g. equally
// active 8-10 AM), we pick the middle of the highest-density window.
const HOUR_WINDOW_FOR_BLENDING = 1;

@Injectable()
export class UserEngagementService {
  private readonly logger = new Logger(UserEngagementService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Record an engagement signal. Call this whenever a user opens OR acts on
   * a notification. The `when` parameter defaults to now and should be in
   * the user's local timezone (we record the hour-of-day as the user
   * experienced it, not UTC).
   *
   * Idempotent in the sense that calling it twice with the same timestamp
   * increments the histogram twice — but the scheduler only calls this when
   * a real engagement event happens, so duplicates are not a concern.
   */
  async recordEngagement(userId: string, when: Date = new Date()): Promise<void> {
    try {
      // We use the LOCAL hour-of-day and day-of-week. The `when` date should
      // already be in the user's TZ (callers should pass `new Date()` which
      // is server-local — if the server runs in UTC, the histogram is in UTC
      // and the scheduler must also send in UTC. That's a known limitation;
      // a future improvement would be to store the user's TZ and convert.)
      const hour = when.getHours(); // 0-23, local
      const weekday = when.getDay(); // 0=Sunday, 6=Saturday, local

      // Fetch existing profile (or initialize empty)
      const existing = await this.prisma.userEngagementProfile.findUnique({
        where: { userId },
      });

      let hours: number[];
      let weekdays: number[];
      let total: number;
      if (existing) {
        try {
          hours = JSON.parse(existing.hourHistogram);
          weekdays = JSON.parse(existing.weekdayHistogram);
          if (!Array.isArray(hours) || hours.length !== 24) hours = new Array(24).fill(0);
          if (!Array.isArray(weekdays) || weekdays.length !== 7) weekdays = new Array(7).fill(0);
          total = existing.totalSamples;
        } catch {
          hours = new Array(24).fill(0);
          weekdays = new Array(7).fill(0);
          total = 0;
        }
      } else {
        hours = new Array(24).fill(0);
        weekdays = new Array(7).fill(0);
        total = 0;
      }

      hours[hour] = (hours[hour] ?? 0) + 1;
      weekdays[weekday] = (weekdays[weekday] ?? 0) + 1;
      total++;

      await this.prisma.userEngagementProfile.upsert({
        where: { userId },
        create: {
          userId,
          hourHistogram: JSON.stringify(hours),
          weekdayHistogram: JSON.stringify(weekdays),
          totalSamples: total,
          lastEngagedAt: when,
        },
        update: {
          hourHistogram: JSON.stringify(hours),
          weekdayHistogram: JSON.stringify(weekdays),
          totalSamples: total,
          lastEngagedAt: when,
        },
      });
    } catch (err) {
      // Best-effort — don't let engagement-recording failures break the
      // notification flow.
      this.logger.debug?.(
        `Failed to record engagement for user ${userId}: ${(err as Error).message}`,
      );
    }
  }

  /**
   * Get the best hour-of-day (0-23, local) to send a notification to this
   * user. Returns `fallbackHour` if:
   *   - the profile doesn't exist (new user)
   *   - total samples < MIN_SAMPLES_FOR_TRUST (not enough data yet)
   *   - lastEngagedAt is more than STALE_AFTER_DAYS ago (pattern may have changed)
   *
   * Otherwise returns the hour with the highest engagement count, blended
   * with its immediate neighbors to smooth out single-hour spikes.
   */
  async getBestSendHour(userId: string, fallbackHour: number = 8): Promise<{
    hour: number;
    confidence: number; // 0..1 — how much we trust this hour
    source: 'profile' | 'fallback_insufficient_samples' | 'fallback_stale' | 'fallback_no_profile';
    samples: number;
  }> {
    const existing = await this.prisma.userEngagementProfile.findUnique({
      where: { userId },
    });

    if (!existing) {
      return { hour: fallbackHour, confidence: 0, source: 'fallback_no_profile', samples: 0 };
    }

    if (existing.totalSamples < MIN_SAMPLES_FOR_TRUST) {
      return {
        hour: fallbackHour,
        confidence: existing.totalSamples / MIN_SAMPLES_FOR_TRUST,
        source: 'fallback_insufficient_samples',
        samples: existing.totalSamples,
      };
    }

    // Staleness check
    if (existing.lastEngagedAt) {
      const ageDays = (Date.now() - existing.lastEngagedAt.getTime()) / (1000 * 60 * 60 * 24);
      if (ageDays > STALE_AFTER_DAYS) {
        return {
          hour: fallbackHour,
          confidence: 0,
          source: 'fallback_stale',
          samples: existing.totalSamples,
        };
      }
    }

    // Parse the hour histogram and find the best hour (with neighbor blending)
    let hours: number[];
    try {
      hours = JSON.parse(existing.hourHistogram);
      if (!Array.isArray(hours) || hours.length !== 24) {
        return { hour: fallbackHour, confidence: 0, source: 'fallback_no_profile', samples: 0 };
      }
    } catch {
      return { hour: fallbackHour, confidence: 0, source: 'fallback_no_profile', samples: 0 };
    }

    // Blended score: for each hour, sum its own count + neighbors within
    // HOUR_WINDOW_FOR_BLENDING. This picks the center of the highest-density
    // window rather than a single noisy spike.
    const blended: number[] = new Array(24).fill(0);
    for (let h = 0; h < 24; h++) {
      let sum = 0;
      for (let d = -HOUR_WINDOW_FOR_BLENDING; d <= HOUR_WINDOW_FOR_BLENDING; d++) {
        const idx = (h + d + 24) % 24; // wrap around midnight
        sum += hours[idx] ?? 0;
      }
      blended[h] = sum;
    }

    let bestHour = 0;
    let bestScore = -1;
    for (let h = 0; h < 24; h++) {
      if (blended[h] > bestScore) {
        bestScore = blended[h];
        bestHour = h;
      }
    }

    // Confidence: how concentrated is the user's engagement on this hour?
    // Computed as best_hour_count / total. A user who engages 100% at 9 AM
    // → confidence 1.0. A user with uniform engagement → confidence ~0.04.
    const total = hours.reduce((a, b) => a + b, 0);
    const hourShare = total > 0 ? (hours[bestHour] ?? 0) / total : 0;
    // Boost confidence a bit so even moderate concentration (20% on one hour)
    // counts as "trustworthy" — we're only shifting the send time, not
    // making an irreversible decision.
    const confidence = Math.min(1, hourShare * 3);

    return {
      hour: bestHour,
      confidence,
      source: 'profile',
      samples: existing.totalSamples,
    };
  }
}
