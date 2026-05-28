import {
  Controller,
  Get,
  Post,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ReferralService } from './referral.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { IsString, IsNotEmpty, Length } from 'class-validator';

class ApplyReferralDto {
  @IsString()
  @IsNotEmpty()
  @Length(8, 8)
  code: string;
}

@Controller('referral')
@UseGuards(JwtAuthGuard)
export class ReferralController {
  constructor(private referralService: ReferralService) {}

  /**
   * GET /api/referral/my-code
   * Get or generate the current user's referral code
   */
  @Get('my-code')
  async getMyCode(@CurrentUser() user: { id: string }) {
    return this.referralService.getMyCode(user.id);
  }

  /**
   * POST /api/referral/apply
   * Apply a referral code
   */
  @Post('apply')
  @HttpCode(HttpStatus.OK)
  async applyReferral(
    @CurrentUser() user: { id: string },
    @Body() dto: ApplyReferralDto,
  ) {
    return this.referralService.applyReferral(user.id, dto.code);
  }

  /**
   * GET /api/referral/stats
   * Get referral statistics for the current user
   */
  @Get('stats')
  async getStats(@CurrentUser() user: { id: string }) {
    return this.referralService.getStats(user.id);
  }
}
