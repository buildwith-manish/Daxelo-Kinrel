import { Controller, Get, Post, Delete, Body, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { PaymentsService } from './payments.service';

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
  async verifyPayment(
    @CurrentUser('id') userId: string,
    @Body() body: Record<string, any>,
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
