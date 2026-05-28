import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FcmService } from '../notifications/fcm.service';

@Injectable()
export class CampaignsService {
  private readonly logger = new Logger(CampaignsService.name);

  constructor(
    private prisma: PrismaService,
    private fcmService: FcmService,
  ) {}

  /**
   * Campaign 1: Dormant user re-engagement
   * Targets users who haven't opened the app in 7+ days
   * - Respects quiet hours based on user's timezoneOffset
   * - Max 2 notifications per day
   * - Only sends if dormantNotificationSent is false
   */
  async runDormantUserCampaign() {
    this.logger.log('Running dormant user re-engagement campaign...');

    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const now = new Date();

    // Find users who haven't opened the app in 7+ days and haven't been notified yet
    const dormantUsers = await this.prisma.user.findMany({
      where: {
        lastOpenedAt: { lt: sevenDaysAgo },
        dormantNotificationSent: false,
        fcmToken: { not: null },
      },
      select: {
        id: true,
        name: true,
        timezoneOffset: true,
        fcmToken: true,
      },
    });

    this.logger.log(`Found ${dormantUsers.length} dormant users`);

    let notified = 0;

    for (const user of dormantUsers) {
      // Check quiet hours — respect user's local time
      if (this.isQuietHours(user.timezoneOffset)) {
        this.logger.debug(`Skipping user ${user.id} — quiet hours`);
        continue;
      }

      // Check max 2 notifications per day for this user
      const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const todayNotifications = await this.prisma.notification.count({
        where: {
          userId: user.id,
          eventType: 'dormant_reengagement',
          createdAt: { gte: todayStart },
        },
      });

      if (todayNotifications >= 2) {
        this.logger.debug(`Skipping user ${user.id} — max 2 notifications/day reached`);
        continue;
      }

      // Send FCM notification
      const sent = await this.fcmService.sendToUser(
        user.id,
        'We miss you! 🏠',
        'Your family tree is waiting. Come back and add new members!',
        { type: 'dormant_reengagement', deepLink: '/family-tree' },
      );

      // Log notification to console
      this.logger.log(
        `[Dormant Campaign] Notification to user ${user.id} (${user.name || 'Unknown'}): ${sent ? 'sent' : 'failed'}`,
      );

      // Create notification record in DB
      await this.prisma.notification.create({
        data: {
          userId: user.id,
          eventType: 'dormant_reengagement',
          title: 'We miss you! 🏠',
          body: 'Your family tree is waiting. Come back and add new members!',
          channels: '["push"]',
          priority: 'normal',
          actionUrl: '/family-tree',
        },
      });

      // Mark user as notified so we don't send again
      await this.prisma.user.update({
        where: { id: user.id },
        data: { dormantNotificationSent: true },
      });

      notified++;
    }

    this.logger.log(`Dormant user campaign complete. Notified ${notified} users`);
  }

  /**
   * Campaign 2: Almost premium — upgrade nudge
   * Targets users with 45-49 family members (close to the free limit of 50)
   * Sends upgrade nudge weekly
   */
  async runAlmostPremiumCampaign() {
    this.logger.log('Running almost-premium upgrade nudge campaign...');

    const now = new Date();
    const oneWeekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    // Find users who are NOT premium
    const freeUsers = await this.prisma.user.findMany({
      where: {
        isPremium: false,
        fcmToken: { not: null },
      },
      select: {
        id: true,
        name: true,
        timezoneOffset: true,
        families: {
          select: {
            familyId: true,
          },
        },
      },
    });

    let notified = 0;

    for (const user of freeUsers) {
      // Get total person count across all families the user belongs to
      const familyIds = user.families.map((f) => f.familyId);
      if (familyIds.length === 0) continue;

      const personCount = await this.prisma.person.count({
        where: {
          familyId: { in: familyIds },
          deletedAt: null,
        },
      });

      // Only target users with 45-49 members
      if (personCount < 45 || personCount > 49) continue;

      // Check quiet hours
      if (this.isQuietHours(user.timezoneOffset)) {
        continue;
      }

      // Check if we've already sent this nudge in the last week
      const recentNudge = await this.prisma.notification.findFirst({
        where: {
          userId: user.id,
          eventType: 'almost_premium_nudge',
          createdAt: { gte: oneWeekAgo },
        },
      });

      if (recentNudge) {
        continue;
      }

      // Send FCM notification
      const sent = await this.fcmService.sendToUser(
        user.id,
        'You\'re almost at the free limit! 🌟',
        `You've added ${personCount} members. Upgrade to Premium for unlimited members!`,
        { type: 'almost_premium_nudge', deepLink: '/premium' },
      );

      this.logger.log(
        `[Almost Premium Campaign] Notification to user ${user.id} (${personCount} members): ${sent ? 'sent' : 'failed'}`,
      );

      // Create notification record
      await this.prisma.notification.create({
        data: {
          userId: user.id,
          eventType: 'almost_premium_nudge',
          title: 'You\'re almost at the free limit! 🌟',
          body: `You've added ${personCount} members. Upgrade to Premium for unlimited members!`,
          channels: '["push"]',
          priority: 'normal',
          actionUrl: '/premium',
        },
      });

      notified++;
    }

    this.logger.log(`Almost-premium campaign complete. Notified ${notified} users`);
  }

