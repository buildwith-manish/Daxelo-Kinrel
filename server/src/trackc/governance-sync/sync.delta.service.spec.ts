// =============================================================================
// Track C v2.0 — SyncDeltaService Tests
// =============================================================================
// Exercises the delta-sync endpoint: watermark monotonicity, family
// membership intersection, and the configured page-size cap.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { SyncDeltaService } from './sync.delta.service';

describe('SyncDeltaService', () => {
  let prisma: any;
  let membership: any;
  let service: SyncDeltaService;

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
    };

    service = new SyncDeltaService(prisma as any, membership as any);
  });

  it('returns empty delta when the user is not a member of any family', async () => {
    prisma.familyMember.findMany.mockResolvedValueOnce([]); // no memberships

    const result = await service.getDelta({
      userId: 'u_1',
      deviceId: 'dev_1',
      since: new Date(0).toISOString(),
    });

    expect(result.changes).toEqual({});
    expect(result.deletions).toEqual({});
    expect(result.clamped).toBe(false);
    // No watermark upserts should happen if there are no families
    expect(prisma.syncWatermark.upsert).not.toHaveBeenCalled();
  });

  it('returns empty delta when client watermark ≥ server watermark (now)', async () => {
    // User is a member of fam_1
    prisma.familyMember.findMany.mockResolvedValueOnce([{ familyId: 'fam_1' }]);
    // All entity findMany calls default to [] (no rows updated since watermark)

    // Watermark in the future → clamped to now
    const futureWatermark = new Date(Date.now() + 60_000).toISOString();
    const result = await service.getDelta({
      userId: 'u_1',
      deviceId: 'dev_1',
      since: futureWatermark,
    });

    // No rows updated since the (clamped) watermark → all entity arrays empty
    expect(result.changes.constitutions).toEqual([]);
    expect(result.changes.decisions).toEqual([]);
    expect(result.changes.timelineEvents).toEqual([]);
    // clamped should be true because the input watermark was in the future
    expect(result.clamped).toBe(true);
  });

  it('returns only entities updated after the watermark', async () => {
    prisma.familyMember.findMany.mockResolvedValueOnce([{ familyId: 'fam_1' }]);
    // The service issues 15 findMany calls in parallel — set up different
    // responses for the ones we want to verify
    const updatedDecision = {
      id: 'd_1',
      familyId: 'fam_1',
      title: 'Updated decision',
      updatedAt: new Date(),
    };

    // The 5th findMany call is for familyDecision
    prisma.familyDecision.findMany.mockResolvedValueOnce([updatedDecision]);
    // The 6th findMany call is for decisionVote
    prisma.decisionVote.findMany.mockResolvedValueOnce([
      { id: 'v_1', decisionId: 'd_1', familyId: 'fam_1' },
    ]);

    const pastWatermark = new Date(Date.now() - 60_000).toISOString();
    const result = await service.getDelta({
      userId: 'u_1',
      deviceId: 'dev_1',
      since: pastWatermark,
      families: ['fam_1'],
    });

    expect(result.changes.decisions).toEqual([updatedDecision]);
    expect(result.changes.votes).toEqual([
      { id: 'v_1', decisionId: 'd_1', familyId: 'fam_1' },
    ]);
    // Other entity types should be empty (mock default)
    expect(result.changes.constitutions).toEqual([]);
    // clamped should be false — watermark was in the past
    expect(result.clamped).toBe(false);
    // Watermark must be upserted for the family/device combination
    expect(prisma.syncWatermark.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          userId_familyId_deviceId: {
            userId: 'u_1',
            familyId: 'fam_1',
            deviceId: 'dev_1',
          },
        },
      }),
    );
  });

  it('caps the delta at the configured page size (limit)', async () => {
    prisma.familyMember.findMany.mockResolvedValueOnce([{ familyId: 'fam_1' }]);
    // Generate 3000 rows; service should cap at limit (max 2000)
    const manyDecisions = Array.from({ length: 3000 }, (_, i) => ({
      id: `d_${i}`,
      familyId: 'fam_1',
    }));
    prisma.familyDecision.findMany.mockResolvedValueOnce(manyDecisions);

    const result = await service.getDelta({
      userId: 'u_1',
      deviceId: 'dev_1',
      since: new Date(0).toISOString(),
      families: ['fam_1'],
      limit: 100, // user requested 100
    });

    // Service should pass take: min(100, 2000) = 100 to findMany
    expect(prisma.familyDecision.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        take: 100,
      }),
    );
    // The mocked return value isn't sliced by the service, but the take arg
    // proves the cap was applied
    expect((result.changes.decisions ?? []).length).toBe(3000); // mock returned all
  });

  it('caps limit at server-side maximum of 2000', async () => {
    prisma.familyMember.findMany.mockResolvedValueOnce([{ familyId: 'fam_1' }]);

    await service.getDelta({
      userId: 'u_1',
      deviceId: 'dev_1',
      since: new Date(0).toISOString(),
      families: ['fam_1'],
      limit: 99999, // over the cap
    });

    // All findMany calls should use take: 2000 (the server cap)
    expect(prisma.familyDecision.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        take: 2000,
      }),
    );
  });

  it('intersects requested families with actual memberships (defense in depth)', async () => {
    // User is a member of fam_1 only
    prisma.familyMember.findMany.mockResolvedValueOnce([{ familyId: 'fam_1' }]);

    // Client requests fam_1 (member) + fam_2 (NOT member)
    await service.getDelta({
      userId: 'u_1',
      deviceId: 'dev_1',
      since: new Date(0).toISOString(),
      families: ['fam_1', 'fam_2'],
    });

    // The where clause should only include fam_1 (the intersection)
    expect(prisma.familyDecision.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          familyId: { in: ['fam_1'] },
        }),
      }),
    );
  });
});
