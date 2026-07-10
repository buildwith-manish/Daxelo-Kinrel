// =============================================================================
// Track C v2.0 — AnalyticsService Tests
// =============================================================================
// Exercises getSummary() (with and without existing snapshots) and the
// listSnapshots() ordering. The v2 spec test plan references a getTrend()
// method — the actual AnalyticsService exposes listSnapshots() instead,
// which returns the time-series ordered by periodStart DESC.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { AnalyticsService } from './analytics.service';
import { Granularity } from './analytics.snapshot-worker';

describe('AnalyticsService', () => {
  let prisma: any;
  let membership: any;
  let worker: any;
  let service: AnalyticsService;

  beforeEach(() => {
    prisma = new PrismaService();
    for (const m of Object.values(prisma) as any[]) {
      if (m && typeof m === 'object' && 'findUnique' in m) {
        (m as any).findUnique.mockResolvedValue(null);
        (m as any).findMany.mockResolvedValue([]);
        (m as any).create.mockResolvedValue({});
        (m as any).update.mockResolvedValue({});
        (m as any).upsert.mockResolvedValue({});
        (m as any).count.mockResolvedValue(0);
      }
    }

    membership = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1' }),
      requireAdmin: jest.fn().mockResolvedValue({ id: 'm_1', role: 'admin' }),
    };

    worker = {
      snapshot: jest.fn().mockResolvedValue({
        id: 'snap_fresh',
        familyId: 'fam_1',
        granularity: 'weekly',
        metrics: { decisionsCreated: 0 },
      }),
    };

    service = new AnalyticsService(
      prisma as any,
      membership as any,
      worker as any,
    );
  });

  // ── getSummary() ─────────────────────────────────────────────────────
  describe('getSummary()', () => {
    it('computes a fresh snapshot on the fly when none exists (previous=null, trend=null)', async () => {
      prisma.familyAnalyticsSnapshot.findMany.mockResolvedValueOnce([]); // no snapshots
      const fresh = {
        id: 'snap_fresh',
        familyId: 'fam_1',
        granularity: 'weekly',
        metrics: { decisionsCreated: 0, decisionsResolved: 0 },
      };
      worker.snapshot.mockResolvedValueOnce(fresh);

      const result = await service.getSummary('fam_1', 'u_1', 'weekly');

      // When no snapshot exists, the service computes one on the fly
      expect(result.current).toEqual(fresh);
      expect(result.previous).toBeNull();
      expect(result.trend).toBeNull();
      // The worker must have been called to compute the fresh snapshot
      expect(worker.snapshot).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          granularity: 'weekly',
        }),
      );
    });

    it('returns the most recent weekly snapshot + trend vs prior period', async () => {
      const current = {
        id: 'snap_curr',
        familyId: 'fam_1',
        granularity: 'weekly',
        periodStart: new Date('2026-07-06'),
        metrics: {
          decisionsCreated: 5,
          decisionsResolved: 4,
          participationRate: 0.8,
          quorumMetRate: 0.75,
          avgDurationHours: 36,
        },
      };
      const previous = {
        id: 'snap_prev',
        familyId: 'fam_1',
        granularity: 'weekly',
        periodStart: new Date('2026-06-29'),
        metrics: {
          decisionsCreated: 3,
          decisionsResolved: 2,
          participationRate: 0.6,
          quorumMetRate: 0.5,
          avgDurationHours: 48,
        },
      };
      prisma.familyAnalyticsSnapshot.findMany.mockResolvedValueOnce([current, previous]);

      const result = await service.getSummary('fam_1', 'u_1', 'weekly');

      // The first item returned by findMany (ordered by periodStart DESC) is the current
      expect(result.current.id).toBe('snap_curr');
      expect((result.previous as any).id).toBe('snap_prev');
      // The trend must be computed against the previous period
      expect(result.trend).not.toBeNull();
      const trend = result.trend as any;
      expect(trend.decisionsCreated.delta).toBe(2); // 5 - 3
      expect(trend.decisionsCreated.pct).toBeCloseTo(2 / 3, 5);
      expect(trend.avgDurationHours.delta).toBe(-12); // 36 - 48
    });

    it('returns trend=null when only one snapshot exists (no prior period)', async () => {
      const only = {
        id: 'snap_only',
        familyId: 'fam_1',
        granularity: 'weekly',
        periodStart: new Date('2026-07-06'),
        metrics: { decisionsCreated: 5 },
      };
      prisma.familyAnalyticsSnapshot.findMany.mockResolvedValueOnce([only]);

      const result = await service.getSummary('fam_1', 'u_1', 'weekly');

      expect(result.current.id).toBe('snap_only');
      expect(result.previous).toBeNull();
      expect(result.trend).toBeNull();
    });

    it('queries the two most recent snapshots (take: 2)', async () => {
      prisma.familyAnalyticsSnapshot.findMany.mockResolvedValueOnce([]);

      await service.getSummary('fam_1', 'u_1', 'weekly');

      // The query must request only the two most recent snapshots
      expect(prisma.familyAnalyticsSnapshot.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId: 'fam_1', granularity: 'weekly' },
          orderBy: { periodStart: 'desc' },
          take: 2,
        }),
      );
    });

    it('rejects non-members', async () => {
      membership.requireMember.mockRejectedValueOnce(new Error('not a member'));
      await expect(service.getSummary('fam_1', 'outsider')).rejects.toThrow('not a member');
    });
  });

  // ── listSnapshots() (the v2 spec's "getTrend" equivalent) ────────────
  describe('listSnapshots() — the time-series read', () => {
    it('returns snapshots ordered by periodStart DESC (reverse-chronological)', async () => {
      // Service returns rows in DESC order (most recent first). Reversing
      // the array yields chronological order, matching the v2 spec's
      // getTrend intent.
      const week1 = { id: 's1', periodStart: new Date('2026-06-29'), metrics: {} };
      const week2 = { id: 's2', periodStart: new Date('2026-07-06'), metrics: {} };
      const week3 = { id: 's3', periodStart: new Date('2026-07-13'), metrics: {} };
      prisma.familyAnalyticsSnapshot.findMany.mockResolvedValueOnce([week3, week2, week1]);

      const result = await service.listSnapshots({
        familyId: 'fam_1',
        userId: 'u_1',
        granularity: 'weekly',
      });

      // Returned in DESC order from the service
      expect(result).toEqual([week3, week2, week1]);
      // Reversed → chronological
      const chronological = [...result].reverse();
      expect(chronological[0].id).toBe('s1');
      expect(chronological[1].id).toBe('s2');
      expect(chronological[2].id).toBe('s3');
    });

    it('applies from/to date range filters when provided', async () => {
      prisma.familyAnalyticsSnapshot.findMany.mockResolvedValueOnce([]);

      await service.listSnapshots({
        familyId: 'fam_1',
        userId: 'u_1',
        granularity: 'weekly',
        from: '2026-06-01',
        to: '2026-07-01',
      });

      expect(prisma.familyAnalyticsSnapshot.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            periodStart: {
              gte: new Date('2026-06-01'),
              lte: new Date('2026-07-01'),
            },
          }),
        }),
      );
    });

    it('caps the result at 52 snapshots (1 year of weekly data)', async () => {
      prisma.familyAnalyticsSnapshot.findMany.mockResolvedValueOnce([]);

      await service.listSnapshots({
        familyId: 'fam_1',
        userId: 'u_1',
        granularity: 'weekly',
      });

      expect(prisma.familyAnalyticsSnapshot.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ take: 52 }),
      );
    });

    it('returns an empty array when no snapshots exist for the family', async () => {
      prisma.familyAnalyticsSnapshot.findMany.mockResolvedValueOnce([]);
      const result = await service.listSnapshots({
        familyId: 'fam_1',
        userId: 'u_1',
        granularity: 'weekly',
      });
      expect(result).toEqual([]);
    });
  });

  // ── triggerSnapshot() ────────────────────────────────────────────────
  describe('triggerSnapshot()', () => {
    it('delegates to the worker after the admin check', async () => {
      const fresh = { id: 'snap_new', familyId: 'fam_1', granularity: 'weekly' };
      worker.snapshot.mockResolvedValueOnce(fresh);

      const result = await service.triggerSnapshot('fam_1', 'u_admin', 'weekly');

      expect(result).toEqual(fresh);
      expect(membership.requireAdmin).toHaveBeenCalledWith('u_admin', 'fam_1');
      expect(worker.snapshot).toHaveBeenCalledWith(
        expect.objectContaining({ familyId: 'fam_1', granularity: 'weekly' }),
      );
    });

    it('rejects non-admins from triggering a snapshot', async () => {
      membership.requireAdmin.mockRejectedValueOnce(new Error('requires admin'));
      await expect(
        service.triggerSnapshot('fam_1', 'u_member', 'weekly'),
      ).rejects.toThrow('requires admin');
      expect(worker.snapshot).not.toHaveBeenCalled();
    });
  });
});
