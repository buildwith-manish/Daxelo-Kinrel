import { Controller, Get, Post, Delete, Body, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { PaymentsService } from './payments.service';

@ApiTags('Payments')
@ApiBearerAuth()
@Controller('payments')
@UseGuards(JwtAuthGuard)
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Post('create-order')
  async createOrder(
    @CurrentUser('id') userId: string,
    @Body() body: { plan: string; amount: number; currency?: string },
  ) {
    return this.paymentsService.createOrder(userId, body.plan, body.amount, body.currency);
  }

  @Post('verify')
  @Throttle({ default: { limit: 3, ttl: 60000 } })
  async verifyPayment(
    @CurrentUser('id') userId: string,
    @Body() body: {
      orderId?: string;
      paymentId?: string;
      signature?: string;
      plan?: string;
      razorpayOrderId?: string;
      razorpayPaymentId?: string;
      razorpaySignature?: string;
    },
  ) {
    return this.paymentsService.verifyAndActivate(userId, body);
  }

  @Get('subscription')
  async getSubscription(@CurrentUser('id') userId: string) {
    return this.paymentsService.getSubscription(userId);
  }

  @Delete('subscription')
  async cancelSubscription(@CurrentUser('id') userId: string) {
    return this.paymentsService.cancelSubscription(userId);
  }
}
