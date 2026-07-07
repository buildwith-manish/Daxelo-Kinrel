// server/src/pulse/brief-generator.service.ts
//
// BriefGeneratorService — the orchestrator that builds the daily brief.
//
// Pipeline (per user):
//   1. Load context: User, Family, FamilyAura (if exists), MemberAuraRole (if exists)
//   2. Build BriefCollectorContext
//   3. Run all 6 collectors in parallel via Promise.allSettled
//      (each collector is defensive — a rejection is logged but doesn't break the brief)
//   4. Merge all BriefItemData[] into one array
//   5. Sort by priority DESC, then by itemType ordering (need_you > birthday > weather > memory_orbit > on_this_day > feed_highlight)
//   6. Cap at 6 items (the "6-item brief" UX target)
//   7. Generate the greeting (localized, 8 languages)
//   8. Generate the summary ("N things need you today" / "Your family is quiet today" / etc.)
//   9. Upsert DailyBrief row (one per user per day — re-generation overwrites)
//  10. Delete old BriefItem rows for this briefId, then insert fresh ones
//  11. Emit 'pulse.brief.generated' event for analytics/notifications
//  12. Return BriefResult
//
// Public methods:
//   - generateBriefForUser(userId, opts?) → BriefResult
//   - generateBriefsForFamily(familyId, opts?) → BriefResult[] (one per family member)
//   - generateAllBriefs(opts?) → { familiesProcessed, usersProcessed, errors[] }
//   - setCollectors(collectors[]) — called by PulseModule OnModuleInit
//
// The `opts.forDate` field lets the caller generate a brief for a specific date
// (defaults to today UTC). This is used by the validation script and the
// `GET /pulse/:date` endpoint.

import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { EventEmitter2 } from '@nestjs/event-emitter';
import { PrismaService } from '../prisma/prisma.service';
import {
  BriefCollector,
  BriefCollectorContext,
  BriefItemData,
  BriefItemType,
  BriefResult,
  localizeGreeting,
  ITEM_TYPE_ICONS,
} from './brief-types';
import { PersonalizationService } from './personalization.service';

const MAX_ITEMS_PER_BRIEF = 6;

// Tie-breaker ordering when priorities are equal
const ITEM_TYPE_ORDER: Record<BriefItemType, number> = {
  need_you: 0,
  birthday: 1,
  weather: 2,
  memory_orbit: 3,
  on_this_day: 4,
  feed_highlight: 5,
};

export interface GenerateBriefOptions {
  forDate?: Date; // defaults to today UTC
  skipPersist?: boolean; // for dry-run validation
}

interface LoadedContext {
  user: {
    id: string;
    name: string | null;
    preferredLanguage: string;
  };
  family: {
    id: string;
    primaryLanguage: string;
  };
  familyArchetype: string;
  userPersonId: string | null;
  userRoleKey: string | null;
}

@Injectable()
export class BriefGeneratorService implements OnModuleInit {
  private readonly logger = new Logger(BriefGeneratorService.name);
  private collectors: BriefCollector[] = [];

  constructor(
    private readonly prisma: PrismaService,
    private readonly eventEmitter: EventEmitter2,
    private readonly personalization: PersonalizationService,
  ) {}

  /**
   * Called by PulseModule after all collectors are injected.
   * Order matters for tie-breaking, but the priority field dominates.
   */
  setCollectors(collectors: BriefCollector[]): void {
    this.collectors = collectors;
    this.logger.log(
      `BriefGeneratorService: ${collectors.length} collectors registered: ${collectors.map((c) => c.name).join(', ')}`,
    );
  }

