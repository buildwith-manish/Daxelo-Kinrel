import { Injectable, BadRequestException, NotFoundException, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import * as crypto from 'crypto';

@Injectable()
export class PremiumService {
  private readonly logger = new Logger(PremiumService.name);

  constructor(private prisma: PrismaService) {}

  /**
   * Activate a premium subscription after Razorpay payment
   * Verifies the Razorpay signature using HMAC SHA256
   */
  async activate(
    userId: string,
    razorpayPaymentId: string,
    razorpayOrderId: string,
    razorpaySignature: string,
    plan: string,
  ) {
    // Verify Razorpay signature
    const razorpaySecret = process.env.RAZORPAY_KEY_SECRET || '';
    if (!razorpaySecret) {
      throw new BadRequestException('Razorpay configuration missing');
    }

    const expectedSignature = crypto
      .createHmac('sha256', razorpaySecret)
      .update(razorpayOrderId + '|' + razorpayPaymentId)
      .digest('hex');

    if (expectedSignature !== razorpaySignature) {
      throw new BadRequestException('Invalid payment signature');
    }

    // Validate plan
    const validPlans = ['pro_monthly', 'pro_annual', 'family_annual', 'lifetime'];
    if (!validPlans.includes(plan)) {
      throw new BadRequestException('Invalid plan specified');
    }

    // Calculate end date based on plan
    const startDate = new Date();
    let endDate: Date | null = null;

    switch (plan) {
      case 'pro_monthly':
        endDate = new Date(startDate.getTime() + 30 * 24 * 60 * 60 * 1000);
        break;
      case 'pro_annual':
        endDate = new Date(startDate.getTime() + 365 * 24 * 60 * 60 * 1000);
        break;
      case 'family_annual':
        endDate = new Date(startDate.getTime() + 365 * 24 * 60 * 60 * 1000);
        break;
      case 'lifetime':
        endDate = null; // No end date for lifetime
        break;
    }

    // Determine support tier based on plan
    const supportTier = plan === 'family_annual' ? 'premium' : 'standard';

    // Check if user already has an active subscription
    const existingSub = await this.prisma.subscription.findUnique({
      where: { userId },
    });

    if (existingSub) {
      // Update existing subscription
      await this.prisma.subscription.update({
        where: { id: existingSub.id },
        data: {
          plan,
          status: 'active',
          supportTier,
          startDate,
          endDate,
        },
      });
    } else {
      // Create new subscription
      await this.prisma.subscription.create({
        data: {
          userId,
          plan,
          status: 'active',
          supportTier,
          startDate,
          endDate,
        },
      });
    }

    // Set user as premium
    await this.prisma.user.update({
      where: { id: userId },
      data: { isPremium: true },
    });

    return {
      success: true,
      message: 'Premium subscription activated',
      plan,
      startDate: startDate.toISOString(),
      endDate: endDate?.toISOString() ?? null,
    };
  }

  /**
   * Get premium status for the current user
   */
  async getStatus(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        isPremium: true,
        subscription: {
          select: {
            plan: true,
            status: true,
            endDate: true,
          },
        },
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    const subscription = user.subscription;

    let daysLeft: number | null = null;
    if (subscription?.endDate) {
      const now = new Date();
      const diffMs = subscription.endDate.getTime() - now.getTime();
      daysLeft = Math.max(0, Math.ceil(diffMs / (24 * 60 * 60 * 1000)));
    }

    return {
      isPremium: user.isPremium,
      plan: subscription?.plan ?? 'free',
      expiresAt: subscription?.endDate?.toISOString() ?? null,
      daysLeft,
    };
  }

  /**
   * Cancel premium subscription
   * User stays premium until expiresAt
   */
  async cancel(userId: string) {
    const subscription = await this.prisma.subscription.findUnique({
      where: { userId },
    });

    if (!subscription) {
      throw new NotFoundException('No active subscription found');
    }

    if (subscription.status === 'cancelled') {
      throw new BadRequestException('Subscription is already cancelled');
    }

    // Mark subscription as cancelled but keep user premium until expiresAt
    await this.prisma.subscription.update({
      where: { id: subscription.id },
      data: { status: 'cancelled' },
    });

    return {
      success: true,
      message: 'Subscription cancelled. You will retain premium benefits until the end of your billing period.',
      expiresAt: subscription.endDate?.toISOString() ?? null,
    };
  }

  /**
   * Daily cron job at 1 AM to expire subscriptions
   * Checks for subscriptions where endDate < now and status is active or cancelled
   */
  @Cron('0 1 * * *', {
    name: 'expire-subscriptions',
  })
  async handleSubscriptionExpiry() {
    this.logger.log('Running subscription expiry check...');

    const now = new Date();

    // Find active or cancelled subscriptions that have expired
    const expiredSubscriptions = await this.prisma.subscription.findMany({
      where: {
        status: { in: ['active', 'cancelled'] },
        endDate: { not: null, lt: now },
      },
      select: {
        id: true,
        userId: true,
        plan: true,
      },
    });

    if (expiredSubscriptions.length === 0) {
      this.logger.log('No expired subscriptions found');
      return;
    }

    this.logger.log(`Found ${expiredSubscriptions.length} expired subscriptions`);

    // Process each expired subscription
    for (const sub of expiredSubscriptions) {
      try {
        // Update subscription status to expired
        await this.prisma.subscription.update({
          where: { id: sub.id },
          data: { status: 'expired' },
        });

        // Set user as non-premium
        await this.prisma.user.update({
          where: { id: sub.userId },
          data: { isPremium: false },
        });

        this.logger.log(`Expired subscription ${sub.id} for user ${sub.userId}`);
      } catch (error) {
        this.logger.error(
          `Failed to expire subscription ${sub.id}: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }

    this.logger.log(`Subscription expiry check complete. Processed ${expiredSubscriptions.length} subscriptions`);
  }
}
