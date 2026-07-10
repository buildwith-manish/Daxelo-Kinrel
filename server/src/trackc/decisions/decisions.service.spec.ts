// =============================================================================
// Track C v2.0 — DecisionsService Tests
// =============================================================================
// Exercises the actual DecisionsService (not just the pure state machine).
// Covers: resolve() happy path + idempotency + reject paths + constitution_amend
// wiring, vote() duplicate/ineligible/closed rejections, autoExpireIfPastDeadline,
// and create() validation edge cases.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { DecisionsService, CreateDecisionInput } from './decisions.service';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';

type ModelMock = ReturnType<typeof makeModelMock>;
function makeModelMock() {
  return {
    findUnique: jest.fn().mockResolvedValue(null),
    findFirst: jest.fn().mockResolvedValue(null),
    findMany: jest.fn().mockResolvedValue([]),
    create: jest.fn().mockResolvedValue({}),
    createMany: jest.fn().mockResolvedValue({ count: 0 }),
    update: jest.fn().mockResolvedValue({}),
    updateMany: jest.fn().mockResolvedValue({ count: 0 }),
    delete: jest.fn().mockResolvedValue({}),
    deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    upsert: jest.fn().mockResolvedValue({}),
    count: jest.fn().mockResolvedValue(0),
    groupBy: jest.fn().mockResolvedValue([]),
    aggregate: jest.fn().mockResolvedValue({}),
  };
}

