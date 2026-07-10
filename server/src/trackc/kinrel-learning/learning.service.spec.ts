// =============================================================================
// Track C v2.0 — LearningService Tests
// =============================================================================
// Exercises ingestSignal() (membership guard + ingestor delegation),
// getProfile() (cached profile read), and resetProfile() (admin-only reset
// + learning_profile_reset timeline event).
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { LearningService } from './learning.service';
import { SignalIngestor } from './learning.signal-ingestor';
import { LearningInference } from './learning.inference';
import { ProfileBuilder } from './learning.profile-builder';
import { NotFoundException, ForbiddenException } from '@nestjs/common';

describe('LearningService', () => {
  let prisma: any;
  let emitter: any;
  let membership: any;
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
      requireRole: jest.fn().mockResolvedValue({ id: 'm_1', role: 'member' }),
      getElderUserIds: jest.fn().mockResolvedValue([]),
      getActiveMemberUserIds: jest.fn().mockResolvedValue(['u1', 'u2']),
    };
    signalIngestor = {
      ingest: jest.fn().mockResolvedValue('sig_1'),
    };
    profileBuilder = {
      recompute: jest.fn().mockResolvedValue(2),
    };
    inference = {
      getProfile: jest.fn().mockResolvedValue({
        familyId: 'fam_1',
        confidenceScore: 0.8,
        usingDefaults: false,
      }),
    };

    service = new LearningService(
      prisma as any,
      emitter as any,
      membership as any,
      signalIngestor as any,
      profileBuilder as any,
      inference as any,
    );
  });

  // ── ingestSignal() ───────────────────────────────────────────────────
  describe('ingestSignal()', () => {
    it('rejects signals from non-members', async () => {
      membership.requireMember.mockRejectedValueOnce(
        new NotFoundException('Family not found'),
      );

      await expect(
        service.ingestSignal('fam_1', 'u_outsider', {
          signalType: 'vote_pattern',
        }),
      ).rejects.toThrow(NotFoundException);

      // Ingestor must not be called when the membership check fails
      expect(signalIngestor.ingest).not.toHaveBeenCalled();
    });

    it('writes the signal through the ingestor and returns its id', async () => {
      signalIngestor.ingest.mockResolvedValueOnce('sig_xyz');

      const result = await service.ingestSignal('fam_1', 'u_1', {
        signalType: 'insight_accepted',
        targetType: 'AIInsight',
        targetId: 'ins_1',
        payload: { kind: 'decision_analysis' },
      });

      expect(result).toBe('sig_xyz');
      // Verify the ingestor was called with the familyId merged in
      expect(signalIngestor.ingest).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          signalType: 'insight_accepted',
          targetType: 'AIInsight',
          targetId: 'ins_1',
        }),
      );
    });

    it('propagates the signal through the ingestor which updates the profile asynchronously', async () => {
      // The signalIngestor is responsible for triggering the profile recompute
      // (per Section 9.2). The LearningService delegates the write to the
      // ingestor — the async profile update happens downstream.
      signalIngestor.ingest.mockResolvedValueOnce('sig_async');

      await service.ingestSignal('fam_1', 'u_1', {
        signalType: 'reminder_acted',
        targetType: 'SmartReminder',
        targetId: 'rem_1',
      });

      // The ingestor call proves the signal was persisted; the profile update
      // is async and not directly observable here, but the signal write is.
      expect(signalIngestor.ingest).toHaveBeenCalledTimes(1);
    });
  });

  // ── getProfile() ─────────────────────────────────────────────────────
  describe('getProfile()', () => {
    it('returns the cached profile from the inference layer', async () => {
      const cachedProfile = {
        familyId: 'fam_1',
        version: 3,
        confidenceScore: 0.85,
        usingDefaults: false,
        preferredReminderLeadHours: { decision: 12, meeting: 24, event: 48 },
      };
      inference.getProfile.mockResolvedValueOnce(cachedProfile);

      const result = await service.getProfile('fam_1', 'u_1');

      expect(result).toEqual(cachedProfile);
      // Must delegate to inference (sub-50ms read path)
      expect(inference.getProfile).toHaveBeenCalledWith('fam_1');
    });

    it('rejects non-members', async () => {
      membership.requireMember.mockRejectedValueOnce(
        new NotFoundException('Family not found'),
      );

      await expect(service.getProfile('fam_1', 'u_outsider')).rejects.toThrow(
        NotFoundException,
      );
      expect(inference.getProfile).not.toHaveBeenCalled();
    });
  });

  // ── resetProfile() ───────────────────────────────────────────────────
  describe('resetProfile()', () => {
    it('clears the profile and emits a learning_profile_reset event', async () => {
      const previousProfile = {
        familyId: 'fam_1',
        version: 5,
        computedAt: new Date(),
        confidenceScore: 0.7,
        preferredReminderLeadHours: { decision: 6 },
      };
      prisma.familyBehaviorProfile.findUnique.mockResolvedValueOnce(previousProfile);
      // Inside the transaction: history.create, defaults lookup, profile upsert
      prisma.globalLearningDefaults.findUnique.mockResolvedValueOnce({
        preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 },
        reminderActionRate: { '6h': 0.42, '12h': 0.55, '24h': 0.71 },
        preferredWeekdayDistribution: { mon: 0.14 },
        preferredTimeOfDayBuckets: { morning: 0.25 },
        elderAutoIncludeThreshold: 0.6,
        insightAcceptRateByKind: {},
        averageDecisionDurationHours: 72,
      });
      const resetProfile = {
        familyId: 'fam_1',
        version: 6,
        confidenceScore: 0,
        sampleSize: 0,
      };
      prisma.familyBehaviorProfile.upsert.mockResolvedValueOnce(resetProfile);

      const result = await service.resetProfile('fam_1', 'u_admin', 'user_request');

      // The reset profile should have version 6 (incremented from 5)
      expect(result.version).toBe(6);
      // History snapshot of the previous profile must be persisted
      expect(prisma.familyBehaviorProfileHistory.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            familyId: 'fam_1',
            version: 5, // the PREVIOUS version
          }),
        }),
      );
      // The timeline event must be emitted
      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          kind: 'learning_profile_reset',
          actorId: 'u_admin',
          title: 'Kinrel Learning profile reset',
        }),
      );
    });

    it('rejects non-admins from resetting the profile', async () => {
      membership.requireAdmin.mockRejectedValueOnce(
        new ForbiddenException('requires admin'),
      );

      await expect(
        service.resetProfile('fam_1', 'u_member', 'user_request'),
      ).rejects.toThrow(ForbiddenException);

      expect(prisma.familyBehaviorProfile.upsert).not.toHaveBeenCalled();
      expect(emitter.append).not.toHaveBeenCalled();
    });

    it('handles reset when no prior profile exists (creates a fresh one)', async () => {
      prisma.familyBehaviorProfile.findUnique.mockResolvedValueOnce(null);
      prisma.globalLearningDefaults.findUnique.mockResolvedValueOnce(null);
      prisma.familyBehaviorProfile.upsert.mockResolvedValueOnce({
        familyId: 'fam_1',
        version: 1, // first version
        confidenceScore: 0,
      });

      const result = await service.resetProfile('fam_1', 'u_admin', 'initial');

      expect(result.version).toBe(1);
      // No history snapshot should be taken (no previous profile)
      expect(prisma.familyBehaviorProfileHistory.create).not.toHaveBeenCalled();
      // Timeline event should still be emitted
      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          kind: 'learning_profile_reset',
        }),
      );
    });
  });
});

