// =============================================================================
// Track C v2.0 — Kinrel Learning Engine
// learning.service.ts
// =============================================================================

import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TimelineEmitter } from '../governance-timeline/timeline.emitter';
import { FamilyMembershipService } from '../common/family-membership.service';
import { VisibilityService } from '../common/visibility.service';
import { SignalIngestor, SignalInput } from './learning.signal-ingestor';
import { ProfileBuilder } from './learning.profile-builder';
import { LearningInference } from './learning.inference';

@Injectable()
export class LearningService {
  private readonly logger = new Logger(LearningService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly emitter: TimelineEmitter,
    private readonly membership: FamilyMembershipService,
    private readonly visibility: VisibilityService,
    private readonly signalIngestor: SignalIngestor,
    private readonly profileBuilder: ProfileBuilder,
    private readonly inference: LearningInference,
  ) {}

  /**
   * Get the raw family behavior profile.
   *
   * VISIBILITY MATRIX: admin-only (owner | admin). The raw profile contains
   * aggregate behavioral signals (reminder action rates, weekday
   * distribution, elder auto-include threshold, insight accept rates by
   * kind) that could be used to infer individual member behavior patterns.
   * Non-admin members and minors should use getProfileSummary() instead,
   * which returns a plain-language sentence.
   */
  async getProfile(familyId: string, userId: string) {
    await this.visibility.requireAdminDataAccess(userId, familyId);
    return this.inference.getProfile(familyId);
  }

  /**
   * Get a plain-language summary of the family's learned behavior.
   *
   * VISIBILITY MATRIX: available to ALL members (including minors). Returns
   * ONLY a pre-templated sentence generated from the profile — never raw
   * signal fields, never per-person data.
   *
   * The summary is generated from the same FamilyBehaviorProfile that
   * getProfile() reads, but all numeric fields are converted to natural
   * language descriptions (e.g. "weekends" instead of
   * `{ sat: 0.25, sun: 0.30 }`).
   */
  async getProfileSummary(familyId: string, userId: string): Promise<{
    familyId: string;
    summary: string;
    confidenceScore: number;
    sampleSize: number;
    usingDefaults: boolean;
    computedAt: string | null;
  }> {
    await this.membership.requireMember(userId, familyId);

    const profile = await this.inference.getProfile(familyId);
    const summary = this.generatePlainLanguageSummary(profile);

    return {
      familyId,
      summary,
      confidenceScore: profile.confidenceScore,
      sampleSize: profile.sampleSize,
      usingDefaults: profile.usingDefaults,
      computedAt: profile.computedAt ? profile.computedAt.toISOString() : null,
    };
  }

  /**
   * Generate a plain-language, pre-templated sentence from the behavior
   * profile. This is the ONLY transformation of raw profile data that is
   * exposed to non-admin members.
   *
   * The sentence is assembled from fixed templates with no per-person
   * data — just family-level aggregate descriptions like "your family
   * checks in most on weekends" or "your family tends to act on
   * reminders within 12 hours".
   */
  private generatePlainLanguageSummary(profile: any): string {
    const parts: string[] = [];

    // 1. Weekday distribution → "most active on weekends/weekdays"
    const dist = profile.preferredWeekdayDistribution;
    if (dist && typeof dist === 'object') {
      const weekend = (dist.sat ?? 0) + (dist.sun ?? 0);
      const weekday = (dist.mon ?? 0) + (dist.tue ?? 0) + (dist.wed ?? 0) +
                      (dist.thu ?? 0) + (dist.fri ?? 0);
      if (weekend > weekday) {
        parts.push('Kinrel has learned your family is most active on weekends');
      } else {
        parts.push('Kinrel has learned your family is most active on weekdays');
      }
    }

    // 2. Time of day → "in the evening/morning/afternoon"
    const buckets = profile.preferredTimeOfDayBuckets;
    if (buckets && typeof buckets === 'object') {
      let maxBucket = 'evening';
      let maxValue = -1;
      for (const [bucket, value] of Object.entries(buckets)) {
        if (typeof value === 'number' && value > maxValue) {
          maxValue = value;
          maxBucket = bucket;
        }
      }
      const timeLabel = maxBucket === 'morning' ? 'mornings'
        : maxBucket === 'afternoon' ? 'afternoons'
        : maxBucket === 'evening' ? 'evenings'
        : 'late nights';
      parts.push(`typically in ${timeLabel}`);
    }

    // 3. Reminder action rate → "acts on reminders within X hours"
    const rates = profile.reminderActionRate;
    if (rates && typeof rates === 'object') {
      const rate24h = rates['24h'] ?? 0;
      if (rate24h > 0.6) {
        parts.push('and tends to act on reminders within 24 hours');
      } else if (rate24h > 0.3) {
        parts.push('and sometimes needs a nudge to act on reminders');
      } else {
        parts.push('and prefers to take their time with reminders');
      }
    }

    // 4. Decision duration → "decisions usually take X days"
    if (profile.averageDecisionDurationHours != null) {
      const days = Math.round(profile.averageDecisionDurationHours / 24);
      if (days > 0) {
        parts.push(`decisions usually take about ${days} day${days === 1 ? '' : 's'}`);
      }
    }

    // 5. Confidence / sample size note
    if (profile.usingDefaults || profile.confidenceScore < 0.4) {
      parts.unshift('Kinrel is still learning your family\'s rhythms.');
    }

    if (parts.length === 0) {
      return 'Kinrel is still gathering data about your family\'s governance patterns.';
    }

    // Join the parts into a flowing sentence
    return parts.join(', ') + '.';
  }

