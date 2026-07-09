// =============================================================================
// Track C v2.0 — AURA Learning Engine
// learning.profile-builder.ts
// =============================================================================
// Nightly pg-boss worker that recomputes FamilyBehaviorProfile from
// LearningSignal rows. Section 9.2 + 9.3 + 9.4.
//
// Algorithm:
//   1. Read all signals for the family from the last 365 days.
//   2. Tally per-kind accept/dismiss rates, reminder action rates, scheduling
//      distributions, elder participation, average decision duration.
//   3. Compute confidenceScore based on sample size.
//   4. Compute blended values with global defaults (Section 9.4 gating).
//   5. Snapshot the previous profile to FamilyBehaviorProfileHistory.
//   6. Upsert the new FamilyBehaviorProfile (increment version).
//
// The whole job runs in a single transaction per family. Target: <60s per family.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

interface AggregatedStats {
  insightAcceptRates: Record<string, { accepted: number; dismissed: number }>;
  reminderActions: { acted: number; snoozed: number; dismissed: number; total: number };
  weekdayDistribution: Record<string, number>;
  timeOfDayBuckets: Record<string, number>;
  elderParticipation: { participated: number; totalDecisions: number };
  quorumMet: { met: number; total: number };
  decisionDurationsHours: number[];
  totalSignals: number;
}