  /** OnModuleInit — collectollectors are set by PulseModule, so we just log here. */
  onModuleInit() {
    if (this.collectors.length === 0) {
      this.logger.warn('BriefGeneratorService: no collectors registered at OnModuleInit');
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────────────

  /**
   * Generate a brief for a single user.
   * If the user has no family, throws an error.
   * If the user has multiple families, generates for the FIRST one (Phase 1
   * limitation — Phase 2 will generate one brief per (user, family) pair).
   */
  async generateBriefForUser(
    userId: string,
    opts: GenerateBriefOptions = {},
  ): Promise<BriefResult> {
    const forDate = opts.forDate ?? this.todayUtc();

    // 1. Load context
    const ctx = await this.loadContext(userId);
    if (!ctx) {
      throw new Error(
        `BriefGenerator: user ${userId} has no family membership — cannot generate brief`,
      );
    }

    // 1b. Phase 2: Load the family graph + cache it for the duration of this brief.
    // Collectors will use ctx.personalization to compute per-target closeness scores.
    try {
      await this.personalization.loadFamilyGraph(ctx.family.id, userId);
    } catch (err) {
      // Non-fatal: personalization is a Phase 2 enhancement. If the graph fails
      // to load, collectors will fall back to neutral 0.5 relevance scores.
      this.logger.warn(
        `BriefGenerator: personalization graph load failed (continuing with neutral scores): ${err instanceof Error ? err.message : err}`,
      );
    }

    // 2. Build BriefCollectorContext
    const collectorCtx: BriefCollectorContext = {
      userId: ctx.user.id,
      familyId: ctx.family.id,
      briefDate: forDate,
      userLanguageCode: ctx.user.preferredLanguage ?? ctx.family.primaryLanguage ?? 'en',
      userDisplayName: ctx.user.name,
      familyArchetype: ctx.familyArchetype,
      userPersonId: ctx.userPersonId,
      userRoleKey: ctx.userRoleKey,
      // Phase 2: expose personalization to collectors (with the cached graph)
      personalization: {
        computeClosenessForTarget: (targetPersonId: string) =>
          this.personalization.computeClosenessForTarget(ctx.family.id, targetPersonId),
      },
    };

    // 3. Run all collectors in parallel (defensive: Promise.allSettled)
    const settled = await Promise.allSettled(
      this.collectors.map((c) => c.collect(collectorCtx)),
    );
    const allItems: BriefItemData[] = [];
    for (let i = 0; i < settled.length; i++) {
      const r = settled[i];
      if (r.status === 'fulfilled') {
        allItems.push(...r.value);
      } else {
        const collectorName = this.collectors[i]?.name ?? 'unknown';
        this.logger.error(
          `BriefGenerator: collector '${collectorName}' rejected: ${r.reason instanceof Error ? r.reason.message : r.reason}`,
        );
      }
    }

    // 4. Sort by priority DESC, then by itemType order
    allItems.sort((a, b) => {
      if (b.priority !== a.priority) return b.priority - a.priority;
      const oA = ITEM_TYPE_ORDER[a.itemType] ?? 99;
      const oB = ITEM_TYPE_ORDER[b.itemType] ?? 99;
      return oA - oB;
    });

    // 4b. Phase 2: Apply closeness-based tie-breaker.
    // Within each priority window of ±5, sort by relevanceScore DESC.
    // This is what makes "Manish (cousin, closeness 0.8)" rank above
    // "RandomDistantUncle (closeness 0.3)" even when both are need_you@60.
    const tieBroken = this.personalization.applyTieBreaker(allItems, 5);

    // 5. Cap at MAX_ITEMS_PER_BRIEF
    const items = tieBroken.slice(0, MAX_ITEMS_PER_BRIEF);

    // 6. Build greeting + summary
    const greeting = localizeGreeting(collectorCtx.userLanguageCode, ctx.user.name);
    const summary = this.buildSummary(items, collectorCtx);

    // 7. Assemble result
    const result: BriefResult = {
      id: '', // will be filled after persist
      userId: ctx.user.id,
      familyId: ctx.family.id,
      briefDate: this.formatDate(forDate),
      greeting,
      familyArchetype: ctx.familyArchetype,
      languageCode: collectorCtx.userLanguageCode,
      items,
      summary,
      generatedAt: new Date().toISOString(),
    };

    if (opts.skipPersist) {
      // Free the personalization cache before returning
      this.personalization.clearCache(ctx.family.id);
      return result;
    }

    // 8. Persist (upsert DailyBrief + replace BriefItem rows)
    const persisted = await this.persistBrief(result, forDate);
    result.id = persisted.id;

    // 9. Emit event for analytics/notifications
    this.eventEmitter.emit('pulse.brief.generated', {
      userId: result.userId,
      familyId: result.familyId,
      briefDate: result.briefDate,
      itemCount: items.length,
      itemTypes: items.map((i) => i.itemType),
    });

    // 10. Phase 2: free the personalization cache for this family
    this.personalization.clearCache(ctx.family.id);

    return result;
  }

  /**
   * Generate briefs for ALL members of a family.
   * Returns one BriefResult per family member (in parallel).
   * Errors are collected, not thrown — one user's failure doesn't block others.
   */
  async generateBriefsForFamily(
    familyId: string,
    opts: GenerateBriefOptions = {},
  ): Promise<BriefResult[]> {
    const members = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: { userId: true },
    });

    if (members.length === 0) {
      this.logger.warn(`BriefGenerator: family ${familyId} has no members`);
      return [];
    }

    const results: BriefResult[] = [];
    const errors: { userId: string; error: string }[] = [];

    // Process in parallel with limited concurrency (5 at a time)
    const concurrency = 5;
    for (let i = 0; i < members.length; i += concurrency) {
      const batch = members.slice(i, i + concurrency);
      const settled = await Promise.allSettled(
        batch.map((m) => this.generateBriefForUser(m.userId, opts)),
      );
      for (let j = 0; j < settled.length; j++) {
        const r = settled[j];
        if (r.status === 'fulfilled') {
          results.push(r.value);
        } else {
          errors.push({
            userId: batch[j].userId,
            error: r.reason instanceof Error ? r.reason.message : String(r.reason),
          });
          this.logger.error(
            `BriefGenerator: failed for user ${batch[j].userId} in family ${familyId}: ${errors[errors.length - 1].error}`,
          );
        }
      }
    }

    this.logger.log(
      `BriefGenerator: family ${familyId} — ${results.length}/${members.length} briefs generated, ${errors.length} errors`,
    );

    return results;
  }

