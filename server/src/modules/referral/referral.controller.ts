import {
  Controller,
  Get,
  Post,
  Body,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { ReferralService } from './referral.service';
import { GenerateReferralDto, ApplyReferralDto } from './dto/referral.dto';

@Controller('v1/referral')
@UseGuards(JwtAuthGuard)
export class ReferralController {
  constructor(private readonly referralService: ReferralService) {}

  // ── Generate Referral Code ──────────────────────────────────────────
  @Post('generate')
  @HttpCode(HttpStatus.OK)
  async generateCode(@CurrentUser('id') userId: string) {
    return this.referralService.generateCode(userId);
  }

  // ── Get Referral Stats ──────────────────────────────────────────────
  @Get('stats')
  async getStats(
    @CurrentUser('id') currentUserId: string,
    @Query('userId') userId?: string,
  ) {
    // Allow querying own stats or specific user (for admin use)
    const targetUserId = userId || currentUserId;
    return this.referralService.getStats(targetUserId);
  }

  // ── Apply Referral Code ─────────────────────────────────────────────
  @Post('apply')
  @HttpCode(HttpStatus.OK)
  async applyCode(
    @CurrentUser('id') userId: string,
    @Body() dto: ApplyReferralDto,
  ) {
    return this.referralService.applyCode(userId, dto.code);
  }

  // ── Get Reward Tiers ────────────────────────────────────────────────
  @Get('rewards')
  async getRewardTiers() {
    return this.referralService.getRewardTiers();
  }
}