  /**
   * Campaign 3: Expiring premium — renewal reminder
   * Targets premium users whose subscription expires in 3 days
   */
  async runExpiringPremiumCampaign() {
    this.logger.log('Running expiring premium renewal reminder campaign...');

    const now = new Date();
    const threeDaysFromNow = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);
    const twoDaysFromNow = new Date(now.getTime() + 2 * 24 * 60 * 60 * 1000);

    // Find subscriptions expiring in 3 days (between 2 and 3 days from now)
    const expiringSubscriptions = await this.prisma.subscription.findMany({
      where: {
        status: { in: ['active', 'cancelled'] },
        endDate: {
          gte: twoDaysFromNow,
          lte: threeDaysFromNow,
        },
      },
      select: {
        id: true,
        userId: true,
        plan: true,
        endDate: true,
        user: {
          select: {
            id: true,
            name: true,
            timezoneOffset: true,
            fcmToken: true,
            isPremium: true,
          },
        },
      },
    });

    let notified = 0;

    for (const sub of expiringSubscriptions) {
      const user = sub.user;

      // Only notify if user is still premium
      if (!user.isPremium) continue;

      // Check quiet hours
      if (this.isQuietHours(user.timezoneOffset)) {
        continue;
      }

      // Check if we've already sent a renewal reminder recently (within 24 hours)
      const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      const recentReminder = await this.prisma.notification.findFirst({
        where: {
          userId: user.id,
          eventType: 'premium_expiring_reminder',
          createdAt: { gte: oneDayAgo },
        },
      });

      if (recentReminder) {
        continue;
      }

      const daysLeft = Math.ceil(
        (sub.endDate!.getTime() - now.getTime()) / (24 * 60 * 60 * 1000),
      );

      // Send FCM notification
      const sent = await this.fcmService.sendToUser(
        user.id,
        'Your Premium is expiring soon! ⏰',
        `Your ${sub.plan} plan expires in ${daysLeft} days. Renew now to keep all features!`,
        { type: 'premium_expiring_reminder', deepLink: '/premium/renew' },
      );

      this.logger.log(
        `[Expiring Premium Campaign] Notification to user ${user.id} (expires ${sub.endDate?.toISOString()}): ${sent ? 'sent' : 'failed'}`,
      );

      // Create notification record
      await this.prisma.notification.create({
        data: {
          userId: user.id,
          eventType: 'premium_expiring_reminder',
          title: 'Your Premium is expiring soon! ⏰',
          body: `Your ${sub.plan} plan expires in ${daysLeft} days. Renew now to keep all features!`,
          channels: '["push"]',
          priority: 'high',
          actionUrl: '/premium/renew',
        },
      });

      notified++;
    }

    this.logger.log(`Expiring premium campaign complete. Notified ${notified} users`);
  }

  /**
   * Check if current time is within the user's quiet hours
   * Quiet hours: 22:00 - 08:00 in user's local timezone
   * timezoneOffset is in minutes (e.g., IST = 330)
   */
  private isQuietHours(timezoneOffset: number): boolean {
    const nowUtc = new Date();
    // Convert UTC to user's local time
    const localMs = nowUtc.getTime() + timezoneOffset * 60 * 1000;
    const localDate = new Date(localMs);
    const localHour = localDate.getUTCHours();

    // Quiet hours: 22:00 to 08:00
    return localHour >= 22 || localHour < 8;
  }
}
