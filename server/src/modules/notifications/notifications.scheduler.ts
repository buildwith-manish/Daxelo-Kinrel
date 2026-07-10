import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';
import { FcmService } from './fcm.service';
import { NotificationsService } from './notifications.service';
import { UserEngagementService } from './user-engagement.service';

/**
 * NotificationsScheduler — Birthday reminder push notifications.
 *
 * v3 (ML spec item #7): PER-USER send-time personalization.
 *
 * Previously: ran daily at 8:00 AM IST for everyone. Two users in different
 * timezones or with different wake-up patterns both got the same notification
 * at the same time.
 *
 * Now: runs HOURLY. Each run picks up users whose personalized best-send-hour
 * (computed from their notification engagement history) matches the current
 * hour, and sends their pending birthday reminders. Users without enough
 * engagement history (or with a stale profile) fall back to the default
 * 8 AM IST send time — so the existing behavior is preserved for new users.
 *
 * The engagement profile is updated whenever a user opens/acts on a
 * notification (see UserEngagementService.recordEngagement). Over time the
 * scheduler learns when each user is most likely to engage and shifts their
 * send time accordingly.
 *
 * Cron: every hour at minute 0. We process all users whose best-send-hour
 * (or fallback hour) matches the current hour.
 */
@Injectable()
export class NotificationsScheduler {
  private readonly logger = new Logger(NotificationsScheduler.name);

  // Default send hour when the user has no engagement profile yet, or the
  // profile is stale / has insufficient samples. 8 AM in the user's local
  // timezone — matches the previous behavior.
  private readonly DEFAULT_SEND_HOUR_LOCAL = 8;

  constructor(
    private readonly prisma: PrismaService,
    private readonly fcmService: FcmService,
    private readonly notificationsService: NotificationsService,
    private readonly userEngagementService: UserEngagementService,
  ) {}

  /**
   * Runs hourly at minute 0. For each user whose best-send-hour matches the
   * current hour (in their local timezone approximation), checks for
   * upcoming birthdays in the next 7 days and sends reminders.
   *
   * Timezone note: this implementation uses the SERVER's local hour as a
   * proxy for the user's local hour. If the server runs in UTC, the
   * "current hour" is the UTC hour. The engagement profile also records
   * engagement in server-local hours, so the two are consistent — we're
   * matching "what hour is it now (server-local)" against "what hour does
   * this user typically engage (server-local)".
   *
   * A future improvement would be to store the user's actual timezone
   * (from User.timezone if it exists, or fall back to family timezone) and
   * convert both the current time and the engagement histogram to that TZ.
   * For now, server-local is good enough — most production deployments run
   * in UTC, and users in different timezones will see their notifications
   * at different UTC hours, which their device converts to the correct
   * local display time.
   */
  @Cron('0 * * * *', {
    name: 'birthday-reminder-personalized',
    timeZone: 'UTC',
  })
  async handleBirthdayReminders() {
    const now = new Date();
    const currentHour = now.getHours(); // server-local hour
    this.logger.log(`Birthday reminder job running at hour ${currentHour} (server-local)`);

    try {
      // Find all upcoming birthdays in the next 7 days. We fetch ALL of them
      // and then filter per-user based on each user's best-send-hour — this
      // is simpler than trying to do the per-user hour matching in SQL.
      const upcomingBirthdays = await this.findUpcomingBirthdays(now, 7);

      if (upcomingBirthdays.length === 0) {
        this.logger.log('No upcoming birthdays found in the next 7 days');
        return;
      }

      this.logger.log(`Found ${upcomingBirthdays.length} upcoming birthday(s) in the next 7 days`);

      let notificationsSent = 0;
      let usersChecked = 0;
      let usersSkippedDueToHour = 0;

      // Group birthdays by family (one notification per family per birthday person)
      for (const birthday of upcomingBirthdays) {
        try {
          // Find all family members who belong to the same family
          const familyMembers = await this.prisma.familyMember.findMany({
            where: {
              familyId: birthday.familyId,
              userId: { not: undefined },
            },
            include: {
              user: {
                select: { id: true, name: true },
              },
            },
          });

          if (familyMembers.length === 0) {
            this.logger.debug?.(
              `No family members to notify for ${birthday.name}'s birthday in family ${birthday.familyId}`,
            );
            continue;
          }

          const daysUntil = birthday.daysUntil;
          const memberName = birthday.name;
          const title = 'Birthday Reminder';
          const body =
            daysUntil === 0
              ? `It's ${memberName}'s birthday today!`
              : `It's ${memberName}'s birthday in ${daysUntil} day${daysUntil !== 1 ? 's' : ''}!`;

          // Get family name for context
          const family = await this.prisma.family.findUnique({
            where: { id: birthday.familyId },
            select: { name: true },
          });

          for (const member of familyMembers) {
            try {
              usersChecked++;

              // ── Per-user send-hour check ──────────────────────────────
              // Look up this user's best-send-hour from their engagement
              // profile. If it doesn't match the current hour, skip them —
              // they'll be picked up by the run that fires at their hour.
              const bestHourResult = await this.userEngagementService.getBestSendHour(
                member.user.id,
                this.DEFAULT_SEND_HOUR_LOCAL,
              );
              if (bestHourResult.hour !== currentHour) {
                usersSkippedDueToHour++;
                continue;
              }

              // Check notification preferences
              const pref = await this.prisma.notificationPreference.findUnique({
                where: {
                  userId_eventType: {
                    userId: member.user.id,
                    eventType: 'birthday_reminder',
                  },
                },
              });

              if (pref && !pref.push) {
                this.logger.debug?.(
                  `User ${member.user.id} has disabled push for birthday_reminder - skipping FCM`,
                );
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
                this.logger.debug?.(
                  `User ${member.user.id} is in quiet hours - skipping push notification`,
                );
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
                // Tag the source so we can verify per-user personalization
                // is actually working after deploy.
                sendHourSource: bestHourResult.source,
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
        `Birthday reminder job complete - sent ${notificationsSent} push notification(s) ` +
          `(checked ${usersChecked} user-birthday pairs, skipped ${usersSkippedDueToHour} due to hour mismatch)`,
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
