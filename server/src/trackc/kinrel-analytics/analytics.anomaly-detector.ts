// =============================================================================
// Track C v2.0 - Kinrel Analytics
// analytics.anomaly-detector.ts
// =============================================================================
// Detects anomalies in family governance patterns. Section 4.
//   - "No decisions in 30 days" - governance_dormant
//   - "Quorum met rate dropped below 30%" - quorum_decline
//   - "Participation rate below 20%" - participation_decline
//
// v3 (ML spec item #4): ADAPTIVE per-family baselines layered on top of the
// existing fixed-threshold rules. Each family has its own rolling mean/stddev
// computed from its last ~8 weekly snapshots. We flag a metric as anomalous
// when:
//   (a) the existing fixed-threshold rule fires (kept as absolute floors so a
//       truly dormant family is still caught), OR
//   (b) the metric deviates > N standard deviations from that family's own
//       baseline - but only if the family has enough history to trust the
//       baseline (>=4 prior snapshots).
//
// Target: <5% false positive rate in beta (Section 18 Phase C5 exit criteria).
// The adaptive layer REDUCES false positives on families with naturally low
// but stable metrics, and INCREASES recall on families whose baseline is
// unusually high (so a drop that's still above the global floor gets caught).
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';

export interface Anomaly {
  kind: string;
  severity: 'low' | 'medium' | 'high';
  message: string;
  detectedAt: string;
  /** Whether this anomaly fired via the fixed-threshold rule, the adaptive
   * z-score rule, or both. Used for telemetry + acceptance-test verification. */
  detectionSource?: 'fixed_threshold' | 'adaptive_zscore' | 'both';
  /** When detectionSource includes 'adaptive_zscore', this is the z-score
   * that triggered the flag. */
  zScore?: number;
  /** The family's rolling baseline mean for the flagged metric. */
  baselineMean?: number;
}

export interface AnomalyHistorySnapshot {
  /** The metric values from a prior weekly snapshot. Undefined/missing fields
   * are treated as "no data" for that metric in that week. */
  quorumMetRate?: number;
  participationRate?: number;
  avgDurationHours?: number;
  decisionsCreated?: number;
  decisionsResolved?: number;
}

// ?? Adaptive-baseline tuning ????????????????????????????????????????????????
//
// Z_SCORE_THRESHOLD: how many standard deviations from the family's own mean
//   counts as "unusual for them". 3sigma is the textbook "statistically
//   significant" threshold; we use a slightly looser 2.5sigma because family
//   governance data is noisy and we'd rather over-flag (and let the admin
//   dismiss) than miss a real drop in a normally-stable family.
//
// MIN_HISTORY_FOR_BASELINE: minimum number of prior snapshots required before
//   the adaptive rule is allowed to fire. Families with <4 weeks of history
//   don't have a meaningful baseline - flagging them for deviating from a
//   1-2 sample "baseline" would be pure noise.
//
// BASELINE_WINDOW: how many recent snapshots to include in the rolling
//   mean/stddev. ~8 weeks balances "recent enough to reflect the family's
//   current pattern" with "enough samples to compute a stable stddev".
const Z_SCORE_THRESHOLD = 2.5;
const MIN_HISTORY_FOR_BASELINE = 4;
const BASELINE_WINDOW = 8;

@Injectable()
export class AnalyticsAnomalyDetector {
  private readonly logger = new Logger(AnalyticsAnomalyDetector.name);

