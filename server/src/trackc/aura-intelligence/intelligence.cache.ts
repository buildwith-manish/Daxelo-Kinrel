// =============================================================================
// Track C v2.0 — AURA Intelligence
// intelligence.cache.ts
// =============================================================================
// Cache layer for AI insights. Section 8.2.
//
// Cache rules per kind:
//   decision_analysis   7 days   invalidated by decision title/description/options change
//   duplicate_detection 1 hour   invalidated by new decision created in family
//   summary             30 days  invalidated by decision resolved or memory updated
//   pros_cons           7 days   invalidated by decision description changed
//   smart_reminder      per-reminder invalidated by reminder acted/snoozed/dismissed
//   action_items        7 days   invalidated by meeting artifact updated
//   draft_minutes       1 hour   invalidated by artifact status → published
//
// The cache uses the AIInsight table itself (no separate cache store needed).
// "Cache hit" = an existing AIInsight row with status != 'stale' and within TTL.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export type InsightKind =
  | 'decision_analysis'
  | 'duplicate_detection'
  | 'summary'
  | 'pros_cons'
  | 'smart_reminder'
  | 'action_items'
  | 'draft_minutes'
  | 'search_synonym';

const TTL_MS: Record<InsightKind, number> = {
  decision_analysis: 7 * 24 * 60 * 60 * 1000,
  duplicate_detection: 60 * 60 * 1000,
  summary: 30 * 24 * 60 * 60 * 1000,
  pros_cons: 7 * 24 * 60 * 60 * 1000,
  smart_reminder: 0, // per-reminder, no TTL
  action_items: 7 * 24 * 60 * 60 * 1000,
  draft_minutes: 60 * 60 * 1000,
  search_synonym: 7 * 24 * 60 * 60 * 1000,
};

@Injectable()
export class IntelligenceCache {
  private readonly logger = new Logger(IntelligenceCache.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Look up a cached insight for a given (decisionId, kind).
   * Returns null if no cached insight or if cache is stale.
   */
  async lookup(params: {
    familyId: string;
    decisionId?: string;
    kind: InsightKind;
    now?: Date;
  }) {
    const now = params.now ?? new Date();
    const ttl = TTL_MS[params.kind];

    const where: any = {
      familyId: params.familyId,
      kind: params.kind,
      status: { in: ['pending', 'presented', 'accepted', 'dismissed'] },
    };
    if (params.decisionId) where.decisionId = params.decisionId;

    const candidates = await this.prisma.aIInsight.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: 5,
    });

    for (const c of candidates) {
      // TTL check (skip for smart_reminder which is per-reminder)
      if (ttl > 0 && now.getTime() - c.createdAt.getTime() > ttl) {
        continue;
      }
      return c;
    }
    return null;
  }

  /**
   * Mark cached insights of a given kind as stale. Called when the underlying
   * entity changes (e.g., decision title edited → invalidate decision_analysis).
   */
  async invalidate(params: {
    familyId: string;
    kind?: InsightKind;
    decisionId?: string;
  }) {
    const where: any = {
      familyId: params.familyId,
      status: { in: ['pending', 'presented'] },
    };
    if (params.kind) where.kind = params.kind;
    if (params.decisionId) where.decisionId = params.decisionId;

    const result = await this.prisma.aIInsight.updateMany({
      where,
      data: { status: 'stale' },
    });
    if (result.count > 0) {
      this.logger.debug(
        `Invalidated ${result.count} cached insights (family=${params.familyId}, kind=${params.kind ?? '*'}, decision=${params.decisionId ?? '*'})`,
      );
    }
    return result.count;
  }

  /**
   * Mark an insight as presented to the user. Called when the client fetches it.
   */
  async markPresented(insightId: string, familyId: string) {
    return this.prisma.aIInsight.update({
      where: { id_familyId: { id: insightId, familyId } },
      data: { status: 'presented', presentedAt: new Date() },
    });
  }

  /**
   * Mark an insight as accepted by the user.
   */
  async markAccepted(insightId: string, familyId: string) {
    return this.prisma.aIInsight.update({
      where: { id_familyId: { id: insightId, familyId } },
      data: { status: 'accepted', acceptedAt: new Date() },
    });
  }

  /**
   * Mark an insight as dismissed by the user.
   */
  async markDismissed(
    insightId: string,
    familyId: string,
    reason: 'not_relevant' | 'already_known' | 'too_prescriptive' | 'other',
  ) {
    return this.prisma.aIInsight.update({
      where: { id_familyId: { id: insightId, familyId } },
      data: { status: 'dismissed', dismissedAt: new Date(), dismissedReason: reason },
    });
  }
}
