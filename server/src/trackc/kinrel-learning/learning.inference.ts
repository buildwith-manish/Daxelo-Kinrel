// =============================================================================
// Track C v2.0 — Kinrel Learning Engine
// learning.inference.ts
// =============================================================================
// Sub-50ms inference reads. Section 9.3.
//
// Reads the FamilyBehaviorProfile for a family in a single-row query and
// returns the learned values. If the family has no profile yet (or
// confidenceScore < lowThreshold), returns the global defaults.
// =============================================================================

import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class LearningInference {
  constructor(private readonly prisma: PrismaService) {}

  async getProfile(familyId: string) {
    const [profile, defaults] = await Promise.all([
      this.prisma.familyBehaviorProfile.findUnique({ where: { familyId } }),
      this.prisma.globalLearningDefaults.findUnique({ where: { id: 'global' } }),
    ]);

    if (!profile || profile.confidenceScore < (defaults?.lowConfidenceThreshold ?? 0.4)) {
      // Use defaults
      return {
        familyId,
        confidenceScore: profile?.confidenceScore ?? 0,
        sampleSize: profile?.sampleSize ?? 0,
        version: profile?.version ?? 0,
        usingDefaults: true,
        preferredReminderLeadHours: defaults?.preferredReminderLeadHours ?? { decision: 24, meeting: 48, event: 72 },
        reminderActionRate: defaults?.reminderActionRate ?? { '6h': 0.42, '12h': 0.55, '24h': 0.71 },
        preferredWeekdayDistribution: defaults?.preferredWeekdayDistribution ?? { mon: 0.14, tue: 0.14, wed: 0.14, thu: 0.14, fri: 0.14, sat: 0.15, sun: 0.15 },
        preferredTimeOfDayBuckets: defaults?.preferredTimeOfDayBuckets ?? { morning: 0.25, afternoon: 0.25, evening: 0.25, night: 0.25 },
        elderAutoIncludeThreshold: defaults?.elderAutoIncludeThreshold ?? 0.6,
        insightAcceptRateByKind: defaults?.insightAcceptRateByKind ?? {},
        averageDecisionDurationHours: defaults?.averageDecisionDurationHours ?? 72,
        typicalQuorumMet: null,
        computedAt: profile?.computedAt ?? null,
      };
    }

    return {
      familyId,
      confidenceScore: profile.confidenceScore,
      sampleSize: profile.sampleSize,
      version: profile.version,
      usingDefaults: false,
      preferredReminderLeadHours: profile.preferredReminderLeadHours as Record<string, number>,
      reminderActionRate: profile.reminderActionRate as Record<string, number>,
      preferredWeekdayDistribution: profile.preferredWeekdayDistribution as Record<string, number>,
      preferredTimeOfDayBuckets: profile.preferredTimeOfDayBuckets as Record<string, number>,
      elderAutoIncludeThreshold: profile.elderAutoIncludeThreshold,
      insightAcceptRateByKind: profile.insightAcceptRateByKind as Record<string, number>,
      averageDecisionDurationHours: profile.averageDecisionDurationHours
        ? Number(profile.averageDecisionDurationHours)
        : null,
      typicalQuorumMet: profile.typicalQuorumMet,
      computedAt: profile.computedAt,
    };
  }
}
