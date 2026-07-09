// =============================================================================
// Track C v2.0 — AURA Analytics
// analytics.snapshot-worker.ts
// =============================================================================
// Weekly/monthly/quarterly snapshot worker. Section 5.9 + Section 13.
// Private, family-scoped insights — NO leaderboards, NO cross-family
// comparisons.
//
// Computes:
//   - decisionsCreated, decisionsResolved, decisionsExpired
//   - avgDurationHours
//   - participationRate (votes cast / eligible votes)
//   - quorumMetRate
//   - lifecycleDistribution (planned/started/in_progress/completed/...)
//   - timelineEventCount
//   - meetingArtifactCount
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { AnalyticsAnomalyDetector } from './analytics.anomaly-detector';

export type Granularity = 'weekly' | 'monthly' | 'quarterly';

@Injectable()
export class AnalyticsSnapshotWorker {
  private readonly logger = new Logger(AnalyticsSnapshotWorker.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly anomalyDetector: AnalyticsAnomalyDetector,
  ) {}

  /**
   * Compute and persist a snapshot for a family + period.
   * Idempotent: re-running for the same period overwrites.
   */
  async snapshot(params: {
    familyId: string;
    periodStart: Date;
    periodEnd: Date;
    granularity: Granularity;
  }) {
    const { familyId, periodStart, periodEnd, granularity } = params;

    // ── Aggregate decision metrics ────────────────────────────────────────
    const decisionsCreated = await this.prisma.familyDecision.count({
      where: { familyId, createdAt: { gte: periodStart, lt: periodEnd } },
    });
    const decisionsResolved = await this.prisma.familyDecision.count({
      where: { familyId, status: 'resolved', resolvedAt: { gte: periodStart, lt: periodEnd } },
    });
    const decisionsExpired = await this.prisma.familyDecision.count({
      where: { familyId, status: 'expired', resolvedAt: { gte: periodStart, lt: periodEnd } },
    });

    // Average duration (createdAt → resolvedAt) for resolved decisions in period
    const resolvedDecisions = await this.prisma.familyDecision.findMany({
      where: {
        familyId,
        status: 'resolved',
        resolvedAt: { gte: periodStart, lt: periodEnd },
      },
      select: { createdAt: true, resolvedAt: true },
    });
    const durations = resolvedDecisions
      .filter((d) => d.resolvedAt)
      .map((d) => (d.resolvedAt!.getTime() - d.createdAt.getTime()) / 3_600_000);
    const avgDurationHours = durations.length > 0
      ? durations.reduce((a, b) => a + b, 0) / durations.length
      : 0;

    // Participation rate: votes cast / sum of eligible voters per decision
    const decisionsInPeriod = await this.prisma.familyDecision.findMany({
      where: { familyId, createdAt: { gte: periodStart, lt: periodEnd } },
      select: { id: true, eligibleUserIds: true },
    });
    const voteCounts = await this.prisma.decisionVote.groupBy({
      by: ['decisionId'],
      where: { familyId, votedAt: { gte: periodStart, lt: periodEnd } },
      _count: true,
    });
    const totalEligible = decisionsInPeriod.reduce((acc, d) => acc + d.eligibleUserIds.length, 0);
    const totalVotes = voteCounts.reduce((acc, v) => acc + v._count, 0);
    const participationRate = totalEligible > 0 ? totalVotes / totalEligible : 0;

    // Quorum met rate (based on resolved outcomes)
    const decisionsWithOutcome = await this.prisma.familyDecision.findMany({
      where: {
        familyId,
        status: 'resolved',
        resolvedAt: { gte: periodStart, lt: periodEnd },
      },
      select: { outcome: true },
    });
    const quorumMetCount = decisionsWithOutcome.filter((d) => d.outcome === 'approved').length;
    const quorumMetRate = decisionsWithOutcome.length > 0
      ? quorumMetCount / decisionsWithOutcome.length
      : 0;

    // Lifecycle distribution
    const lifecycleDistribution = await this.prisma.familyDecision.groupBy({
      by: ['lifecycleState'],
      where: { familyId, updatedAt: { gte: periodStart, lt: periodEnd } },
      _count: true,
    });

    // Timeline event count
    const timelineEventCount = await this.prisma.aURATimelineEvent.count({
      where: { familyId, occurredAt: { gte: periodStart, lt: periodEnd } },
    });

    // Meeting artifact count
    const meetingArtifactCount = await this.prisma.meetingArtifact.count({
      where: { familyId, heldAt: { gte: periodStart, lt: periodEnd } },
    });

    // ── Build metrics object ───────────────────────────────────────────────
    const metrics = {
      decisionsCreated,
      decisionsResolved,
      decisionsExpired,
      avgDurationHours,
      participationRate,
      quorumMetRate,
      lifecycleDistribution: lifecycleDistribution.reduce((acc, l) => {
        acc[l.lifecycleState ?? 'null'] = l._count;
        return acc;
      }, {} as Record<string, number>),
      timelineEventCount,
      meetingArtifactCount,
      totalVotes,
      totalEligible,
    };

    // ── Anomaly detection ──────────────────────────────────────────────────
    const anomalies = this.anomalyDetector.detect({
      familyId,
      periodStart,
      periodEnd,
      granularity,
      metrics,
    });

    // ── Persist the snapshot ──────────────────────────────────────────────
    return this.prisma.familyAnalyticsSnapshot.upsert({
      where: {
        familyId_granularity_periodStart: {
          familyId,
          granularity,
          periodStart,
        },
      },
      create: {
        familyId,
        periodStart,
        periodEnd,
        granularity,
        metrics: metrics as any,
        anomalies: anomalies as any,
      },
      update: {
        periodEnd,
        metrics: metrics as any,
        anomalies: anomalies as any,
      },
    });
  }
}
