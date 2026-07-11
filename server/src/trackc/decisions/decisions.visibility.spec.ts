// =============================================================================
// Track C v2.0 — Decisions Visibility Tests
// =============================================================================
// Tests:
//   - Minor blocked from voting (requireCanAct throws)
//   - Viewer blocked from creating a decision (requireCanAct throws)
//   - All roles (including minors/viewers) can list + getOne (view is open)
// Covers matrix requirement #2.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { TimelineEmitter } from '../governance-timeline/timeline.emitter';
import { FamilyMembershipService } from '../common/family-membership.service';
import { VisibilityService } from '../common/visibility.service';
import { DecisionsService } from './decisions.service';
import { ConstitutionService } from '../constitution/constitution.service';
import { ForbiddenException, NotFoundException } from '@nestjs/common';

describe('DecisionsService — visibility matrix', () => {
  let prisma: any;
  let emitter: any;
  let membership: any;
  let visibility: any;
  let constitutionService: any;
  let service: DecisionsService;

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
    emitter = { append: jest.fn().mockResolvedValue('event-id') };
    membership = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1', role: 'member' }),
      requireAdmin: jest.fn().mockResolvedValue({ id: 'm_1', role: 'admin' }),
      requireRole: jest.fn(),
      getElderUserIds: jest.fn().mockResolvedValue([]),
      getActiveMemberUserIds: jest.fn().mockResolvedValue(['u1', 'u2']),
    };
    visibility = {
      requireCanAct: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      }),
      requireAdminDataAccess: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'admin', isMinor: false, isAdmin: true, canAct: true,
      }),
      requireMemberWithAge: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      }),
    };
    constitutionService = {
      commitAmendment: jest.fn(),
      discardDraft: jest.fn(),
    };
    service = new DecisionsService(prisma, emitter, membership, visibility, constitutionService);
  });

  // ── Test: minor blocked from voting ──────────────────────────────────
  describe('vote — minor blocked', () => {
    it('throws ForbiddenException for a minor', async () => {
      visibility.requireCanAct.mockRejectedValue(
        new ForbiddenException('Family members under 18 cannot perform this governance action.'),
      );

      await expect(
        service.vote('fam_1', 'd_1', 'u_minor', 'approve'),
      ).rejects.toThrow(ForbiddenException);

      expect(visibility.requireCanAct).toHaveBeenCalledWith('u_minor', 'fam_1');
    });
  });

  // ── Test: viewer blocked from creating ──────────────────────────────
  describe('create — viewer blocked', () => {
    it('throws ForbiddenException for a viewer', async () => {
      visibility.requireCanAct.mockRejectedValue(
        new ForbiddenException('Viewers cannot perform this action'),
      );

      await expect(
        service.create('fam_1', 'u_viewer', {
          title: 'Test',
          type: 'simple' as any,
          options: ['yes', 'no'],
          deadlineAt: new Date(Date.now() + 86400000).toISOString(),
        }),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  // ── Test: view (list + getOne) is open to all roles ─────────────────
  describe('list — open to all members', () => {
    it('succeeds for a viewer (membership verified, no canAct check)', async () => {
      membership.requireMember.mockResolvedValue({ id: 'm_1', role: 'viewer' });
      prisma.familyDecision.findMany.mockResolvedValue([]);

      const result = await service.list('fam_1', 'u_viewer', {});
      expect(result).toBeDefined();
      expect(membership.requireMember).toHaveBeenCalledWith('u_viewer', 'fam_1');
      // requireCanAct should NOT have been called for list
      expect(visibility.requireCanAct).not.toHaveBeenCalled();
    });

    it('succeeds for a minor (membership verified, no canAct check)', async () => {
      membership.requireMember.mockResolvedValue({ id: 'm_1', role: 'member' });
      prisma.familyDecision.findMany.mockResolvedValue([]);

      const result = await service.list('fam_1', 'u_minor', {});
      expect(result).toBeDefined();
      expect(visibility.requireCanAct).not.toHaveBeenCalled();
    });
  });

  describe('getOne — open to all members', () => {
    it('succeeds for a viewer', async () => {
      membership.requireMember.mockResolvedValue({ id: 'm_1', role: 'viewer' });
      prisma.familyDecision.findUnique.mockResolvedValue({
        id: 'd_1', familyId: 'fam_1', title: 'Test', votes: [], memory: null, impacts: [],
      });

      const result = await service.getOne('fam_1', 'd_1', 'u_viewer');
      expect(result.id).toBe('d_1');
      expect(visibility.requireCanAct).not.toHaveBeenCalled();
    });
  });

  // ── Test: non-member gets NotFoundException on list ──────────────────
  describe('list — non-member blocked', () => {
    it('throws NotFoundException for a non-member', async () => {
      membership.requireMember.mockRejectedValue(new NotFoundException('Family not found'));

      await expect(service.list('fam_1', 'u_stranger', {})).rejects.toThrow(NotFoundException);
    });
  });

  // ── Test: create succeeds for an adult member ───────────────────────
  describe('create — adult member succeeds', () => {
    it('creates a decision for an adult member', async () => {
      prisma.familyDecision.create.mockResolvedValue({
        id: 'd_1', familyId: 'fam_1', title: 'Test Decision', type: 'simple',
        status: 'open', deadlineAt: new Date(),
      });

      const result = await service.create('fam_1', 'u_adult', {
        title: 'Test Decision',
        type: 'simple' as any,
        options: ['yes', 'no'],
        deadlineAt: new Date(Date.now() + 86400000).toISOString(),
      });

      expect(result.id).toBe('d_1');
      expect(visibility.requireCanAct).toHaveBeenCalledWith('u_adult', 'fam_1');
    });
  });
});
