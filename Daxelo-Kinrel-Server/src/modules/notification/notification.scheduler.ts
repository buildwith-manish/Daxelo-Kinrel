import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { NotificationService } from './notification.service';

/**
 * NotificationScheduler — Cron-based reminder scheduler
 *
 * Runs periodic jobs to check for:
 * - Birthday alerts (daily at 8:00 AM IST)
 * - Anniversary reminders (daily at 9:00 AM IST)
 * - Festival greetings (daily at 10:00 AM IST)
 */
@Injectable()
export class NotificationScheduler {
  private readonly logger = new Logger(NotificationScheduler.name);

  constructor(private readonly notificationService: NotificationService) {}

  /**
   * Daily birthday check at 8:00 AM IST (2:30 AM UTC)
   */
  @Cron('30 2 * * *', {
    name: 'birthday-check',
  })
  async handleBirthdayCheck() {
    this.logger.log('🕐 Running daily birthday check...');
    try {
      const count = await this.notificationService.checkBirthdays();
      this.logger.log(`Birthday check complete: ${count} notifications sent`);
    } catch (error) {
      this.logger.error(
        'Birthday check failed:',
        error instanceof Error ? error.message : String(error),
      );
    }
  }

  /**
   * Daily anniversary check at 9:00 AM IST (3:30 AM UTC)
   */
  @Cron('30 3 * * *', {
    name: 'anniversary-check',
  })
  async handleAnniversaryCheck() {
    this.logger.log('🕐 Running daily anniversary check...');
    try {
      const count = await this.notificationService.checkAnniversaries();
      this.logger.log(`Anniversary check complete: ${count} notifications sent`);
    } catch (error) {
      this.logger.error(
        'Anniversary check failed:',
        error instanceof Error ? error.message : String(error),
      );
    }
  }

  /**
   * Daily festival greeting check at 10:00 AM IST (4:30 AM UTC)
   */
  @Cron('30 4 * * *', {
    name: 'festival-check',
  })
  async handleFestivalCheck() {
    this.logger.log('🕐 Running daily festival check...');
    try {
      const count = await this.notificationService.checkFestivals();
      this.logger.log(`Festival check complete: ${count} notifications sent`);
    } catch (error) {
      this.logger.error(
        'Festival check failed:',
        error instanceof Error ? error.message : String(error),
      );
    }
  }
}
