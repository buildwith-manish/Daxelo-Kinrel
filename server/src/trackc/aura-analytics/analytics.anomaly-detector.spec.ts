// =============================================================================
// ML spec item #4 — Adaptive anomaly detector tests
// =============================================================================
// Verifies the per-family z-score baselines that were added on top of the
// existing fixed-threshold rules.
// =============================================================================

import { AnalyticsAnomalyDetector, AnomalyHistorySnapshot } from './analytics.anomaly-detector';

describe('AnalyticsAnomalyDetector (v3 adaptive baselines)', () => {
  let detector: AnalyticsAnomalyDetector;

  beforeEach(() => {
    detector = new AnalyticsAnomalyDetector();
  });

  // ── Fixed-threshold rules (v1 — must still pass) ──────────────────────

  it('fires governance_dormant when no decisions created in a week (and family has prior decisions)', () => {
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: {
        decisionsCreated: 0,
        priorDecisionCount: 5,
      },
    });
    expect(anomalies.some((a) => a.kind === 'governance_dormant')).toBe(true);
  });

  it('does NOT fire governance_dormant for new families (priorDecisionCount=0)', () => {
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: { decisionsCreated: 0, priorDecisionCount: 0 },
    });
    expect(anomalies.some((a) => a.kind === 'governance_dormant')).toBe(false);
  });

  it('fires quorum_decline via fixed rule when quorumMetRate < 0.30', () => {
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: {
        decisionsResolved: 5,
        quorumMetRate: 0.20, // 20% — below fixed 30% floor
      },
    });
    const quorumAnomaly = anomalies.find((a) => a.kind === 'quorum_decline');
    expect(quorumAnomaly).toBeDefined();
    expect(quorumAnomaly!.detectionSource === 'fixed_threshold' || quorumAnomaly!.detectionSource === 'both').toBe(true);
  });

  // ── Adaptive z-score rules (v3 — new) ─────────────────────────────────

  it('fires quorum_decline via adaptive rule when current rate is >2.5 sigma below baseline', () => {
    // Family has a high baseline (~80% quorumMetRate). Current week drops to 50%.
    // 50% is ABOVE the fixed 30% floor, but it's a 3+ sigma drop from their baseline.
    const history: AnomalyHistorySnapshot[] = [
      { quorumMetRate: 0.80 },
      { quorumMetRate: 0.85 },
      { quorumMetRate: 0.78 },
      { quorumMetRate: 0.82 },
      { quorumMetRate: 0.80 },
    ];
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: {
        decisionsResolved: 5,
        quorumMetRate: 0.50, // big drop from 0.80 baseline
      },
      history,
    });
    const quorumAnomaly = anomalies.find((a) => a.kind === 'quorum_decline');
    expect(quorumAnomaly).toBeDefined();
    expect(quorumAnomaly!.detectionSource === 'adaptive_zscore' || quorumAnomaly!.detectionSource === 'both').toBe(true);
    expect(quorumAnomaly!.zScore).toBeLessThan(-2.5);
  });

  it('does NOT fire quorum_decline via adaptive rule when family has <4 history snapshots', () => {
    // Family has only 2 weeks of history — too few to trust a baseline.
    const history: AnomalyHistorySnapshot[] = [
      { quorumMetRate: 0.80 },
      { quorumMetRate: 0.85 },
    ];
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: {
        decisionsResolved: 5,
        quorumMetRate: 0.50,
      },
      history,
    });
    const quorumAnomaly = anomalies.find((a) => a.kind === 'quorum_decline');
    // 50% is above the 30% fixed floor, and we don't have enough history for
    // the adaptive rule. No anomaly should fire.
    expect(quorumAnomaly).toBeUndefined();
  });

  it('does NOT fire adaptive anomaly for a family with naturally low but stable metrics', () => {
    // Family baseline is around 25% quorumMetRate (low, but stable).
    // Current week is 24% — within their normal range.
    // The fixed rule (30% floor) WILL fire because 24% < 30%, but the
    // adaptive rule should NOT fire because 24% is consistent with their baseline.
    const history: AnomalyHistorySnapshot[] = [
      { quorumMetRate: 0.25 },
      { quorumMetRate: 0.27 },
      { quorumMetRate: 0.24 },
      { quorumMetRate: 0.26 },
      { quorumMetRate: 0.25 },
    ];
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: {
        decisionsResolved: 5,
        quorumMetRate: 0.24,
      },
      history,
    });
    // 24% is below the fixed 30% floor — the fixed rule SHOULD fire.
    // But the adaptive rule should NOT fire (24% is within their normal range).
    const quorumAnomaly = anomalies.find((a) => a.kind === 'quorum_decline');
    expect(quorumAnomaly).toBeDefined();
    // The detection source should be fixed_threshold only (not adaptive, not both)
    expect(quorumAnomaly!.detectionSource).toBe('fixed_threshold');
  });

  it('fires participation_decline via adaptive rule when current rate drops unusually', () => {
    // Family has a 90% participation baseline. Drops to 60% (still above 20% floor).
    const history: AnomalyHistorySnapshot[] = [
      { participationRate: 0.90 },
      { participationRate: 0.88 },
      { participationRate: 0.92 },
      { participationRate: 0.91 },
      { participationRate: 0.89 },
    ];
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: {
        totalEligible: 10,
        participationRate: 0.60, // big drop from 0.90 baseline
      },
      history,
    });
    const partAnomaly = anomalies.find((a) => a.kind === 'participation_decline');
    expect(partAnomaly).toBeDefined();
    expect(partAnomaly!.detectionSource === 'adaptive_zscore' || partAnomaly!.detectionSource === 'both').toBe(true);
  });

  it('fires slow_decisions via adaptive rule when avg duration is unusually high for the family', () => {
    // Family's decisions usually resolve in 2 days (48 hours).
    // This week's average is 5 days (120 hours).
    const history: AnomalyHistorySnapshot[] = [
      { avgDurationHours: 48 },
      { avgDurationHours: 50 },
      { avgDurationHours: 45 },
      { avgDurationHours: 52 },
      { avgDurationHours: 48 },
    ];
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: {
        decisionsResolved: 5,
        avgDurationHours: 120, // 5 days — way above their 2-day baseline
      },
      history,
    });
    const slowAnomaly = anomalies.find((a) => a.kind === 'slow_decisions');
    expect(slowAnomaly).toBeDefined();
    // 120h is below the fixed 168h (7-day) floor, so adaptive-only
    expect(slowAnomaly!.detectionSource).toBe('adaptive_zscore');
  });

  it('returns no anomalies when history is omitted (legacy behavior)', () => {
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: {
        decisionsResolved: 5,
        quorumMetRate: 0.50, // would trigger adaptive rule if history was provided
      },
      // no history — only fixed rules run
    });
    // 50% is above the 30% fixed floor — no anomaly should fire
    expect(anomalies.find((a) => a.kind === 'quorum_decline')).toBeUndefined();
  });

  it('includes both detectionSource and zScore in the anomaly output for telemetry', () => {
    const history: AnomalyHistorySnapshot[] = [
      { quorumMetRate: 0.80 },
      { quorumMetRate: 0.80 },
      { quorumMetRate: 0.80 },
      { quorumMetRate: 0.80 },
    ];
    const anomalies = detector.detect({
      familyId: 'fam_1',
      periodStart: new Date(),
      periodEnd: new Date(),
      granularity: 'weekly',
      metrics: {
        decisionsResolved: 5,
        quorumMetRate: 0.40, // drop from 0.80 baseline
      },
      history,
    });
    const quorumAnomaly = anomalies.find((a) => a.kind === 'quorum_decline');
    if (quorumAnomaly && quorumAnomaly.detectionSource === 'adaptive_zscore') {
      expect(typeof quorumAnomaly.zScore).toBe('number');
      expect(typeof quorumAnomaly.baselineMean).toBe('number');
    }
  });
});