describe('DecisionsService', () => {
  let prisma: any;
  let emitter: any;
  let membership: any;
  let constitutionService: any;
  let service: DecisionsService;

  beforeEach(() => {
    prisma = new PrismaService();
    // Reset all auto-mock return values to a known baseline
    for (const m of Object.values(prisma) as any[]) {
      if (m && typeof m === 'object' && 'findUnique' in m) {
        (m as any).findUnique.mockResolvedValue(null);
        (m as any).findMany.mockResolvedValue([]);
        (m as any).create.mockResolvedValue({});
        (m as any).update.mockResolvedValue({});
        (m as any).upsert.mockResolvedValue({});
        (m as any).count.mockResolvedValue(0);
        (m as any).delete.mockResolvedValue({});
        (m as any).deleteMany.mockResolvedValue({ count: 0 });
      }
    }

    emitter = { append: jest.fn().mockResolvedValue('event-id') };
    membership = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1', role: 'member' }),
      requireAdmin: jest.fn().mockResolvedValue({ id: 'm_1', role: 'admin' }),
      requireRole: jest.fn().mockResolvedValue({ id: 'm_1', role: 'member' }),
      getElderUserIds: jest.fn().mockResolvedValue([]),
      getActiveMemberUserIds: jest.fn().mockResolvedValue(['u1', 'u2', 'u3']),
    };
    constitutionService = {
      commitAmendment: jest.fn().mockResolvedValue({ id: 'v_new' }),
      discardDraft: jest.fn().mockResolvedValue(undefined),
    };

    service = new DecisionsService(
      prisma as any,
      emitter as any,
      membership as any,
      constitutionService as any,
    );
  });

  // ── Helpers ──────────────────────────────────────────────────────────
  function buildDecision(overrides: Partial<any> = {}): any {
    return {
      id: 'd_1',
      familyId: 'fam_1',
      createdById: 'u_admin',
      title: 'Test decision',
      description: null,
      type: 'simple_vote',
      status: 'open',
      lifecycleState: null,
      options: ['yes', 'no'],
      eligibleUserIds: ['u1', 'u2', 'u3'],
      quorumPct: 50,
      showVotesLive: false,
      deadlineAt: new Date(Date.now() + 86_400_000),
      resolvedAt: null,
      outcome: null,
      constitutionVersionId: null,
      votes: [],
      memory: null,
      impacts: [],
      ...overrides,
    };
  }

  // ── resolve() ────────────────────────────────────────────────────────
  describe('resolve()', () => {
    it('happy path: status open → resolved, outcome computed from votes', async () => {
      // 3 eligible, 3 votes yes → simple_vote majority → approved
      const decision = buildDecision({
        eligibleUserIds: ['u1', 'u2', 'u3'],
        votes: [
          { option: 'yes' },
          { option: 'yes' },
          { option: 'yes' },
        ],
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      const updatedRow = { ...decision, status: 'resolved', outcome: 'approved' };
      prisma.familyDecision.update.mockResolvedValueOnce(updatedRow);

      const result = await service.resolve('fam_1', 'd_1', 'u_admin', 'note');

      expect(result.status).toBe('resolved');
      expect(result.outcome).toBe('approved');
      // Verify the update was called with status=resolved and the right outcome
      expect(prisma.familyDecision.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id_familyId: { id: 'd_1', familyId: 'fam_1' } },
          data: expect.objectContaining({
            status: 'resolved',
            outcome: 'approved',
            lifecycleState: 'planned',
          }),
        }),
      );
      // Verify timeline event emitted
      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          kind: 'decision_resolved',
          targetEntityId: 'd_1',
        }),
      );
      // Not a constitution_amend → commitAmendment should NOT be called
      expect(constitutionService.commitAmendment).not.toHaveBeenCalled();
      expect(constitutionService.discardDraft).not.toHaveBeenCalled();
    });

    it('is idempotent when decision is already resolved', async () => {
      const decision = buildDecision({ status: 'resolved', outcome: 'approved' });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);

      const result = await service.resolve('fam_1', 'd_1', 'u_admin');

      expect(result).toBe(decision);
      expect(prisma.familyDecision.update).not.toHaveBeenCalled();
      expect(emitter.append).not.toHaveBeenCalled();
    });

    it('rejects with ConflictException when decision is cancelled', async () => {
      const decision = buildDecision({ status: 'cancelled' });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);

      await expect(service.resolve('fam_1', 'd_1', 'u_admin')).rejects.toThrow(
        ConflictException,
      );
    });

    it('rejects with ConflictException when decision is expired', async () => {
      const decision = buildDecision({ status: 'expired' });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);

      await expect(service.resolve('fam_1', 'd_1', 'u_admin')).rejects.toThrow(
        ConflictException,
      );
    });

    it('calls commitAmendment() when type=constitution_amend and outcome=approved', async () => {
      const decision = buildDecision({
        type: 'constitution_amend',
        eligibleUserIds: ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8', 'u9', 'u10'],
        options: ['approve', 'reject'],
        quorumPct: 67,
        constitutionVersionId: 'ver_current',
        votes: Array.from({ length: 7 }, () => ({ option: 'approve' })),
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      prisma.familyDecision.update.mockResolvedValueOnce({
        ...decision,
        status: 'resolved',
        outcome: 'approved',
      });

      await service.resolve('fam_1', 'd_1', 'u_admin');

      expect(constitutionService.commitAmendment).toHaveBeenCalledWith(
        'fam_1',
        'ver_current',
        'u_admin',
        expect.anything(), // tx (the prisma client itself, since $transaction runs the callback synchronously)
        'd_1',
      );
      expect(constitutionService.discardDraft).not.toHaveBeenCalled();
    });

    it('calls discardDraft() when type=constitution_amend and outcome=rejected', async () => {
      const decision = buildDecision({
        type: 'constitution_amend',
        eligibleUserIds: ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8', 'u9', 'u10'],
        options: ['approve', 'reject'],
        quorumPct: 67,
        constitutionVersionId: 'ver_current',
        // 7 votes total (quorum met), 4 approve / 3 reject → topCount=4 < 7 supermajority → rejected
        votes: [
          { option: 'approve' },
          { option: 'approve' },
          { option: 'approve' },
          { option: 'approve' },
          { option: 'reject' },
          { option: 'reject' },
          { option: 'reject' },
        ],
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      prisma.familyDecision.update.mockResolvedValueOnce({
        ...decision,
        status: 'resolved',
        outcome: 'rejected',
      });

      await service.resolve('fam_1', 'd_1', 'u_admin');

      expect(constitutionService.discardDraft).toHaveBeenCalledWith(
        'fam_1',
        'u_admin',
        expect.anything(), // tx
      );
      expect(constitutionService.commitAmendment).not.toHaveBeenCalled();
    });

    it('falls through to expireInternal() when quorum is not met (no_quorum outcome)', async () => {
      // 3 eligible, quorumPct=50 → requires 2 votes. 0 votes → no_quorum
      const decision = buildDecision({
        eligibleUserIds: ['u1', 'u2', 'u3'],
        votes: [],
        quorumPct: 50,
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      prisma.familyDecision.update.mockResolvedValueOnce({
        ...decision,
        status: 'expired',
        resolvedAt: new Date(),
      });

      const result = await service.resolve('fam_1', 'd_1', 'u_admin');

      // The result of expireInternal is the updated row, status=expired
      expect(result.status).toBe('expired');
      // The update should have set status='expired' (not 'resolved')
      expect(prisma.familyDecision.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'expired' }),
        }),
      );
      // decision_expired event should be emitted (not decision_resolved)
      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          kind: 'decision_expired',
        }),
      );
    });
  });

  // ── vote() ───────────────────────────────────────────────────────────
  describe('vote()', () => {
    it('rejects duplicate votes with ConflictException (P2002)', async () => {
      const decision = buildDecision({
        eligibleUserIds: ['u1', 'u2', 'u3'],
        deadlineAt: new Date(Date.now() + 86_400_000),
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      // Simulate the unique constraint violation Prisma throws
      const p2002 = Object.assign(new Error('Unique constraint failed'), {
        code: 'P2002',
      });
      prisma.decisionVote.create.mockRejectedValueOnce(p2002);

      await expect(
        service.vote('fam_1', 'd_1', 'u1', 'yes'),
      ).rejects.toThrow(ConflictException);
    });

    it('rejects ineligible voters with ForbiddenException', async () => {
      const decision = buildDecision({
        eligibleUserIds: ['u1', 'u2'], // u3 is NOT eligible
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);

      await expect(
        service.vote('fam_1', 'd_1', 'u3', 'yes'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('rejects vote when decision is not open (already resolved)', async () => {
      const decision = buildDecision({ status: 'resolved' });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);

      await expect(
        service.vote('fam_1', 'd_1', 'u1', 'yes'),
      ).rejects.toThrow(ConflictException);
    });

    it('rejects vote with an invalid option', async () => {
      const decision = buildDecision({
        eligibleUserIds: ['u1', 'u2'],
        options: ['yes', 'no'],
        deadlineAt: new Date(Date.now() + 86_400_000),
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);

      await expect(
        service.vote('fam_1', 'd_1', 'u1', 'maybe'),
      ).rejects.toThrow(BadRequestException);
    });
  });

  // ── autoExpireIfPastDeadline() ───────────────────────────────────────
  describe('autoExpireIfPastDeadline()', () => {
    it('skips non-open decisions (returns false)', async () => {
      const decision = buildDecision({ status: 'resolved' });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);

      const result = await service.autoExpireIfPastDeadline('fam_1', 'd_1');
      expect(result).toBe(false);
      expect(prisma.familyDecision.update).not.toHaveBeenCalled();
    });

    it('skips decisions whose deadline has not passed (returns false)', async () => {
      const decision = buildDecision({
        status: 'open',
        deadlineAt: new Date(Date.now() + 86_400_000), // 24h in future
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);

      const result = await service.autoExpireIfPastDeadline('fam_1', 'd_1');
      expect(result).toBe(false);
      expect(prisma.familyDecision.update).not.toHaveBeenCalled();
    });

    it('calls discardDraft() for constitution_amend type when expiring', async () => {
      const decision = buildDecision({
        type: 'constitution_amend',
        status: 'open',
        deadlineAt: new Date(Date.now() - 1000), // past
        constitutionVersionId: 'ver_current',
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      prisma.familyDecision.update.mockResolvedValueOnce({
        ...decision,
        status: 'expired',
      });

      const result = await service.autoExpireIfPastDeadline('fam_1', 'd_1');
      expect(result).toBe(true);
      // discardDraft should be called because type is constitution_amend
      expect(constitutionService.discardDraft).toHaveBeenCalledWith(
        'fam_1',
        null, // actorId is null for auto-expire path
        expect.anything(), // tx
      );
      // Update should set status='expired'
      expect(prisma.familyDecision.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'expired' }),
        }),
      );
    });

    it('expires a simple_vote decision without touching constitution service', async () => {
      const decision = buildDecision({
        type: 'simple_vote',
        status: 'open',
        deadlineAt: new Date(Date.now() - 1000),
      });
      prisma.familyDecision.findUnique.mockResolvedValueOnce(decision);
      prisma.familyDecision.update.mockResolvedValueOnce({
        ...decision,
        status: 'expired',
      });

      const result = await service.autoExpireIfPastDeadline('fam_1', 'd_1');
      expect(result).toBe(true);
      expect(constitutionService.discardDraft).not.toHaveBeenCalled();
      expect(constitutionService.commitAmendment).not.toHaveBeenCalled();
    });
  });

  // ── create() ─────────────────────────────────────────────────────────
  describe('create()', () => {
    function baseInput(): CreateDecisionInput {
      return {
        title: 'My decision',
        type: 'simple_vote',
        options: ['yes', 'no'],
        deadlineAt: new Date(Date.now() + 86_400_000).toISOString(),
      };
    }

    it('rejects empty title', async () => {
      await expect(
        service.create('fam_1', 'u_admin', { ...baseInput(), title: '   ' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects empty options array', async () => {
      await expect(
        service.create('fam_1', 'u_admin', { ...baseInput(), options: [] }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects elder_council with no elders defined', async () => {
      membership.getElderUserIds.mockResolvedValueOnce([]);

      await expect(
        service.create('fam_1', 'u_admin', { ...baseInput(), type: 'elder_council' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects deadline in the past', async () => {
      await expect(
        service.create('fam_1', 'u_admin', {
          ...baseInput(),
          deadlineAt: new Date(Date.now() - 1000).toISOString(),
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('creates a decision and emits decision_created event', async () => {
      const created = { id: 'd_new', ...baseInput(), deadlineAt: new Date(baseInput().deadlineAt) };
      prisma.familyDecision.create.mockResolvedValueOnce(created);

      const result = await service.create('fam_1', 'u_admin', baseInput());

      expect(result.id).toBe('d_new');
      expect(prisma.familyDecision.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            familyId: 'fam_1',
            createdById: 'u_admin',
            title: 'My decision',
            type: 'simple_vote',
            status: 'open',
          }),
        }),
      );
      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          kind: 'decision_created',
          targetEntityType: 'FamilyDecision',
        }),
      );
    });
  });
});
