// =============================================================================
// Track C v2.0 — Visibility Service Tests
// =============================================================================
// Tests the pure isMinorUser helper + the VisibilityService guard methods.
// Covers the 4 required test cases from the matrix:
//   1. Minor blocked from voting (requireCanAct throws for minor)
//   2. Viewer blocked from editing constitution (requireCanAct throws for viewer)
//   3. Non-admin blocked from raw timeline (requireAdminDataAccess throws)
//   4. Non-admin blocked from raw learning profile (requireAdminDataAccess throws)
// =============================================================================

import {
  isMinorUser,
  canActByRole,
  isAdminRole,
  isViewerRole,
  MINOR_AGE_THRESHOLD,
  VisibilityService,
} from './visibility.service';
import { ForbiddenException, NotFoundException } from '@nestjs/common';

describe('isMinorUser (pure helper)', () => {
  it('returns false for null dateOfBirth (fail-open)', () => {
    expect(isMinorUser(null)).toBe(false);
  });

  it('returns false for undefined dateOfBirth (fail-open)', () => {
    expect(isMinorUser(undefined)).toBe(false);
  });

  it('returns false for invalid date string (fail-open)', () => {
    expect(isMinorUser(new Date('not-a-date'))).toBe(false);
  });

  it('returns true for a date 10 years ago', () => {
    const dob = new Date();
    dob.setFullYear(dob.getFullYear() - 10);
    expect(isMinorUser(dob)).toBe(true);
  });

  it('returns false for a date 18 years ago (exactly 18 = adult)', () => {
    const dob = new Date();
    dob.setFullYear(dob.getFullYear() - 18);
    expect(isMinorUser(dob)).toBe(false);
  });

  it('returns false for a date 25 years ago', () => {
    const dob = new Date();
    dob.setFullYear(dob.getFullYear() - 25);
    expect(isMinorUser(dob)).toBe(false);
  });

  it('returns true for a date 17 years ago (just under 18)', () => {
    const dob = new Date();
    dob.setFullYear(dob.getFullYear() - 17);
    expect(isMinorUser(dob)).toBe(true);
  });

  it('handles birthday today (edge case: turns 18 today)', () => {
    const dob = new Date();
    dob.setFullYear(dob.getFullYear() - 18);
    // Same month, same day → age is exactly 18 → not a minor
    expect(isMinorUser(dob)).toBe(false);
  });

  it('MINOR_AGE_THRESHOLD is 18', () => {
    expect(MINOR_AGE_THRESHOLD).toBe(18);
  });
});

describe('Role helper functions', () => {
  it('canActByRole returns true for owner, admin, elder, member', () => {
    expect(canActByRole('owner')).toBe(true);
    expect(canActByRole('admin')).toBe(true);
    expect(canActByRole('elder')).toBe(true);
    expect(canActByRole('member')).toBe(true);
  });

  it('canActByRole returns false for viewer', () => {
    expect(canActByRole('viewer')).toBe(false);
  });

  it('isAdminRole returns true for owner, admin', () => {
    expect(isAdminRole('owner')).toBe(true);
    expect(isAdminRole('admin')).toBe(true);
  });

  it('isAdminRole returns false for elder, member, viewer', () => {
    expect(isAdminRole('elder')).toBe(false);
    expect(isAdminRole('member')).toBe(false);
    expect(isAdminRole('viewer')).toBe(false);
  });

  it('isViewerRole returns true only for viewer', () => {
    expect(isViewerRole('viewer')).toBe(true);
    expect(isViewerRole('member')).toBe(false);
    expect(isViewerRole('admin')).toBe(false);
  });
});

