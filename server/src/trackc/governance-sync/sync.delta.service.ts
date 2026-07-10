// =============================================================================
// Track C v2.0 — Governance Sync
// sync.delta.service.ts
// =============================================================================
// Delta sync endpoint. Section 7 + 6.8.
//
// Each device maintains a per-family `sync_watermark` (ISO timestamp of last
// successful delta fetch). The server's delta endpoint returns all rows where
// `updatedAt > watermark` AND `familyId IN (...)`.
//
// Monotonic clock guarantee: the DB trigger `fn_trackc_monotonic_updated_at`
// ensures `updatedAt` is strictly greater than the previous value on every
// UPDATE, preventing microsecond collisions from skipping rows.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { FamilyMembershipService } from '../common/family-membership.service';

@Injectable()
export class SyncDeltaService {
  private readonly logger = new Logger(SyncDeltaService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly membership: FamilyMembershipService,
  ) {}

  /**
   * Get all changes since the watermark for the families the user is a member of.
   * Updates the watermark to `now()` on success.
   *
   * Edge case #15: Sync watermark in the future (clock skew) — clamp to now().
   */
  async getDelta(params: {
    userId: string;
    deviceId: string;
    since?: string; // ISO timestamp watermark; defaults to epoch
    families?: string[]; // CSV; defaults to all user's families
    limit?: number;
  }) {
    // Determine which families the user is a member of
    const membershipFilter = { userId: params.userId };
    const memberships = await this.prisma.familyMember.findMany({
      where: membershipFilter,
      select: { familyId: true },
    });
    const allFamilyIds = memberships.map((m) => m.familyId);
    const requestedFamilies = params.families?.length ? params.families : allFamilyIds;
    // Intersect: only families the user is actually a member of (defense in depth)
    const familyIds = requestedFamilies.filter((id) => allFamilyIds.includes(id));

    if (familyIds.length === 0) {
      return {
        watermark: new Date().toISOString(),
        changes: {},
        deletions: {},
        clamped: false,
      };
    }

    // Clamp watermark if it's in the future (edge case #15)
    let sinceDate = params.since ? new Date(params.since) : new Date(0);
    let clamped = false;
    const now = new Date();
    if (sinceDate > now) {
      sinceDate = now;
      clamped = true;
    }

    const limit = Math.min(params.limit ?? 500, 2000);

    // ── Parallel fetch of all entity types ────────────────────────────────
    const [
      constitutions,
      constitutionVersions,
      constitutionArticles,
      constitutionClauses,
      decisions,
      votes,
      timelineEvents,
      memories,
      impacts,
      meetingArtifacts,
      insights,
      behaviorProfile,
      reminders,
      searchIndex,
      analyticsSnapshots,
    ] = await Promise.all([
      this.prisma.familyConstitution.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.constitutionVersion.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.constitutionArticle.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.constitutionClause.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.familyDecision.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.decisionVote.findMany({
        where: { familyId: { in: familyIds }, createdAt: { gt: sinceDate } },
        take: limit,
      }),
      // Timeline events use occurredAt (no updatedAt; append-only)
      this.prisma.kinrelTimelineEvent.findMany({
        where: { familyId: { in: familyIds }, occurredAt: { gt: sinceDate } },
        take: limit,
        orderBy: { occurredAt: 'asc' },
      }),
      this.prisma.decisionMemory.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.decisionImpact.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.meetingArtifact.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.aIInsight.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.familyBehaviorProfile.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.smartReminder.findMany({
        where: { familyId: { in: familyIds }, targetUserId: params.userId, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.searchIndex.findMany({
        where: { familyId: { in: familyIds }, updatedAt: { gt: sinceDate } },
        take: limit,
      }),
      this.prisma.familyAnalyticsSnapshot.findMany({
        where: { familyId: { in: familyIds }, createdAt: { gt: sinceDate } },
        take: limit,
      }),
    ]);

    // ── Update the per-device watermark ───────────────────────────────────
    const newWatermark = now.toISOString();
    await Promise.all(
      familyIds.map((familyId) =>
        this.prisma.syncWatermark.upsert({
          where: {
            userId_familyId_deviceId: {
              userId: params.userId,
              familyId,
              deviceId: params.deviceId,
            },
          },
          create: {
            userId: params.userId,
            familyId,
            deviceId: params.deviceId,
            watermark: now,
          },
          update: { watermark: now },
        }),
      ),
    );

    return {
      watermark: newWatermark,
      clamped,
      changes: {
        constitutions,
        constitutionVersions,
        constitutionArticles,
        constitutionClauses,
        decisions,
        votes,
        timelineEvents,
        memories,
        impacts,
        meetingArtifacts,
        insights,
        behaviorProfile,
        reminders,
        searchIndex,
        analyticsSnapshots,
      },
      deletions: {
        // Track C v2.0 entities are soft-delete (cascade on Family delete);
        // individual hard deletes are rare and tracked via timeline 'correction' events.
        // For now, no per-entity deletions are returned.
      },
    };
  }
}
