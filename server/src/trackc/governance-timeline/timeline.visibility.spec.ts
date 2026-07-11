// =============================================================================
// Track C v2.0 — Timeline Visibility Tests
// =============================================================================
// Tests the summary whitelist filtering + raw=true admin-only restriction.
// Covers matrix requirement #3: non-admin blocked from raw timeline.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { TimelineService } from './timeline.service';
import { TimelineEmitter } from './timeline.emitter';
import { FamilyMembershipService } from '../common/family-membership.service';
import { VisibilityService } from '../common/visibility.service';
import { TIMELINE_SUMMARY_EVENT_TYPES } from './timeline.types';
import { ForbiddenException, BadRequestException } from '@nestjs/common';

describe('TimelineService — visibility matrix', () => {
  let prisma: any;
  let emitter: any;
  let membership: any;
  let visibility: any;
  let service: TimelineService;

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
      requireMemberWithAge: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      }),
      requireAdminDataAccess: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'admin', isMinor: false, isAdmin: true, canAct: true,
      }),
      requireCanAct: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      }),
    };
    service = new TimelineService(prisma, emitter, membership, visibility);
  });

  // ── Test: default list returns only summary event types ─────────────
  it('default list (no raw) returns only summary event types', async () => {
    // Simulate DB returning events of all kinds
    prisma.kinrelTimelineEvent.findMany.mockResolvedValue([
      { id: 'e1', familyId: 'fam_1', kind: 'decision_created', occurredAt: new Date() },
      { id: 'e2', familyId: 'fam_1', kind: 'decision_voted', occurredAt: new Date() },
      { id: 'e3', familyId: 'fam_1', kind: 'decision_resolved', occurredAt: new Date() },
      { id: 'e4', familyId: 'fam_1', kind: 'member_joined', occurredAt: new Date() },
      { id: 'e5', familyId: 'fam_1', kind: 'constitution_amended', occurredAt: new Date() },
    ]);

    const result = await service.list('fam_1', { userId: 'u_member' });

    // The DB query should filter to summary kinds only
    const findManyCall = prisma.kinrelTimelineEvent.findMany.mock.calls[0][0];
    const kindsInQuery = findManyCall.where.kind?.in;
    expect(kindsInQuery).toBeDefined();
    // Every kind in the query must be in the summary whitelist
    for (const k of kindsInQuery) {
      expect(TIMELINE_SUMMARY_EVENT_TYPES.has(k)).toBe(true);
    }
    expect(result.mode).toBe('summary');
  });

  // ── Test: raw=true requires admin ───────────────────────────────────
  it('raw=true throws ForbiddenException for non-admin', async () => {
    visibility.requireAdminDataAccess.mockRejectedValue(
      new ForbiddenException('This data is only available to family admins and owners.'),
    );

    await expect(
      service.list('fam_1', { raw: true, userId: 'u_member' }),
    ).rejects.toThrow(ForbiddenException);

    expect(visibility.requireAdminDataAccess).toHaveBeenCalledWith('u_member', 'fam_1');
  });

  // ── Test: raw=true succeeds for admin ───────────────────────────────
  it('raw=true succeeds for admin and returns all event types', async () => {
    prisma.kinrelTimelineEvent.findMany.mockResolvedValue([
      { id: 'e1', familyId: 'fam_1', kind: 'decision_voted', occurredAt: new Date() },
      { id: 'e2', familyId: 'fam_1', kind: 'member_joined', occurredAt: new Date() },
    ]);

    const result = await service.list('fam_1', { raw: true, userId: 'u_admin' });

    // In raw mode, no kind filter should be applied (all kinds returned)
    const findManyCall = prisma.kinrelTimelineEvent.findMany.mock.calls[0][0];
    expect(findManyCall.where.kind).toBeUndefined();
    expect(result.mode).toBe('raw');
  });

  // ── Test: non-admin requesting a non-summary kind gets empty result ─
  it('non-admin requesting decision_voted gets filtered to empty (not in whitelist)', async () => {
    prisma.kinrelTimelineEvent.findMany.mockResolvedValue([]);

    await service.list('fam_1', {
      kind: 'decision_voted' as any,
      userId: 'u_member',
    });

    // The query should have kind: { in: [] } (filtered out)
    const findManyCall = prisma.kinrelTimelineEvent.findMany.mock.calls[0][0];
    // kinds array was filtered to empty since decision_voted is not in summary
    expect(findManyCall.where.kind?.in).toEqual([]);
  });

  // ── Test: non-admin requesting a summary kind gets it ───────────────
  it('non-admin requesting decision_created (summary kind) gets it', async () => {
    prisma.kinrelTimelineEvent.findMany.mockResolvedValue([
      { id: 'e1', familyId: 'fam_1', kind: 'decision_created', occurredAt: new Date() },
    ]);

    await service.list('fam_1', {
      kind: 'decision_created' as any,
      userId: 'u_member',
    });

    const findManyCall = prisma.kinrelTimelineEvent.findMany.mock.calls[0][0];
    expect(findManyCall.where.kind?.in).toEqual(['decision_created']);
  });

  // ── Test: getOne for non-summary event requires admin ───────────────
  it('getOne for non-summary event (decision_voted) requires admin for non-admin user', async () => {
    prisma.kinrelTimelineEvent.findUnique.mockResolvedValue({
      id: 'e1', familyId: 'fam_1', kind: 'decision_voted', occurredAt: new Date(),
    });

    visibility.requireAdminDataAccess.mockRejectedValue(
      new ForbiddenException('admin only'),
    );

    await expect(
      service.getOne('fam_1', 'e1', 'u_member'),
    ).rejects.toThrow(ForbiddenException);
  });

  // ── Test: getOne for summary event allows any member ────────────────
  it('getOne for summary event (decision_created) allows any member', async () => {
    prisma.kinrelTimelineEvent.findUnique.mockResolvedValue({
      id: 'e1', familyId: 'fam_1', kind: 'decision_created', occurredAt: new Date(),
    });

    const event = await service.getOne('fam_1', 'e1', 'u_member');
    expect(event.kind).toBe('decision_created');
    // requireAdminDataAccess should NOT have been called
    expect(visibility.requireAdminDataAccess).not.toHaveBeenCalled();
  });

  // ── Test: TIMELINE_SUMMARY_EVENT_TYPES is a whitelist (not blacklist) ─
  it('TIMELINE_SUMMARY_EVENT_TYPES contains exactly the 6 headline kinds', () => {
    expect(TIMELINE_SUMMARY_EVENT_TYPES.size).toBe(6);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('decision_created')).toBe(true);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('decision_resolved')).toBe(true);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('constitution_amended')).toBe(true);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('constitution_version_published')).toBe(true);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('constitution_created')).toBe(true);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('meeting_artifact_published')).toBe(true);

    // Non-summary kinds
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('decision_voted')).toBe(false);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('decision_expired')).toBe(false);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('member_joined')).toBe(false);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('learning_profile_reset')).toBe(false);
    expect(TIMELINE_SUMMARY_EVENT_TYPES.has('correction')).toBe(false);
  });
});
