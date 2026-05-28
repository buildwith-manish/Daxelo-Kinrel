import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async createOrder(userId: string, plan: string, amount: number, currency: string = 'INR') {
    this.logger.log(`Creating order for user ${userId}, plan: ${plan}, amount: ${amount}`);
    return {
      orderId: `order_${Date.now()}`,
      amount,
      currency,
      plan,
    };
  }

  async verifyAndActivate(userId: string, paymentData: Record<string, any>) {
    this.logger.log(`Verifying payment for user ${userId}`);

    return this.prisma.subscription.upsert({
      where: { userId },
      update: {
        plan: paymentData.plan || 'pro_monthly',
        status: 'active',
        supportTier: 'standard',
        startDate: new Date(),
      },
      create: {
        userId,
        plan: paymentData.plan || 'pro_monthly',
        status: 'active',
        supportTier: 'standard',
        startDate: new Date(),
      },
    });
  }

  async getSubscription(userId: string) {
    return this.prisma.subscription.findUnique({ where: { userId } });
  }

  async cancelSubscription(userId: string) {
    return this.prisma.subscription.update({
      where: { userId },
      data: { status: 'cancelled' },
    });
  }
}
