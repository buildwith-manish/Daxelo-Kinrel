import {
  Controller,
  Post,
  Get,
  Body,
  Query,
} from '@nestjs/common';
import { ReferralService } from './referral.service';
import { GenerateReferralDto, ApplyReferralDto } from './dto/referral.dto';

/**
 * ReferralController — /api/v1/referral
 *
 * Handles:
 * - POST /api/v1/referral/generate — Generate a referral code
 * - POST /api/v1/referral/apply    — Apply a referral code
 * - GET  /api/v1/referral/stats    — Get referral stats for a user
 * - GET  /api/v1/referral/rewards  — Get available reward tiers
 */
@Controller('v1/referral')
export class ReferralController {
  constructor(private readonly referralService: ReferralService) {}

  @Post('generate')
  async generateCode(@Body() dto: GenerateReferralDto) {
    return this.referralService.generateReferralCode(dto.userId);
  }

  @Post('apply')
  async applyCode(@Body() dto: ApplyReferralDto) {
    return this.referralService.applyReferralCode(dto.code, dto.userId);
  }

  @Get('stats')
  async getStats(@Query('userId') userId: string) {
    return this.referralService.getReferralStats(userId);
  }

  @Get('rewards')
  async getRewards() {
    return this.referralService.getRewards();
  }
}
