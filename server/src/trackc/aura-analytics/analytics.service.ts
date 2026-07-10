// =============================================================================
// Track C v2.0 — AURA Analytics
// analytics.service.ts
// =============================================================================

import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { FamilyMembershipService } from '../common/family-membership.service';
import { VisibilityService, isMinorUser } from '../common/visibility.service';
import { AnalyticsSnapshotWorker, Granularity } from './analytics.snapshot-worker';

@Injectable()
export class AnalyticsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly membership: FamilyMembershipService,
    private readonly visibility: VisibilityService,
    private readonly worker: AnalyticsSnapshotWorker,
  ) {}

  /**
   * List analytics snapshots for a family.
   *
   * VISIBILITY MATRIX: aggregate/family-level snapshots are visible to ALL
   * roles including minors. However, any per-name fields in the snapshot
   * metrics (e.g. "topContributor") are stripped from the response if the
   * requesting user is a minor — at the service layer, not just the UI.
   */
  async listSnapshots(params: {
    familyId: string;
    userId: string;
    granularity: Granularity;
    from?: string;
    to?: string;
  }) {
    const ctx = await this.visibility.requireMemberWithAge(params.userId, params.familyId);

    const snapshots = await this.prisma.familyAnalyticsSnapshot.findMany({
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

    // Strip per-name fields from metrics if the viewer is a minor
    if (ctx.isMinor) {
      return snapshots.map((s) => ({
        ...s,
        metrics: this.stripPerNameFields(s.metrics as any),
      }));
    }
    return snapshots;
  }

  /**
   * Latest snapshot + trend vs prior period.
   *
   * VISIBILITY MATRIX: visible to ALL roles including minors. Per-name
   * fields in the metrics are stripped for minors.
   */
  async getSummary(familyId: string, userId: string, granularity: Granularity = 'weekly') {
    const ctx = await this.visibility.requireMemberWithAge(userId, familyId);

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
        current: ctx.isMinor ? this.stripPerNameFieldsFromSnapshot(fresh) : fresh,
        previous: null,
        trend: null,
      };
    }

    const current = snapshots[0];
    const previous = snapshots[1] ?? null;

    // Compute trend (delta vs previous period)
    const trend = previous ? this.computeTrend(current.metrics as any, previous.metrics as any) : null;

    // Strip per-name fields if the viewer is a minor
    const sanitizedCurrent = ctx.isMinor
      ? { ...current, metrics: this.stripPerNameFields(current.metrics as any) }
      : current;
    const sanitizedPrevious = ctx.isMinor && previous
      ? { ...previous, metrics: this.stripPerNameFields(previous.metrics as any) }
      : previous;

    return { current: sanitizedCurrent, previous: sanitizedPrevious, trend };
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

  // ===========================================================================
  // VISIBILITY MATRIX: Per-member analytics breakdown (FUTURE-PROOF GUARD)
  // ===========================================================================
  //
  // The current AnalyticsService doesn't expose per-member data yet, but the
  // matrix requires that ANY future per-member endpoint be admin-only. This
  // guard method is the single entry point for all future per-member queries.
  // When you add a new method that returns per-user analytics (e.g. "voting
  // participation by member"), call this guard first:
  //
  //   async getPerMemberBreakdown(familyId, userId) {
  //     await this.requireAdminForPerMemberData(userId, familyId);
  //     ...
  //   }
  //
  // This ensures the restriction is enforced even if a future developer
  // forgets to add it at the controller level.
  // ===========================================================================

  /**
   * Require admin access for any per-member analytics breakdown.
   * This is a future-proof guard — call it at the top of any new method
   * that returns per-user analytics data.
   */
  async requireAdminForPerMemberData(userId: string, familyId: string) {
    await this.visibility.requireAdminDataAccess(userId, familyId);
  }

  // ===========================================================================
  // Per-name field stripping (for minors)
  // ===========================================================================

  /**
   * Strip any per-name fields from analytics metrics before returning to
   * a minor. Per the matrix: "Minors should never see even aggregate
   * analytics that could indirectly expose another member's individual
   * behavior (e.g. a 'top contributor' field)".
   *
   * This is a defensive strip — it removes any key that looks like it
   * contains a user name or ID. The current snapshot metrics don't
   * include per-name fields, but this guard protects against future
   * additions.
   */
  private stripPerNameFields(metrics: any): any {
    if (!metrics || typeof metrics !== 'object') return metrics;

    const PER_NAME_KEY_PATTERNS = [
      'topContributor',
      'topVoter',
      'mostActiveMember',
      'leastActiveMember',
      'topPerformer',
      'memberName',
      'userName',
      'displayName',
      'participantName',
      'contributorName',
      'voterName',
    ];

    const result: any = Array.isArray(metrics) ? [...metrics] : { ...metrics };

    for (const key of Object.keys(result)) {
      // Remove exact matches
      if (PER_NAME_KEY_PATTERNS.some((p) => key === p || key.endsWith(p))) {
        delete result[key];
        continue;
      }
      // Recursively strip nested objects/arrays
      if (result[key] && typeof result[key] === 'object') {
        result[key] = this.stripPerNameFields(result[key]);
      }
    }

    return result;
  }

  /**
   * Strip per-name fields from a full snapshot object (for the on-the-fly
   * computed snapshot in getSummary).
   */
  private stripPerNameFieldsFromSnapshot(snapshot: any): any {
    if (!snapshot) return snapshot;
    return {
      ...snapshot,
      metrics: this.stripPerNameFields(snapshot.metrics),
    };
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
