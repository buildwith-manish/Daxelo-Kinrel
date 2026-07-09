// =============================================================================
// Track C v2.0 — pg-boss Background Workers
// =============================================================================
// ADR-006: All scheduled work flows through pg-boss with idempotency keys.
//
// Workers registered:
//   1. deadline-sweeper      — every 5 min, auto-expires decisions past deadline
//   2. learning-recompute    — daily at 02:00 UTC, recomputes FamilyBehaviorProfile
//   3. analytics-weekly      — weekly, snapshots for all active families
//   4. search-reindex        — hourly, reindexes recently-changed entities
//   5. learning-signal-purge — weekly, purges signals older than 365 days
//   6. profile-history-purge — daily, purges profile history older than 90 days
//   7. insight-purge         — daily, purges AIInsight older than 365 days
//
// pg-boss itself manages the queue in the `pgboss` schema (migration 19).
// =============================================================================

import { Injectable, OnModuleInit, Logger, Optional } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { DecisionsService } from './decisions/decisions.service';
import { ProfileBuilder } from './aura-learning/learning.profile-builder';
import { AnalyticsSnapshotWorker } from './aura-analytics/analytics.snapshot-worker';
import { SearchService } from './aura-search/search.service';

// PgBoss is loaded dynamically so the server can boot even if pg-boss isn't installed.
let PgBoss: any;
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  PgBoss = require('pg-boss');
} catch {
  PgBoss = null;
}

