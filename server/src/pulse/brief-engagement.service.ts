// =============================================================================
// ML spec item #5 — Brief Engagement Service
// =============================================================================
// Prerequisite for the learned-weights model in closeness-weights.ts.
//
// Records per-user engagement events (open / tap / dismiss) on brief items,
// along with a snapshot of the 5 closeness signal scores that produced the
// item's relevanceScore. This snapshot is essential for training: we need
// to know what the signals WERE at the time the user made their engagement
// decision, even if the closeness formula changes later.
//
// Recording API:
//   recordEngagement({
//     userId, familyId, briefDate, itemKey, itemType, targetPersonId,
//     signalScores: { graphDistance, generationDistance, relationshipSemantic,
//                     kinrelRoleMatch, sharedConnections },
//     engagementType: 'opened' | 'tapped' | 'dismissed' | 'snoozed' | 'skipped',
//   })
//
// The trainer (closeness-weights.ts) reads these rows to learn weights.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export type BriefEngagementType =
  | 'opened'
  | 'tapped'
  | 'snoozed'
  | 'skipped'
  | 'dismissed';

export interface BriefSignalScores {
  graphDistance: number;
  generationDistance: number;
  relationshipSemantic: number;
  kinrelRoleMatch: number;
  sharedConnections: number;
}

@Injectable()
export class BriefEngagementService {
  private readonly logger = new Logger(BriefEngagementService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Record a brief item engagement event. Idempotent per (userId, itemKey,
   * engagementType) — the same user opening the same item twice is recorded
   * once with `engagementType='opened'`, then once with `engagementType='tapped'`
   * if they tap the action button, etc.
   *
   * The `engaged` and `dismissed` boolean flags are derived from
   * `engagementType` for fast aggregation in training queries:
   *   - opened, tapped → engaged=true, dismissed=false
   *   - snoozed, skipped → engaged=false, dismissed=false (neutral)
   *   - dismissed → engaged=false, dismissed=true (explicit negative)
   */
  async recordEngagement(params: {
    userId: string;
    familyId: string;
    briefDate: Date;
    itemKey: string;
    itemType: string;
    targetPersonId?: string | null;
    signalScores: BriefSignalScores;
    engagementType: BriefEngagementType;
  }): Promise<void> {
    const engaged = params.engagementType === 'opened' || params.engagementType === 'tapped';
    const dismissed = params.engagementType === 'dismissed';

    try {
      await this.prisma.briefEngagement.create({
        data: {
          userId: params.userId,
          familyId: params.familyId,
          briefDate: params.briefDate,
          itemKey: params.itemKey,
          itemType: params.itemType,
          targetPersonId: params.targetPersonId ?? null,
          signalScores: JSON.stringify(params.signalScores),
          engagementType: params.engagementType,
          engaged,
          dismissed,
          engagedAt: new Date(),
        },
      });
    } catch (err) {
      // Best-effort — don't break the brief open flow if engagement recording fails
      this.logger.debug?.(
        `Failed to record brief engagement for user ${params.userId}, item ${params.itemKey}: ${(err as Error).message}`,
      );
    }
  }

  /**
   * Export engagement data for training. Returns rows with parsed signal
   * scores and the engagement label. Used by the batch trainer in
   * closeness-weights.ts.
   *
   * Only returns rows where `engaged OR dismissed` is true — neutral events
   * (snoozed, skipped) don't provide a clear training signal.
   */
  async exportTrainingData(opts?: {
    familyId?: string;
    sinceDays?: number;
    limit?: number;
  }): Promise<Array<{
    userId: string;
    familyId: string;
    signalScores: BriefSignalScores;
    label: 1 | 0; // 1 = engaged, 0 = dismissed
  }>> {
    const where: any = {
      OR: [{ engaged: true }, { dismissed: true }],
    };
    if (opts?.familyId) where.familyId = opts.familyId;
    if (opts?.sinceDays) {
      const since = new Date(Date.now() - opts.sinceDays * 24 * 60 * 60 * 1000);
      where.engagedAt = { gte: since };
    }

    const rows = await this.prisma.briefEngagement.findMany({
      where,
      orderBy: { engagedAt: 'desc' },
      take: opts?.limit ?? 10000,
      select: {
        userId: true,
        familyId: true,
        signalScores: true,
        engaged: true,
      },
    });

    return rows.map((r) => {
      let scores: BriefSignalScores = {
        graphDistance: 0.5,
        generationDistance: 0.5,
        relationshipSemantic: 0.5,
        kinrelRoleMatch: 0.5,
        sharedConnections: 0.5,
      };
      try {
        const parsed = JSON.parse(r.signalScores);
        if (parsed && typeof parsed === 'object') {
          scores = {
            graphDistance: Number(parsed.graphDistance) || 0.5,
            generationDistance: Number(parsed.generationDistance) || 0.5,
            relationshipSemantic: Number(parsed.relationshipSemantic) || 0.5,
            kinrelRoleMatch: Number(parsed.kinrelRoleMatch) || 0.5,
            sharedConnections: Number(parsed.sharedConnections) || 0.5,
          };
        }
      } catch {
        // malformed row — use neutral defaults
      }
      return {
        userId: r.userId,
        familyId: r.familyId,
        signalScores: scores,
        label: (r.engaged ? 1 : 0) as 1 | 0,
      };
    });
  }

  /**
   * Get engagement summary stats for a family (or globally). Used by the
   * trainer to decide whether there's enough data to trust a learned model.
   */
  async getEngagementStats(opts?: { familyId?: string }): Promise<{
    totalEvents: number;
    engagedCount: number;
    dismissedCount: number;
    uniqueUsers: number;
    oldestEventAt: Date | null;
  }> {
    const where: any = {};
    if (opts?.familyId) where.familyId = opts.familyId;

    const [total, engaged, dismissed, oldest] = await Promise.all([
      this.prisma.briefEngagement.count({ where }),
      this.prisma.briefEngagement.count({ where: { ...where, engaged: true } }),
      this.prisma.briefEngagement.count({ where: { ...where, dismissed: true } }),
      this.prisma.briefEngagement.findFirst({
        where,
        orderBy: { engagedAt: 'asc' },
        select: { engagedAt: true },
      }),
    ]);

    const uniqueUsersRows = await this.prisma.briefEngagement.groupBy({
      by: ['userId'],
      where,
      _count: true,
    });

    return {
      totalEvents: total,
      engagedCount: engaged,
      dismissedCount: dismissed,
      uniqueUsers: uniqueUsersRows.length,
      oldestEventAt: oldest?.engagedAt ?? null,
    };
  }
}
