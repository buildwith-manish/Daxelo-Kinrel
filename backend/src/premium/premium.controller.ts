import {
  Controller,
  Get,
  Post,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { PremiumService } from './premium.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { IsString, IsNotEmpty, IsIn } from 'class-validator';

class ActivatePremiumDto {
  @IsString()
  @IsNotEmpty()
  razorpayPaymentId: string;

  @IsString()
  @IsNotEmpty()
  razorpayOrderId: string;

  @IsString()
  @IsNotEmpty()
  razorpaySignature: string;

  @IsString()
  @IsIn(['pro_monthly', 'pro_annual', 'family_annual', 'lifetime'])
  plan: string;
}

@Controller('premium')
@UseGuards(JwtAuthGuard)
export class PremiumController {
  constructor(private premiumService: PremiumService) {}

  /**
   * POST /api/premium/activate
   * Activate premium subscription after Razorpay payment verification
   */
  @Post('activate')
  @HttpCode(HttpStatus.CREATED)
  async activate(
    @CurrentUser() user: { id: string },
    @Body() dto: ActivatePremiumDto,
  ) {
    return this.premiumService.activate(
      user.id,
      dto.razorpayPaymentId,
      dto.razorpayOrderId,
      dto.razorpaySignature,
      dto.plan,
    );
  }

  /**
   * GET /api/premium/status
   * Get current premium subscription status
   */
  @Get('status')
  async getStatus(@CurrentUser() user: { id: string }) {
    return this.premiumService.getStatus(user.id);
  }

  /**
   * POST /api/premium/cancel
   * Cancel premium subscription (user keeps premium until expiresAt)
   */
  @Post('cancel')
  @HttpCode(HttpStatus.OK)
  async cancel(@CurrentUser() user: { id: string }) {
    return this.premiumService.cancel(user.id);
  }
}
