// server/src/pulse/pulse-cron.service.ts
//
// PulseCronService — daily scheduled jobs for the Pulse system.
//
// Two crons:
//   1. 7am IST daily — generate briefs for ALL users
//      Cron expr: '0 7 * * *'  (UTC + 5:30 → IST 7:00am)
//      Actually: 7am IST = 1:30am UTC. We use '30 1 * * *' for accuracy.
//      For dev/iteration we ALSO keep a `--pulse-now` env flag to fire immediately.
//
//   2. 1am IST daily — compute RelationshipWeather for all pairs
//      Cron expr: '0 1 * * *'  (IST) = '30 19 * * *' (UTC, previous day)
//      This pre-computes weather so it's ready when the 7am brief runs.
//
// Implementation notes:
//   - The 7am job calls briefGeneratorService.generateAllBriefs() which iterates
//     all families and all members in parallel (capped at 5 concurrent per family).
//   - The 1am job calls computeWeatherForAllPairs() defined below. For Phase 1,
//     this is a simple stub that computes weather based on daysSinceLastContact
//     using BriefInteraction events. Phase 4 will refine this with sentiment scoring.
//   - Both crons log completion stats. Errors are caught and logged, not thrown
//     (a cron job throwing would crash the Nest process).

import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { BriefGeneratorService } from './brief-generator.service';

