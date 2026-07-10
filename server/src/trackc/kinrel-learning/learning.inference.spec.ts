// =============================================================================
// Track C v2.0 — LearningInference Tests
// =============================================================================
// Section 9.3: sub-50ms inference reads from FamilyBehaviorProfile.
//
// NOTE: the v2 spec test plan refers to an `infer()` method. The current
// LearningInference implementation exposes `getProfile()` instead, which
// performs the equivalent role: returns the cached profile when confidence
// is high, or global defaults when the profile is missing/insufficient.
// These tests exercise `getProfile()` for the three spec'd behaviors:
//   1. "no profile" → returns defaults (usingDefaults=true)
//   2. "insufficient data" (low confidence) → returns defaults
//   3. "rich profile" (high confidence) → returns learned values
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { LearningInference } from './learning.inference';

describe('LearningInference', () => {
  let prisma: any;
  let inference: LearningInference;

  beforeEach(() => {
    prisma = new PrismaService();
    for (const m of Object.values(prisma) as any[]) {
      if (m && typeof m === 'object' && 'findUnique' in m) {
        (m as any).findUnique.mockResolvedValue(null);
        (m as any).findMany.mockResolvedValue([]);
        (m as any).count.mockResolvedValue(0);
      }
    }
    inference = new LearningInference(prisma as any);
  });

  it('returns defaults (usingDefaults=true) when no profile exists', async () => {
    prisma.familyBehaviorProfile.findUnique.mockResolvedValueOnce(null);
    prisma.globalLearningDefaults.findUnique.mockResolvedValueOnce(null);

    const result = await inference.getProfile('fam_1');

    expect(result.usingDefaults).toBe(true);
    expect(result.confidenceScore).toBe(0);
    expect(result.sampleSize).toBe(0);
    expect(result.version).toBe(0);
    // Fallback defaults should be populated
    expect(result.preferredReminderLeadHours).toEqual({ decision: 24, meeting: 48, event: 72 });
    expect(result.reminderActionRate).toEqual({ '6h': 0.42, '12h': 0.55, '24h': 0.71 });
  });

  it('returns defaults (usingDefaults=true) when profile has insufficient data (low confidence)', async () => {
    // Profile exists but confidence is below the low-confidence threshold (0.4)
    prisma.familyBehaviorProfile.findUnique.mockResolvedValueOnce({
      familyId: 'fam_1',
      version: 1,
      confidenceScore: 0.1, // well below 0.4 threshold
      sampleSize: 5,
      computedAt: new Date(),
      preferredReminderLeadHours: { decision: 6 },
      reminderActionRate: { '6h': 0.3 },
      preferredWeekdayDistribution: { mon: 0.5 },
      preferredTimeOfDayBuckets: { morning: 0.5 },
      elderAutoIncludeThreshold: 0.5,
      insightAcceptRateByKind: {},
      averageDecisionDurationHours: 24,
      typicalQuorumMet: null,
    });
    prisma.globalLearningDefaults.findUnique.mockResolvedValueOnce({
      lowConfidenceThreshold: 0.4,
      preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 },
      reminderActionRate: { '6h': 0.42, '12h': 0.55, '24h': 0.71 },
      preferredWeekdayDistribution: { mon: 0.14 },
      preferredTimeOfDayBuckets: { morning: 0.25 },
      elderAutoIncludeThreshold: 0.6,
      insightAcceptRateByKind: {},
      averageDecisionDurationHours: 72,
    });

    const result = await inference.getProfile('fam_1');

    expect(result.usingDefaults).toBe(true);
    // Even though the profile exists, the returned values must come from the defaults
    expect(result.preferredReminderLeadHours).toEqual({ decision: 24, meeting: 48, event: 72 });
    // The profile's own confidence/sampleSize are surfaced for observability
    expect(result.confidenceScore).toBe(0.1);
    expect(result.sampleSize).toBe(5);
  });

  it('returns the learned profile when confidence is high (rich profile)', async () => {
    prisma.familyBehaviorProfile.findUnique.mockResolvedValueOnce({
      familyId: 'fam_1',
      version: 7,
      confidenceScore: 0.85, // above the 0.4 threshold
      sampleSize: 200,
      computedAt: new Date(),
      preferredReminderLeadHours: { decision: 6, meeting: 12, event: 24 },
      reminderActionRate: { '6h': 0.6, '12h': 0.7, '24h': 0.85 },
      preferredWeekdayDistribution: { mon: 0.1, tue: 0.1, wed: 0.1, thu: 0.1, fri: 0.1, sat: 0.25, sun: 0.25 },
      preferredTimeOfDayBuckets: { morning: 0.4, afternoon: 0.3, evening: 0.2, night: 0.1 },
      elderAutoIncludeThreshold: 0.5,
      insightAcceptRateByKind: { decision_analysis: 0.7 },
      averageDecisionDurationHours: 48,
      typicalQuorumMet: true,
    });
    prisma.globalLearningDefaults.findUnique.mockResolvedValueOnce({
      lowConfidenceThreshold: 0.4,
      preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 },
      reminderActionRate: { '6h': 0.42, '12h': 0.55, '24h': 0.71 },
      preferredWeekdayDistribution: { mon: 0.14 },
      preferredTimeOfDayBuckets: { morning: 0.25 },
      elderAutoIncludeThreshold: 0.6,
      insightAcceptRateByKind: {},
      averageDecisionDurationHours: 72,
    });

    const result = await inference.getProfile('fam_1');

    expect(result.usingDefaults).toBe(false);
    // Learned values should be returned, not the defaults
    expect(result.version).toBe(7);
    expect(result.confidenceScore).toBe(0.85);
    expect(result.sampleSize).toBe(200);
    expect(result.preferredReminderLeadHours).toEqual({ decision: 6, meeting: 12, event: 24 });
    expect(result.reminderActionRate['24h']).toBe(0.85);
    expect((result.insightAcceptRateByKind as any).decision_analysis).toBe(0.7);
    expect(result.averageDecisionDurationHours).toBe(48);
    expect(result.typicalQuorumMet).toBe(true);
  });

  it('treats the confidence threshold boundary correctly (exactly at threshold → uses learned profile)', async () => {
    prisma.familyBehaviorProfile.findUnique.mockResolvedValueOnce({
      familyId: 'fam_1',
      version: 1,
      confidenceScore: 0.4, // exactly equal to threshold → strictly NOT < threshold → uses learned
      sampleSize: 30,
      computedAt: new Date(),
      preferredReminderLeadHours: { decision: 6 },
      reminderActionRate: {},
      preferredWeekdayDistribution: {},
      preferredTimeOfDayBuckets: {},
      elderAutoIncludeThreshold: 0.5,
      insightAcceptRateByKind: {},
      averageDecisionDurationHours: 24,
      typicalQuorumMet: null,
    });
    prisma.globalLearningDefaults.findUnique.mockResolvedValueOnce({
      lowConfidenceThreshold: 0.4,
      preferredReminderLeadHours: { decision: 24, meeting: 48, event: 72 },
      reminderActionRate: { '6h': 0.42, '12h': 0.55, '24h': 0.71 },
      preferredWeekdayDistribution: { mon: 0.14 },
      preferredTimeOfDayBuckets: { morning: 0.25 },
      elderAutoIncludeThreshold: 0.6,
      insightAcceptRateByKind: {},
      averageDecisionDurationHours: 72,
    });

    const result = await inference.getProfile('fam_1');
    // The check is `confidenceScore < threshold`, so at exactly threshold it
    // uses the learned profile.
    expect(result.usingDefaults).toBe(false);
  });

  it('issues both profile + defaults lookups in parallel (single round-trip)', async () => {
    prisma.familyBehaviorProfile.findUnique.mockResolvedValueOnce(null);
    prisma.globalLearningDefaults.findUnique.mockResolvedValueOnce(null);

    await inference.getProfile('fam_1');

    // Both lookups must happen (the Promise.all branch)
    expect(prisma.familyBehaviorProfile.findUnique).toHaveBeenCalledWith({
      where: { familyId: 'fam_1' },
    });
    expect(prisma.globalLearningDefaults.findUnique).toHaveBeenCalledWith({
      where: { id: 'global' },
    });
  });
});
