import { Injectable, Logger, BadRequestException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
import { SubscriptionPlan } from '@prisma/client';
import * as crypto from 'crypto';

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /** Creates a new payment order for a subscription plan. */
  async createOrder(userId: string, plan: string, amount: number, currency: string = 'INR') {
    this.logger.log(`Creating order for user ${userId}, plan: ${plan}, amount: ${amount}`);

    // Validate plan
    const validPlans: SubscriptionPlan[] = ['pro_monthly', 'pro_annual', 'family_annual', 'lifetime'];
    if (!validPlans.includes(plan as SubscriptionPlan)) {
      throw new BadRequestException(`Invalid plan: ${plan}. Valid plans: ${validPlans.join(', ')}`);
    }

    // Validate amount
    if (!amount || amount <= 0) {
      throw new BadRequestException('Amount must be a positive number');
    }

    // In production, this would call Razorpay/Stripe to create a real order
    // For now, generate a deterministic order ID
    const orderId = `order_${crypto.randomBytes(16).toString('hex')}`;
    return {
      orderId,
      amount,
      currency,
      plan,
    };
  }

  /** Verifies a payment and activates or upgrades the user's subscription. */
  async verifyAndActivate(userId: string, paymentData: {
    orderId?: string;
    paymentId?: string;
    signature?: string;
    plan?: string;
    razorpayOrderId?: string;
    razorpayPaymentId?: string;
    razorpaySignature?: string;
  }) {
    this.logger.log(`Verifying payment for user ${userId}`);

    // If Razorpay signature is provided, verify it
    const razorpayOrderId = paymentData.razorpayOrderId || paymentData.orderId;
    const razorpayPaymentId = paymentData.razorpayPaymentId || paymentData.paymentId;
    const razorpaySignature = paymentData.razorpaySignature || paymentData.signature;

    if (razorpayOrderId && razorpayPaymentId && razorpaySignature) {
      // Verify Razorpay signature: HMAC-SHA256(orderId + '|' + paymentId, secret)
      const secret = this.config.get('RAZORPAY_KEY_SECRET');
      if (!secret) {
        this.logger.error('RAZORPAY_KEY_SECRET not configured — cannot verify payment');
        throw new BadRequestException('Payment verification is not configured');
      }

      const expectedSignature = crypto
        .createHmac('sha256', secret)
        .update(`${razorpayOrderId}|${razorpayPaymentId}`)
        .digest('hex');

      if (!crypto.timingSafeEqual(
        Buffer.from(razorpaySignature, 'hex'),
        Buffer.from(expectedSignature, 'hex'),
      )) {
        this.logger.warn(`Payment signature verification FAILED for user ${userId}`);
        throw new BadRequestException('Payment verification failed — invalid signature');
      }

      this.logger.log(`Payment signature verified for user ${userId}`);
    } else {
      // No signature provided — reject in production
      if (this.config.get('NODE_ENV') === 'production') {
        throw new BadRequestException('Payment signature is required in production');
      }
      // In development, allow without signature but log a warning
      this.logger.warn(`⚠️ Payment activated WITHOUT signature verification for user ${userId} (development mode only)`);
    }

    // Validate plan
    const plan = (paymentData.plan || 'pro_monthly') as SubscriptionPlan;
    const validPlans: SubscriptionPlan[] = ['pro_monthly', 'pro_annual', 'family_annual', 'lifetime'];
    if (!validPlans.includes(plan)) {
      throw new BadRequestException(`Invalid plan: ${plan}`);
    }

    return this.prisma.subscription.upsert({
      where: { userId },
      update: {
        plan,
        status: 'active',
        supportTier: 'standard',
        startDate: new Date(),
      },
      create: {
        userId,
        plan,
        status: 'active',
        supportTier: 'standard',
        startDate: new Date(),
      },
    });
  }

  /** Returns the current subscription for a user. */
  async getSubscription(userId: string) {
    return this.prisma.subscription.findUnique({ where: { userId } });
  }

  /** Cancels the user's active subscription. */
  async cancelSubscription(userId: string) {
    const subscription = await this.prisma.subscription.findUnique({ where: { userId } });
    if (!subscription) {
      throw new NotFoundException('No active subscription found');
    }
    return this.prisma.subscription.update({
      where: { userId },
      data: { status: 'cancelled' },
    });
  }
}