describe('VisibilityService', () => {
  let prisma: any;
  let membership: any;
  let service: VisibilityService;

  beforeEach(() => {
    prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue(null), // null DOB = adult by default
      },
    };
    membership = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1', familyId: 'fam_1', userId: 'u_1', role: 'member' }),
      requireRole: jest.fn(),
      requireAdmin: jest.fn(),
      getElderUserIds: jest.fn(),
      getActiveMemberUserIds: jest.fn(),
    };
    service = new VisibilityService(prisma, membership);
  });

  // ── Test 1: Minor blocked from voting (requireCanAct) ────────────────
  describe('requireCanAct — minor blocked', () => {
    it('throws ForbiddenException for a minor (age 15) even with member role', async () => {
      // membership returns a member role
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_minor', role: 'member',
      });
      // user.dateOfBirth = 15 years ago
      const dob = new Date();
      dob.setFullYear(dob.getFullYear() - 15);
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: dob });

      await expect(service.requireCanAct('u_minor', 'fam_1')).rejects.toThrow(ForbiddenException);
      await expect(service.requireCanAct('u_minor', 'fam_1')).rejects.toThrow(
        /under 18/,
      );
    });

    it('allows an adult member (age 25)', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_adult', role: 'member',
      });
      const dob = new Date();
      dob.setFullYear(dob.getFullYear() - 25);
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: dob });

      const ctx = await service.requireCanAct('u_adult', 'fam_1');
      expect(ctx.canAct).toBe(true);
      expect(ctx.isMinor).toBe(false);
    });
  });

  // ── Test 2: Viewer blocked from editing constitution (requireCanAct) ─
  describe('requireCanAct — viewer blocked', () => {
    it('throws ForbiddenException for a viewer (even adult)', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_viewer', role: 'viewer',
      });
      const dob = new Date();
      dob.setFullYear(dob.getFullYear() - 30);
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: dob });

      await expect(service.requireCanAct('u_viewer', 'fam_1')).rejects.toThrow(ForbiddenException);
      await expect(service.requireCanAct('u_viewer', 'fam_1')).rejects.toThrow(
        /Viewers cannot/,
      );
    });

    it('allows an adult admin', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_admin', role: 'admin',
      });
      const dob = new Date();
      dob.setFullYear(dob.getFullYear() - 40);
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: dob });

      const ctx = await service.requireCanAct('u_admin', 'fam_1');
      expect(ctx.canAct).toBe(true);
      expect(ctx.isAdmin).toBe(true);
    });
  });

  // ── Test 3: Non-admin blocked from raw timeline (requireAdminDataAccess) ─
  describe('requireAdminDataAccess — non-admin blocked', () => {
    it('throws ForbiddenException for a member (non-admin)', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_member', role: 'member',
      });
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: null });

      await expect(service.requireAdminDataAccess('u_member', 'fam_1')).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('throws ForbiddenException for an elder (non-admin)', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_elder', role: 'elder',
      });
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: null });

      await expect(service.requireAdminDataAccess('u_elder', 'fam_1')).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('allows an owner', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_owner', role: 'owner',
      });
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: null });

      const ctx = await service.requireAdminDataAccess('u_owner', 'fam_1');
      expect(ctx.isAdmin).toBe(true);
    });

    it('allows an admin', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_admin', role: 'admin',
      });
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: null });

      const ctx = await service.requireAdminDataAccess('u_admin', 'fam_1');
      expect(ctx.isAdmin).toBe(true);
    });
  });

  // ── Test 4: Non-admin blocked from raw learning profile ─────────────
  // (same guard as test 3 — requireAdminDataAccess — but tested via the
  //  LearningService.getProfile path in learning.service.spec.ts)

  // ── Test: null DOB is fail-open (treated as adult) ──────────────────
  describe('requireMemberWithAge — null DOB fail-open', () => {
    it('treats null dateOfBirth as adult (isMinor=false, canAct=true for member)', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_1', role: 'member',
      });
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: null });

      const ctx = await service.requireMemberWithAge('u_1', 'fam_1');
      expect(ctx.isMinor).toBe(false);
      expect(ctx.canAct).toBe(true);
    });

    it('treats missing user row as adult (dateOfBirth=null)', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_1', role: 'member',
      });
      prisma.user.findUnique.mockResolvedValue(null);

      const ctx = await service.requireMemberWithAge('u_1', 'fam_1');
      expect(ctx.isMinor).toBe(false);
      expect(ctx.canAct).toBe(true);
    });
  });

  // ── Test: non-member gets NotFoundException ─────────────────────────
  describe('requireMemberWithAge — non-member', () => {
    it('throws NotFoundException if not a family member', async () => {
      membership.requireMember.mockRejectedValue(new NotFoundException('Family not found'));

      await expect(service.requireMemberWithAge('u_stranger', 'fam_1')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  // ── Test: admin who is a minor (edge case) ──────────────────────────
  describe('admin who is a minor', () => {
    it('canAct is false (minor blocked) even though isAdmin is true', async () => {
      membership.requireMember.mockResolvedValue({
        id: 'm_1', familyId: 'fam_1', userId: 'u_teen_admin', role: 'admin',
      });
      const dob = new Date();
      dob.setFullYear(dob.getFullYear() - 16);
      prisma.user.findUnique.mockResolvedValue({ dateOfBirth: dob });

      const ctx = await service.requireMemberWithAge('u_teen_admin', 'fam_1');
      expect(ctx.role).toBe('admin');
      expect(ctx.isAdmin).toBe(true);
      expect(ctx.isMinor).toBe(true);
      expect(ctx.canAct).toBe(false); // minor blocked from acting

      // But can still access admin data (isAdmin is true)
      // This is intentional: a teen admin can VIEW raw timeline/learning
      // but cannot vote/create (the action restriction is about capacity,
      // not trust).
    });
  });
});