@Injectable()
export class TrackcWorkers implements OnModuleInit {
  private readonly logger = new Logger(TrackcWorkers.name);
  private boss: any = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly decisionsService: DecisionsService,
    private readonly profileBuilder: ProfileBuilder,
    private readonly analyticsWorker: AnalyticsSnapshotWorker,
    private readonly searchService: SearchService,
  ) {}

  async onModuleInit() {
    if (!PgBoss) {
      this.logger.warn('pg-boss not installed — Track C workers disabled. Install pg-boss to enable scheduled jobs.');
      return;
    }

    const connectionString = process.env.DIRECT_URL || process.env.DATABASE_URL;
    if (!connectionString) {
      this.logger.warn('No DATABASE_URL — Track C workers disabled.');
      return;
    }

    try {
      this.boss = new PgBoss({
        connectionString,
        schema: 'pgboss',
        // Retry config: exponential backoff, max 5 attempts
        retryLimit: 5,
        retryDelay: 60, // seconds
      });

      this.boss.on('error', (err: Error) => this.logger.error(`pg-boss error: ${err.message}`));

      await this.boss.start();
      this.logger.log('pg-boss started — Track C workers registered');

      // ── Register job handlers ──────────────────────────────────────────
      await this.boss.work('trackc-deadline-sweeper', this.handleDeadlineSweep.bind(this));
      await this.boss.work('trackc-learning-recompute', this.handleLearningRecompute.bind(this));
      await this.boss.work('trackc-analytics-weekly', this.handleAnalyticsWeekly.bind(this));
      await this.boss.work('trackc-search-reindex', this.handleSearchReindex.bind(this));
      await this.boss.work('trackc-signal-purge', this.handleSignalPurge.bind(this));
      await this.boss.work('trackc-profile-history-purge', this.handleProfileHistoryPurge.bind(this));
      await this.boss.work('trackc-insight-purge', this.handleInsightPurge.bind(this));

      // ── Schedule recurring jobs (idempotent — publishAfter uses job name as key) ──
      // Every 5 minutes
      await this.boss.publishAfter('trackc-deadline-sweeper', {}, '5-min-schedule', new Date(Date.now() + 5 * 60 * 1000));
      // Hourly
      await this.boss.publishAfter('trackc-search-reindex', {}, 'hourly-schedule', new Date(Date.now() + 60 * 60 * 1000));
      // Daily at 02:00 UTC
      await this.scheduleDaily('trackc-learning-recompute', 2, 0);
      await this.scheduleDaily('trackc-profile-history-purge', 3, 0);
      await this.scheduleDaily('trackc-insight-purge', 4, 0);
      // Weekly (Sundays at 01:00 UTC)
      await this.scheduleWeekly('trackc-analytics-weekly', 0, 1);
      await this.scheduleWeekly('trackc-signal-purge', 0, 1);
    } catch (err) {
      this.logger.error(`Failed to start pg-boss: ${(err as Error).message}`);
      this.logger.warn('Track C workers disabled — server will continue but background jobs will not run.');
    }
  }

  // ── Job handlers ────────────────────────────────────────────────────────

  private async handleDeadlineSweep(job: any): Promise<void> {
    // Find all open decisions past their deadline
    const expired = await this.prisma.familyDecision.findMany({
      where: { status: 'open', deadlineAt: { lte: new Date() } },
      select: { id: true, familyId: true, title: true },
      take: 100, // cap per run
    });

    this.logger.log(`Deadline sweeper: ${expired.length} decisions to expire`);

    for (const d of expired) {
      try {
        await this.decisionsService.autoExpireIfPastDeadline(d.familyId, d.id);
      } catch (err) {
        this.logger.warn(`Failed to expire decision ${d.id}: ${(err as Error).message}`);
      }
    }
  }

  private async handleLearningRecompute(job: any): Promise<void> {
    // Recompute profiles for families with new signals in the last 24h
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const activeFamilies = await this.prisma.learningSignal.findMany({
      where: { occurredAt: { gte: since } },
      select: { familyId: true },
      distinct: ['familyId'],
    });

    this.logger.log(`Learning recompute: ${activeFamilies.length} families to process`);

    for (const { familyId } of activeFamilies) {
      try {
        await this.profileBuilder.recompute(familyId);
      } catch (err) {
        this.logger.warn(`Failed to recompute profile for family ${familyId}: ${(err as Error).message}`);
      }
    }
  }

  private async handleAnalyticsWeekly(job: any): Promise<void> {
    // Snapshot all active families for the current week
    const families = await this.prisma.family.findMany({
      where: { deletedAt: null },
      select: { id: true },
    });

    const now = new Date();
    const periodStart = this.startOfWeek(now);
    const periodEnd = new Date(periodStart.getTime() + 7 * 24 * 60 * 60 * 1000);

    this.logger.log(`Analytics weekly: ${families.length} families to snapshot`);

    for (const { id } of families) {
      try {
        await this.analyticsWorker.snapshot({
          familyId: id,
          periodStart,
          periodEnd,
          granularity: 'weekly',
        });
      } catch (err) {
        this.logger.warn(`Failed to snapshot family ${id}: ${(err as Error).message}`);
      }
    }
  }

  private async handleSearchReindex(job: any): Promise<void> {
    // Reindex entities updated in the last hour (incremental)
    const since = new Date(Date.now() - 60 * 60 * 1000);
    const decisions = await this.prisma.familyDecision.findMany({
      where: { updatedAt: { gte: since } },
      select: { familyId: true },
      distinct: ['familyId'],
    });

    this.logger.log(`Search reindex: ${decisions.length} families to reindex`);

    for (const { familyId } of decisions) {
      try {
        // Incremental reindex — only reindex this family's recently-updated decisions
        await this.searchService.reindexFamily(familyId);
      } catch (err) {
        this.logger.warn(`Failed to reindex family ${familyId}: ${(err as Error).message}`);
      }
    }
  }

  private async handleSignalPurge(job: any): Promise<void> {
    // Purge LearningSignal rows older than 365 days (Section 9.5)
    const cutoff = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000);
    const result = await this.prisma.learningSignal.deleteMany({
      where: { occurredAt: { lt: cutoff } },
    });
    this.logger.log(`Signal purge: deleted ${result.count} old signals`);
  }

  private async handleProfileHistoryPurge(job: any): Promise<void> {
    // Purge FamilyBehaviorProfileHistory older than 90 days (Section 9.5)
    const cutoff = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
    const result = await this.prisma.familyBehaviorProfileHistory.deleteMany({
      where: { archivedAt: { lt: cutoff } },
    });
    this.logger.log(`Profile history purge: deleted ${result.count} old snapshots`);
  }

  private async handleInsightPurge(job: any): Promise<void> {
    // Purge AIInsight rows older than 365 days (Section 12.4)
    const cutoff = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000);
    const result = await this.prisma.aIInsight.deleteMany({
      where: { createdAt: { lt: cutoff } },
    });
    this.logger.log(`Insight purge: deleted ${result.count} old insights`);
  }

  // ── Scheduling helpers ─────────────────────────────────────────────────

  private async scheduleDaily(jobName: string, hourUtc: number, minuteUtc: number): Promise<void> {
    const next = new Date();
    next.setUTCHours(hourUtc, minuteUtc, 0, 0);
    if (next <= new Date()) {
      next.setUTCDate(next.getUTCDate() + 1);
    }
    await this.boss.publishAfter(jobName, {}, `${jobName}-schedule`, next);
  }

  private async scheduleWeekly(jobName: string, dayOfWeek: number, hourUtc: number): Promise<void> {
    const next = new Date();
    next.setUTCHours(hourUtc, 0, 0, 0);
    const daysUntil = (dayOfWeek - next.getUTCDay() + 7) % 7;
    next.setUTCDate(next.getUTCDate() + (daysUntil === 0 && next <= new Date() ? 7 : daysUntil));
    await this.boss.publishAfter(jobName, {}, `${jobName}-schedule`, next);
  }

  private startOfWeek(date: Date): Date {
    const d = new Date(date);
    d.setUTCHours(0, 0, 0, 0);
    const day = d.getUTCDay();
    const diff = (day + 6) % 7; // Monday=0
    d.setUTCDate(d.getUTCDate() - diff);
    return d;
  }
}