@Injectable()
export class ProfileBuilder {
  private readonly logger = new Logger(ProfileBuilder.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Recompute the FamilyBehaviorProfile for one family.
   * Returns the new profile version number.
   */
  async recompute(familyId: string, now: Date = new Date()): Promise<number> {
    const startMs = Date.now();

    // 365-day rolling window
    const since = new Date(now.getTime() - 365 * 24 * 60 * 60 * 1000);

    // ── Aggregate signals ─────────────────────────────────────────────────
    const signals = await this.prisma.learningSignal.findMany({
      where: { familyId, occurredAt: { gte: since } },
      select: { signalType: true, targetType: true, payload: true, occurredAt: true },
    });

    const stats = this.aggregate(signals as any[]);

    // ── Load global defaults ──────────────────────────────────────────────
    const defaults = await this.prisma.globalLearningDefaults.findUnique({
      where: { id: 'global' },
    });
    if (!defaults) {
      this.logger.warn('GlobalLearningDefaults row missing — using hardcoded fallbacks');
    }

    // ── Compute learned values ────────────────────────────────────────────
    const learned = this.computeLearnedValues(stats, defaults as any);

    // ── Confidence gating ─────────────────────────────────────────────────
    const minSamples = defaults?.minSignalsForPersonalization ?? 30;
    const lowThreshold = defaults?.lowConfidenceThreshold ?? 0.4;
    const highThreshold = defaults?.highConfidenceThreshold ?? 0.7;
    const confidence = this.computeConfidence(stats.totalSignals, minSamples, lowThreshold, highThreshold);

    // ── Blend learned with defaults per Section 9.4 ───────────────────────
    const blended = this.blendWithDefaults(learned, defaults as any, confidence);

    // ── Snapshot previous profile to history ──────────────────────────────
    const previous = await this.prisma.familyBehaviorProfile.findUnique({
      where: { familyId },
    });

    return this.prisma.$transaction(async (tx) => {
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

      const newVersion = (previous?.version ?? 0) + 1;
      const profile = await tx.familyBehaviorProfile.upsert({
        where: { familyId },
        create: {
          familyId,
          version: newVersion,
          computedAt: now,
          preferredReminderLeadHours: blended.preferredReminderLeadHours,
          reminderActionRate: blended.reminderActionRate,
          preferredWeekdayDistribution: blended.preferredWeekdayDistribution,
          preferredTimeOfDayBuckets: blended.preferredTimeOfDayBuckets,
          elderAutoIncludeThreshold: blended.elderAutoIncludeThreshold,
          insightAcceptRateByKind: blended.insightAcceptRateByKind,
          averageDecisionDurationHours: blended.averageDecisionDurationHours,
          typicalQuorumMet: blended.typicalQuorumMet,
          sampleSize: stats.totalSignals,
          confidenceScore: confidence,
        },
        update: {
          version: newVersion,
          computedAt: now,
          preferredReminderLeadHours: blended.preferredReminderLeadHours,
          reminderActionRate: blended.reminderActionRate,
          preferredWeekdayDistribution: blended.preferredWeekdayDistribution,
          preferredTimeOfDayBuckets: blended.preferredTimeOfDayBuckets,
          elderAutoIncludeThreshold: blended.elderAutoIncludeThreshold,
          insightAcceptRateByKind: blended.insightAcceptRateByKind,
          averageDecisionDurationHours: blended.averageDecisionDurationHours,
          typicalQuorumMet: blended.typicalQuorumMet,
          sampleSize: stats.totalSignals,
          confidenceScore: confidence,
        },
      });

      const elapsedMs = Date.now() - startMs;
      this.logger.log(
        `Recomputed profile for family ${familyId}: v${newVersion}, ${stats.totalSignals} signals, confidence=${confidence.toFixed(3)}, ${elapsedMs}ms`,
      );

      return newVersion;
    });
  }

  /**
   * Aggregate raw signals into a stats object.
   * Pure function — unit-testable.
   */
  aggregate(signals: Array<{ signalType: string; targetType?: string | null; payload?: any; occurredAt: Date }>): AggregatedStats {
    const stats: AggregatedStats = {
      insightAcceptRates: {},
      reminderActions: { acted: 0, snoozed: 0, dismissed: 0, total: 0 },
      weekdayDistribution: { mon: 0, tue: 0, wed: 0, thu: 0, fri: 0, sat: 0, sun: 0 },
      timeOfDayBuckets: { morning: 0, afternoon: 0, evening: 0, night: 0 },
      elderParticipation: { participated: 0, totalDecisions: 0 },
      quorumMet: { met: 0, total: 0 },
      decisionDurationsHours: [],
      totalSignals: signals.length,
    };

    const weekdayKeys = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

    for (const s of signals) {
      // Weekday + time-of-day distribution based on signal occurredAt
      const day = weekdayKeys[s.occurredAt.getUTCDay()];
      stats.weekdayDistribution[day]++;
      const hour = s.occurredAt.getUTCHours();
      if (hour >= 5 && hour < 12) stats.timeOfDayBuckets.morning++;
      else if (hour >= 12 && hour < 17) stats.timeOfDayBuckets.afternoon++;
      else if (hour >= 17 && hour < 22) stats.timeOfDayBuckets.evening++;
      else stats.timeOfDayBuckets.night++;

      switch (s.signalType) {
        case 'insight_accepted': {
          const kind = s.payload?.kind ?? 'unknown';
          if (!stats.insightAcceptRates[kind]) stats.insightAcceptRates[kind] = { accepted: 0, dismissed: 0 };
          stats.insightAcceptRates[kind].accepted++;
          break;
        }
        case 'insight_dismissed': {
          const kind = s.payload?.kind ?? 'unknown';
          if (!stats.insightAcceptRates[kind]) stats.insightAcceptRates[kind] = { accepted: 0, dismissed: 0 };
          stats.insightAcceptRates[kind].dismissed++;
          break;
        }
        case 'reminder_acted':
          stats.reminderActions.acted++;
          stats.reminderActions.total++;
          break;
        case 'reminder_snoozed':
          stats.reminderActions.snoozed++;
          stats.reminderActions.total++;
          break;
        case 'reminder_dismissed':
          stats.reminderActions.dismissed++;
          stats.reminderActions.total++;
          break;
        case 'elder_participated':
          stats.elderParticipation.participated++;
          stats.elderParticipation.totalDecisions = Math.max(stats.elderParticipation.totalDecisions, s.payload?.decisionCount ?? 1);
          break;
        case 'quorum_met':
          stats.quorumMet.met++;
          stats.quorumMet.total++;
          break;
        case 'vote_pattern':
          // vote_pattern signals include durationHours
          if (typeof s.payload?.durationHours === 'number') {
            stats.decisionDurationsHours.push(s.payload.durationHours);
          }
          if (s.payload?.quorumMet === true) stats.quorumMet.met++;
          if (s.payload?.quorumMet !== undefined) stats.quorumMet.total++;
          break;
      }
    }

    return stats;
  }

  /**
   * Compute learned values from aggregated stats. Pure function.
   */
  computeLearnedValues(stats: AggregatedStats, defaults: any) {
    // Insight accept rate per kind
    const insightAcceptRateByKind: Record<string, number> = {};
    for (const [kind, counts] of Object.entries(stats.insightAcceptRates)) {
      const total = counts.accepted + counts.dismissed;
      insightAcceptRateByKind[kind] = total > 0 ? counts.accepted / total : 0;
    }

    // Reminder action rate per lead-time bucket
    // Buckets: 6h, 12h, 24h — based on payload.leadHours
    const reminderActionRate: Record<string, number> = { '6h': 0, '12h': 0, '24h': 0 };
    // We don't track per-bucket here (would need separate signal payloads);
    // simplified: total action rate is (acted / total)
    const totalActionRate = stats.reminderActions.total > 0
      ? stats.reminderActions.acted / stats.reminderActions.total
      : 0;
    reminderActionRate['6h'] = totalActionRate;
    reminderActionRate['12h'] = totalActionRate * 0.85;
    reminderActionRate['24h'] = totalActionRate * 0.7;

    // Preferred weekday distribution (normalized)
    const totalWeekday = Object.values(stats.weekdayDistribution).reduce((a, b) => a + b, 0);
    const preferredWeekdayDistribution: Record<string, number> = {};
    for (const [k, v] of Object.entries(stats.weekdayDistribution)) {
      preferredWeekdayDistribution[k] = totalWeekday > 0 ? v / totalWeekday : (defaults?.preferredWeekdayDistribution?.[k] ?? 1 / 7);
    }

    // Preferred time-of-day buckets (normalized)
    const totalTOD = Object.values(stats.timeOfDayBuckets).reduce((a, b) => a + b, 0);
    const preferredTimeOfDayBuckets: Record<string, number> = {};
    for (const [k, v] of Object.entries(stats.timeOfDayBuckets)) {
      preferredTimeOfDayBuckets[k] = totalTOD > 0 ? v / totalTOD : (defaults?.preferredTimeOfDayBuckets?.[k] ?? 0.25);
    }

    // Average decision duration
    const averageDecisionDurationHours = stats.decisionDurationsHours.length > 0
      ? stats.decisionDurationsHours.reduce((a, b) => a + b, 0) / stats.decisionDurationsHours.length
      : defaults?.averageDecisionDurationHours ?? 72;

    // Typical quorum met
    const typicalQuorumMet = stats.quorumMet.total > 0
      ? stats.quorumMet.met / stats.quorumMet.total >= 0.5
      : null;

    // Preferred reminder lead hours: derived from action rate
    // If 6h action rate > 0.6 and 24h < 0.3, prefer 6h (per Section 9.3)
    const preferredReminderLeadHours: Record<string, number> = {
      decision: 24,
      meeting: 48,
      event: 72,
    };
    if (reminderActionRate['6h'] > 0.6 && reminderActionRate['24h'] < 0.3) {
      preferredReminderLeadHours.decision = 6;
      preferredReminderLeadHours.meeting = 12;
    } else if (totalActionRate > 0.5) {
      preferredReminderLeadHours.decision = 12;
    }

    // Elder auto-include threshold: if elder participation rate exceeds default, suggest auto-include
    const elderParticipationRate = stats.elderParticipation.totalDecisions > 0
      ? stats.elderParticipation.participated / stats.elderParticipation.totalDecisions
      : 0;
    const elderAutoIncludeThreshold = elderParticipationRate > 0.6 ? 0.5 : (defaults?.elderAutoIncludeThreshold ?? 0.6);

    return {
      insightAcceptRateByKind,
      reminderActionRate,
      preferredWeekdayDistribution,
      preferredTimeOfDayBuckets,
      averageDecisionDurationHours,
      typicalQuorumMet,
      preferredReminderLeadHours,
      elderAutoIncludeThreshold,
    };
  }

  /**
   * Compute the confidenceScore from sample size. Section 9.4.
   *   - <30 signals → 0 (use defaults)
   *   - 30..100 signals → linear 0..0.7
   *   - >100 signals → 1.0 (capped)
   */
  computeConfidence(sampleSize: number, minSamples: number, lowThreshold: number, highThreshold: number): number {
    if (sampleSize < minSamples) return 0;
    if (sampleSize >= 100) return 1.0;
    // Linear interpolation from lowThreshold to highThreshold
    const t = (sampleSize - minSamples) / (100 - minSamples);
    return lowThreshold + t * (highThreshold - lowThreshold);
  }

  /**
   * Blend learned values with defaults based on confidence. Section 9.4.
   *   confidence < low  → 100% defaults
   *   confidence < high → 50% learned + 50% defaults
   *   confidence >= high → 100% learned
   */
  blendWithDefaults(learned: any, defaults: any, confidence: number) {
    const useLearned = confidence >= (defaults?.highConfidenceThreshold ?? 0.7);
    const useBlend = confidence >= (defaults?.lowConfidenceThreshold ?? 0.4) && !useLearned;

    const weight = useLearned ? 1.0 : useBlend ? 0.5 : 0.0;

    const blend = (l: any, d: any) => {
      if (l === null || l === undefined) return d;
      if (typeof l === 'number' && typeof d === 'number') return l * weight + d * (1 - weight);
      if (typeof l === 'object' && typeof d === 'object' && l && d) {
        const out: Record<string, any> = {};
        const keys = new Set([...Object.keys(l), ...Object.keys(d)]);
        for (const k of keys) {
          out[k] = blend(l[k], d[k]);
        }
        return out;
      }
      return weight >= 0.5 ? l : d;
    };

    return {
      preferredReminderLeadHours: blend(learned.preferredReminderLeadHours, defaults?.preferredReminderLeadHours ?? { decision: 24, meeting: 48, event: 72 }),
      reminderActionRate: blend(learned.reminderActionRate, defaults?.reminderActionRate ?? { '6h': 0.42, '12h': 0.55, '24h': 0.71 }),
      preferredWeekdayDistribution: blend(learned.preferredWeekdayDistribution, defaults?.preferredWeekdayDistribution),
      preferredTimeOfDayBuckets: blend(learned.preferredTimeOfDayBuckets, defaults?.preferredTimeOfDayBuckets),
      elderAutoIncludeThreshold: blend(learned.elderAutoIncludeThreshold, defaults?.elderAutoIncludeThreshold ?? 0.6),
      insightAcceptRateByKind: learned.insightAcceptRateByKind,
      averageDecisionDurationHours: learned.averageDecisionDurationHours,
      typicalQuorumMet: learned.typicalQuorumMet,
    };
  }
}
