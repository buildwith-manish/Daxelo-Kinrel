import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';
import { FcmService } from './fcm.service';
import { NotificationsService } from './notifications.service';
import { UserEngagementService } from './user-engagement.service';
// Step 5 — IST helpers. The scheduler previously used
// `new Date().getHours()` (server-local = UTC in production) as a
// proxy for the user's local hour. Since the family base is India-only
// today, we now compute the IST hour explicitly via date-fns-tz so
// the "best send hour" comparison is correct. Per-user timezone
// support is intentionally NOT built here — see the TODO in the
// handleBirthdayReminders comment below.
import {
  IST_TZ,
  getIstHour,
  getIstDay,
  getIstMonth,
  getIstDateOfMonth,
  getIstYear,
  isInIstQuietHours,
} from './timezone-utils';

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
  // profile is stale / has insufficient samples. 8 AM IST — matches the
  // previous behavior. Step 5: this is now explicitly IST (was previously
  // documented as "8 AM in the user's local timezone" but the scheduler
  // ran in UTC, so it was effectively 8 AM UTC = 1:30 PM IST).
  private readonly DEFAULT_SEND_HOUR_IST = 8;

  constructor(
    private readonly prisma: PrismaService,
    private readonly fcmService: FcmService,
    private readonly notificationsService: NotificationsService,
    private readonly userEngagementService: UserEngagementService,
  ) {}

  /**
   * Runs hourly at minute 0. For each user whose best-send-hour matches the
   * current IST hour, checks for upcoming birthdays in the next 7 days and
   * sends reminders.
   *
   * Step 5 timezone fix:
   * ───────────────────
   * Previously the cron ran with `timeZone: 'UTC'` and the code used
   * `now.getHours()` (server-local = UTC) as a proxy for the user's local
   * hour. The engagement histogram was also recorded in server-local
   * hours, so the two were CONSISTENT but the labels were wrong — a
   * "9 AM" histogram entry was actually "9 AM UTC = 2:30 PM IST", and
   * the scheduler fired at 9 AM UTC (2:30 PM IST) too.
   *
   * Now: the cron still fires at every UTC hour (hourly at minute 0),
   * but the hour-comparison uses the explicit IST hour computed via
   * `getIstHour(now)`. The engagement histogram is also recorded in
   * IST hours (see UserEngagementService.recordEngagement). So a user
   * whose histogram says "9 AM" (IST) gets the notification at 9 AM
   * IST — not 9 AM UTC (2:30 PM IST). For users in non-IST timezones,
   * the histogram is still in IST — which is wrong, but no worse than
   * the previous UTC behavior, and the family base is India-only
   * today.
   *
   * FUTURE IMPROVEMENT (kept as a TODO; not built in this step):
   * Store the user's actual timezone in `User.timezone` (a column
   * already exists for `quietHoursTimezone` with default
   * 'Asia/Kolkata'; we'd extend it to be the user's full timezone),
   * and convert both the current time and the engagement histogram
   * to that per-user TZ. Until then, IST is the best approximation
   * for the current India-only family base.
   */
  @Cron('0 * * * *', {
    name: 'birthday-reminder-personalized',
    timeZone: 'UTC',
  })
  async handleBirthdayReminders() {
    const now = new Date();
    // Step 5: compute the IST hour explicitly via date-fns-tz.
    const currentIstHour = getIstHour(now);
    this.logger.log(
      `Birthday reminder job running at IST hour ${currentIstHour} ` +
      `(UTC: ${now.toISOString()})`,
    );

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

              // ── Per-user send-hour check (IST) ──────────────────────
              // Step 5: look up this user's best-send-hour (now in IST)
              // and compare against the current IST hour. If they
              // don't match, skip them — they'll be picked up by the
              // run that fires at their IST hour.
              const bestHourResult = await this.userEngagementService.getBestSendHour(
                member.user.id,
                this.DEFAULT_SEND_HOUR_IST,
              );
              if (bestHourResult.hour !== currentIstHour) {
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

              // Check quiet hours (Step 5: now IST-aware)
              if (pref && isInIstQuietHours(now, pref.quietHoursStart, pref.quietHoursEnd)) {
                this.logger.debug?.(
                  `User ${member.user.id} is in IST quiet hours - skipping push notification`,
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
                // Step 5: tag the timezone so we can verify IST scheduling
                // is actually being used after deploy.
                sendHourTimezone: IST_TZ,
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
          `(checked ${usersChecked} user-birthday pairs, skipped ${usersSkippedDueToHour} due to IST-hour mismatch)`,
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
   *
   * Step 5: "Today" is now computed as IST today (not server-local today).
   * For an IST user on Sep 22 at 00:30 IST (= Sep 21 19:00 UTC), this
   * correctly returns Sep 22 as today. Previously it returned Sep 21
   * (the UTC date), which would have missed a Sep 22 birthday until
   * the UTC clock caught up 5.5 hours later.
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
    // the next `daysAhead` days from today (IST today).
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

    // Step 5: compute the IST "today" components once for efficiency.
    // We pass them into getDaysUntilNextBirthday so it doesn't have to
    // re-derive them per person.
    const istYear = getIstYear(now);
    const istMonth = getIstMonth(now); // 0-11
    const istDay = getIstDateOfMonth(now);

    const results: Array<{
      id: string;
      name: string;
      familyId: string;
      dateOfBirth: Date;
      daysUntil: number;
    }> = [];

    for (const person of persons) {
      if (!person.dateOfBirth) continue;

      const daysUntil = this.getDaysUntilNextBirthday(
        person.dateOfBirth,
        istYear,
        istMonth,
        istDay,
      );

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
   *
   * Step 5: the "today" reference is now passed in as IST components
   * (year, month, day) computed via date-fns-tz. The birthday month/
   * day are from the stored `dateOfBirth` which is timezone-agnostic
   * (a birthday is a calendar date, not an instant).
   */
  private getDaysUntilNextBirthday(
    dateOfBirth: Date,
    todayYear: number,
    todayMonth: number, // 0-11
    todayDay: number,    // 1-31
  ): number {
    const birthMonth = dateOfBirth.getMonth(); // 0-11
    const birthDay = dateOfBirth.getDate(); // 1-31

    // This year's birthday (in IST terms)
    let nextBirthday = new Date(todayYear, birthMonth, birthDay);

    // If birthday has already passed this IST year, use next year
    if (
      nextBirthday.getMonth() < todayMonth ||
      (nextBirthday.getMonth() === todayMonth && nextBirthday.getDate() < todayDay)
    ) {
      nextBirthday = new Date(todayYear + 1, birthMonth, birthDay);
    }

    // Calculate days difference (IST today vs IST next birthday)
    const todayMidnight = new Date(todayYear, todayMonth, todayDay);
    const diffMs = nextBirthday.getTime() - todayMidnight.getTime();
    return Math.round(diffMs / (1000 * 60 * 60 * 24));
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
