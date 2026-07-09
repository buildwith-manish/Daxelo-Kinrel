// =============================================================================
// Track C v2.0 — AURA Learning Engine
// learning.controller.ts
// =============================================================================

import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { LearningService } from './learning.service';

@Controller('api/v1/families/:familyId/learning')
@UseGuards(JwtAuthGuard)
export class LearningController {
  constructor(private readonly service: LearningService) {}

  @Get('profile')
  getProfile(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.service.getProfile(familyId, userId);
  }

  @Post('signals')
  ingestSignal(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { signalType: string; targetType?: string; targetId?: string; payload?: any },
  ) {
    if (!body?.signalType) throw new BadRequestException('signalType is required');
    return this.service.ingestSignal(familyId, userId, body as any);
  }

  @Post('reset')
  reset(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: { reason?: string },
  ) {
    return this.service.resetProfile(familyId, userId, body?.reason ?? 'user_request');
  }

  @Post('recompute')
  recompute(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.service.triggerRecompute(familyId, userId);
  }
}
