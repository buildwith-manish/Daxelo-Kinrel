// =============================================================================
// Track C v2.0 — AURA Learning Engine
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
    private readonly signalIngestor: SignalIngestor,
    private readonly profileBuilder: ProfileBuilder,
    private readonly inference: LearningInference,
  ) {}

  async getProfile(familyId: string, userId: string) {
    await this.membership.requireMember(userId, familyId);
    return this.inference.getProfile(familyId);
  }

  async ingestSignal(familyId: string, userId: string, signal: Omit<SignalInput, 'familyId'>) {
    await this.membership.requireMember(userId, familyId);
    return this.signalIngestor.ingest({ ...signal, familyId });
  }

  /**
   * Reset the family's behavior profile. Admin-only.
   * Section 9.5: Reset logs a learning_profile_reset event to the AURA Timeline.
   * Previous profile version is retained server-side for 90 days.
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
        title: 'AURA Learning profile reset',
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
