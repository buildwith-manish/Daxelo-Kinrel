import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from './notifications.service';

@Injectable()
export class BirthdayScheduler {
  private readonly logger = new Logger(BirthdayScheduler.name);

  constructor(
    private prisma: PrismaService,
    private notificationsService: NotificationsService,
  ) {}

  /**
   * Run daily at 2:30 AM UTC (= 8:00 AM IST)
   * Checks for birthdays in the next 7 days and sends reminders
   */
  @Cron('0 30 2 * * *')
  async handleBirthdayCheck() {
    this.logger.log('Birthday scheduler running...');

    try {
      const now = new Date();

      // Find all persons with dateOfBirth who are not soft-deleted or deceased
      const persons = await this.prisma.person.findMany({
        where: {
          dateOfBirth: { not: null },
          deletedAt: null,
          isDeceased: false,
        },
        select: {
          id: true,
          name: true,
          dateOfBirth: true,
          familyId: true,
        },
      });

      let notificationsSent = 0;

      for (const person of persons) {
        if (!person.dateOfBirth || !person.familyId) continue;

        const dob = new Date(person.dateOfBirth);

        // Calculate this year's birthday
        let birthdayThisYear = new Date(now.getFullYear(), dob.getMonth(), dob.getDate());

        // If birthday already passed this year, check next year
        if (birthdayThisYear < now) {
          birthdayThisYear = new Date(now.getFullYear() + 1, dob.getMonth(), dob.getDate());
        }

        const daysUntil = Math.ceil(
          (birthdayThisYear.getTime() - now.getTime()) / (1000 * 60 * 60 * 24),
        );

        // Only send for birthdays within the next 7 days
        if (daysUntil >= 0 && daysUntil <= 7) {
          const count = await this.notificationsService.sendBirthdayReminder(
            person.id,
            person.name || 'Family Member',
            person.familyId,
            daysUntil,
          );
          notificationsSent += count;
        }
      }

      this.logger.log(
        `Birthday scheduler complete: ${notificationsSent} notifications sent for ${persons.length} persons checked`,
      );
    } catch (error: unknown) {
      const msg = error instanceof Error ? error.message : String(error);
      const stack = error instanceof Error ? error.stack : undefined;
      this.logger.error('Birthday scheduler failed: ' + msg, stack);
    }
  }
}
