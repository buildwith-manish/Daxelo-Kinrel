// server/src/addictiveness/festival.service.ts
//
// A-6 Festival Intelligence — service for the Indian festival calendar.
//
// Responsibilities:
//   1. seedFestivals() — populate the Festival table from festival-data.ts
//   2. getUpcomingFestivals() — festivals in the next N days (for the Pulse brief)
//   3. getFestivalToday() — festivals happening today
//   4. getFestivalByKey() — fetch a specific festival
//   5. refreshFestivalDates() — monthly cron: advance lunar dates that have passed
//
// The seed is idempotent: it upserts by festivalKey, so re-running it is safe.

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  FESTIVAL_SEEDS,
  computeNextFestivalDate,
  computeDaysUntil,
  type FestivalSeed,
} from './festival-data';

@Injectable()
export class FestivalService {
  private readonly logger = new Logger(FestivalService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Seed the Festival table from the static dataset.
   * Idempotent: upserts by festivalKey.
   * Returns the count of festivals seeded.
   */
  async seedFestivals(): Promise<{ count: number; skipped: number }> {
    let count = 0;
    let skipped = 0;

    for (const seed of FESTIVAL_SEEDS) {
      const nextDate = computeNextFestivalDate(seed);
      if (!nextDate) {
        this.logger.warn(`FestivalService: no date for ${seed.festivalKey} — skipping`);
        skipped++;
        continue;
      }

      const daysUntil = computeDaysUntil(nextDate);

      await this.prisma.festival.upsert({
        where: { festivalKey: seed.festivalKey },
        create: {
          festivalKey: seed.festivalKey,
          dateType: seed.dateType,
          festivalDate: nextDate,
          region: seed.region,
          names: seed.names as any,
          greetings: seed.greetings as any,
          description: seed.description,
          themes: seed.themes as any,
          rituals: seed.rituals as any,
          daysUntil,
          isActive: true,
        },
        update: {
          dateType: seed.dateType,
          festivalDate: nextDate,
          region: seed.region,
          names: seed.names as any,
          greetings: seed.greetings as any,
          description: seed.description,
          themes: seed.themes as any,
          rituals: seed.rituals as any,
          daysUntil,
          isActive: true,
        },
      });
      count++;
    }

    this.logger.log(
      `FestivalService: seeded ${count} festivals (${skipped} skipped)`,
    );
    return { count, skipped };
  }

  /**
   * Get festivals happening in the next N days.
   * Used by the Pulse brief's festival collector + the Festival Intelligence widget.
   */
  async getUpcomingFestivals(
    daysAhead: number = 30,
    regionFilter?: string,
  ): Promise<any[]> {
    const now = new Date();
    const cutoff = new Date(now.getTime() + daysAhead * 24 * 60 * 60 * 1000);

    const festivals = await this.prisma.festival.findMany({
      where: {
        isActive: true,
        daysUntil: { gte: 0, lte: daysAhead },
        ...(regionFilter && regionFilter !== 'all'
          ? { OR: [{ region: regionFilter }, { region: 'all' }] }
          : {}),
      },
      orderBy: { daysUntil: 'asc' },
    });

    return festivals.map((f) => this.serializeFestival(f, now));
  }

  /** Get festivals happening today (daysUntil === 0). */
  async getFestivalsToday(): Promise<any[]> {
    const festivals = await this.prisma.festival.findMany({
      where: { isActive: true, daysUntil: 0 },
    });
    const now = new Date();
    return festivals.map((f) => this.serializeFestival(f, now));
  }

  /** Get a single festival by its key. */
  async getFestivalByKey(festivalKey: string): Promise<any | null> {
    const festival = await this.prisma.festival.findUnique({
      where: { festivalKey },
    });
    if (!festival) return null;
    return this.serializeFestival(festival, new Date());
  }

  /**
   * Monthly cron: advance lunar festivals that have passed.
   * For each lunar festival where daysUntil < 0 (the date has passed):
   *   - Find the next date in the seed's lunarDates[] array
   *   - If no more dates in the array, mark as inactive (stale data)
   *   - Otherwise, update festivalDate + recompute daysUntil
   */
  async refreshFestivalDates(): Promise<{ updated: number; deactivated: number }> {
    let updated = 0;
    let deactivated = 0;
    const now = new Date();

    const staleFestivals = await this.prisma.festival.findMany({
      where: { daysUntil: { lt: 0 } },
    });

    for (const f of staleFestivals) {
      const seed = FESTIVAL_SEEDS.find((s) => s.festivalKey === f.festivalKey);
      if (!seed) {
        // No seed data — can't refresh, deactivate
        await this.prisma.festival.update({
          where: { id: f.id },
          data: { isActive: false },
        });
        deactivated++;
        continue;
      }

      const nextDate = computeNextFestivalDate(seed, now);
      if (!nextDate) {
        await this.prisma.festival.update({
          where: { id: f.id },
          data: { isActive: false },
        });
        deactivated++;
        continue;
      }

      const daysUntil = computeDaysUntil(nextDate, now);
      await this.prisma.festival.update({
        where: { id: f.id },
        data: { festivalDate: nextDate, daysUntil, isActive: true },
      });
      updated++;
    }

    // Also refresh daysUntil for all active festivals (it changes daily)
    const allActive = await this.prisma.festival.findMany({
      where: { isActive: true },
    });
    for (const f of allActive) {
      const daysUntil = computeDaysUntil(f.festivalDate, now);
      if (daysUntil !== f.daysUntil) {
        await this.prisma.festival.update({
          where: { id: f.id },
          data: { daysUntil },
        });
      }
    }

    this.logger.log(
      `FestivalService: refreshed dates — ${updated} advanced, ${deactivated} deactivated, ${allActive.length} active`,
    );
    return { updated, deactivated };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────

  private serializeFestival(f: any, now: Date) {
    return {
      id: f.id,
      festivalKey: f.festivalKey,
      dateType: f.dateType,
      festivalDate: f.festivalDate.toISOString().slice(0, 10),
      region: f.region,
      names: f.names,
      greetings: f.greetings,
      description: f.description,
      themes: f.themes,
      rituals: f.rituals,
      daysUntil: f.daysUntil,
      isActive: f.isActive,
      // Helper: localized name + greeting for a given language
      getLocalized: (lang: string) => ({
        name: (f.names as any)?.[lang]?.name ?? (f.names as any)?.en ?? f.festivalKey,
        greeting:
          (f.greetings as any)?.[lang] ?? (f.greetings as any)?.en ?? '',
      }),
    };
  }
}