// =============================================================================
// Cross-check: real SignalIngestor used by LearningService — verify the
// "writes the signal" half of the contract end-to-end against the mock prisma.
// =============================================================================
describe('LearningService with real SignalIngestor', () => {
  let prisma: any;
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
    const emitter: any = { append: jest.fn().mockResolvedValue('event-id') };
    const membership: any = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1' }),
      requireAdmin: jest.fn().mockResolvedValue({ id: 'm_1' }),
      getElderUserIds: jest.fn().mockResolvedValue([]),
      getActiveMemberUserIds: jest.fn().mockResolvedValue(['u_1']),
    };
    const realIngestor = new SignalIngestor(prisma as any);
    const realInference = new LearningInference(prisma as any);
    const profileBuilder: any = { recompute: jest.fn().mockResolvedValue(1) };

    service = new LearningService(
      prisma as any,
      emitter,
      membership,
      realIngestor,
      profileBuilder,
      realInference,
    );
  });

  it('ingestSignal() persists the signal through the real ingestor', async () => {
    prisma.learningSignal.create.mockResolvedValueOnce({ id: 'sig_real' });

    const id = await service.ingestSignal('fam_1', 'u_1', {
      signalType: 'vote_pattern',
      payload: { count: 1 },
    });

    expect(id).toBe('sig_real');
    expect(prisma.learningSignal.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          familyId: 'fam_1',
          signalType: 'vote_pattern',
        }),
      }),
    );
  });
});
