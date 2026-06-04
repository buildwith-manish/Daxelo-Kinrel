import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';
import { FcmService } from './fcm.service';
import { NotificationsService } from './notifications.service';

/**
 * NotificationsScheduler — Daily cron job that sends birthday reminder
 * push notifications for upcoming birthdays within the next 7 days.
 *
 * Runs daily at 8:00 AM IST (UTC+5:30), which is 2:30 AM UTC.
 * Cron expression: "30 2 * * *"
 *
 * Flow:
 * 1. Query all Persons with dateOfBirth within the next 7 days
 * 2. For each birthday person, find all family members who should be notified
 * 3. Send FCM push notification with type `birthday_reminder`
 * 4. Create in-app notification records
 * 5. Group by family: one notification per family per birthday person
 */
@Injectable()
export class NotificationsScheduler {
  private readonly logger = new Logger(NotificationsScheduler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly fcmService: FcmService,
    private readonly notificationsService: NotificationsService,
  ) {}

  /**
   * Daily at 8:00 AM IST = 2:30 AM UTC
   * IST is UTC+5:30, so 8:00 IST = 2:30 UTC
   */
  @Cron('30 2 * * *', {
    name: 'birthday-reminder',
    timeZone: 'UTC',
  })
  async handleBirthdayReminders() {
    this.logger.log('🎂 Running daily birthday reminder job...');

    try {
      const now = new Date();
      const upcomingBirthdays = await this.findUpcomingBirthdays(now, 7);

      if (upcomingBirthdays.length === 0) {
        this.logger.log('🎂 No upcoming birthdays found in the next 7 days');
        return;
      }

      this.logger.log(`🎂 Found ${upcomingBirthdays.length} upcoming birthday(s) in the next 7 days`);

      let notificationsSent = 0;

      for (const birthday of upcomingBirthdays) {
        try {
          // Find all family members (users) who belong to the same family
          const familyMembers = await this.prisma.familyMember.findMany({
            where: {
              familyId: birthday.familyId,
              userId: { not: undefined }, // Only actual users, not just Person records
            },
            include: {
              user: {
                select: {
                  id: true,
                  name: true,
                },
              },
            },
          });

          if (familyMembers.length === 0) {
            this.logger.debug(
              `No family members to notify for ${birthday.name}'s birthday in family ${birthday.familyId}`,
            );
            continue;
          }

          const daysUntil = birthday.daysUntil;
          const memberName = birthday.name;
          const title = '🎂 Birthday Reminder';
          const body =
            daysUntil === 0
              ? `It's ${memberName}'s birthday today! 🎉`
              : `It's ${memberName}'s birthday in ${daysUntil} day${daysUntil !== 1 ? 's' : ''}!`;

          // Get family name for context
          const family = await this.prisma.family.findUnique({
            where: { id: birthday.familyId },
            select: { name: true },
          });

          for (const member of familyMembers) {
            try {
              // Check notification preferences — skip if user disabled push for birthday_reminder
              const pref = await this.prisma.notificationPreference.findUnique({
                where: {
                  userId_eventType: {
                    userId: member.user.id,
                    eventType: 'birthday_reminder',
                  },
                },
              });

              if (pref && !pref.push) {
                this.logger.debug(
                  `User ${member.user.id} has disabled push for birthday_reminder — skipping FCM`,
                );
                // Still create in-app notification if enabled
                if (pref.inApp) {
                  await this.createInAppNotification(
                    member.user.id,
                    birthday,
                    title,
                    body,
                    family?.name,
                  );
                }
                continue;
              }

              // Check quiet hours
              if (pref && this.isInQuietHours(pref.quietHoursStart, pref.quietHoursEnd)) {
                this.logger.debug(
                  `User ${member.user.id} is in quiet hours — skipping push notification`,
                );
                // Still create in-app notification
                await this.createInAppNotification(
                  member.user.id,
                  birthday,
                  title,
                  body,
                  family?.name,
                );
                continue;
              }

              // Send FCM push notification
              const notificationData: Record<string, string> = {
                type: 'birthday_reminder',
                memberId: birthday.id,
                memberName,
                familyId: birthday.familyId,
                daysUntil: String(daysUntil),
                title,
                body,
              };

              if (family?.name) {
                notificationData.familyName = family.name;
              }

              const fcmSent = await this.fcmService.sendToUser(member.user.id, {
                title,
                body,
                data: notificationData,
              });

              // Also create in-app notification record
              await this.createInAppNotification(
                member.user.id,
                birthday,
                title,
                body,
                family?.name,
              );

              if (fcmSent) {
                notificationsSent++;
              }
            } catch (error: any) {
              this.logger.error(
                `Error sending birthday reminder to user ${member.user.id}: ${error?.message}`,
              );
            }
          }
        } catch (error: any) {
          this.logger.error(
            `Error processing birthday for ${birthday.name}: ${error?.message}`,
          );
        }
      }

      this.logger.log(
        `🎂 Birthday reminder job complete — sent ${notificationsSent} push notification(s)`,
      );
    } catch (error: any) {
      this.logger.error(
        `Birthday reminder job failed: ${error?.message}`,
        error?.stack,
      );
    }
  }

