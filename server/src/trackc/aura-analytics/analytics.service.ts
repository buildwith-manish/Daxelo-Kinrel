// =============================================================================
// Track C v2.0 — AURA Analytics
// analytics.service.ts
// =============================================================================

import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { FamilyMembershipService } from '../common/family-membership.service';
import { AnalyticsSnapshotWorker, Granularity } from './analytics.snapshot-worker';

@Injectable()
export class AnalyticsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly membership: FamilyMembershipService,
    private readonly worker: AnalyticsSnapshotWorker,
  ) {}

  async listSnapshots(params: {
    familyId: string;
    userId: string;
    granularity: Granularity;
    from?: string;
    to?: string;
  }) {
    await this.membership.requireMember(params.userId, params.familyId);
    return this.prisma.familyAnalyticsSnapshot.findMany({
      where: {
        familyId: params.familyId,
        granularity: params.granularity,
        ...(params.from || params.to
          ? {
              periodStart: {
                ...(params.from ? { gte: new Date(params.from) } : {}),
                ...(params.to ? { lte: new Date(params.to) } : {}),
              },
            }
          : {}),
      },
      orderBy: { periodStart: 'desc' },
      take: 52, // up to 1 year of weekly snapshots
    });
  }

  /**
   * Latest snapshot + trend vs prior period.
   */
  async getSummary(familyId: string, userId: string, granularity: Granularity = 'weekly') {
    await this.membership.requireMember(userId, familyId);

    const snapshots = await this.prisma.familyAnalyticsSnapshot.findMany({
      where: { familyId, granularity },
      orderBy: { periodStart: 'desc' },
      take: 2,
    });

    if (snapshots.length === 0) {
      // No snapshot yet — try to compute one on the fly for the current period
      const now = new Date();
      const periodStart = this.startOfPeriod(now, granularity);
      const periodEnd = this.endOfPeriod(periodStart, granularity);
      const fresh = await this.worker.snapshot({
        familyId,
        periodStart,
        periodEnd,
        granularity,
      });
      return {
        current: fresh,
        previous: null,
        trend: null,
      };
    }

    const current = snapshots[0];
    const previous = snapshots[1] ?? null;

    // Compute trend (delta vs previous period)
    const trend = previous ? this.computeTrend(current.metrics as any, previous.metrics as any) : null;

    return { current, previous, trend };
  }

  /**
   * Trigger a snapshot generation (admin-only). Normally done by weekly pg-boss job.
   */
  async triggerSnapshot(familyId: string, userId: string, granularity: Granularity = 'weekly') {
    await this.membership.requireAdmin(userId, familyId);
    const now = new Date();
    const periodStart = this.startOfPeriod(now, granularity);
    const periodEnd = this.endOfPeriod(periodStart, granularity);
    return this.worker.snapshot({ familyId, periodStart, periodEnd, granularity });
  }

  private computeTrend(current: any, previous: any) {
    const delta = (a: number, b: number) => a - b;
    const pctChange = (a: number, b: number) => (b > 0 ? (a - b) / b : 0);
    return {
      decisionsCreated: {
        delta: delta(current.decisionsCreated ?? 0, previous.decisionsCreated ?? 0),
        pct: pctChange(current.decisionsCreated ?? 0, previous.decisionsCreated ?? 0),
      },
      decisionsResolved: {
        delta: delta(current.decisionsResolved ?? 0, previous.decisionsResolved ?? 0),
        pct: pctChange(current.decisionsResolved ?? 0, previous.decisionsResolved ?? 0),
      },
      participationRate: {
        delta: delta(current.participationRate ?? 0, previous.participationRate ?? 0),
      },
      quorumMetRate: {
        delta: delta(current.quorumMetRate ?? 0, previous.quorumMetRate ?? 0),
      },
      avgDurationHours: {
        delta: delta(current.avgDurationHours ?? 0, previous.avgDurationHours ?? 0),
      },
    };
  }

  private startOfPeriod(date: Date, granularity: Granularity): Date {
    const d = new Date(date);
    d.setUTCHours(0, 0, 0, 0);
    if (granularity === 'weekly') {
      // Start of ISO week (Monday)
      const day = d.getUTCDay();
      const diff = (day + 6) % 7; // Monday=0
      d.setUTCDate(d.getUTCDate() - diff);
    } else if (granularity === 'monthly') {
      d.setUTCDate(1);
    } else if (granularity === 'quarterly') {
      d.setUTCMonth(Math.floor(d.getUTCMonth() / 3) * 3);
      d.setUTCDate(1);
    }
    return d;
  }

  private endOfPeriod(start: Date, granularity: Granularity): Date {
    const e = new Date(start);
    if (granularity === 'weekly') e.setUTCDate(e.getUTCDate() + 7);
    else if (granularity === 'monthly') e.setUTCMonth(e.getUTCMonth() + 1);
    else if (granularity === 'quarterly') e.setUTCMonth(e.getUTCMonth() + 3);
    return e;
  }
}