@Injectable()
export class PulseCronService {
  private readonly logger = new Logger(PulseCronService.name);
  private isGenerating = false;
  private isComputingWeather = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly briefGenerator: BriefGeneratorService,
  ) {}

  // ────────────────────────────────────────────────────────────────────────
  // 7am IST daily — generate all briefs
  // ────────────────────────────────────────────────────────────────────────
  //
  // IST = UTC + 5:30. So 7:00 IST = 01:30 UTC.
  // Cron expression '30 1 * * *' = "at 01:30 UTC every day".
  //
  // For dev: set PULSE_FIRE_ON_BOOT=1 to trigger once at boot (after 10s settle).
  //
  @Cron('30 1 * * *')
  async dailyBriefGeneration(): Promise<void> {
    if (this.isGenerating) {
      this.logger.warn('Daily brief generation already in progress — skipping');
      return;
    }
    this.isGenerating = true;
    const start = Date.now();
    try {
      this.logger.log('🌙 Pulse 7am IST cron: starting brief generation for all users');
      const stats = await this.briefGenerator.generateAllBriefs();
      const elapsed = Date.now() - start;
      this.logger.log(
        `✅ Pulse 7am cron done in ${elapsed}ms — families=${stats.familiesProcessed}, ` +
          `users=${stats.usersProcessed}, briefs=${stats.briefsGenerated}, errors=${stats.errors.length}`,
      );
      if (stats.errors.length > 0) {
        for (const e of stats.errors.slice(0, 5)) {
          this.logger.error(`  - family=${e.familyId} user=${e.userId} err=${e.error}`);
        }
      }
    } catch (err) {
      this.logger.error(
        `💥 Pulse 7am cron failed: ${err instanceof Error ? err.message : err}`,
        err instanceof Error ? err.stack : undefined,
      );
    } finally {
      this.isGenerating = false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // 1am IST daily — compute RelationshipWeather for all pairs
  // ────────────────────────────────────────────────────────────────────────
  //
  // IST = UTC + 5:30. So 1:00 IST = 19:30 UTC (previous day).
  // Cron '30 19 * * *' = "at 19:30 UTC every day" → 1:00am IST next day.
  //
  // Phase 1 weather computation (simple, deterministic):
  //   For each (userA, personB/userB) pair in each family:
  //     - Look up the last BriefInteraction involving either party in the last 60 days
  //     - daysSinceLastContact = floor((now - lastInteraction) / day)
  //     - interactionCount30d = count of interactions in last 30 days
  //     - Apply weather heuristic:
  //         stormy         if daysSince >= 60
  //         rainy          if daysSince >= 30
  //         cloudy         if daysSince >= 14
  //         partly_cloudy  if daysSince >= 7
  //         sunny          otherwise
  //     - Upsert RelationshipWeather row
  //
  // Phase 4 will add: sentimentScore (from chat message analysis), streakDays,
  // previousWeather diff, and weatherChangedAt.
  //
  @Cron('30 19 * * *')
  async dailyWeatherComputation(): Promise<void> {
    if (this.isComputingWeather) {
      this.logger.warn('Weather computation already in progress — skipping');
      return;
    }
    this.isComputingWeather = true;
    const start = Date.now();
    try {
      this.logger.log('🌧️ Pulse 1am IST cron: computing relationship weather');
      const stats = await this.computeWeatherForAllPairs();
      const elapsed = Date.now() - start;
      this.logger.log(
        `✅ Pulse weather cron done in ${elapsed}ms — families=${stats.families}, ` +
          `pairs=${stats.pairs}, upserts=${stats.upserts}, errors=${stats.errors.length}`,
      );
    } catch (err) {
      this.logger.error(
        `💥 Pulse weather cron failed: ${err instanceof Error ? err.message : err}`,
        err instanceof Error ? err.stack : undefined,
      );
    } finally {
      this.isComputingWeather = false;
    }
  }

  /**
   * Phase 1 weather computation — see class docstring for the algorithm.
   * Exposed as a public method so the validation script can call it directly.
   */
  async computeWeatherForAllPairs(): Promise<{
    families: number;
    pairs: number;
    upserts: number;
    errors: { familyId: string; error: string }[];
  }> {
    const families = await this.prisma.family.findMany({
      where: { deletedAt: null },
      select: { id: true },
    });

    let pairs = 0;
    let upserts = 0;
    const errors: { familyId: string; error: string }[] = [];

    for (const fam of families) {
      try {
        // Load all members of this family
        const members = await this.prisma.familyMember.findMany({
          where: { familyId: fam.id },
          select: { userId: true },
        });
        if (members.length < 2) continue;

        // Load all Persons in this family (with linkedUserId, if any)
        const persons = await this.prisma.person.findMany({
          where: { familyId: fam.id, deletedAt: null, isDeceased: false },
          select: { id: true, linkedUserId: true },
        });
        const personByLinkedUser = new Map<string, string>();
        for (const p of persons) {
          if (p.linkedUserId) personByLinkedUser.set(p.linkedUserId, p.id);
        }

        // For each userA in this family, compute weather against every OTHER
        // user (userB) AND every Person without linkedUserId.
        // To avoid duplicate pairs (A↔B and B↔A), only compute pairs where
        // userA.id < userB.id (lexicographically).
        const sortedUserIds = members.map((m) => m.userId).sort();

        for (let i = 0; i < sortedUserIds.length; i++) {
          const userAId = sortedUserIds[i];

          // Pairs with other users
          for (let j = i + 1; j < sortedUserIds.length; j++) {
            const userBId = sortedUserIds[j];
            pairs++;
            try {
              await this.upsertWeather({
                familyId: fam.id,
                userAId,
                userBId,
                personBId: personByLinkedUser.get(userBId) ?? null,
              });
              upserts++;
            } catch (err) {
              errors.push({
                familyId: fam.id,
                error: `pair ${userAId}↔${userBId}: ${err instanceof Error ? err.message : err}`,
              });
            }
          }

          // Pairs with Persons who have NO linkedUserId (elders not on the app)
          for (const p of persons) {
            if (p.linkedUserId) continue; // already covered above
            if (personByLinkedUser.has(userAId) && personByLinkedUser.get(userAId) === p.id) {
              continue; // skip self-pair
            }
            pairs++;
            try {
              await this.upsertWeather({
                familyId: fam.id,
                userAId,
                userBId: null,
                personBId: p.id,
              });
              upserts++;
            } catch (err) {
              errors.push({
                familyId: fam.id,
                error: `pair ${userAId}→person ${p.id}: ${err instanceof Error ? err.message : err}`,
              });
            }
          }
        }
      } catch (err) {
        errors.push({
          familyId: fam.id,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    return { families: families.length, pairs, upserts, errors };
  }

  /** Compute weather for a single pair and upsert the RelationshipWeather row. */
  private async upsertWeather(args: {
    familyId: string;
    userAId: string;
    userBId: string | null;
    personBId: string | null;
  }): Promise<void> {
    const now = new Date();
    const msPerDay = 1000 * 60 * 60 * 24;
    const thirtyDaysAgo = new Date(now.getTime() - 30 * msPerDay);

    // Find the most recent BriefInteraction involving either user
    // (we look at BriefInteraction rows for items where the user was the target
    // OR the actor)
    const lastInteraction = await this.prisma.briefInteraction.findFirst({
      where: {
        OR: [
          { userId: args.userAId },
          ...(args.userBId ? [{ userId: args.userBId }] : []),
        ],
      },
      orderBy: { interactedAt: 'desc' },
      select: { interactedAt: true },
    });

    const interactionCount30d = await this.prisma.briefInteraction.count({
      where: {
        interactedAt: { gte: thirtyDaysAgo },
        OR: [
          { userId: args.userAId },
          ...(args.userBId ? [{ userId: args.userBId }] : []),
        ],
      },
    });

    const daysSinceLastContact = lastInteraction
      ? Math.floor((now.getTime() - lastInteraction.interactedAt.getTime()) / msPerDay)
      : 9999; // never interacted → very high

    let weather: string;
    if (daysSinceLastContact >= 60) weather = 'stormy';
    else if (daysSinceLastContact >= 30) weather = 'rainy';
    else if (daysSinceLastContact >= 14) weather = 'cloudy';
    else if (daysSinceLastContact >= 7) weather = 'partly_cloudy';
    else weather = 'sunny';

    // Compute the unique key for upsert
    const where = {
      familyId_userAId_personBId_userBId: {
        familyId: args.familyId,
        userAId: args.userAId,
        personBId: args.personBId ?? '',
        userBId: args.userBId ?? '',
      },
    };

    // Note: the @@unique constraint uses nullable columns, which Prisma's
    // composite unique doesn't handle well. We use a manual upsert pattern instead.
    const existing = await this.prisma.relationshipWeather.findFirst({
      where: {
        familyId: args.familyId,
        userAId: args.userAId,
        personBId: args.personBId ?? null,
        userBId: args.userBId ?? null,
      },
      select: { id: true, weather: true },
    });

    const previousWeather = existing?.weather ?? null;
    const weatherChangedAt = existing && existing.weather !== weather ? now : null;

    if (existing) {
      await this.prisma.relationshipWeather.update({
        where: { id: existing.id },
        data: {
          weather,
          daysSinceLastContact,
          interactionCount30d,
          previousWeather,
          weatherChangedAt,
          computedAt: now,
        },
      });
    } else {
      await this.prisma.relationshipWeather.create({
        data: {
          familyId: args.familyId,
          userAId: args.userAId,
          personBId: args.personBId ?? null,
          userBId: args.userBId ?? null,
          weather,
          daysSinceLastContact,
          interactionCount30d,
          previousWeather: null,
          weatherChangedAt: null,
          computedAt: now,
        },
      });
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Lifecycle hook: optional boot-time fire for dev/iteration
  // ────────────────────────────────────────────────────────────────────────
  async onModuleInit() {
    if (process.env.PULSE_FIRE_ON_BOOT === '1') {
      this.logger.warn('🔥 PULSE_FIRE_ON_BOOT=1 — firing brief generation in 10s');
      setTimeout(() => {
        this.dailyBriefGeneration().catch(() => {});
      }, 10_000);
    }
  }
}