  detect(params: {
    familyId: string;
    periodStart: Date;
    periodEnd: Date;
    granularity: string;
    metrics: any;
    /**
     * v3: prior weekly snapshots for this family, oldest first. Used to
     * compute the family's own rolling baseline. Optional - when omitted,
     * only the fixed-threshold rules run (legacy behavior).
     */
    history?: AnomalyHistorySnapshot[];
  }): Anomaly[] {
    const anomalies: Anomaly[] = [];
    const now = new Date().toISOString();
    const m = params.metrics;
    const history = params.history ?? [];

    // Compute rolling baseline stats (mean, stddev) for each metric we care
    // about. We use the most recent BASELINE_WINDOW snapshots - caller
    // passes them oldest-first, so we slice from the end.
    const recent = history.slice(-BASELINE_WINDOW);
    const baseline = computeBaselineStats(recent);

    // ?? 1. Governance dormancy: no decisions created in the period ????????
    // Fixed rule only - adaptive z-score on "decisionsCreated=0" doesn't
    // make sense for a count metric (many families legitimately have zero
    // decisions in a given week, especially small families).
    if (params.granularity === 'weekly' && m.decisionsCreated === 0) {
      if (m.priorDecisionCount && m.priorDecisionCount > 0) {
        anomalies.push({
          kind: 'governance_dormant',
          severity: 'medium',
          message: 'No decisions were created this week. Consider opening a family discussion.',
          detectedAt: now,
          detectionSource: 'fixed_threshold',
        });
      }
    }

    // ?? 2. Quorum decline ?????????????????????????????????????????????????
    // Fixed: <30% of decisions met quorum (only if >=3 decisions resolved).
    // Adaptive: current quorumMetRate is >2.5sigma below the family's own
    //   rolling mean. Catches a family whose baseline is e.g. 80% dropping
    //   to 50% - above the fixed 30% floor but unusual for them.
    let quorumFixed = false;
    if (m.decisionsResolved >= 3 && m.quorumMetRate < 0.30) {
      quorumFixed = true;
    }
    let quorumAdaptive = false;
    let quorumZ: number | undefined;
    let quorumMean: number | undefined;
    if (
      baseline.quorumMetRate &&
      baseline.quorumMetRate.count >= MIN_HISTORY_FOR_BASELINE &&
      typeof m.quorumMetRate === 'number'
    ) {
      const z = zScore(m.quorumMetRate, baseline.quorumMetRate.mean, baseline.quorumMetRate.stddev);
      if (z !== null && z <= -Z_SCORE_THRESHOLD) {
        quorumAdaptive = true;
        quorumZ = z;
        quorumMean = baseline.quorumMetRate.mean;
      }
    }
    if (quorumFixed || quorumAdaptive) {
      anomalies.push({
        kind: 'quorum_decline',
        severity: 'high',
        message: quorumAdaptive && !quorumFixed
          ? `Quorum met rate is ${(m.quorumMetRate * 100).toFixed(0)}% - unusually low for this family (baseline ${(quorumMean! * 100).toFixed(0)}%, z=${quorumZ!.toFixed(2)}).`
          : `Only ${(m.quorumMetRate * 100).toFixed(0)}% of resolved decisions met quorum this ${params.granularity.replace('ly', '')}.`,
        detectedAt: now,
        detectionSource: quorumFixed && quorumAdaptive ? 'both' : quorumFixed ? 'fixed_threshold' : 'adaptive_zscore',
        zScore: quorumZ,
        baselineMean: quorumMean,
      });
    }

    // ?? 3. Participation decline ??????????????????????????????????????????
    // Fixed: <20% average participation (only if >=5 eligible voters).
    // Adaptive: participation drops >2.5sigma below the family's own baseline.
    //   Catches a family with normally 90% participation dropping to 60%
    //   (still above the 20% floor, but unusual for them).
    let partFixed = false;
    if (m.totalEligible >= 5 && m.participationRate < 0.20) {
      partFixed = true;
    }
    let partAdaptive = false;
    let partZ: number | undefined;
    let partMean: number | undefined;
    if (
      baseline.participationRate &&
      baseline.participationRate.count >= MIN_HISTORY_FOR_BASELINE &&
      typeof m.participationRate === 'number'
    ) {
      const z = zScore(m.participationRate, baseline.participationRate.mean, baseline.participationRate.stddev);
      if (z !== null && z <= -Z_SCORE_THRESHOLD) {
        partAdaptive = true;
        partZ = z;
        partMean = baseline.participationRate.mean;
      }
    }
    if (partFixed || partAdaptive) {
      anomalies.push({
        kind: 'participation_decline',
        severity: 'medium',
        message: partAdaptive && !partFixed
          ? `Participation rate is ${(m.participationRate * 100).toFixed(0)}% - unusually low for this family (baseline ${(partMean! * 100).toFixed(0)}%, z=${partZ!.toFixed(2)}).`
          : `Participation rate is ${(m.participationRate * 100).toFixed(0)}%. Consider sending reminders or reducing decision frequency.`,
        detectedAt: now,
        detectionSource: partFixed && partAdaptive ? 'both' : partFixed ? 'fixed_threshold' : 'adaptive_zscore',
        zScore: partZ,
        baselineMean: partMean,
      });
    }

    // ?? 4. Long decision durations ????????????????????????????????????????
    // Fixed: avg > 7 days (168h), only if >=2 decisions resolved.
    // Adaptive: avg duration >2.5sigma above the family's own baseline. Catches
    //   a family whose decisions normally resolve in 2 days suddenly taking 5.
    let slowFixed = false;
    if (m.decisionsResolved >= 2 && m.avgDurationHours > 168) {
      slowFixed = true;
    }
    let slowAdaptive = false;
    let slowZ: number | undefined;
    let slowMean: number | undefined;
    if (
      baseline.avgDurationHours &&
      baseline.avgDurationHours.count >= MIN_HISTORY_FOR_BASELINE &&
      typeof m.avgDurationHours === 'number'
    ) {
      const z = zScore(m.avgDurationHours, baseline.avgDurationHours.mean, baseline.avgDurationHours.stddev);
      if (z !== null && z >= Z_SCORE_THRESHOLD) {
        slowAdaptive = true;
        slowZ = z;
        slowMean = baseline.avgDurationHours.mean;
      }
    }
    if (slowFixed || slowAdaptive) {
      anomalies.push({
        kind: 'slow_decisions',
        severity: 'low',
        message: slowAdaptive && !slowFixed
          ? `Average decision duration is ${(m.avgDurationHours / 24).toFixed(1)} days - unusually slow for this family (baseline ${(slowMean! / 24).toFixed(1)} days, z=${slowZ!.toFixed(2)}).`
          : `Average decision duration is ${(m.avgDurationHours / 24).toFixed(1)} days. Consider setting tighter deadlines.`,
        detectedAt: now,
        detectionSource: slowFixed && slowAdaptive ? 'both' : slowFixed ? 'fixed_threshold' : 'adaptive_zscore',
        zScore: slowZ,
        baselineMean: slowMean,
      });
    }

    // Telemetry: how many anomalies fired from each path. Useful for
    // measuring the false-positive rate after shipping.
    const fixedCount = anomalies.filter((a) => a.detectionSource === 'fixed_threshold' || a.detectionSource === 'both').length;
    const adaptiveCount = anomalies.filter((a) => a.detectionSource === 'adaptive_zscore' || a.detectionSource === 'both').length;
    this.logger.debug?.(
      `AnomalyDetector: family=${params.familyId}, fixed=${fixedCount}, adaptive=${adaptiveCount}, ` +
        `history=${history.length} (baseline-eligible=${recent.length >= MIN_HISTORY_FOR_BASELINE ? 'yes' : 'no'})`,
    );

    return anomalies;
  }
}

