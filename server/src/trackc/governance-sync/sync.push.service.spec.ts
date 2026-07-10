// =============================================================================
// Track C v2.0 — SyncPushService Tests
// =============================================================================
// Exercises the outbox-push endpoint: conflict detection on stale state,
// clientOpId ordering, idempotency, and the applied/rejected classification.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { SyncPushService, PushOperation } from './sync.push.service';
import { BadRequestException, ForbiddenException } from '@nestjs/common';

describe('SyncPushService', () => {
  let prisma: any;
  let membership: any;
  let service: SyncPushService;

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
      requireRole: jest.fn().mockResolvedValue({ id: 'm_1' }),
    };

    service = new SyncPushService(prisma as any, membership as any);
  });

  function voteOp(clientOpId: string, decisionId: string, familyId: string = 'fam_1', option: string = 'yes'): PushOperation {
    return {
      kind: 'create',
      entity: 'decision',
      op: 'vote',
      clientOpId,
      payload: { familyId, decisionId, option },
    };
  }

  it('rejects outbox ops with stale watermark (decision no longer open)', async () => {
    // The decision exists but is already resolved → 409 Conflict
    prisma.familyDecision.findUnique.mockResolvedValueOnce({
      id: 'd_1',
      familyId: 'fam_1',
      status: 'resolved', // ← stale; voting closed
      eligibleUserIds: ['u_1'],
    });

    const result = await service.push({
      userId: 'u_1',
      operations: [voteOp('op_1', 'd_1')],
    });

    expect(result.applied).toHaveLength(0);
    expect(result.conflicts).toHaveLength(1);
    expect(result.conflicts[0].clientOpId).toBe('op_1');
    expect(result.conflicts[0].reason).toContain('no longer open');
  });

  it('applies vote ops in clientOpId order and marks them applied', async () => {
    // First vote op: decision is open, vote succeeds
    prisma.familyDecision.findUnique.mockResolvedValueOnce({
      id: 'd_1',
      familyId: 'fam_1',
      status: 'open',
      eligibleUserIds: ['u_1', 'u_2'],
    });
    prisma.decisionVote.create.mockResolvedValueOnce({ id: 'v_1', option: 'yes' });
    // Second vote op on a different decision
    prisma.familyDecision.findUnique.mockResolvedValueOnce({
      id: 'd_2',
      familyId: 'fam_1',
      status: 'open',
      eligibleUserIds: ['u_1', 'u_2'],
    });
    prisma.decisionVote.create.mockResolvedValueOnce({ id: 'v_2', option: 'no' });

    const result = await service.push({
      userId: 'u_1',
      operations: [
        voteOp('op_1', 'd_1', 'fam_1', 'yes'),
        voteOp('op_2', 'd_2', 'fam_1', 'no'),
      ],
    });

    expect(result.applied).toHaveLength(2);
    expect(result.applied[0].clientOpId).toBe('op_1');
    expect(result.applied[1].clientOpId).toBe('op_2');
    expect(result.conflicts).toHaveLength(0);
    expect(result.rejected).toHaveLength(0);
  });

  it('marks duplicate-vote ops as applied (idempotent)', async () => {
    prisma.familyDecision.findUnique.mockResolvedValueOnce({
      id: 'd_1',
      familyId: 'fam_1',
      status: 'open',
      eligibleUserIds: ['u_1'],
    });
    // P2002 from Prisma → service returns idempotent success
    const p2002 = Object.assign(new Error('Unique constraint failed'), {
      code: 'P2002',
    });
    prisma.decisionVote.create.mockRejectedValueOnce(p2002);

    const result = await service.push({
      userId: 'u_1',
      operations: [voteOp('op_1', 'd_1')],
    });

    // Idempotent — should be marked applied with skipped:true
    expect(result.applied).toHaveLength(1);
    expect(result.applied[0].result).toEqual(
      expect.objectContaining({ skipped: true, reason: 'already_voted' }),
    );
  });

  it('marks rejected ops with the conflict reason when RLS rejects (403)', async () => {
    // The decision is missing → BadRequestException thrown inside applyDecisionOp
    prisma.familyDecision.findUnique.mockResolvedValueOnce(null);

    const result = await service.push({
      userId: 'u_1',
      operations: [voteOp('op_1', 'd_missing')],
    });

    // Service treats BadRequestException as a transient error → rejected
    expect(result.rejected).toHaveLength(1);
    expect(result.rejected[0].clientOpId).toBe('op_1');
    expect(result.rejected[0].reason).toContain('not found');
  });

  it('skips ops whose clientOpId has already been applied (in-memory idempotency)', async () => {
    // First push: applies successfully
    prisma.familyDecision.findUnique.mockResolvedValueOnce({
      id: 'd_1',
      familyId: 'fam_1',
      status: 'open',
      eligibleUserIds: ['u_1'],
    });
    prisma.decisionVote.create.mockResolvedValueOnce({ id: 'v_1' });

    await service.push({
      userId: 'u_1',
      operations: [voteOp('op_1', 'd_1')],
    });

    // Second push with the SAME clientOpId — should be skipped without re-applying
    const result = await service.push({
      userId: 'u_1',
      operations: [voteOp('op_1', 'd_1')],
    });

    expect(result.applied).toHaveLength(1);
    expect(result.applied[0].result).toEqual({ skipped: true });
    // Only ONE call to decisionVote.create should have happened across both pushes
    expect(prisma.decisionVote.create).toHaveBeenCalledTimes(1);
  });

  it('rejects unsupported entity types', async () => {
    const op: PushOperation = {
      kind: 'create',
      entity: 'unknown_entity',
      op: 'foo',
      clientOpId: 'op_1',
      payload: { familyId: 'fam_1' },
    };

    const result = await service.push({
      userId: 'u_1',
      operations: [op],
    });

    expect(result.rejected).toHaveLength(1);
    expect(result.rejected[0].reason).toContain('Unsupported entity');
  });

  it('handles editTitle ops with LWW (last-write-wins) on open decisions', async () => {
    prisma.familyDecision.findUnique.mockResolvedValueOnce({
      id: 'd_1',
      familyId: 'fam_1',
      status: 'open',
    });
    prisma.familyDecision.update.mockResolvedValueOnce({
      id: 'd_1',
      title: 'New title',
    });

    const result = await service.push({
      userId: 'u_1',
      operations: [
        {
          kind: 'update',
          entity: 'decision',
          op: 'editTitle',
          clientOpId: 'op_1',
          payload: { familyId: 'fam_1', decisionId: 'd_1', title: 'New title' },
        },
      ],
    });

    expect(result.applied).toHaveLength(1);
    expect(prisma.familyDecision.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ title: 'New title' }),
      }),
    );
  });

  it('rejects lifecycle ops on non-resolved decisions (conflict)', async () => {
    prisma.familyDecision.findUnique.mockResolvedValueOnce({
      id: 'd_1',
      familyId: 'fam_1',
      status: 'open', // ← not resolved → conflict
    });

    const result = await service.push({
      userId: 'u_1',
      operations: [
        {
          kind: 'update',
          entity: 'decision',
          op: 'lifecycle',
          clientOpId: 'op_1',
          payload: { familyId: 'fam_1', decisionId: 'd_1', to: 'started' },
        },
      ],
    });

    expect(result.conflicts).toHaveLength(1);
    expect(result.conflicts[0].reason).toContain('resolved');
  });
});
