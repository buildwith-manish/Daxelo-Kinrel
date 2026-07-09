// =============================================================================
// Track C v2.0 — AURA Analytics
// analytics.anomaly-detector.ts
// =============================================================================
// Detects anomalies in family governance patterns. Section 4.
//   - "No decisions in 30 days" — governance_dormant
//   - "Quorum met rate dropped below 30%" — quorum_decline
//   - "Participation rate below 20%" — participation_decline
//
// Target: <5% false positive rate in beta (Section 18 Phase C5 exit criteria).
// =============================================================================

import { Injectable } from '@nestjs/common';

export interface Anomaly {
  kind: string;
  severity: 'low' | 'medium' | 'high';
  message: string;
  detectedAt: string;
}

@Injectable()
export class AnalyticsAnomalyDetector {
  detect(params: {
    familyId: string;
    periodStart: Date;
    periodEnd: Date;
    granularity: string;
    metrics: any;
  }): Anomaly[] {
    const anomalies: Anomaly[] = [];
    const now = new Date().toISOString();
    const m = params.metrics;

    // 1. Governance dormancy: no decisions created in the period
    // (Only flag for weekly snapshots — monthly is too coarse)
    if (params.granularity === 'weekly' && m.decisionsCreated === 0) {
      // Only flag if the family has at least one prior decision (don't nag new families)
      // The caller can pass priorDecisionCount via metrics.priorDecisionCount
      if (m.priorDecisionCount && m.priorDecisionCount > 0) {
        anomalies.push({
          kind: 'governance_dormant',
          severity: 'medium',
          message: 'No decisions were created this week. Consider opening a family discussion.',
          detectedAt: now,
        });
      }
    }

    // 2. Quorum decline: <30% of decisions met quorum (only flag if ≥3 decisions)
    if (m.decisionsResolved >= 3 && m.quorumMetRate < 0.30) {
      anomalies.push({
        kind: 'quorum_decline',
        severity: 'high',
        message: `Only ${(m.quorumMetRate * 100).toFixed(0)}% of resolved decisions met quorum this ${params.granularity.replace('ly', '')}.`,
        detectedAt: now,
      });
    }

    // 3. Participation decline: <20% average participation
    if (m.totalEligible >= 5 && m.participationRate < 0.20) {
      anomalies.push({
        kind: 'participation_decline',
        severity: 'medium',
        message: `Participation rate is ${(m.participationRate * 100).toFixed(0)}%. Consider sending reminders or reducing decision frequency.`,
        detectedAt: now,
      });
    }

    // 4. Long decision durations: avg > 7 days
    if (m.decisionsResolved >= 2 && m.avgDurationHours > 168) {
      anomalies.push({
        kind: 'slow_decisions',
        severity: 'low',
        message: `Average decision duration is ${(m.avgDurationHours / 24).toFixed(1)} days. Consider setting tighter deadlines.`,
        detectedAt: now,
      });
    }

    return anomalies;
  }
}
