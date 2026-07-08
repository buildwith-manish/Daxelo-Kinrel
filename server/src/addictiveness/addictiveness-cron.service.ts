// server/src/addictiveness/addictiveness-cron.service.ts
//
// Daily cron jobs for the addictiveness features.
//
// Three crons:
//   1. 6am IST daily — refresh festival dates (advance past lunar festivals, recompute daysUntil)
//      IST = UTC + 5:30, so 6am IST = 0:30 UTC → '30 0 * * *'
//   2. 8am IST daily — deliver due blessings + reveal due time capsules
//      IST = UTC + 5:30, so 8am IST = 2:30 UTC → '30 2 * * *'
//   3. (same cron) — send FCM pushes for delivered blessings + revealed capsules
//
// All crons are defensive: errors are caught and logged, never thrown.

import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { FestivalService } from './festival.service';
import { BlessingChainService } from './blessing-chain.service';
import { TimeCapsuleService } from './time-capsule.service';

@Injectable()
export class AddictivenessCronService {
  private readonly logger = new Logger(AddictivenessCronService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly festivalService: FestivalService,
    private readonly blessingChainService: BlessingChainService,
    private readonly timeCapsuleService: TimeCapsuleService,
  ) {}

  // 6am IST daily — refresh festival dates
  @Cron('30 0 * * *')
  async refreshFestivals(): Promise<void> {
    const start = Date.now();
    try {
      this.logger.log('🌅 6am IST cron: refreshing festival dates');
      const result = await this.festivalService.refreshFestivalDates();
      this.logger.log(
        `✅ Festival refresh done in ${Date.now() - start}ms — ${result.updated} advanced, ${result.deactivated} deactivated`,
      );
    } catch (err) {
      this.logger.error(
        `💥 Festival refresh cron failed: ${err instanceof Error ? err.message : err}`,
        err instanceof Error ? err.stack : undefined,
      );
    }
  }

  // 8am IST daily — deliver blessings + reveal time capsules
  @Cron('30 2 * * *')
  async dailyDelivery(): Promise<void> {
    const start = Date.now();
    try {
      this.logger.log('🎁 8am IST cron: delivering blessings + revealing time capsules');

      // 1. Deliver due blessings
      const deliveredBlessings = await this.blessingChainService.deliverDueBlessings();
      for (const b of deliveredBlessings) {
        // FCM push would go here — for now, we just log it.
        // In production, inject FcmService and call sendToUser().
        this.logger.log(
          `  → blessing ${b.blessingId} delivered to ${b.recipientUserId ?? b.recipientPersonId} from ${b.elderName}`,
        );
      }

      // 2. Reveal due time capsules
      const revealedCapsules = await this.timeCapsuleService.revealDueCapsules();
      for (const c of revealedCapsules) {
        this.logger.log(
          `  → capsule "${c.title}" revealed for ${c.recipientUserId ?? 'family'} (creator: ${c.creatorName})`,
        );
      }

      this.logger.log(
        `✅ Daily delivery done in ${Date.now() - start}ms — ${deliveredBlessings.length} blessings, ${revealedCapsules.length} capsules`,
      );
    } catch (err) {
      this.logger.error(
        `💥 Daily delivery cron failed: ${err instanceof Error ? err.message : err}`,
        err instanceof Error ? err.stack : undefined,
      );
    }
  }

  /**
   * On module init, seed the festival table if it's empty.
   * This ensures festivals are available immediately after deployment
   * without requiring a manual POST /addictiveness/festivals/seed call.
   */
  async onModuleInit() {
    try {
      const count = await this.prisma.festival.count();
      if (count === 0) {
        this.logger.log('🌱 Festival table is empty — seeding on boot...');
        const result = await this.festivalService.seedFestivals();
        this.logger.log(`🌱 Seeded ${result.count} festivals`);
      } else {
        // Refresh daysUntil on boot (in case the server was down for a while)
        await this.festivalService.refreshFestivalDates();
        this.logger.log(`🌱 Festival table has ${count} rows — refreshed dates`);
      }
    } catch (err) {
      this.logger.error(
        `💥 Festival seed on boot failed: ${err instanceof Error ? err.message : err}`,
      );
    }
  }
}