  /**
   * Generate briefs for ALL users across ALL families.
   * Called by the 7am cron job. Designed to be idempotent and resumable.
   * Returns aggregate stats for monitoring.
   */
  async generateAllBriefs(
    opts: GenerateBriefOptions = {},
  ): Promise<{
    familiesProcessed: number;
    usersProcessed: number;
    briefsGenerated: number;
    errors: { familyId: string; userId: string; error: string }[];
  }> {
    const families = await this.prisma.family.findMany({
      where: { deletedAt: null },
      select: { id: true },
    });

    let usersProcessed = 0;
    let briefsGenerated = 0;
    const errors: { familyId: string; userId: string; error: string }[] = [];

    for (const fam of families) {
      try {
        const before = briefsGenerated;
        const results = await this.generateBriefsForFamily(fam.id, opts);
        briefsGenerated += results.length;
        usersProcessed += results.length;
        if (results.length === 0) {
          // family had no members or all failed — log it
          this.logger.warn(`BriefGenerator: family ${fam.id} produced 0 briefs`);
        }
        // Any per-user errors from generateBriefsForFamily are already logged,
        // but we don't get the structured error list back. To capture them,
        // we'd need to refactor — for now, the per-family log line is enough.
        void before;
      } catch (err) {
        errors.push({
          familyId: fam.id,
          userId: '*',
          error: err instanceof Error ? err.message : String(err),
        });
        this.logger.error(
          `BriefGenerator: family ${fam.id} failed: ${errors[errors.length - 1].error}`,
        );
      }
    }

    this.logger.log(
      `BriefGenerator: all briefs done — families=${families.length}, users=${usersProcessed}, briefs=${briefsGenerated}, errors=${errors.length}`,
    );

    return {
      familiesProcessed: families.length,
      usersProcessed,
      briefsGenerated,
      errors,
    };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ────────────────────────────────────────────────────────────────────────

  private async loadContext(userId: string): Promise<LoadedContext | null> {
    // 1. Find the user's FIRST family membership
    const fm = await this.prisma.familyMember.findFirst({
      where: { userId },
      select: {
        familyId: true,
        family: {
          select: { id: true, primaryLanguage: true },
        },
        user: {
          select: { id: true, name: true, preferredLanguage: true },
        },
      },
    });

    if (!fm) return null;

    // 2. Look up the user's linked Person (if any)
    const linkedPerson = await this.prisma.person.findFirst({
      where: { linkedUserId: userId, deletedAt: null },
      select: { id: true, familyId: true },
    });

    // 3. Look up FamilyAura (current archetype for this family)
    const aura = await this.prisma.familyAura.findUnique({
      where: { familyId: fm.familyId },
      select: { archetypeKey: true },
    });

    // 4. Look up MemberAuraRole for this user's Person (if any)
    let userRoleKey: string | null = null;
    if (linkedPerson) {
      const role = await this.prisma.memberAuraRole.findUnique({
        where: {
          familyId_memberId: {
            familyId: fm.familyId,
            memberId: linkedPerson.id,
          },
        },
        select: { roleKey: true },
      }).catch(() => null);
      userRoleKey = role?.roleKey ?? null;
    }

    return {
      user: {
        id: fm.user.id,
        name: fm.user.name,
        preferredLanguage: fm.user.preferredLanguage,
      },
      family: {
        id: fm.family.id,
        primaryLanguage: fm.family.primaryLanguage,
      },
      familyArchetype: aura?.archetypeKey ?? 'unknown',
      userPersonId: linkedPerson?.id ?? null,
      userRoleKey,
    };
  }

  /**
   * Build the one-sentence summary that appears under the greeting.
   * Examples:
   *   "3 things need your attention today."
   *   "Your family is quiet today — reach out to someone."
   *   "Birthdays this week, and 1 relationship needs a check-in."
   *   "Nothing urgent today. Enjoy your family."
   */
  private buildSummary(
    items: BriefItemData[],
    ctx: BriefCollectorContext,
  ): string {
    if (items.length === 0) {
      return 'Nothing urgent today. Enjoy your family.';
    }

    const counts: Record<string, number> = {};
    for (const item of items) {
      counts[item.itemType] = (counts[item.itemType] ?? 0) + 1;
    }

    const needYou = counts['need_you'] ?? 0;
    const birthdays = counts['birthday'] ?? 0;
    const weather = counts['weather'] ?? 0;
    const feeds = counts['feed_highlight'] ?? 0;
    const onThisDay = counts['on_this_day'] ?? 0;
    const memoryOrbit = counts['memory_orbit'] ?? 0;

    const parts: string[] = [];
    if (needYou > 0) {
      parts.push(
        needYou === 1
          ? '1 person needs you today'
          : `${needYou} people need you today`,
      );
    }
    if (birthdays > 0) {
      parts.push(
        birthdays === 1 ? '1 birthday this week' : `${birthdays} birthdays this week`,
      );
    }
    if (weather > 0) {
      parts.push(
        weather === 1
          ? '1 relationship needs a check-in'
          : `${weather} relationships need a check-in`,
      );
    }
    if (memoryOrbit > 0) {
      parts.push(`${memoryOrbit} memory to revisit`);
    }
    if (onThisDay > 0) {
      parts.push('a moment from the past');
    }
    if (feeds > 0) {
      parts.push(feeds === 1 ? '1 family update' : `${feeds} family updates`);
    }

    if (parts.length === 0) {
      return 'Nothing urgent today. Enjoy your family.';
    }
    if (parts.length === 1) {
      return parts[0] + '.';
    }
    if (parts.length === 2) {
      return parts.join(' and ') + '.';
    }
    return parts.slice(0, -1).join(', ') + ', and ' + parts[parts.length - 1] + '.';
  }

  /**
   * Upsert the DailyBrief row + replace all BriefItem rows for this brief.
   * The (userId, briefDate) UNIQUE constraint means regenerating today's brief
   * overwrites the previous one (same id, fresh content).
   */
  private async persistBrief(
    result: BriefResult,
    forDate: Date,
  ): Promise<{ id: string }> {
    const briefDate = new Date(this.formatDate(forDate) + 'T00:00:00Z');

    return await this.prisma.$transaction(async (tx) => {
      // 1. Find existing brief for this user+date (if regenerating)
      const existing = await tx.dailyBrief.findUnique({
        where: {
          userId_briefDate: {
            userId: result.userId,
            briefDate,
          },
        },
        select: { id: true },
      });

      const briefId = existing?.id ?? this.makeId();

      // 2. Build the content JSONB payload
      const content = {
        items: result.items.map((it) => ({
          ...it,
          icon: ITEM_TYPE_ICONS[it.itemType],
        })),
        summary: result.summary,
        generatedAt: result.generatedAt,
      };

      // 3. Upsert the DailyBrief row
      await tx.dailyBrief.upsert({
        where: { id: briefId },
        create: {
          id: briefId,
          userId: result.userId,
          familyId: result.familyId,
          briefDate,
          greeting: result.greeting,
          familyArchetype: result.familyArchetype,
          languageCode: result.languageCode,
          content: content as any,
          generatedAt: new Date(result.generatedAt),
        },
        update: {
          greeting: result.greeting,
          familyArchetype: result.familyArchetype,
          languageCode: result.languageCode,
          content: content as any,
          generatedAt: new Date(result.generatedAt),
        },
      });

      // 4. Delete old BriefItem rows for this brief (if regenerating)
      if (existing) {
        await tx.briefItem.deleteMany({ where: { briefId } });
      }

      // 5. Insert fresh BriefItem rows
      if (result.items.length > 0) {
        await tx.briefItem.createMany({
          data: result.items.map((it) => ({
            briefId,
            userId: result.userId,
            familyId: result.familyId,
            itemType: it.itemType,
            priority: it.priority,
            title: it.title,
            body: it.body,
            actionLabel: it.actionLabel,
            actionType: it.actionType,
            actionData: it.actionData as any,
            targetPersonId: it.targetPersonId ?? null,
            targetUserId: it.targetUserId ?? null,
            targetSparqId: it.targetSparqId ?? null,
            targetPostId: it.targetPostId ?? null,
            relevanceScore: it.relevanceScore ?? 0.5,
          })),
        });
      }

      return { id: briefId };
    });
  }

  private todayUtc(): Date {
    const now = new Date();
    return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  }

  private formatDate(d: Date): string {
    const yyyy = d.getUTCFullYear();
    const mm = String(d.getUTCMonth() + 1).padStart(2, '0');
    const dd = String(d.getUTCDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }

  private makeId(): string {
    // Generate a cuid-like ID. We use a timestamp + random hex.
    // (Prisma's @default(cuid()) only fires on .create{} without an id field —
    // we're passing id explicitly in .upsert, so we must generate it ourselves.)
    const ts = Date.now().toString(36);
    const rand = Math.random().toString(36).slice(2, 10);
    return `cmr${ts}${rand}`.slice(0, 24);
  }
}