  /**
   * Find all persons with birthdays in the next N days.
   * Compares only month and day (ignoring year) to find recurring birthdays.
   */
  private async findUpcomingBirthdays(
    now: Date,
    daysAhead: number,
  ): Promise<
    Array<{
      id: string;
      name: string;
      familyId: string;
      dateOfBirth: Date;
      daysUntil: number;
    }>
  > {
    // We need to find persons whose birthday (month-day) falls within
    // the next `daysAhead` days from today.
    // Since Person.dateOfBirth is a DateTime field in SQLite (stored as string),
    // we need to query all persons with a dateOfBirth and filter in JS.

    const persons = await this.prisma.person.findMany({
      where: {
        dateOfBirth: { not: null },
        isDeceased: false,
        deletedAt: null,
      },
      select: {
        id: true,
        name: true,
        familyId: true,
        dateOfBirth: true,
      },
    });

    const results: Array<{
      id: string;
      name: string;
      familyId: string;
      dateOfBirth: Date;
      daysUntil: number;
    }> = [];

    for (const person of persons) {
      if (!person.dateOfBirth) continue;

      const daysUntil = this.getDaysUntilNextBirthday(person.dateOfBirth, now);

      if (daysUntil >= 0 && daysUntil <= daysAhead) {
        results.push({
          id: person.id,
          name: person.name,
          familyId: person.familyId,
          dateOfBirth: person.dateOfBirth,
          daysUntil,
        });
      }
    }

    // Sort by daysUntil (soonest first)
    results.sort((a, b) => a.daysUntil - b.daysUntil);

    return results;
  }

  /**
   * Calculate the number of days until the next occurrence of a birthday.
   * Compares month and day only, ignoring the year.
   */
  private getDaysUntilNextBirthday(dateOfBirth: Date, now: Date): number {
    const birthMonth = dateOfBirth.getMonth(); // 0-11
    const birthDay = dateOfBirth.getDate(); // 1-31

    const currentYear = now.getFullYear();
    const currentMonth = now.getMonth();
    const currentDay = now.getDate();

    // This year's birthday
    let nextBirthday = new Date(currentYear, birthMonth, birthDay);

    // If birthday has already passed this year, use next year
    if (
      nextBirthday.getMonth() < currentMonth ||
      (nextBirthday.getMonth() === currentMonth && nextBirthday.getDate() < currentDay)
    ) {
      nextBirthday = new Date(currentYear + 1, birthMonth, birthDay);
    }

    // Calculate days difference
    const diffMs = nextBirthday.getTime() - new Date(currentYear, currentMonth, currentDay).getTime();
    return Math.round(diffMs / (1000 * 60 * 60 * 24));
  }

  /**
   * Check if the current time is within quiet hours.
   */
  private isInQuietHours(
    quietStart: string | null | undefined,
    quietEnd: string | null | undefined,
  ): boolean {
    if (!quietStart || !quietEnd) return false;

    try {
      const now = new Date();
      const currentMinutes = now.getHours() * 60 + now.getMinutes();

      const [startH, startM] = quietStart.split(':').map(Number);
      const [endH, endM] = quietEnd.split(':').map(Number);

      const startMinutes = startH * 60 + startM;
      const endMinutes = endH * 60 + endM;

      if (startMinutes <= endMinutes) {
        // e.g. 08:00 - 22:00
        return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
      } else {
        // e.g. 22:00 - 08:00 (overnight)
        return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
      }
    } catch {
      return false;
    }
  }

  /**
   * Create an in-app notification record in the database.
   */
  private async createInAppNotification(
    userId: string,
    birthday: { id: string; name: string; familyId: string },
    title: string,
    body: string,
    familyName?: string,
  ): Promise<void> {
    try {
      await this.notificationsService.create({
        userId,
        eventType: 'birthday_reminder',
        title,
        body,
        familyId: birthday.familyId,
        personId: birthday.id,
        priority: 'normal',
        actionUrl: `/family/${birthday.familyId}`,
      });
    } catch (error: any) {
      this.logger.error(
        `Error creating in-app notification for user ${userId}: ${error?.message}`,
      );
    }
  }
}
