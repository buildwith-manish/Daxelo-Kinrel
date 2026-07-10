// =============================================================================
// Track C v2.0 — Secretary Visibility Tests
// =============================================================================
// Tests:
//   - Draft minutes visible only to participants + admins
//   - Published minutes with visibility='family' visible to all members
//   - Published minutes with visibility='participants_only' restricted
//   - Create restricted to non-viewer, non-minor (requireCanAct)
// Covers matrix requirement #6.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { TimelineEmitter } from '../governance-timeline/timeline.emitter';
import { FamilyMembershipService } from '../common/family-membership.service';
import { VisibilityService } from '../common/visibility.service';
import { SecretaryService, CreateArtifactInput } from './secretary.service';
import { RedactionService } from '../kinrel-intelligence/redaction';
import { ActionItemsKind } from '../kinrel-intelligence/kinds/action-items.kind';
import { LLMProvider } from '../kinrel-intelligence/llm-provider';
import { ForbiddenException, NotFoundException } from '@nestjs/common';

describe('SecretaryService — visibility matrix', () => {
  let prisma: any;
  let emitter: any;
  let membership: any;
  let visibility: any;
  let redaction: RedactionService;
  let actionItemsKind: ActionItemsKind;
  let llm: jest.Mocked<LLMProvider>;
  let service: SecretaryService;

  beforeEach(() => {
    prisma = new PrismaService();
    for (const m of Object.values(prisma) as any[]) {
      if (m && typeof m === 'object' && 'findUnique' in m) {
        (m as any).findUnique.mockResolvedValue(null);
        (m as any).findMany.mockResolvedValue([]);
        (m as any).create.mockResolvedValue({});
        (m as any).update.mockResolvedValue({});
        (m as any).count.mockResolvedValue(0);
      }
    }
    emitter = { append: jest.fn().mockResolvedValue('event-id') };
    membership = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1', role: 'member' }),
      requireAdmin: jest.fn().mockResolvedValue({ id: 'm_1', role: 'admin' }),
    };
    visibility = {
      requireCanAct: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      }),
      requireMemberWithAge: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      }),
      requireAdminDataAccess: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'admin', isMinor: false, isAdmin: true, canAct: true,
      }),
    };
    redaction = new RedactionService();
    actionItemsKind = new ActionItemsKind(redaction);
    llm = {
      generate: jest.fn().mockResolvedValue({
        modelId: 'mock', content: JSON.stringify({ actionItems: [] }),
        tokensIn: 100, tokensOut: 50, costUsd: 0, latencyMs: 10,
      }),
      providerName: 'mock',
      getUsageStats: jest.fn().mockReturnValue({}),
    } as any;

    service = new SecretaryService(
      prisma as any, emitter as any, membership as any, visibility as any,
      redaction, actionItemsKind, llm as any,
    );
  });

  // ── Test: draft minutes visible only to participants + admins ────────
  describe('list — draft visibility', () => {
    it('admin sees all artifacts (including drafts)', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'admin', isMinor: false, isAdmin: true, canAct: true,
      });
      prisma.meetingArtifact.findMany.mockResolvedValue([
        { id: 'a1', familyId: 'fam_1', status: 'draft', participants: ['u_other'], visibility: 'family' },
        { id: 'a2', familyId: 'fam_1', status: 'published', participants: [], visibility: 'family' },
      ]);

      const result = await service.list('fam_1', 'u_admin', {});
      expect(result).toHaveLength(2);
    });

    it('non-admin participant sees drafts they are part of', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      });
      prisma.meetingArtifact.findMany.mockResolvedValue([
        { id: 'a1', familyId: 'fam_1', status: 'draft', participants: ['u_member'], visibility: 'family' },
        { id: 'a2', familyId: 'fam_1', status: 'draft', participants: ['u_other'], visibility: 'family' },
      ]);

      const result = await service.list('fam_1', 'u_member', {});
      // Should only see a1 (where they are a participant)
      expect(result).toHaveLength(1);
      expect(result[0].id).toBe('a1');
    });

    it('non-admin non-participant does NOT see drafts', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      });
      prisma.meetingArtifact.findMany.mockResolvedValue([
        { id: 'a1', familyId: 'fam_1', status: 'draft', participants: ['u_other'], visibility: 'family' },
      ]);

      const result = await service.list('fam_1', 'u_member', {});
      expect(result).toHaveLength(0);
    });
  });

  // ── Test: published 'family' visible to all ──────────────────────────
  describe('list — published family visibility', () => {
    it('non-admin sees published family-visibility artifacts', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      });
      prisma.meetingArtifact.findMany.mockResolvedValue([
        { id: 'a1', familyId: 'fam_1', status: 'published', participants: ['u_other'], visibility: 'family' },
      ]);

      const result = await service.list('fam_1', 'u_member', {});
      expect(result).toHaveLength(1);
    });

    it('minor sees published family-visibility artifacts', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: true, isAdmin: false, canAct: false,
      });
      prisma.meetingArtifact.findMany.mockResolvedValue([
        { id: 'a1', familyId: 'fam_1', status: 'published', participants: [], visibility: 'family' },
      ]);

      const result = await service.list('fam_1', 'u_minor', {});
      expect(result).toHaveLength(1);
    });
  });

  // ── Test: published 'participants_only' restricted ───────────────────
  describe('list — published participants_only visibility', () => {
    it('non-admin participant sees published participants_only artifacts', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      });
      prisma.meetingArtifact.findMany.mockResolvedValue([
        { id: 'a1', familyId: 'fam_1', status: 'published', participants: ['u_member'], visibility: 'participants_only' },
      ]);

      const result = await service.list('fam_1', 'u_member', {});
      expect(result).toHaveLength(1);
    });

    it('non-admin non-participant does NOT see published participants_only artifacts', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      });
      prisma.meetingArtifact.findMany.mockResolvedValue([
        { id: 'a1', familyId: 'fam_1', status: 'published', participants: ['u_other'], visibility: 'participants_only' },
      ]);

      const result = await service.list('fam_1', 'u_member', {});
      expect(result).toHaveLength(0);
    });

    it('admin sees published participants_only artifacts regardless of participation', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'admin', isMinor: false, isAdmin: true, canAct: true,
      });
      prisma.meetingArtifact.findMany.mockResolvedValue([
        { id: 'a1', familyId: 'fam_1', status: 'published', participants: ['u_other'], visibility: 'participants_only' },
      ]);

      const result = await service.list('fam_1', 'u_admin', {});
      expect(result).toHaveLength(1);
    });
  });

  // ── Test: getOne enforces visibility ─────────────────────────────────
  describe('getOne — visibility enforced', () => {
    it('throws ForbiddenException for non-participant on a draft', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      });
      prisma.meetingArtifact.findUnique.mockResolvedValue({
        id: 'a1', familyId: 'fam_1', status: 'draft', participants: ['u_other'], visibility: 'family',
      });

      await expect(service.getOne('fam_1', 'a1', 'u_member')).rejects.toThrow(ForbiddenException);
    });

    it('allows participant to view a draft', async () => {
      visibility.requireMemberWithAge.mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      });
      prisma.meetingArtifact.findUnique.mockResolvedValue({
        id: 'a1', familyId: 'fam_1', status: 'draft', participants: ['u_member'], visibility: 'family',
      });

      const result = await service.getOne('fam_1', 'a1', 'u_member');
      expect(result.id).toBe('a1');
    });
  });

  // ── Test: create restricted to non-viewer, non-minor ─────────────────
  describe('create — requireCanAct', () => {
    it('throws ForbiddenException for a viewer', async () => {
      visibility.requireCanAct.mockRejectedValue(
        new ForbiddenException('Viewers cannot perform this action'),
      );

      const input: CreateArtifactInput = {
        title: 'Test Meeting',
        heldAt: new Date().toISOString(),
        participants: ['u1'],
        agenda: ['Item 1'],
        discussionPoints: [],
        decisions: [],
      };

      await expect(service.create('fam_1', 'u_viewer', input)).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException for a minor', async () => {
      visibility.requireCanAct.mockRejectedValue(
        new ForbiddenException('Family members under 18 cannot perform this governance action.'),
      );

      const input: CreateArtifactInput = {
        title: 'Test Meeting',
        heldAt: new Date().toISOString(),
        participants: ['u1'],
        agenda: ['Item 1'],
        discussionPoints: [],
        decisions: [],
      };

      await expect(service.create('fam_1', 'u_minor', input)).rejects.toThrow(ForbiddenException);
    });
  });

  // ── Test: create defaults visibility to 'family' ─────────────────────
  describe('create — visibility default', () => {
    it('defaults visibility to family when not specified', async () => {
      prisma.meetingArtifact.create.mockResolvedValue({
        id: 'a1', visibility: 'family', status: 'draft',
      });

      const input: CreateArtifactInput = {
        title: 'Test Meeting',
        heldAt: new Date().toISOString(),
        participants: ['u1'],
        agenda: ['Item 1'],
        discussionPoints: [],
        decisions: [],
        // visibility not specified → should default to 'family'
      };

      await service.create('fam_1', 'u_member', input);

      const createCall = prisma.meetingArtifact.create.mock.calls[0][0];
      expect(createCall.data.visibility).toBe('family');
    });

    it('honors participants_only visibility when specified', async () => {
      prisma.meetingArtifact.create.mockResolvedValue({
        id: 'a1', visibility: 'participants_only', status: 'draft',
      });

      const input: CreateArtifactInput = {
        title: 'Private Meeting',
        heldAt: new Date().toISOString(),
        participants: ['u1', 'u2'],
        agenda: ['Item 1'],
        discussionPoints: [],
        decisions: [],
        visibility: 'participants_only',
      };

      await service.create('fam_1', 'u_member', input);

      const createCall = prisma.meetingArtifact.create.mock.calls[0][0];
      expect(createCall.data.visibility).toBe('participants_only');
    });
  });
});
