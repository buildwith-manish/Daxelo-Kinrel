// =============================================================================
// Track C v2.0 — AnalyticsAnomalyDetector Tests
// =============================================================================
// Section 4: anomaly detection on weekly/monthly/quarterly metrics.
//
// NOTE: the v2 spec test plan describes 3-sigma-style anomaly detection
// ("value exceeds 3 standard deviations", "flat series", "fewer than 4
// data points"). The actual AnalyticsAnomalyDetector implementation uses
// rule-based thresholds (dormancy, quorum decline, participation decline,
// slow decisions) rather than statistical 3-sigma analysis.
//
// These tests exercise the implemented rule-based behavior, with `.skip`
// tests documenting the spec-required statistical behavior for a future
// implementer.
// =============================================================================

import { AnalyticsAnomalyDetector } from './analytics.anomaly-detector';

describe('AnalyticsAnomalyDetector', () => {
  let detector: AnalyticsAnomalyDetector;

  beforeEach(() => {
    detector = new AnalyticsAnomalyDetector();
  });

  function baseParams(metricsOverrides: any = {}, topLevelOverrides: any = {}) {
    return {
      familyId: 'fam_1',
      periodStart: new Date('2026-07-06'),
      periodEnd: new Date('2026-07-13'),
      granularity: 'weekly',
      metrics: {
        decisionsCreated: 5,
        decisionsResolved: 5,
        decisionsExpired: 0,
        avgDurationHours: 24,
        participationRate: 0.7,
        quorumMetRate: 0.8,
        totalEligible: 10,
        totalVotes: 7,
        priorDecisionCount: 10,
        ...metricsOverrides,
      },
      ...topLevelOverrides,
    };
  }

  it('returns no anomalies when all metrics are within healthy ranges (flat series)', () => {
    const result = detector.detect(baseParams());
    expect(result).toEqual([]);
  });

  it('detects governance_dormant when no decisions were created this week (and family has prior decisions)', () => {
    const result = detector.detect(
      baseParams({ decisionsCreated: 0, priorDecisionCount: 5 }),
    );
    expect(result).toHaveLength(1);
    expect(result[0].kind).toBe('governance_dormant');
    expect(result[0].severity).toBe('medium');
    expect(result[0].message).toContain('No decisions');
  });

  it('does NOT flag governance_dormant for new families (no prior decisions)', () => {
    // New family with no decisions — should NOT be flagged as dormant
    const result = detector.detect(
      baseParams({ decisionsCreated: 0, priorDecisionCount: 0 }),
    );
    // No dormancy anomaly (but other rules may still fire if metrics trigger them)
    const dormancy = result.filter((a) => a.kind === 'governance_dormant');
    expect(dormancy).toHaveLength(0);
  });

  it('does NOT flag governance_dormant for monthly granularity (too coarse)', () => {
    const result = detector.detect(
      baseParams(
        { decisionsCreated: 0, priorDecisionCount: 5 },
        { granularity: 'monthly' },
      ),
    );
    const dormancy = result.filter((a) => a.kind === 'governance_dormant');
    expect(dormancy).toHaveLength(0);
  });

  it('detects quorum_decline when quorumMetRate < 30% with >=3 resolved decisions', () => {
    const result = detector.detect(
      baseParams({ decisionsResolved: 4, quorumMetRate: 0.2 }),
    );
    const quorumAnomaly = result.find((a) => a.kind === 'quorum_decline');
    expect(quorumAnomaly).toBeDefined();
    expect(quorumAnomaly!.severity).toBe('high');
    expect(quorumAnomaly!.message).toContain('20%'); // (0.2 * 100).toFixed(0)
  });

  it('does NOT flag quorum_decline when there are fewer than 3 resolved decisions (insufficient data)', () => {
    const result = detector.detect(
      baseParams({ decisionsResolved: 2, quorumMetRate: 0.1 }), // only 2 resolved
    );
    const quorumAnomaly = result.find((a) => a.kind === 'quorum_decline');
    expect(quorumAnomaly).toBeUndefined();
  });

  it('detects participation_decline when participation < 20% with >=5 eligible voters', () => {
    const result = detector.detect(
      baseParams({ totalEligible: 10, participationRate: 0.1 }),
    );
    const participationAnomaly = result.find((a) => a.kind === 'participation_decline');
    expect(participationAnomaly).toBeDefined();
    expect(participationAnomaly!.severity).toBe('medium');
    expect(participationAnomaly!.message).toContain('10%');
  });

  it('does NOT flag participation_decline when there are fewer than 5 eligible voters (insufficient data)', () => {
    const result = detector.detect(
      baseParams({ totalEligible: 4, participationRate: 0.05 }), // only 4 eligible
    );
    const participationAnomaly = result.find((a) => a.kind === 'participation_decline');
    expect(participationAnomaly).toBeUndefined();
  });

  it('detects slow_decisions when avgDurationHours > 168 (7 days)', () => {
    const result = detector.detect(
      baseParams({ decisionsResolved: 3, avgDurationHours: 200 }),
    );
    const slowAnomaly = result.find((a) => a.kind === 'slow_decisions');
    expect(slowAnomaly).toBeDefined();
    expect(slowAnomaly!.severity).toBe('low');
    expect(slowAnomaly!.message).toContain('days');
  });

  it('does NOT flag slow_decisions when there are fewer than 2 resolved decisions (insufficient data)', () => {
    const result = detector.detect(
      baseParams({ decisionsResolved: 1, avgDurationHours: 500 }), // only 1 resolved
    );
    const slowAnomaly = result.find((a) => a.kind === 'slow_decisions');
    expect(slowAnomaly).toBeUndefined();
  });

  it('can detect multiple anomalies simultaneously', () => {
    const result = detector.detect(
      baseParams({
        decisionsCreated: 0,
        priorDecisionCount: 10,
        decisionsResolved: 5,
        quorumMetRate: 0.1, // < 30%
        totalEligible: 10,
        participationRate: 0.1, // < 20%
        avgDurationHours: 200, // > 168
      }),
    );
    // Should fire: governance_dormant + quorum_decline + participation_decline + slow_decisions
    expect(result.length).toBeGreaterThanOrEqual(3);
    const kinds = result.map((r) => r.kind);
    expect(kinds).toContain('governance_dormant');
    expect(kinds).toContain('quorum_decline');
    expect(kinds).toContain('participation_decline');
    expect(kinds).toContain('slow_decisions');
  });

  // SPEC GAP — the v2 spec test plan calls for 3-sigma statistical anomaly
  // detection. The current implementation uses rule-based thresholds only.
  // The tests below are skipped until a statistical layer is added.
  describe.skip('statistical (3-sigma) anomaly detection — spec gap', () => {
    it('returns no anomalies when the series is flat (zero variance)', () => {
      // A constant series has zero variance → no value can exceed 3σ.
    });

    it('returns an anomaly when a value exceeds 3 standard deviations', () => {
      // Construct a series where one value is >3σ from the mean and verify
      // the detector flags it.
    });

    it('returns no anomalies when there are fewer than 4 data points (insufficient data)', () => {
      // The statistical layer should require a minimum sample size before
      // computing standard deviation.
    });
  });
});
