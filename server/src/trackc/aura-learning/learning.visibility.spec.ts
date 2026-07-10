// =============================================================================
// Track C v2.0 — Learning Visibility Tests
// =============================================================================
// Tests:
//   - Non-admin blocked from raw learning profile (getProfile)
//   - All members (including minors) can access getProfileSummary
//   - getProfileSummary returns a plain-language sentence, never raw fields
// Covers matrix requirement #5.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { TimelineEmitter } from '../governance-timeline/timeline.emitter';
import { FamilyMembershipService } from '../common/family-membership.service';
import { VisibilityService } from '../common/visibility.service';
import { LearningService } from './learning.service';
import { SignalIngestor } from './learning.signal-ingestor';
import { ProfileBuilder } from './learning.profile-builder';
import { LearningInference } from './learning.inference';
import { ForbiddenException } from '@nestjs/common';

describe('LearningService — visibility matrix', () => {
  let prisma: any;
  let emitter: any;
  let membership: any;
  let visibility: any;
  let signalIngestor: any;
  let profileBuilder: any;
  let inference: any;
  let service: LearningService;

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
    };
    visibility = {
      requireAdminDataAccess: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'admin', isMinor: false, isAdmin: true, canAct: true,
      }),
      requireMemberWithAge: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      }),
      requireCanAct: jest.fn().mockResolvedValue({
        id: 'm_1', role: 'member', isMinor: false, isAdmin: false, canAct: true,
      }),
    };
    signalIngestor = { ingest: jest.fn().mockResolvedValue({ id: 'sig_1' }) };
    profileBuilder = { recompute: jest.fn().mockResolvedValue({}) };
    inference = {
      getProfile: jest.fn().mockResolvedValue({
        familyId: 'fam_1',
        confidenceScore: 0.7,
        sampleSize: 50,
        version: 3,
        usingDefaults: false,
        preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 },
        reminderActionRate: { '6h': 0.3, '12h': 0.5, '24h': 0.8 },
        preferredWeekdayDistribution: { mon: 0.1, tue: 0.1, wed: 0.1, thu: 0.1, fri: 0.1, sat: 0.25, sun: 0.25 },
        preferredTimeOfDayBuckets: { morning: 0.2, afternoon: 0.2, evening: 0.5, night: 0.1 },
        elderAutoIncludeThreshold: 0.6,
        insightAcceptRateByKind: { summary: 0.7, pros_cons: 0.5 },
        averageDecisionDurationHours: 72,
        typicalQuorumMet: true,
        computedAt: new Date(),
      }),
    };

    service = new LearningService(
      prisma, emitter, membership, visibility,
      signalIngestor, profileBuilder, inference,
    );
  });

  // ── Test 4: Non-admin blocked from raw learning profile ─────────────
  describe('getProfile — admin-only', () => {
    it('throws ForbiddenException for a non-admin member', async () => {
      visibility.requireAdminDataAccess.mockRejectedValue(
        new ForbiddenException('This data is only available to family admins and owners.'),
      );

      await expect(service.getProfile('fam_1', 'u_member')).rejects.toThrow(ForbiddenException);
      expect(visibility.requireAdminDataAccess).toHaveBeenCalledWith('u_member', 'fam_1');
    });

    it('succeeds for an admin and returns raw profile', async () => {
      const result = await service.getProfile('fam_1', 'u_admin');
      expect(result.confidenceScore).toBe(0.7);
      expect(result.preferredWeekdayDistribution).toBeDefined();
      expect(result.insightAcceptRateByKind).toBeDefined();
      // Raw fields are present for admin
      expect(result).toHaveProperty('elderAutoIncludeThreshold');
      expect(result).toHaveProperty('reminderActionRate');
    });

    it('succeeds for an owner', async () => {
      visibility.requireAdminDataAccess.mockResolvedValue({
        id: 'm_1', role: 'owner', isMinor: false, isAdmin: true, canAct: true,
      });
      const result = await service.getProfile('fam_1', 'u_owner');
      expect(result).toBeDefined();
    });
  });

  // ── Test: getProfileSummary available to all members ────────────────
  describe('getProfileSummary — all members', () => {
    it('succeeds for a regular member', async () => {
      const result = await service.getProfileSummary('fam_1', 'u_member');
      expect(result.familyId).toBe('fam_1');
      expect(result.summary).toBeDefined();
      expect(typeof result.summary).toBe('string');
      expect(result.summary.length).toBeGreaterThan(0);
    });

    it('succeeds for a viewer', async () => {
      membership.requireMember.mockResolvedValue({ id: 'm_1', role: 'viewer' });
      const result = await service.getProfileSummary('fam_1', 'u_viewer');
      expect(result.summary).toBeDefined();
    });

    it('succeeds for a minor (member under 18)', async () => {
      membership.requireMember.mockResolvedValue({ id: 'm_1', role: 'member' });
      const result = await service.getProfileSummary('fam_1', 'u_minor');
      expect(result.summary).toBeDefined();
    });

    it('returns a plain-language summary, never raw signal fields', async () => {
      const result = await service.getProfileSummary('fam_1', 'u_member');
      // The summary should be a natural-language sentence
      expect(result.summary).toContain('Kinrel');
      // Should NOT contain raw JSON field names
      expect(result.summary).not.toContain('elderAutoIncludeThreshold');
      expect(result.summary).not.toContain('preferredWeekdayDistribution');
      expect(result.summary).not.toContain('reminderActionRate');
      expect(result.summary).not.toContain('insightAcceptRateByKind');
      // Should NOT contain raw numeric values from the profile
      expect(result.summary).not.toContain('0.6'); // elderAutoIncludeThreshold value
      expect(result.summary).not.toContain('0.7'); // confidenceScore value
    });

    it('returns confidenceScore and sampleSize (safe aggregate metrics)', async () => {
      const result = await service.getProfileSummary('fam_1', 'u_member');
      expect(result.confidenceScore).toBe(0.7);
      expect(result.sampleSize).toBe(50);
      expect(result.usingDefaults).toBe(false);
    });

    it('mentions weekends when weekend distribution is higher', async () => {
      const result = await service.getProfileSummary('fam_1', 'u_member');
      expect(result.summary.toLowerCase()).toContain('weekend');
    });

    it('mentions evenings when evening bucket is highest', async () => {
      const result = await service.getProfileSummary('fam_1', 'u_member');
      expect(result.summary.toLowerCase()).toContain('evening');
    });
  });

  // ── Test: getProfileSummary with default profile (low confidence) ───
  describe('getProfileSummary — default profile', () => {
    it('mentions "still learning" when usingDefaults is true', async () => {
      inference.getProfile.mockResolvedValue({
        familyId: 'fam_1',
        confidenceScore: 0.1,
        sampleSize: 2,
        version: 0,
        usingDefaults: true,
        preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 },
        reminderActionRate: { '6h': 0.42, '12h': 0.55, '24h': 0.71 },
        preferredWeekdayDistribution: { mon: 0.14, tue: 0.14, wed: 0.14, thu: 0.14, fri: 0.14, sat: 0.15, sun: 0.15 },
        preferredTimeOfDayBuckets: { morning: 0.25, afternoon: 0.25, evening: 0.25, night: 0.25 },
        elderAutoIncludeThreshold: 0.6,
        insightAcceptRateByKind: {},
        averageDecisionDurationHours: 72,
        typicalQuorumMet: null,
        computedAt: null,
      });

      const result = await service.getProfileSummary('fam_1', 'u_member');
      expect(result.summary.toLowerCase()).toContain('still learning');
    });
  });
});
