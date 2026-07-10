// =============================================================================
// Track C v2.0 — Learning Profile Builder Tests
// =============================================================================
// Section 14.2 + 14.3 mandatory coverage:
//   - 100% on confidence gating
//   - 100% on profile recomputation
//   - 100% on signal ingestion
//   - Property test: confidenceScore is monotonic in signal count
// =============================================================================

import { ProfileBuilder } from './learning.profile-builder';
import { SignalIngestor } from './learning.signal-ingestor';

describe('ProfileBuilder', () => {
  let builder: ProfileBuilder;

  beforeEach(() => {
    builder = new ProfileBuilder({} as any);
  });

  describe('computeConfidence', () => {
    it('returns 0 for sampleSize < minSamples', () => {
      expect(builder.computeConfidence(0, 30, 0.4, 0.7)).toBe(0);
      expect(builder.computeConfidence(29, 30, 0.4, 0.7)).toBe(0);
    });

    it('returns highThreshold (capped) for sampleSize >= 100', () => {
      expect(builder.computeConfidence(100, 30, 0.4, 0.7)).toBe(0.7);
      expect(builder.computeConfidence(500, 30, 0.4, 0.7)).toBe(0.7);
    });

    it('linearly interpolates between lowThreshold and highThreshold for 30..100', () => {
      const at30 = builder.computeConfidence(30, 30, 0.4, 0.7);
      const at65 = builder.computeConfidence(65, 30, 0.4, 0.7);

      expect(at30).toBeCloseTo(0.4, 5);
      expect(at65).toBeCloseTo(0.55, 5); // midpoint
    });

    // Property: confidenceScore is monotonic in signal count
    it('property: confidenceScore is monotonically non-decreasing in sample size', () => {
      let prev = -1;
      for (let n = 0; n <= 200; n += 5) {
        const c = builder.computeConfidence(n, 30, 0.4, 0.7);
        expect(c).toBeGreaterThanOrEqual(prev);
        prev = c;
      }
    });
  });

  describe('aggregate', () => {
    it('counts insight_accept and insight_dismiss signals by kind', () => {
      const signals = [
        { signalType: 'insight_accepted', occurredAt: new Date('2026-07-09T10:00:00Z'), payload: { kind: 'decision_analysis' } },
        { signalType: 'insight_accepted', occurredAt: new Date('2026-07-09T11:00:00Z'), payload: { kind: 'decision_analysis' } },
        { signalType: 'insight_dismissed', occurredAt: new Date('2026-07-09T12:00:00Z'), payload: { kind: 'decision_analysis' } },
        { signalType: 'insight_accepted', occurredAt: new Date('2026-07-09T13:00:00Z'), payload: { kind: 'pros_cons' } },
      ];
      const stats = builder.aggregate(signals as any);
      expect(stats.insightAcceptRates.decision_analysis).toEqual({ accepted: 2, dismissed: 1 });
      expect(stats.insightAcceptRates.pros_cons).toEqual({ accepted: 1, dismissed: 0 });
      expect(stats.totalSignals).toBe(4);
    });

    it('tracks reminder action outcomes', () => {
      const signals = [
        { signalType: 'reminder_acted', occurredAt: new Date() },
        { signalType: 'reminder_acted', occurredAt: new Date() },
        { signalType: 'reminder_snoozed', occurredAt: new Date() },
        { signalType: 'reminder_dismissed', occurredAt: new Date() },
      ];
      const stats = builder.aggregate(signals as any);
      expect(stats.reminderActions).toEqual({ acted: 2, snoozed: 1, dismissed: 1, total: 4 });
    });

    it('distributes signals across weekday + time-of-day buckets', () => {
      // 2026-07-06 is a Monday (UTC)
      const monday = new Date('2026-07-06T10:00:00Z'); // morning
      const tuesday = new Date('2026-07-07T15:00:00Z'); // afternoon
      const saturday = new Date('2026-07-11T20:00:00Z'); // evening
      const sunday = new Date('2026-07-12T02:00:00Z'); // night

      const stats = builder.aggregate([
        { signalType: 'vote_pattern', occurredAt: monday, payload: {} },
        { signalType: 'vote_pattern', occurredAt: tuesday, payload: {} },
        { signalType: 'vote_pattern', occurredAt: saturday, payload: {} },
        { signalType: 'vote_pattern', occurredAt: sunday, payload: {} },
      ] as any);

      expect(stats.weekdayDistribution.mon).toBe(1);
      expect(stats.weekdayDistribution.tue).toBe(1);
      expect(stats.weekdayDistribution.sat).toBe(1);
      expect(stats.weekdayDistribution.sun).toBe(1);

      expect(stats.timeOfDayBuckets.morning).toBe(1);
      expect(stats.timeOfDayBuckets.afternoon).toBe(1);
      expect(stats.timeOfDayBuckets.evening).toBe(1);
      expect(stats.timeOfDayBuckets.night).toBe(1);
    });
  });

  describe('computeLearnedValues', () => {
    it('computes accept rate per kind', () => {
      const stats = {
        insightAcceptRates: {
          decision_analysis: { accepted: 4, dismissed: 6 },
          pros_cons: { accepted: 7, dismissed: 3 },
        },
        reminderActions: { acted: 5, snoozed: 3, dismissed: 2, total: 10 },
        weekdayDistribution: { mon: 2, tue: 2, wed: 2, thu: 2, fri: 2, sat: 4, sun: 6 },
        timeOfDayBuckets: { morning: 5, afternoon: 5, evening: 8, night: 2 },
        elderParticipation: { participated: 3, totalDecisions: 5 },
        quorumMet: { met: 4, total: 5 },
        decisionDurationsHours: [24, 48, 72],
        totalSignals: 20,
      };

      const learned = builder.computeLearnedValues(stats as any, {
        preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 },
        reminderActionRate: { '6h': 0.42, '12h': 0.55, '24h': 0.71 },
        preferredWeekdayDistribution: { mon: 0.14, tue: 0.14, wed: 0.14, thu: 0.14, fri: 0.14, sat: 0.15, sun: 0.15 },
        preferredTimeOfDayBuckets: { morning: 0.25, afternoon: 0.25, evening: 0.25, night: 0.25 },
        elderAutoIncludeThreshold: 0.6,
        averageDecisionDurationHours: 72,
      });

      expect(learned.insightAcceptRateByKind.decision_analysis).toBeCloseTo(0.4, 2);
      expect(learned.insightAcceptRateByKind.pros_cons).toBeCloseTo(0.7, 2);
      expect(learned.averageDecisionDurationHours).toBeCloseTo(48, 0); // (24+48+72)/3
      expect(learned.typicalQuorumMet).toBe(true); // 4/5 >= 0.5
    });
  });

  describe('blendWithDefaults', () => {
    it('uses 100% defaults when confidence=0', () => {
      const learned = { preferredReminderLeadHours: { decision: 6, meeting: 12, event: 24 } };
      const defaults = { preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 } };
      const blended = builder.blendWithDefaults(learned, defaults as any, 0.0);
      expect(blended.preferredReminderLeadHours.decision).toBe(24); // default
    });

    it('uses 100% learned when confidence >= highThreshold', () => {
      const learned = { preferredReminderLeadHours: { decision: 6, meeting: 12, event: 24 } };
      const defaults = { preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 } };
      const blended = builder.blendWithDefaults(learned, defaults as any, 0.9);
      expect(blended.preferredReminderLeadHours.decision).toBe(6); // learned
    });

    it('blends 50/50 when confidence is between thresholds', () => {
      const learned = { preferredReminderLeadHours: { decision: 6, meeting: 12, event: 24 } };
      const defaults = { preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 } };
      const blended = builder.blendWithDefaults(learned, defaults as any, 0.55);
      // weight=0.5 → 6*0.5 + 24*0.5 = 15
      expect(blended.preferredReminderLeadHours.decision).toBe(15);
    });
  });
});

