// server/src/pulse/pulse-query.service.ts
//
// PulseQueryService — read-only queries for the Pulse controller.
//
// All methods verify family membership inline (there is no FamilyMemberGuard).
// All methods return JSON-serializable shapes (no Prisma model instances).
//
// Methods:
//   - getTodayBrief(userId)        — today's brief for the user (or null)
//   - getBriefByDate(userId, date) — a specific date's brief (history)
//   - getBriefHistory(userId, opts)— last N days of briefs (paginated)
//   - getWeatherForUser(userId)    — all RelationshipWeather rows for the user
//   - getStreaksForUser(userId)    — all ConnectionStreak rows for the user
//   - getKarmaForUser(userId)      — all FamilyKarma rows for the user
//   - markBriefViewed(briefId, userId) — set viewedAt (idempotent)
//   - recordInteraction(briefItemId, userId, type, data?) — create BriefInteraction
//     + update BriefItem.interactedAt + award karma
//
// Note: the controller delegates all writes to recordInteraction so karma
// logic lives in one place.

import { Injectable, Logger, ForbiddenException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { InteractionType } from './brief-types';

// Karma awarded per interaction type. Tied to Kinrel role multipliers in Phase 6.
const KARMA_BY_INTERACTION: Record<InteractionType, number> = {
  call: 10,
  message: 5,
  view: 2,
  dismiss: 0,
  skip: 0,
  snooze: 0,
};

// Kinrel role multipliers (Phase 6 will refine these)
const KARMA_ROLE_MULTIPLIER: Record<string, number> = {
  root: 1.5,
  anchor: 1.3,
  bridge: 1.2,
  weaver: 1.1,
  leaf: 1.0,
  twin_node: 1.1,
};

@Injectable()
export class PulseQueryService {
  private readonly logger = new Logger(PulseQueryService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ────────────────────────────────────────────────────────────────────────
  // Reads
  // ────────────────────────────────────────────────────────────────────────

  async getTodayBrief(userId: string) {
    const today = this.todayUtcDate();
    return this.getBriefByDate(userId, today);
  }

  async getBriefByDate(userId: string, date: Date) {
    // Verify ownership (the (userId, briefDate) UNIQUE constraint guarantees
    // the brief belongs to this user, but we double-check family membership too)
    const brief = await this.prisma.dailyBrief.findUnique({
      where: {
        userId_briefDate: { userId, briefDate: date },
      },
      include: {
        items: {
          orderBy: { priority: 'desc' },
        },
      },
    });

    if (!brief) return null;

    // Family membership check (defense-in-depth)
    const isMember = await this.isFamilyMember(userId, brief.familyId);
    if (!isMember) {
      throw new ForbiddenException('User is not a member of this family');
    }

    return this.serializeBrief(brief);
  }

  async getBriefHistory(
    userId: string,
    opts: { days?: number; limit?: number } = {},
  ) {
    const days = opts.days ?? 30;
    const limit = opts.limit ?? 30;
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const briefs = await this.prisma.dailyBrief.findMany({
      where: {
        userId,
        briefDate: { gte: since },
      },
      orderBy: { briefDate: 'desc' },
      take: limit,
      include: {
        items: {
          orderBy: { priority: 'desc' },
        },
      },
    });

    return briefs.map((b) => this.serializeBrief(b));
  }

  async getWeatherForUser(userId: string) {
    const rows = await this.prisma.relationshipWeather.findMany({
      where: {
        OR: [{ userAId: userId }, { userBId: userId }],
      },
      orderBy: { updatedAt: 'desc' },
      include: {
        personB: { select: { id: true, name: true, photoThumb: true } },
        userB: { select: { id: true, name: true, photoThumb: true } },
      },
    });
    return rows.map((r) => ({
      id: r.id,
      familyId: r.familyId,
      weather: r.weather,
      daysSinceLastContact: r.daysSinceLastContact,
      interactionCount30d: r.interactionCount30d,
      sentimentScore: r.sentimentScore ? Number(r.sentimentScore) : null,
      streakDays: r.streakDays,
      previousWeather: r.previousWeather,
      weatherChangedAt: r.weatherChangedAt?.toISOString() ?? null,
      computedAt: r.computedAt.toISOString(),
      counterpart: r.personB
        ? { type: 'person', id: r.personB.id, name: r.personB.name, photoThumb: r.personB.photoThumb }
        : r.userB
          ? { type: 'user', id: r.userB.id, name: r.userB.name, photoThumb: r.userB.photoThumb }
          : null,
    }));
  }

  async getStreaksForUser(userId: string) {
    const rows = await this.prisma.connectionStreak.findMany({
      where: {
        OR: [{ userAId: userId }, { userBId: userId }],
      },
      orderBy: { currentStreak: 'desc' },
      include: {
        personB: { select: { id: true, name: true, photoThumb: true } },
        userB: { select: { id: true, name: true, photoThumb: true } },
      },
    });
    return rows.map((r) => ({
      id: r.id,
      familyId: r.familyId,
      currentStreak: r.currentStreak,
      longestStreak: r.longestStreak,
      lastInteractionAt: r.lastInteractionAt?.toISOString() ?? null,
      streakStartedAt: r.streakStartedAt?.toISOString() ?? null,
      streakBrokenAt: r.streakBrokenAt?.toISOString() ?? null,
      streakType: r.streakType,
      counterpart: r.personB
        ? { type: 'person', id: r.personB.id, name: r.personB.name, photoThumb: r.personB.photoThumb }
        : r.userB
          ? { type: 'user', id: r.userB.id, name: r.userB.name, photoThumb: r.userB.photoThumb }
          : null,
    }));
  }

  async getKarmaForUser(userId: string) {
    const rows = await this.prisma.familyKarma.findMany({
      where: { userId },
      orderBy: { totalKarma: 'desc' },
    });
    return rows.map((r) => ({
      id: r.id,
      familyId: r.familyId,
      totalKarma: r.totalKarma,
      karmaThisWeek: r.karmaThisWeek,
      karmaThisMonth: r.karmaThisMonth,
      karmaTrend: r.karmaTrend,
      karmaByRole: {
        root: r.karmaAsRoot,
        anchor: r.karmaAsAnchor,
        bridge: r.karmaAsBridge,
        weaver: r.karmaAsWeaver,
        leaf: r.karmaAsLeaf,
      },
      recentReasons: r.recentReasons,
      lastKarmaAt: r.lastKarmaAt?.toISOString() ?? null,
    }));
  }

  // ────────────────────────────────────────────────────────────────────────
  // Writes
  // ────────────────────────────────────────────────────────────────────────

  /** Mark a brief as viewed (idempotent — only sets viewedAt if not already set). */
  async markBriefViewed(briefId: string, userId: string): Promise<void> {
    const brief = await this.prisma.dailyBrief.findUnique({
      where: { id: briefId },
      select: { userId: true, viewedAt: true },
    });
    if (!brief) throw new NotFoundException('Brief not found');
    if (brief.userId !== userId) throw new ForbiddenException('Not your brief');

    if (!brief.viewedAt) {
      await this.prisma.dailyBrief.update({
        where: { id: briefId },
        data: { viewedAt: new Date() },
      });
    }
  }

  /**
   * Record a user's interaction with a brief item.
   *   1. Verify the brief item belongs to the user
   *   2. Create BriefInteraction row
   *   3. Update BriefItem.interactedAt + interactionType (denormalized for fast queries)
   *   4. Update DailyBrief aggregates (interactionCount, callsInitiated, messagesSent, etc.)
   *   5. Award karma: look up the user's Kinrel role in this family, compute
   *      KARMA_BY_INTERACTION[type] * KARMA_ROLE_MULTIPLIER[roleKey], round, then
   *      upsert FamilyKarma row + append to recentReasons.
   * Returns the awarded karma amount.
   */
  async recordInteraction(
    briefItemId: string,
    userId: string,
    interactionType: InteractionType,
    interactionData: Record<string, unknown> = {},
  ): Promise<{ karmaAwarded: number }> {
    // 1. Verify ownership
    const item = await this.prisma.briefItem.findUnique({
      where: { id: briefItemId },
      select: {
        id: true,
        briefId: true,
        userId: true,
        familyId: true,
        itemType: true,
        actionType: true,
        brief: { select: { id: true, callsInitiated: true, messagesSent: true, memoriesViewed: true, interactionCount: true, karmaEarned: true } },
      },
    });
    if (!item) throw new NotFoundException('Brief item not found');
    if (item.userId !== userId) throw new ForbiddenException('Not your brief item');

    // 2. Lookup user's Kinrel role for karma multiplier
    let roleKey: string | null = null;
    const linkedPerson = await this.prisma.person.findFirst({
      where: { linkedUserId: userId, deletedAt: null },
      select: { id: true },
    });
    if (linkedPerson) {
      const role = await this.prisma.memberKinrelRole
        .findUnique({
          where: {
            familyId_memberId: {
              familyId: item.familyId,
              memberId: linkedPerson.id,
            },
          },
          select: { roleKey: true },
        })
        .catch(() => null);
      roleKey = role?.roleKey ?? null;
    }

    // 3. Compute karma
    const baseKarma = KARMA_BY_INTERACTION[interactionType] ?? 0;
    const multiplier = roleKey ? (KARMA_ROLE_MULTIPLIER[roleKey] ?? 1.0) : 1.0;
    const karmaAwarded = Math.round(baseKarma * multiplier);

    // 4. Transaction: create interaction + update brief item + update brief aggregates + upsert karma
    await this.prisma.$transaction(async (tx) => {
      // 4a. BriefInteraction row
      await tx.briefInteraction.create({
        data: {
          briefItemId,
          userId,
          interactionType,
          interactionData: interactionData as any,
          karmaAwarded,
        },
      });

      // 4b. Update BriefItem (denormalized interaction tracking)
      await tx.briefItem.update({
        where: { id: briefItemId },
        data: {
          interactedAt: new Date(),
          interactionType,
        },
      });

      // 4c. Update DailyBrief aggregates
      const briefUpdates: any = {
        interactionCount: { increment: 1 },
        karmaEarned: { increment: karmaAwarded },
        interactedAt: new Date(),
      };
      if (interactionType === 'call') briefUpdates.callsInitiated = { increment: 1 };
      if (interactionType === 'message') briefUpdates.messagesSent = { increment: 1 };
      if (item.itemType === 'memory_orbit' && interactionType === 'view') {
        briefUpdates.memoriesViewed = { increment: 1 };
      }
      await tx.dailyBrief.update({
        where: { id: item.briefId },
        data: briefUpdates,
      });

      // 4d. Upsert FamilyKarma
      if (karmaAwarded > 0) {
        const reason = `${interactionType} on ${item.itemType} item`;
        const newReason = {
          amount: karmaAwarded,
          reason,
          timestamp: new Date().toISOString(),
          roleKey: roleKey ?? 'leaf',
        };

        // Read existing karma row
        const existing = await tx.familyKarma.findUnique({
          where: {
            userId_familyId: {
              userId,
              familyId: item.familyId,
            },
          },
        });

        if (existing) {
          // Append to recentReasons (cap at 10)
          const recentReasons = Array.isArray(existing.recentReasons)
            ? (existing.recentReasons as any[])
            : [];
          const updatedReasons = [newReason, ...recentReasons].slice(0, 10);

          // Increment role-specific karma bucket
          const roleBucket =
            roleKey === 'root'
              ? { karmaAsRoot: { increment: karmaAwarded } }
              : roleKey === 'anchor'
                ? { karmaAsAnchor: { increment: karmaAwarded } }
                : roleKey === 'bridge'
                  ? { karmaAsBridge: { increment: karmaAwarded } }
                  : roleKey === 'weaver'
                    ? { karmaAsWeaver: { increment: karmaAwarded } }
                    : { karmaAsLeaf: { increment: karmaAwarded } };

          await tx.familyKarma.update({
            where: { id: existing.id },
            data: {
              totalKarma: { increment: karmaAwarded },
              karmaThisWeek: { increment: karmaAwarded },
              karmaThisMonth: { increment: karmaAwarded },
              lastKarmaAt: new Date(),
              recentReasons: updatedReasons as any,
              ...roleBucket,
            },
          });
        } else {
          // Create new karma row
          const roleBucket =
            roleKey === 'root'
              ? { karmaAsRoot: karmaAwarded }
              : roleKey === 'anchor'
                ? { karmaAsAnchor: karmaAwarded }
                : roleKey === 'bridge'
                  ? { karmaAsBridge: karmaAwarded }
                  : roleKey === 'weaver'
                    ? { karmaAsWeaver: karmaAwarded }
                    : { karmaAsLeaf: karmaAwarded };

          await tx.familyKarma.create({
            data: {
              userId,
              familyId: item.familyId,
              totalKarma: karmaAwarded,
              karmaThisWeek: karmaAwarded,
              karmaThisMonth: karmaAwarded,
              lastKarmaAt: new Date(),
              recentReasons: [newReason] as any,
              ...roleBucket,
            },
          });
        }
      }
    });

    return { karmaAwarded };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────

  private async isFamilyMember(userId: string, familyId: string): Promise<boolean> {
    const fm = await this.prisma.familyMember.findUnique({
      where: {
        familyId_userId: { familyId, userId },
      },
      select: { id: true },
    });
    return fm !== null;
  }

  private serializeBrief(brief: any) {
    return {
      id: brief.id,
      userId: brief.userId,
      familyId: brief.familyId,
      briefDate: this.formatDate(brief.briefDate),
      greeting: brief.greeting,
      familyArchetype: brief.familyArchetype,
      languageCode: brief.languageCode,
      content: brief.content,
      generatedAt: brief.generatedAt.toISOString(),
      deliveredAt: brief.deliveredAt?.toISOString() ?? null,
      viewedAt: brief.viewedAt?.toISOString() ?? null,
      interactedAt: brief.interactedAt?.toISOString() ?? null,
      interactionCount: brief.interactionCount,
      callsInitiated: brief.callsInitiated,
      messagesSent: brief.messagesSent,
      memoriesViewed: brief.memoriesViewed,
      karmaEarned: brief.karmaEarned,
      items: (brief.items ?? []).map((it: any) => ({
        id: it.id,
        itemType: it.itemType,
        priority: it.priority,
        title: it.title,
        body: it.body,
        actionLabel: it.actionLabel,
        actionType: it.actionType,
        actionData: it.actionData,
        targetPersonId: it.targetPersonId,
        targetUserId: it.targetUserId,
        targetSparqId: it.targetSparqId,
        targetPostId: it.targetPostId,
        relevanceScore: it.relevanceScore ? Number(it.relevanceScore) : null,
        interactedAt: it.interactedAt?.toISOString() ?? null,
        interactionType: it.interactionType,
        createdAt: it.createdAt.toISOString(),
      })),
    };
  }

  private todayUtcDate(): Date {
    const now = new Date();
    return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  }

  private formatDate(d: Date): string {
    const yyyy = d.getUTCFullYear();
    const mm = String(d.getUTCMonth() + 1).padStart(2, '0');
    const dd = String(d.getUTCDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }
}