  async ingestSignal(familyId: string, userId: string, signal: Omit<SignalInput, 'familyId'>) {
    await this.membership.requireMember(userId, familyId);
    return this.signalIngestor.ingest({ ...signal, familyId });
  }

  /**
   * Reset the family's behavior profile. Admin-only.
   * Section 9.5: Reset logs a learning_profile_reset event to the Kinrel Timeline.
   * Previous profile version is retained server-side for 90 days.
   *
   * The learning_profile_reset event IS in the TIMELINE_SUMMARY_EVENT_TYPES
   * whitelist? No — it's NOT in the summary whitelist by design (it's a
   * system maintenance event, not a governance headline). It IS visible
   * in the raw admin log (?raw=true).
   */
  async resetProfile(familyId: string, actorId: string, reason: string = 'user_request') {
    await this.membership.requireAdmin(actorId, familyId);

    const previous = await this.prisma.familyBehaviorProfile.findUnique({
      where: { familyId },
    });

    return this.prisma.$transaction(async (tx) => {
      // Snapshot the previous profile to history (retained 90 days)
      if (previous) {
        await tx.familyBehaviorProfileHistory.create({
          data: {
            familyId,
            version: previous.version,
            snapshot: previous as any,
            computedAt: previous.computedAt,
          },
        });
      }

      // Reset to defaults (version continues incrementing; sampleSize=0; confidence=0)
      const newVersion = (previous?.version ?? 0) + 1;
      const defaults = await tx.globalLearningDefaults.findUnique({ where: { id: 'global' } });

      const reset = await tx.familyBehaviorProfile.upsert({
        where: { familyId },
        create: {
          familyId,
          version: newVersion,
          computedAt: new Date(),
          preferredReminderLeadHours: defaults?.preferredReminderLeadHours ?? { decision: 24, meeting: 48, event: 72 },
          reminderActionRate: defaults?.reminderActionRate ?? { '6h': 0.42, '12h': 0.55, '24h': 0.71 },
          preferredWeekdayDistribution: (defaults?.preferredWeekdayDistribution as any) ?? { mon: 0.14, tue: 0.14, wed: 0.14, thu: 0.14, fri: 0.14, sat: 0.15, sun: 0.15 },
          preferredTimeOfDayBuckets: (defaults?.preferredTimeOfDayBuckets as any) ?? { morning: 0.25, afternoon: 0.25, evening: 0.25, night: 0.25 },
          elderAutoIncludeThreshold: defaults?.elderAutoIncludeThreshold ?? 0.6,
          insightAcceptRateByKind: (defaults?.insightAcceptRateByKind as any) ?? {},
          averageDecisionDurationHours: defaults?.averageDecisionDurationHours ?? 72,
          typicalQuorumMet: null,
          sampleSize: 0,
          confidenceScore: 0,
        },
        update: {
          version: newVersion,
          computedAt: new Date(),
          preferredReminderLeadHours: defaults?.preferredReminderLeadHours ?? { decision: 24, meeting: 48, event: 72 },
          reminderActionRate: defaults?.reminderActionRate ?? { '6h': 0.42, '12h': 0.55, '24h': 0.71 },
          preferredWeekdayDistribution: (defaults?.preferredWeekdayDistribution as any) ?? { mon: 0.14, tue: 0.14, wed: 0.14, thu: 0.14, fri: 0.14, sat: 0.15, sun: 0.15 },
          preferredTimeOfDayBuckets: (defaults?.preferredTimeOfDayBuckets as any) ?? { morning: 0.25, afternoon: 0.25, evening: 0.25, night: 0.25 },
          elderAutoIncludeThreshold: defaults?.elderAutoIncludeThreshold ?? 0.6,
          insightAcceptRateByKind: (defaults?.insightAcceptRateByKind as any) ?? {},
          averageDecisionDurationHours: defaults?.averageDecisionDurationHours ?? 72,
          typicalQuorumMet: null,
          sampleSize: 0,
          confidenceScore: 0,
        },
      });

      return reset;
    }).then(async (result) => {
      // Emit timeline event (best-effort, after the transaction commits)
      await this.emitter.append({
        familyId,
        kind: 'learning_profile_reset',
        actorId,
        title: 'Kinrel Learning profile reset',
        description: `Reason: ${reason}`,
        payload: { actorId, reason, previousVersion: previous?.version ?? 0, newVersion: result.version },
      });
      return result;
    });
  }

  /**
   * Trigger an immediate profile recompute (normally done by the nightly worker).
   * Admin-only.
   */
  async triggerRecompute(familyId: string, actorId: string) {
    await this.membership.requireAdmin(actorId, familyId);
    return this.profileBuilder.recompute(familyId);
  }
}