// ?? Pure statistics helpers ??????????????????????????????????????????????

interface MetricBaseline {
  count: number;
  mean: number;
  stddev: number;
}

function computeBaselineStats(history: AnomalyHistorySnapshot[]): {
  quorumMetRate?: MetricBaseline;
  participationRate?: MetricBaseline;
  avgDurationHours?: MetricBaseline;
} {
  return {
    quorumMetRate: stats(history.map((h) => h.quorumMetRate).filter((v): v is number => typeof v === 'number')),
    participationRate: stats(history.map((h) => h.participationRate).filter((v): v is number => typeof v === 'number')),
    avgDurationHours: stats(history.map((h) => h.avgDurationHours).filter((v): v is number => typeof v === 'number')),
  };
}

/**
 * Compute mean + sample stddev for a list of values. Returns undefined if
 * the list is empty (no data) so callers can distinguish "no data" from
 * "data with zero variance".
 */
function stats(values: number[]): MetricBaseline | undefined {
  if (values.length === 0) return undefined;
  const n = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  if (n < 2) {
    // Single sample - stddev is undefined; return 0 so zScore will return 0
    // (no anomaly) rather than crashing.
    return { count: n, mean, stddev: 0 };
  }
  const variance = values.reduce((acc, v) => acc + (v - mean) ** 2, 0) / (n - 1);
  const stddev = Math.sqrt(variance);
  return { count: n, mean, stddev };
}

/**
 * Compute z-score: (x - mean) / stddev. Returns null if stddev is 0 (constant
 * series - no anomaly possible) or undefined inputs.
 */
function zScore(x: number, mean: number, stddev: number): number | null {
  if (!isFinite(x) || !isFinite(mean) || !isFinite(stddev)) return null;
  if (stddev === 0) return 0;
  return (x - mean) / stddev;
}
