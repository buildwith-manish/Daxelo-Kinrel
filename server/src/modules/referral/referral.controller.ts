import {
  Controller,
  Get,
  Post,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { ReferralService } from './referral.service';
import { GenerateReferralDto, ApplyReferralDto } from './dto/referral.dto';

@ApiTags('Referral')
@ApiBearerAuth()
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
  async getStats(@CurrentUser('id') userId: string) {
    return this.referralService.getStats(userId);
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