describe('SignalIngestor', () => {
  let ingestor: SignalIngestor;
  let createdData: any;

  beforeEach(() => {
    createdData = null;
    const mockPrisma: any = {
      learningSignal: {
        create: (args: any) => {
          createdData = args.data;
          return Promise.resolve({ id: 'sig_1', ...args.data });
        },
        createMany: (args: any) => Promise.resolve({ count: args.data.length }),
      },
    };
    ingestor = new SignalIngestor(mockPrisma);
  });

  it('persists the signal with sanitized payload', async () => {
    const id = await ingestor.ingest({
      familyId: 'fam1',
      signalType: 'insight_accepted',
      targetType: 'AIInsight',
      targetId: 'ins1',
      payload: { kind: 'decision_analysis', score: 0.8 },
    });
    expect(id).toBe('sig_1');
    expect(createdData.familyId).toBe('fam1');
    expect(createdData.signalType).toBe('insight_accepted');
    expect(createdData.payload.kind).toBe('decision_analysis');
  });

  it('truncates long strings to prevent storing long text (PII protection)', async () => {
    const longString = 'x'.repeat(500);
    await ingestor.ingest({
      familyId: 'fam1',
      signalType: 'vote_pattern',
      payload: { description: longString },
    });
    expect((createdData.payload.description as string).length).toBe(200);
  });

  it('drops functions and undefined values', async () => {
    await ingestor.ingest({
      familyId: 'fam1',
      signalType: 'vote_pattern',
      payload: {
        keep: 'me',
        fn: () => 'dropped',
        u: undefined,
      } as any,
    });
    expect(createdData.payload.keep).toBe('me');
    expect(createdData.payload.fn).toBeUndefined();
    expect(createdData.payload.u).toBeUndefined();
  });
});
